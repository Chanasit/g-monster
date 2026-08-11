"""One slime, deformed. Every pose is the base grid's geometry scaled about the
floor, so the eyes and the gloss ride the deformation instead of sitting still
while the body moves around them -- holding them put is what makes a squashed
sprite look like a resized sprite.

Volume is the invariant: a slime holds a fixed amount of goo, so `half * height`
is held near the base grid's 28 * 45 -- 2224 cells of silhouette once drawn --
and what a pose loses in height it gains in width. Count the silhouette rather
than the ink when checking that: a closed eye removes fewer cells than an open
one, so the sleep frames run 78 ink cells heavy on the lids alone. The attacks
break the invariant on purpose and say so in their own notes.
"""
from draw import *
from base import CX, TOP, HALF, GLOSS

BASE_H = FLOOR - TOP          # 45
EYE_X0, EYE_X1, EYE_Y = 25, 46, 42
EYE_W, EYE_H = 8, 16


def pose(half=HALF, height=BASE_H, lift=0, flank=0.0, n=2.6,
         eye_dx=0, lids=False, gloss_on=True, face=True, cx=CX):
    """half/height deform the silhouette; lift raises the whole body off the
    floor. Feature coordinates are mapped through the same scale."""
    floor = FLOOR - lift
    top = floor - height
    sx, sy = half / HALF, height / BASE_H
    X = lambda x: int(round(cx + (x - CX) * sx))
    Y = lambda y: int(round(floor - (FLOOR - y) * sy))

    g = blank()
    body(g, cx, top, floor, half, n, flank)
    solid = ink(g)

    ew, eh = max(4, int(round(EYE_W * sx))), max(6, int(round(EYE_H * sy)))
    ey = Y(EYE_Y)
    # The lean carries the face over the leading edge with the mass; on a blob
    # there is no ear to occlude and no limb to turn, so the eyes moving with
    # the shear is the whole of the head turn.
    lean = int(round(flank * 0.6)) + eye_dx
    lx, rx = X(EYE_X0) + lean, X(EYE_X1) + lean
    if face:
        if lids:
            for ex in (lx + ew // 2, rx + ew // 2):
                y = ey + eh // 2
                stroke(g, (ex - 6, y - 2), (ex, y + 4), (ex + 6, y - 2), 5, 5)
        else:
            rect(g, lx, lx + ew - 1, ey, ey + eh - 1)
            rect(g, rx, rx + ew - 1, ey, ey + eh - 1)
    if gloss_on:
        # Pinned above the eyes rather than to the crest, and at a fixed size:
        # fixed to the crest the highlight lands on the eye in the flattest
        # frames, and two holes that touch are one hole -- which reads as damage
        # to the silhouette, not as a face. Scaling it with the body was worse
        # still: the crescent grew a fifth between the idle's neutral and squash
        # frames, and a highlight that changes area on its own is a glitch, not a
        # breath. So every pose wears the same crescent, carried by the socket.
        (_p0, _c, _p1, w0, w1) = GLOSS
        spec = gloss_fit(g, lx + 7, ey - 8, w0, w1, span=11, cx=cx)
        if spec:
            stroke(g, *spec)
    return g, solid


# ------------------------------------------------------------------- the z's
def zed(g, x, y, s=9, t=3):
    """A z: two bars and the diagonal joining them, s across and t thick. 9 by 3
    is the smallest that still reads -- below 3 the diagonal stops separating the
    two arms at 1x, and the glyph closes into a bar."""
    rect(g, x, x + s - 1, y, y + t - 1, '#')
    rect(g, x, x + s - 1, y + s - t, y + s - 1, '#')
    for i in range(s):                       # top right down to bottom left
        for k in range(t):
            xx = min(x + s - 1, max(x, x + s - 1 - i + k))
            g[y + i][xx] = '#'
    return g


# ------------------------------------------------------------------ the lean
def fight(crest_x, top, half_l, half_r, eye_y, gloss_at, n_l=1.5, n_r=4.0):
    """The stance. Not the dome shoved sideways -- that carries no direction at
    all, and ACTION_FIGHT_LEFT is this grid mirrored, so a direction is the one
    thing it must have. The crest is carried out over the leading edge, the rear
    falls away left in one unbroken slope, and the eyes ride forward with it."""
    g = blank()
    body_asym(g, crest_x, top, FLOOR, half_l, half_r, n_l, n_r)
    solid = ink(g)
    # 5 columns of ink between the sockets, not 3: at 3 they read as one wide
    # window with a bar down it rather than as two eyes.
    rect(g, crest_x - 8, crest_x - 1, eye_y, eye_y + 15)
    rect(g, crest_x + 5, crest_x + 12, eye_y, eye_y + 15)
    stroke(g, *gloss_at)
    return g, solid
