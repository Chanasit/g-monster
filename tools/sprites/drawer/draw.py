#!/usr/bin/env python3
"""Parametric slime drawer. Emits 72x72 #/. grids for sprites.txt.

Reference: tools/sprites/ascii/tmp/input_161924.png -- a 14x11 pixel-art slime,
flat-bottomed dome with square shoulders, two tall rectangular eyes set right of
centre, no mouth, highlight on the upper right.
"""
import math

SIZE = 72
FLOOR = 67          # lowest ink row; 68-71 stay clear (reserve is 3 at 72)


def blank():
    return [['.'] * SIZE for _ in range(SIZE)]


def ink(g):
    return sum(r.count('#') for r in g)


def bbox(g):
    xs = [c for r in g for c, v in enumerate(r) if v == '#']
    ys = [i for i, r in enumerate(g) if '#' in r]
    return min(xs), max(xs), min(ys), max(ys)


def to_text(g):
    return '\n'.join(''.join(r) for r in g)


# ---------------------------------------------------------------- silhouette
def body(g, cx, top, floor, half, n=2.6, flank=0.0):
    """Flat-bottomed superellipse: |x/half|^n + |y/h|^n = 1, lower half only.
    n=2 is a plain dome; n=2.6 squares the shoulders and stands the flanks up
    over the bottom third, which is what the reference does at 14px wide.
    flank shears the whole shape right, strongest at the crest."""
    h = floor - top
    for y in range(top, floor + 1):
        t = (y - top) / h
        w = half * (1.0 - (1.0 - t) ** n) ** (1.0 / n)
        sh = flank * (1.0 - t)
        lo = int(round(cx + sh - w))
        hi = int(round(cx + sh + w))
        for x in range(max(0, lo), min(SIZE - 1, hi) + 1):
            g[y][x] = '#'
    return g


def rect(g, x0, x1, y0, y1, ch='.'):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= y < SIZE and 0 <= x < SIZE:
                g[y][x] = ch
    return g


def eyes(g, cx, cy, w, h, gap):
    """Two tall rectangles, w x h, separated by gap columns of ink."""
    x0 = cx - gap // 2 - w
    rect(g, x0, x0 + w - 1, cy, cy + h - 1)
    rect(g, cx + gap // 2 + 1, cx + gap // 2 + w, cy, cy + h - 1)
    return g


def gloss(g, cx, cy, r_out, r_in, dx, dy, thick_from=None):
    """Tilted crescent: inside the outer disc, outside the inner one."""
    for y in range(cy - r_out, cy + r_out + 1):
        for x in range(cx - r_out, cx + r_out + 1):
            if not (0 <= x < SIZE and 0 <= y < SIZE):
                continue
            d0 = math.hypot((x - cx) / 1.0, (y - cy) / 0.78)
            d1 = math.hypot((x - cx - dx) / 1.0, (y - cy - dy) / 0.78)
            if d0 <= r_out and d1 > r_in and g[y][x] == '#':
                g[y][x] = '.'
    return g


# ------------------------------------------------------------------- preview
def preview(grids, path, scale=4, cols=None):
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit('preview needs Pillow (pip install pillow). Everything else here is '
                         'stdlib, so a bare checkout can still check and write grids.')
    cols = cols or len(grids)
    rows = (len(grids) + cols - 1) // cols
    pad = 4
    W = cols * (SIZE + pad) * scale
    H = rows * (SIZE + pad) * scale
    im = Image.new('RGB', (W, H), (210, 210, 210))
    px = im.load()
    for i, g in enumerate(grids):
        ox = (i % cols) * (SIZE + pad) * scale
        oy = (i // cols) * (SIZE + pad) * scale
        for y in range(SIZE):
            for x in range(SIZE):
                col = (0, 0, 0) if g[y][x] == '#' else (255, 255, 255)
                for dy in range(scale):
                    for dx in range(scale):
                        px[ox + x * scale + dx, oy + y * scale + dy] = col
    im.save(path)
    return path


# ------------------------------------------------------------------ validate
def _comps(g, ch):
    from collections import deque
    seen = [[False] * SIZE for _ in range(SIZE)]
    out = []
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] == ch and not seen[y][x]:
                q = deque([(y, x)]); seen[y][x] = True; comp = []
                edge = False
                while q:
                    a, b = q.popleft(); comp.append((a, b))
                    if a in (0, SIZE - 1) or b in (0, SIZE - 1):
                        edge = True
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        na, nb = a + dy, b + dx
                        if 0 <= na < SIZE and 0 <= nb < SIZE and g[na][nb] == ch and not seen[na][nb]:
                            seen[na][nb] = True; q.append((na, nb))
                out.append((comp, edge))
    return out


def holes(g):
    return [c for c, edge in _comps(g, '.') if not edge]


def _gap(a, b):
    return min(max(abs(y1 - y2), abs(x1 - x2)) for y1, x1 in a for y2, x2 in b) - 1


def validate(g, name='grid', min_gap=3, quiet=False):
    """Grid contract + the house rules that no script downstream checks."""
    bad = []
    if len(g) != SIZE or any(len(r) != SIZE for r in g):
        bad.append('not 72x72')
    for y in range(SIZE - 3, SIZE):
        if '#' in g[y]:
            bad.append(f'ink in reserved row {y}')
    hs = holes(g)
    bg = [c for c, edge in _comps(g, '.') if edge]
    for i, h in enumerate(hs):
        d = min(_gap(h, b) for b in bg)
        if d < min_gap:
            bad.append(f'hole {i} ({len(h)} cells) only {d}px from the outline')
    for i in range(len(hs)):
        for j in range(i + 1, len(hs)):
            d = _gap(hs[i], hs[j])
            if d < min_gap:
                bad.append(f'holes {i}/{j} only {d}px apart')
    x0, x1, y0, y1 = bbox(g)
    if not quiet:
        print(f'{name:18} ink {ink(g):5}  cols {x0}-{x1} ({x1-x0+1}w)  '
              f'rows {y0}-{y1} ({y1-y0+1}h)  holes {sorted(len(h) for h in hs)}')
        for b in bad:
            print(f'  !! {name}: {b}')
    return bad


# -------------------------------------------------------------------- stroke
def bez(p0, c, p1, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
            u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1])


