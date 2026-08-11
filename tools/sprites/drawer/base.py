"""The knobs every slime pose deforms.

Reference: ../assets/slime-reference.png -- a 14x11 pixel-art slime. What is
taken from it: a flat-bottomed dome wider than it is tall with square shoulders,
two tall rectangular eyes set right of centre, no mouth, and the light coming
from the upper right.

There is no base-grid function here. `pose()` with its defaults *is* the base
grid, and it is also `idle.0`, which is the point: if the neutral pose were drawn
by a second code path the two would drift apart, and the drift would be invisible
until someone diffed two bitmaps that are meant to be identical.
"""

# 57 columns against 46 rows: the reference's 14x11 aspect, and narrow enough
# that the crouch and the lean can gain their volume sideways without the flanks
# being cut off square by the canvas edge.
CX, TOP, HALF = 35, 22, 28

# p0, control, p1, width at p0, width at p1. Only the widths are read now -- the
# points are the shape this crescent was struck at, kept because gloss_fit()
# searches outward from a position rather than inventing a curve.
GLOSS = ((34, 36), (40, 28), (45, 30), 5, 3)
