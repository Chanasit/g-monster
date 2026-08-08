#!/usr/bin/env python3
"""Emit creature sprite PNGs from the ASCII art in sprites.txt.

The watch app wants five action states per species -- idle, sleep, walk, fight,
run -- two frames each. Only one grid per species is authored; every action's
frames are derived from it by grid transforms, the same way the idle breath was
always derived by dropping the whole silhouette one row. Deriving means the
artist maintains 29 grids instead of 145, a new species costs one grid rather
than five, and no species' poses can drift apart from each other.

What a derived pose can be is limited, and the transforms are honest about it:
these are motion cues built out of one silhouette -- bob, waddle, lean, lunge.
A sleeping creature here is a squashed creature, not a curled-up one.

Output is 24x24 scaled 3x with nearest-neighbour to 72x72, in exactly two
colours -- opaque black for ink, fully transparent for everything else. Two
colours is not an aesthetic choice, it is the app's: Theme keeps the whole UI
two-tone, so a sprite with anti-aliased edges would be the only soft thing on
the screen.

Besides the PNGs this writes the two files that would otherwise have to be kept
in sync by hand, which is where adding a species used to go wrong: the <bitmap>
block of resources/drawables/drawables.xml, and the resource-id table in
source/ui/SpriteIndex.mc.

Stdlib only (zlib, struct) so this runs on a bare checkout with no pip install.

    python3 tools/sprites/generate_sprites.py [--check]

--check verifies everything on disk matches what the ASCII would produce and
exits non-zero if not, without writing anything.
"""

import os
import re
import struct
import sys
import zlib

SCALE = 3
GRID = 24
SIZE = GRID * SCALE

#! Every frame of a variant lives in one bitmap, stacked top to bottom.
#!
#! Not a packing optimisation — a hard platform limit. Rez.Drawables takes at
#! most 254 members, and a bitmap per frame would need 406 of them. Sprites.mc
#! clips to the slice it wants, which costs one setClip per draw and keeps the
#! roster inside the cap with room for more species.
#!
#! Two is what a derived variant produces. An override may supply more, and then
#! only that one bitmap grows -- which is why the frame count is per variant
#! rather than global: a taller sheet for every species would multiply the
#! resident bitmap on a device with a small memory budget.
FRAMES = 2
SHEET_H = SIZE * FRAMES

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SOURCE = os.path.join(HERE, "sprites.txt")
OUTDIR = os.path.join(REPO, "resources", "drawables")
DRAWABLES_XML = os.path.join(OUTDIR, "drawables.xml")
INDEX_MC = os.path.join(REPO, "source", "ui", "SpriteIndex.mc")

INK = b"\x00\x00\x00\xff"
CLEAR = b"\x00\x00\x00\x00"

BLANK = "." * GRID

#! Action order is load-bearing: Sprites.mc indexes each species' flat id array
#! as slot * 2 + frame, so a variant's position here is its slot number, and the
#! first five have to stay in the order of ACTION_*.
#!
#! Lunging and leaning are the only transforms with a direction in them, so they
#! are the only ones with a mirrored variant. In battle the player's creature
#! commits to the right and the enemy to the left; drawing both with the same
#! rightward lean would have the enemy leaning away from its own charge. Idle,
#! sleep and walk carry no direction -- walk swings both ways across its two
#! frames -- so mirroring them would cost resources to say nothing.
#!
#! (label, action, mirrored)
VARIANTS = (
    ("idle", "idle", False),
    ("sleep", "sleep", False),
    ("walk", "walk", False),
    ("fight", "fight", False),
    ("run", "run", False),
    ("fight_left", "fight", True),
    ("run_left", "run", True),
)

#! The rows that read as legs. Row 23 is excluded because it must stay blank.
LEGS = frozenset(range(GRID - 7, GRID - 1))
ALL_ROWS = frozenset(range(GRID))

#! How much of a silhouette's ink a transform may push off the canvas edge.
#!
#! Eight of the authored grids touch column 0 or column 23, so the shifts below
#! do not fit every species. Rather than clip a wingtip silently or reject the
#! art, each magnitude is clamped per species to the largest value that stays
#! inside this budget. 2% of a 250-cell silhouette is five cells, which at 3x on
#! a 240px screen is a sliver on a frame that shows for half a second.
CLIP_TOLERANCE = 0.02