def stroke(g, p0, c, p1, w0, w1=None, ch='.', only_on='#'):
    """Quadratic bezier stroke, width tapering w0 -> w1, stamped as discs so it
    never leaves a diagonal-only orphan the way a disc difference does."""
    w1 = w0 if w1 is None else w1
    n = 240
    for i in range(n + 1):
        t = i / n
        x, y = bez(p0, c, p1, t)
        r = (w0 + (w1 - w0) * t) / 2.0
        for dy in range(int(-r) - 1, int(r) + 2):
            for dx in range(int(-r) - 1, int(r) + 2):
                px_, py_ = int(round(x)) + dx, int(round(y)) + dy
                if not (0 <= px_ < SIZE and 0 <= py_ < SIZE):
                    continue
                if math.hypot(px_ - x, py_ - y) <= r and (only_on is None or g[py_][px_] == only_on):
                    g[py_][px_] = ch
    return g


def specks(g, ch='.'):
    """Hole components of 1-2 cells: the 3px-speck failure mode, as a count."""
    return [c for c in holes(g) if len(c) <= 2]


def body_asym(g, crest_x, top, floor, half_l, half_r, n_l=1.5, n_r=4.0):
    """A silhouette with a different profile on each side, for the fight stance.
    A blob turning has no ear to occlude and no limb to put edge-on, so the turn
    has to be in the mass: the rear falls away from the crest in one long slope
    (low n) while the leading edge stands up steep and boxy (high n)."""
    h = floor - top
    for y in range(top, floor + 1):
        t = (y - top) / h
        wl = half_l * (1.0 - (1.0 - t) ** n_l) ** (1.0 / n_l)
        wr = half_r * (1.0 - (1.0 - t) ** n_r) ** (1.0 / n_r)
        lo, hi = int(round(crest_x - wl)), int(round(crest_x + wr))
        for x in range(max(0, lo), min(SIZE - 1, hi) + 1):
            g[y][x] = '#'
    return g


def gloss_fit(g, x, y, w0=5, w1=3, span=11, cx=35):
    """Place the highlight crescent at (x, y), or at the nearest offset from it
    that still leaves a hole with 3px of ink on every side.

    Arithmetic alone does not settle this. A quadratic bulges toward its control
    point, so a curve whose endpoints clear the outline can still break it at the
    apex, and every deformation moves the apex somewhere new. So the placement is
    tried and checked rather than computed: the first offset that validates wins,
    searched inward and downward because that is where the ink is."""
    before = len(holes(g))
    # Nearest offset first, ties going to whichever sits closer to the centre
    # line -- the ink runs out at the flanks, so inward is where a fit is found.
    offsets = sorted(((dx, dy) for dx in range(-16, 17) for dy in range(-10, 11)),
                     key=lambda o: (abs(o[0]) + abs(o[1]), abs(x + o[0] - cx)))
    for dx, dy in offsets:
        spec = ((x + dx, y + dy + 4), (x + dx + span // 2, y + dy - 3),
                (x + dx + span, y + dy - 1), w0, w1)
        trial = [r[:] for r in g]
        stroke(trial, *spec)
        if (len(holes(trial)) == before + 1 and not specks(trial)
                and not validate(trial, quiet=True)):
            return spec
    return None
