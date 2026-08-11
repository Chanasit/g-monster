"""The body states: idle, move, sleep, fight. One set of knobs each, so the
volume arithmetic is checkable rather than asserted."""
from pose import pose, zed, fight

# half, height, lift. `half * height` is what holds the volume: 28 * 45 at rest,
# and every other row here is within a few percent of that product.
IDLE = [(28, 45, 0), (31, 40, 0), (28, 45, 0), (25, 51, 0)]
MOVE = [(31, 40, 0), (23, 54, 0), (26, 48, 9), (32, 39, 0)]
# The land frame is the widest pose there is; its eyes come back in a couple of
# columns so the right one keeps 3px of ink between it and the flank.
MOVE_EYE_DX = [0, 0, 0, -2]
# Neutral, then settled three rows shorter and four columns wider: 2238 and
# 2207 solid cells against the base grid's 2224, so the breath redistributes the
# slime instead of deflating it.
SLEEP_BODY = [(31, 41, 0), (33, 38, 0)]

# Bottom to top: three columns left and eleven rows up each step. Both numbers
# are load-bearing. The glyphs are 9 tall, so a pitch of 11 leaves two clear rows
# between them, 10 leaves one, and 9 has them touching and merged into a bar. And
# the lowest z has to stay clear of the dome -- four columns, measured -- or it
# reads as a horn growing out of the creature rather than a breath leaving it.
Z_STEPS = [(62, 22), (59, 11), (56, 0)]


def frames():
    out = {}

    # ---- idle: neutral / squash / neutral / stretch
    out['idle'] = [pose(h, v, lift=l)[0] for h, v, l in IDLE]

    # ---- move: crouch / launch / apex / land -- a hop, not a stride
    out['move'] = [pose(h, v, lift=l, eye_dx=d)[0]
                   for (h, v, l), d in zip(MOVE, MOVE_EYE_DX)]

    # ---- sleep: shut lids, a body breathing under them, and the z stream
    sleep = []
    for i in range(4):
        h, v, l = SLEEP_BODY[i % 2]
        g = pose(h, v, lids=True)[0]
        # 1 z, 2 z, 3 z, then the lowest one gone: the stream fills, then its
        # bottom dissipates, so the loop restarts without every z popping.
        show = [Z_STEPS[:1], Z_STEPS[:2], Z_STEPS[:3], Z_STEPS[1:]][i]
        for x, y in show:
            zed(g, x, y, s=9)
        sleep.append(g)
    out['sleep'] = sleep

    # ---- fight: reared, sheared over the leading edge, facing right
    out['fight'] = [
        fight(44, 11, 34, 16, 30, ((39, 24), (45, 17), (51, 19), 5, 3))[0],
        fight(47, 14, 36, 16, 33, ((42, 27), (48, 20), (54, 22), 5, 3))[0],
    ]
    return out