#! Sleep compresses the silhouette to this fraction of its height...
SLEEP_SQUASH = 0.60
#! ...and rests it here, high enough that the frame B drop still has somewhere
#! to go.
SLEEP_FLOOR = GRID - 3


def parse(path):
    """sprites.txt -> ({key: grid}, {(key, action): [grid, ...]}), in file order.

    A bare `key:` header is the species' one authored grid, from which every
    action is derived. A `key.action.n:` header is an explicit frame of one
    action, which overrides the derivation for that action alone -- that is how
    hand-drawn art gets in, and how an action can carry more than two frames.
    """
    sprites = {}
    overrides = {}
    key = None
    action = None
    frame = None
    rows = []

    def flush():
        if key is None:
            return
        if len(rows) != GRID:
            raise ValueError("%s: expected %d rows, got %d" % (key, GRID, len(rows)))
        for i, r in enumerate(rows):
            if len(r) != GRID:
                raise ValueError("%s row %d: expected %d cols, got %d"
                                 % (key, i, GRID, len(r)))
            bad = set(r) - set("#.")
            if bad:
                raise ValueError("%s row %d: bad characters %s" % (key, i, sorted(bad)))
        # Several actions shift the body down a row, so anything on the last row
        # would fall off the bottom of the bitmap.
        if "#" in rows[GRID - 1]:
            raise ValueError("%s: last row must be blank (frames shift down 1)" % key)
        if not any("#" in r for r in rows):
            raise ValueError("%s: sprite is empty" % key)
        if action is None:
            sprites[key] = list(rows)
        else:
            overrides.setdefault((key, action), []).append((frame, list(rows)))

    def is_art(line):
        # Tested before the comment rule on purpose: '#' is also the ink
        # character, so a row that starts on ink looks exactly like a comment.
        return len(line) == GRID and not (set(line) - set("#."))

    with open(SOURCE if path is None else path) as f:
        for line in f:
            line = line.rstrip("\n")
            if is_art(line):
                if key is None:
                    raise ValueError("art before any species key: %r" % line)
                rows.append(line)
            elif not line.strip() or line.startswith("#"):
                continue
            elif line.endswith(":"):
                flush()
                header = line[:-1].strip()
                rows = []
                if "." in header:
                    parts = header.split(".")
                    if len(parts) != 3:
                        raise ValueError("expected key.action.frame, got %r" % header)
                    key, action, index = parts[0], parts[1], parts[2]
                    if action not in set(a for _l, a, _m in VARIANTS):
                        raise ValueError("%s: unknown action %r" % (header, action))
                    try:
                        frame = int(index)
                    except ValueError:
                        raise ValueError("%s: frame must be a number" % header)
                else:
                    key, action, frame = header, None, None
                    if key in sprites:
                        raise ValueError("%s: duplicate entry" % key)
            else:
                raise ValueError("unparseable line: %r" % line)
    flush()

    # Frames arrive in file order; sort by index so the sheet is built in the
    # order the animation plays, whatever order they were written in.
    packed = {}
    for (k, a), frames in overrides.items():
        if k not in sprites:
            raise ValueError("%s.%s: no base grid for %r" % (k, a, k))
        seen = sorted(n for n, _g in frames)
        if seen != list(range(len(seen))):
            raise ValueError("%s.%s: frames must be numbered 0..n, got %s" % (k, a, seen))
        if len(seen) < 2:
            raise ValueError("%s.%s: needs at least two frames" % (k, a))
        packed[(k, a)] = [g for _n, g in sorted(frames)]

    return sprites, packed


# --- grid transforms -------------------------------------------------------
#
# Every one of these takes and returns a 24-row grid, and any ink pushed past an
# edge is dropped rather than wrapped. Callers keep that loss inside
# CLIP_TOLERANCE by way of clamp().


def down(rows, n=1):
    """The whole silhouette drops n rows."""
    return [BLANK] * n + rows[:GRID - n]


def up(rows, n=1):
    """The whole silhouette lifts n rows."""
    return rows[n:] + [BLANK] * n


def hshift(rows, which, dx):
    """Slide the given row indices sideways; positive dx moves right."""
    if dx == 0:
        return list(rows)
    out = []
    for i, row in enumerate(rows):
        if i in which:
            row = ("." * dx + row[:GRID - dx]) if dx > 0 else (row[-dx:] + "." * -dx)
        out.append(row)
    return out


