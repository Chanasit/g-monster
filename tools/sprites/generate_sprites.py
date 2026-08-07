#!/usr/bin/env python3
"""Emit creature sprite PNGs from the ASCII art in sprites.txt.

The watch app wants two idle frames per species. Only frame A is authored; frame
B is frame A shifted down one row, which is what reads as a breath when the two
alternate at 500ms. Deriving B mechanically means the artist only ever maintains
one grid and the two frames cannot drift apart.

Output matches the sprites that shipped before this script existed: 24x24 scaled
3x with nearest-neighbour to 72x72, and exactly two colours -- opaque black for
ink, fully transparent for everything else. Two colours is not an aesthetic
choice, it is the app's: Theme keeps the whole UI two-tone, so a sprite with
anti-aliased edges would be the only soft thing on the screen.

Stdlib only (zlib, struct) so this runs on a bare checkout with no pip install.

    python3 tools/sprites/generate_sprites.py [--check]

--check verifies the PNGs on disk match what the ASCII would produce and exits
non-zero if not, without writing anything.
"""

import os
import struct
import sys
import zlib

SCALE = 3
GRID = 24
SIZE = GRID * SCALE

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SOURCE = os.path.join(HERE, "sprites.txt")
OUTDIR = os.path.join(REPO, "resources", "drawables")

INK = b"\x00\x00\x00\xff"
CLEAR = b"\x00\x00\x00\x00"


def parse(path):
    """sprites.txt -> {key: [24 rows of 24 chars]}, in file order."""
    sprites = {}
    key = None
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
        # Frame B shifts everything down one row, so anything on the last row
        # would fall off the bottom of the bitmap.
        if "#" in rows[GRID - 1]:
            raise ValueError("%s: last row must be blank (frame B shifts down 1)" % key)
        if not any("#" in r for r in rows):
            raise ValueError("%s: sprite is empty" % key)
        sprites[key] = list(rows)

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
                key = line[:-1].strip()
                rows = []
                if key in sprites:
                    raise ValueError("%s: duplicate entry" % key)
            else:
                raise ValueError("unparseable line: %r" % line)
    flush()
    return sprites


def breathe(rows):
    """Frame B: the whole silhouette drops one row."""
    return ["." * GRID] + rows[:GRID - 1]


def pixels(rows):
    """Flat RGBA bytes for the 72x72 upscale of a 24x24 grid."""
    out = bytearray()
    for row in rows:
        line = bytearray()
        for ch in row:
            line += (INK if ch == "#" else CLEAR) * SCALE
        out += line * SCALE
    return bytes(out)


def encode_png(raw):
    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    # Filter type 0 on every scanline. The images are tiny and two-tone, so
    # nothing cleverer would pay for itself.
    stride = SIZE * 4
    scanlines = bytearray()
    for y in range(SIZE):
        scanlines += b"\x00" + raw[y * stride:(y + 1) * stride]

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
            + chunk(b"IEND", b""))


def read_pixels(path):
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

    if (width, height, depth, color) != (SIZE, SIZE, 8, 6):
        return None

    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error:
        return None

    stride = SIZE * 4
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _ in range(SIZE):
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


def main(argv):
    check_only = "--check" in argv[1:]
    sprites = parse(None)

    written = 0
    unchanged = 0
    stale = []

    for key, rows in sprites.items():
        for suffix, frame in (("0", rows), ("1", breathe(rows))):
            path = os.path.join(OUTDIR, "%s_%s.png" % (key, suffix))
            want = pixels(frame)
            have = read_pixels(path)

            if have is not None and normalise(have) == normalise(want):
                unchanged += 1
                continue

            stale.append(os.path.relpath(path, REPO))
            if check_only:
                continue
            with open(path, "wb") as f:
                f.write(encode_png(want))
            written += 1

    if check_only:
        if stale:
            sys.stderr.write("out of date:\n  %s\n" % "\n  ".join(stale))
            return 1
        print("%d sprites up to date" % unchanged)
        return 0

    print("%d species: %d written, %d already correct"
          % (len(sprites), written, unchanged))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
