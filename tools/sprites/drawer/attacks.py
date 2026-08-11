"""rock / paper / scissors -- the three attacks on the combat wheel.

Nothing derives these, and they are the one place the slime stops holding its
volume: a hammer at the creature's own 1898 cells is a bar joined to a bar of
its own width, which is a bent tube rather than a T. Each attack conserves its
own volume across its two frames, which is what stops the weapon growing
between them.

All three face right, because ACTION_*_LEFT is the generated mirror and the
enemy plays it.
"""
import math
from draw import *
from pose import pose


def slab(g, cx, cy, w, h, deg=0.0, ch='#'):
    """Filled rectangle, rotated about its centre. Sampled from the destination
    so a rotation never leaves holes in the middle of the slab."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    r = int(math.hypot(w, h) / 2) + 2
    for y in range(max(0, cy - r), min(SIZE, cy + r + 1)):
        for x in range(max(0, cx - r), min(SIZE, cx + r + 1)):
            dx, dy = x - cx, y - cy
            u, v = dx * ca + dy * sa, -dx * sa + dy * ca
            if abs(u) <= w / 2 and abs(v) <= h / 2:
                g[y][x] = ch
    return g


def ring(g, cx, cy, r_out, thick, gap_deg=(-45, 45), ch='#'):
    """Annulus with one sector left out. Closing the ring reads as a doughnut --
    one big hole ringed by ink is a shape with no direction in it, and direction
    is the one thing an attack has to have. gap_deg is measured with 0 to the
    right, positive downward."""
    lo, hi = gap_deg
    for y in range(max(0, cy - r_out - 1), min(SIZE, cy + r_out + 2)):
        for x in range(max(0, cx - r_out - 1), min(SIZE, cx + r_out + 2)):
            d = math.hypot(x - cx, y - cy)
            if not (r_out - thick <= d <= r_out):
                continue
            ang = math.degrees(math.atan2(y - cy, x - cx))
            if lo <= ang <= hi:
                continue
            g[y][x] = ch
    return g


def face(g, x0, y0, w=8, h=16, gap=5, vertical=False):
    """Two tall rectangles. No mouth -- the reference has none, and on a slab
    this thick a third hole is what turns a face into a bitten edge."""
    if vertical:
        rect(g, x0, x0 + h - 1, y0, y0 + w - 1)
        rect(g, x0, x0 + h - 1, y0 + w + gap, y0 + 2 * w + gap - 1)
    else:
        rect(g, x0, x0 + w - 1, y0, y0 + h - 1)
        rect(g, x0 + w + gap, x0 + 2 * w + gap - 1, y0, y0 + h - 1)
    return g


# ------------------------------------------------------------------ ATTACK_CRUSH
def rock(frame):
    """The slime does not pick a hammer up, it becomes one. There is no torso in
    either frame -- the whole silhouette is head and handle, and the eyes punched
    into the head are the only thing left saying which creature this is.

    Frame 0 is cocked, the head lying across the top with the handle dropping
    from under its middle to the left. Frame 1 is the impact: a rotation of about
    ninety degrees, the butt staying down at the left while the head swings to a
    slab standing on the floor row. Reaching the floor is the whole point -- a
    pound that stops short of it is a wave."""
    g = blank()
    if frame == 0:
        slab(g, 40, 15, 54, 26)                      # head, across the top
        stroke(g, (38, 28), (30, 43), (16, 61), 15, 12, ch='#', only_on=None)
        face(g, 30, 7, 8, 16, 6)
    else:
        slab(g, 52, 42, 32, 49)                      # head, standing, on row 67
        stroke(g, (36, 40), (26, 51), (14, 61), 15, 12, ch='#', only_on=None)
        face(g, 40, 28, 8, 16, 6, vertical=True)     # the face rotates with it
    return g


# ------------------------------------------------------------------ ATTACK_ABILITY
def paper(frame):
    """The slime does not throw water, it becomes the wave. The curl is a ring
    with its right quarter missing, so the barrel is open toward the target. The
    flat band of water under it is load-bearing: a curl drawn on its own is a
    shell, and the water is what makes it read as sea.

    Frame 1 is the pitch -- the whole curl rolls right and down and the lip
    extends further out and further under, so the barrel narrows from above
    while its mouth stays open. The water and the face do not move."""
    g = blank()
    dx, dy = (0, 0) if frame == 0 else (2, 2)
    # The sea first, so the curl can stand on it. It is load-bearing: a curl
    # drawn on its own is a shell, and the flat water is what makes it sea. Its
    # surface is stepped in rather than cut square -- a square corner at this
    # size reads as a crate the wave is standing on.
    rect(g, 4, 67, 50, FLOOR, '#')
    for k, y in enumerate(range(46, 50)):
        rect(g, 4 + (4 - k) * 4, 67 - (4 - k) * 4, y, y, '#')
    # The curl is a hook, not a ring. An annulus with a bite out of it reads as
    # a doughnut however the bite is aimed; a hook leaves the barrel open to the
    # background on the right, which is the only way the mouth stays a mouth.
    stroke(g, (14 + dx, 52), (14 + dx, 12 + dy), (44 + dx, 14 + dy), 16, 11,
           ch='#', only_on=None)
    # The lip is thrown out past the mouth and tucks back under itself, tapering
    # as it goes. A hook that only descends is a wall of water; the inward tuck
    # is the difference between a breaking wave and a slope.
    tip = (52 + dx * 2, 18 + dy)
    stroke(g, (44 + dx, 14 + dy), tip, (50 + dx, 34 + dy), 11, 5,
           ch='#', only_on=None)
    face(g, 38, 54, 8, 11, 6)                        # in the water, not the arc
    spec = gloss_fit(g, 12, 56, 5, 3)
    if spec:
        stroke(g, *spec)
    return g


# ------------------------------------------------------------------ ATTACK_ENERGY
def scissors(frame):
    """A chakram: a ring of goo held up and back, then thrown down and forward.
    The ring stays attached by an arm tapering out of the crest, and that is not
    decoration -- a hoop floating clear of the creature is a second object, and
    this slime does not pick weapons up. The arm is what says the ring is still
    part of it."""
    dx, dy = (0, 0) if frame == 0 else (3, 5)
    g, _ = pose(32, 33, gloss_on=False)              # squatter than the idle
    cx_, cy_ = 52 + dx, 20 + dy
    # Carried forward and high on frame 0, thrown down and further forward on
    # frame 1. Forward rather than back, and off to the side rather than over the
    # crest: a hoop centred on top of the dome reads as a head, and a head with
    # a neck is not this creature. The arm is a stalk at 8 cells, not a neck at
    # 12 -- a hoop floating clear would be a second object, and this slime does
    # not pick weapons up.
    stroke(g, (42, 37), (45, 33), (cx_ - 5, cy_ + 7), 10, 6, ch='#', only_on=None)
    ring(g, cx_, cy_, 15, 8, gap_deg=(200, 201))
    spec = gloss_fit(g, 24, 40, 5, 3)
    if spec:
        stroke(g, *spec)
    return g


def attacks():
    return {'rock': [rock(0), rock(1)],
            'paper': [paper(0), paper(1)],
            'scissors': [scissors(0), scissors(1)]}