def shear(rows, amount):
    """Lean the silhouette right, ramping from 0 at the feet to amount at the top."""
    if amount == 0:
        return list(rows)
    out = []
    for i, row in enumerate(rows):
        dx = amount * (GRID - 1 - i) // (GRID - 1)
        out.append(("." * dx + row)[:GRID])
    return out


def squash(rows, factor, floor):
    """Compress the silhouette vertically and rest it on the floor row.

    Source rows are OR-ed into their destination rather than sampled, so a limb
    that lands between two output rows thickens instead of disappearing.
    """
    filled = [i for i, r in enumerate(rows) if "#" in r]
    top, bottom = filled[0], filled[-1]
    span = bottom - top + 1
    height = max(1, int(round(span * factor)))

    packed = [["."] * GRID for _ in range(height)]
    for i in range(top, bottom + 1):
        dest = min(height - 1, (i - top) * height // span)
        for x, ch in enumerate(rows[i]):
            if ch == "#":
                packed[dest][x] = "#"

    out = [BLANK] * GRID
    start = max(0, floor - height + 1)
    for i, row in enumerate(packed[:floor - start + 1]):
        out[start + i] = "".join(row)
    return out


def mirror(rows):
    """Flip left to right. Free here, where a second bitmap on the watch is not."""
    return [row[::-1] for row in rows]


def ink(rows):
    return sum(row.count("#") for row in rows)


def clamp(rows, build, desired):
    """The largest magnitude, counting down from desired, that fits the budget.

    build(magnitude) returns the frames that magnitude would produce; the
    magnitude is acceptable when no frame loses more ink than CLIP_TOLERANCE.
    """
    budget = ink(rows) * CLIP_TOLERANCE
    for magnitude in range(desired, -1, -1):
        if all(ink(rows) - ink(f) <= budget for f in build(magnitude)):
            return magnitude
    return 0


def bob(rows):
    """Fallback second frame for a silhouette with no room to move sideways.

    A lift if the head allows it, otherwise a squash -- which always fits.
    """
    lifted = up(rows)
    if ink(rows) - ink(lifted) <= ink(rows) * CLIP_TOLERANCE:
        return lifted
    return squash(rows, 0.92, GRID - 2)


def frames_for(rows, action, clamps, override=None):
    """The frames of one action, recording any magnitude that clamped.

    An override is hand-drawn art for this action and is used verbatim: it is
    already the poses someone wanted, so deriving anything from it would only
    degrade it. It is also the only way a variant gets more than two frames.
    """
    if override is not None:
        return [list(g) for g in override]

    if action == "idle":
        return [list(rows), down(rows)]

    if action == "sleep":
        slumped = squash(rows, SLEEP_SQUASH, SLEEP_FLOOR)
        return [slumped, down(slumped)]

    if action == "walk":
        # Body and legs counter-swing: the torso goes one way, the feet the other.
        #
        # The legs are shifted by twice the body's magnitude because that shift lands on rows the
        # body shift already moved. At 1x they would only cancel it out, leaving the feet planted
        # at the origin in both frames and nothing but a sliding torso -- which read as a wobble,
        # not as walking. At 2x they end up displaced opposite the body, so the two frames differ
        # by a full stride at the feet as well as at the shoulders.
        def build(d):
            return [hshift(hshift(rows, ALL_ROWS, -d), LEGS, 2 * d),
                    hshift(hshift(rows, ALL_ROWS, d), LEGS, -2 * d)]

        d = clamp(rows, build, 2)
        if d == 0:
            clamps.append((action, "sideways swing"))
            return [list(rows), bob(rows)]
        return build(d)

    if action == "fight":
        # Frame B throws the whole body forward and up: a lunge, snapping back
        # to the neutral frame A.
        def build(f):
            return [list(rows), up(hshift(rows, ALL_ROWS, f))]

        f = clamp(rows, build, 2)
        if f == 0:
            clamps.append((action, "lunge reach"))
            return [list(rows), bob(rows)]
        return build(f)

    if action == "run":
        # The lean is the run. Legs split under it and the body leaves the
        # ground on frame B.
        def build(a):
            leaned = shear(rows, a)
            return [hshift(leaned, LEGS, 1), up(hshift(leaned, LEGS, -1))]

        a = clamp(rows, build, 3)
        if a == 0:
            clamps.append((action, "forward lean"))
            return [list(rows), bob(rows)]
        return build(a)

    raise ValueError("unknown action %r" % action)


# --- naming ----------------------------------------------------------------


#! One directory per species rather than 200-odd files in a flat drawables/.
#! The name stays prefixed inside the folder so a file is still identifiable on
#! its own -- in an editor tab, in a diff, in git status -- where a bare
#! idle.png would be one of thirty.
def png_name(key, label):
    return "%s/%s_%s.png" % (key, key, label)


def rez_id(key, label):
    parts = "".join(part.capitalize() for part in label.split("_"))
    return "%s%s" % (key.capitalize(), parts)


#! Files from earlier sprite schemes, all of which sat at the top level of
#! drawables/: <key>_0.png from before actions existed, <key>_<action>_0.png
#! from before both frames shared one bitmap, and <key>_<action>.png from
#! before the per-species directories. Matched narrowly -- the numbered forms
#! by shape, the flat form only against a live species key -- so nothing else
#! in the directory is ever a deletion candidate.
LEGACY_PNG = re.compile(r"^[a-z]+(_[a-z]+)*_[01]\.png$")


def superseded(names, keys):
    flat = tuple("%s_" % key for key in keys)
    return sorted(n for n in names
                  if n.endswith(".png")
                  and (LEGACY_PNG.match(n) or n.startswith(flat)))


# --- PNG encode / decode ---------------------------------------------------


def pixels(rows):
    """Flat RGBA bytes for the 3x upscale of a grid of 24-char rows."""
    out = bytearray()
    for row in rows:
        line = bytearray()
        for ch in row:
            line += (INK if ch == "#" else CLEAR) * SCALE
        out += line * SCALE
    return bytes(out)


def encode_png(raw, height=SHEET_H):
    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    # Filter type 0 on every scanline. The images are tiny and two-tone, so
    # nothing cleverer would pay for itself.
    stride = SIZE * 4
    scanlines = bytearray()
    for y in range(height):
        scanlines += b"\x00" + raw[y * stride:(y + 1) * stride]

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
            + chunk(b"IEND", b""))


