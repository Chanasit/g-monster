#!/usr/bin/env python3
"""Redraw slime's 21 grids in sprites.txt.

`slime` is the one species whose grids are struck by code rather than by hand.
The reason is the 72 promotion: at 1x a pose is a curve and a volume, both of
which are arithmetic, and 21 frames of 72 rows is more than anyone will re-derive
by eye when a proportion changes. So the shapes live here and `sprites.txt` stays
the artifact -- the parser, the generator and `--check` all still read the text,
and nothing downstream knows this file exists.

    python3 tools/sprites/drawer/redraw_slime.py                 # check, no writes
    python3 tools/sprites/drawer/redraw_slime.py --write          # rewrite the grids
    python3 tools/sprites/drawer/redraw_slime.py --preview p.png  # contact sheet

Only the 72 art rows under each `slime*:` header are ever rewritten. The notes
above them are hand-written prose and this script does not generate, move or read
them -- which means it cannot keep them true either. If a shape changes here, the
note in `sprites.txt` is yours to correct. See *Hand-authored motion (overrides)*
in ../CLAUDE.md.

Stdlib only, except `--preview`, which needs Pillow.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from draw import SIZE, ink, holes, specks, to_text, validate      # noqa: E402
from pose import pose, BASE_H                                     # noqa: E402
from base import HALF                                             # noqa: E402
from frames import frames                                         # noqa: E402
from attacks import attacks                                       # noqa: E402

SPRITES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sprites.txt')
HEADER = re.compile(r'^(slime(?:\.[a-z]+\.\d+)?):\s*$')


def build():
    """Every slime grid, keyed exactly as sprites.txt keys it. The base grid is
    `pose()` at its defaults, which is idle.0 -- one drawing, not two."""
    grids = {'slime': pose(HALF, BASE_H)[0]}
    for group in (frames(), attacks()):
        for action, gs in group.items():
            for i, g in enumerate(gs):
                grids['slime.%s.%d' % (action, i)] = g
    return grids


def blocks(lines):
    """(key, first art row, row after the last) for each slime block in the file."""
    out = []
    for i, line in enumerate(lines):
        m = HEADER.match(line)
        if not m:
            continue
        start = i + 1
        end = start
        while end < len(lines) and len(lines[end]) == SIZE and set(lines[end]) <= set('#.'):
            end += 1
        if end - start != SIZE:
            sys.exit('%s: %d art rows in sprites.txt, expected %d' % (m.group(1), end - start, SIZE))
        out.append((m.group(1), start, end))
    return out


def check_grids(grids):
    """The house rules nothing downstream enforces: the parser will happily accept
    a grid whose highlight has merged with an eye, and --check will happily call
    the PNG of it up to date."""
    bad = 0
    for key in sorted(grids):
        g = grids[key]
        faults = validate(g, key, quiet=True)
        sp = specks(g)
        if sp:
            faults = faults + ['%d speck holes of 1-2 cells' % len(sp)]
        solid = ink(g) + sum(len(h) for h in holes(g))
        print('%-18s ink %4d  silhouette %4d  holes %s'
              % (key, ink(g), solid, sorted(len(h) for h in holes(g))))
        for f in faults:
            print('  !! %s: %s' % (key, f))
        bad += len(faults)
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--write', action='store_true',
                    help='rewrite the art rows in sprites.txt (notes are left alone)')
    ap.add_argument('--preview', metavar='PATH',
                    help='write a contact sheet of all 21 grids (needs Pillow)')
    args = ap.parse_args()

    grids = build()
    faults = check_grids(grids)
    if faults:
        print('\n%d fault(s): fix the shapes before writing them out' % faults)
        return 1

    lines = open(SPRITES).read().split('\n')
    found = blocks(lines)
    missing = set(grids) ^ set(k for k, _, _ in found)
    if missing:
        sys.exit('sprites.txt and the drawer disagree on which blocks exist: %s'
                 % ', '.join(sorted(missing)))

    stale = [k for k, s, e in found if lines[s:e] != to_text(grids[k]).split('\n')]
    if args.preview:
        from draw import preview
        order = ['slime'] + ['slime.%s.%d' % (a, i) for a in
                             ('idle', 'move', 'sleep', 'fight', 'rock', 'paper', 'scissors')
                             for i in range(4) if 'slime.%s.%d' % (a, i) in grids]
        print('preview:', preview([grids[k] for k in order], args.preview, scale=3, cols=5))

    if not args.write:
        print('\n%d of %d blocks differ from sprites.txt%s'
              % (len(stale), len(found), (': ' + ', '.join(stale)) if stale else ''))
        return 1 if stale else 0

    # Bottom up: replacing a block never shifts the ones above it.
    for key, start, end in reversed(found):
        lines[start:end] = to_text(grids[key]).split('\n')
    open(SPRITES, 'w').write('\n'.join(lines))
    print('\nrewrote %d blocks (%d changed). Re-run generate_sprites.py, and read the '
          'notes back against the cells.' % (len(found), len(stale)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