def read_pixels(path, want_height=SHEET_H):
    """Decode one of our own PNGs back to flat RGBA, or None if unreadable.

    Only handles what encode_png produces plus the filter types the original
    hand-made sprites used, which is enough to tell "already correct" from
    "needs rewriting" without pulling in an image library.
    """
    try:
        with open(path, "rb") as f:
            data = f.read()
    except IOError:
        return None
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None

    pos = 8
    idat = bytearray()
    width = height = depth = color = None
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        pos += 12 + length

    if (width, height, depth, color) != (SIZE, want_height, 8, 6):
        return None

    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error:
        return None

    stride = SIZE * 4
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _ in range(want_height):
        if pos >= len(raw):
            return None
        ft = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        if len(line) != stride:
            return None
        pos += 1 + stride
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if ft == 0:
                pass
            elif ft == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ft == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ft == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
            else:
                return None
        out += line
        prev = line
    return bytes(out)


def normalise(raw):
    """Collapse to what actually renders: any fully transparent pixel is the
    same pixel regardless of the RGB bytes sitting underneath it."""
    out = bytearray(raw)
    for i in range(3, len(out), 4):
        if out[i] == 0:
            out[i - 3:i] = b"\x00\x00\x00"
    return bytes(out)


# --- generated companions --------------------------------------------------


def drawables_xml(keys):
    lines = ["<drawables>",
             '    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>',
             "",
             "    <!-- Five action states per creature, plus a mirrored lunge and lean for creatures",
             "         facing left. Each file holds every frame of its state, stacked top to bottom.",
             "         All generated from tools/sprites/sprites.txt by",
             "         tools/sprites/generate_sprites.py. Edit the ASCII there, not these PNGs, and",
             "         not this list. -->"]
    for key in keys:
        for label, _action, _mirrored in VARIANTS:
            lines.append('    <bitmap id="%s" filename="%s"/>'
                         % (rez_id(key, label), png_name(key, label)))
    lines.append("</drawables>")
    return "\n".join(lines) + "\n"


def index_mc(keys, counts):
    lines = ["import Toybox.Lang;",
             "import Toybox.WatchUi;",
             "",
             "//! Species key -> drawable ids, generated by tools/sprites/generate_sprites.py.",
             "//!",
             "//! Do not edit: rerun the generator. Each species maps to one array of slots, where",
             "//! the first five are the ACTION_* values in order and the last two are the",
             "//! left-facing lunge and lean. A slot's bitmap holds all of its frames stacked, so",
             "//! Sprites clips to the slice it wants. Flat rather than nested because this table is",
             "//! built lazily on a watch and an array of ids is the cheapest shape that works.",
             "module SpriteIndex {",
             "",
             "    function build() as Dictionary<String, Array<ResourceId> > {",
             "        return {"]
    for n, key in enumerate(keys):
        ids = ["Rez.Drawables." + rez_id(key, label)
               for label, _action, _mirrored in VARIANTS]
        lines.append('            "%s" => [' % key)
        for start in range(0, len(ids), 4):
            row = ", ".join(ids[start:start + 4])
            lines.append("                " + row + ("," if start + 4 < len(ids) else ""))
        lines.append("            ]" + ("," if n < len(keys) - 1 else ""))
    lines += ["        };", "    }", ""]

    slot_of = dict((label, n) for n, (label, _a, _m) in enumerate(VARIANTS))
    lines += [
        "    //! Frames in one species' variant, when it is not the usual two.",
        "    //!",
        "    //! An if-chain over just the exceptions rather than a table: almost every variant is",
        "    //! two frames, so the common answer should cost no allocation and no lookup. Hand-drawn",
        "    //! overrides are the only source of anything else.",
        "    function frameCount(key as String, slot as Number) as Number {"]
    if counts:
        for (key, label) in sorted(counts):
            lines.append('        if (slot == %d && key.equals("%s")) { return %d; }'
                         % (slot_of[label], key, counts[(key, label)]))
    lines += [
        "        return %d;" % FRAMES,
        "    }",
        "}",
        ""]
    return "\n".join(lines)


def sync_text(path, want, check_only, stale):
    try:
        with open(path) as f:
            have = f.read()
    except IOError:
        have = None
    if have == want:
        return False
    stale.append(os.path.relpath(path, REPO))
    if not check_only:
        with open(path, "w") as f:
            f.write(want)
    return True


def main(argv):
    check_only = "--check" in argv[1:]
    sprites, overrides = parse(None)
    keys = list(sprites.keys())

    # slot -> frame count, for the variants that are not the usual two.
    counts = {}

    written = 0
    unchanged = 0
    stale = []
    clamped = []

    for key, rows in sprites.items():
        clamps = []
        for label, action, mirrored in VARIANTS:
            # A mirrored variant is the same transform seen from the other side, so it clamps
            # identically -- reporting it again would just double every note.
            override = overrides.get((key, action))
            frames = frames_for(rows, action, [] if mirrored else clamps, override)
            if mirrored:
                frames = [mirror(grid) for grid in frames]
            if len(frames) != FRAMES:
                counts[(key, label)] = len(frames)

            path = os.path.join(OUTDIR, png_name(key, label))
            # Frames stacked top to bottom: one bitmap, clipped to a slice at draw time.
            stacked = []
            for grid in frames:
                stacked += grid
            want = pixels(stacked)
            have = read_pixels(path, SIZE * len(frames))

            if have is not None and normalise(have) == normalise(want):
                unchanged += 1
                continue

            stale.append(os.path.relpath(path, REPO))
            if check_only:
                continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(encode_png(want, SIZE * len(frames)))
            written += 1
        for action, what in clamps:
            clamped.append("%s %s: no room for the %s, using a bob instead"
                           % (key, action, what))

    sync_text(DRAWABLES_XML, drawables_xml(keys), check_only, stale)
    sync_text(INDEX_MC, index_mc(keys, counts), check_only, stale)

    legacy = superseded(os.listdir(OUTDIR), sprites.keys())
    for name in legacy:
        stale.append(os.path.relpath(os.path.join(OUTDIR, name), REPO) + " (superseded)")
        if not check_only:
            os.remove(os.path.join(OUTDIR, name))

    for line in clamped:
        sys.stderr.write("note: %s\n" % line)

    if check_only:
        if stale:
            sys.stderr.write("out of date:\n  %s\n" % "\n  ".join(stale))
            return 1
        print("%d sprites up to date" % unchanged)
        return 0

    print("%d species x %d variants (2 frames each): %d written, %d already correct, %d removed"
          % (len(sprites), len(VARIANTS), written, unchanged, len(legacy)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
