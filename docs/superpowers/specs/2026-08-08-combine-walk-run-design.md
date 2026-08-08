# Combine the walk and run actions

Status: approved, not yet implemented.

## Problem

Movement is two action states today — `walk` and `run` — and the split costs more than it pays
for.

The run carries a direction, so it needs a mirrored slot, which makes movement 3 of the 7 variants
per species: `walk`, `run`, `run_left`. At 29 species that is 87 drawables spent on movement
against a hard `Rez.Drawables` cap of 254. Total spend today is 204 of 254, leaving room for about
seven more species.

The two states are also barely distinguishable on screen. Both animate at `FRAME_MS = 500`, both
are two frames derived from the same base grid, and the difference between "body shifts ±d with
counter-swinging legs" and "body sheared forward with split legs" reads at 72px as two similar
waddles rather than as a walk and a run.

## Decision

Collapse movement into a single action, named `move`, derived exactly as `walk` is derived today.
Delete `run` and `run_left` outright — the art, the transform, the `Sprites` constants, and the
`Motion` state.

Movement keeps no direction, matching the existing rule that only the lunge and the lean are
mirrored: `move` swings both ways across its two frames, so a mirror would cost resources to say
nothing.

Four explicit choices shape this, each with a cheaper-looking alternative that was rejected:

**Movement does not get a faster cadence when the player runs.** A 250 ms run period was
considered and dropped. `FRAME_MS` is not only the frame duration, it is the period of the views'
redraw timer (`GMonsterView.mc:51`, `CharacterSelectView.mc:29`). A 250 ms frame sampled by a
500 ms timer lands on the same frame every tick, which freezes a two-frame animation outright. The
fix would be retiming the timer whenever the action changes — 2 Hz redraws for the duration of a
run, which is battery this animation does not justify. So run and walk are the same animation at
the same rate, and the run has no visual identity left to preserve.

**The battle-intro charge-in loses its lean.** `BattleView.mc:226` draws the enemy charging in from
off screen as `ACTION_RUN, FACE_LEFT`, and its comment states that the lean has to point the way
the slide travels. With `run_left` gone the charge-in draws `ACTION_MOVE` and the horizontal slide
carries the charge on its own. A `move_left` mirror would have kept the lean, but only by deriving
`move` with the run's forward shear, which would leave every species permanently leaning — on a
stroll as much as on a charge. Losing one lean on one screen is the cheaper trade.

**The run state is deleted from `Motion`, not merely unmapped.** `Motion.current()` feeds exactly
one draw site (`GMonsterView.mc:144`). With no run art and no speed split, nothing can observe the
difference between `ACTION_RUN` and `ACTION_WALK`, which makes `RUN_ENTER_SPM`, `RUN_EXIT_SPM`,
their derived step counts, the run's exit hysteresis, and its tests dead logic. Keeping the state
"in case a speed split comes back later" would preserve machinery that no test can meaningfully
assert against.

**The surviving slot is renamed `walk` → `move`.** The slot now covers running as well, and a name
that says `walk` while answering for a run is a comment that lies. The rename is the larger part of
the diff — 145 PNG filenames, `sprites.txt` override headers, `DEBUG_FORCE_ACTION` pose names — but
it is mechanical and the generator does the file half of it.

The Blair reference does not change meaning under the new name: `assets/blair-walk.jpg` remains the
spec any hand-authored `move` cycle is drawn against, because what it specifies is a stride, and a
stride is still what the state depicts.

## Result

Variants per species drop from 7 to 5: `idle`, `sleep`, `move`, `fight`, `fight_left`.

Drawables drop from 204 to 146 (29 × 5, plus `LauncherIcon`). Headroom under the 254 cap goes from
about seven more species to about twenty-one.

## Changes

### `tools/sprites/generate_sprites.py`

- `VARIANTS` becomes five entries; `("run", "run", False)` and `("run_left", "run", True)` are
  removed, and `("walk", "walk", False)` becomes `("move", "move", False)`.
- `frames_for`'s `action == "walk"` branch becomes `action == "move"`, unchanged otherwise. The
  `action == "run"` branch is deleted.
- `shear()` is deleted — the run branch was its only caller.
- The module comment describing five action states is rewritten for four.
- `superseded()` already removes PNGs no longer named by `VARIANTS`, so the 58 `*_run*.png` files
  and the 29 `*_walk.png` files are deleted by the regeneration rather than by hand.

### `tools/sprites/sprites.txt`

- The header comment's five-state list becomes four.
- `emberling.walk.0:` through `emberling.walk.3:` become `emberling.move.0:` through
  `emberling.move.3:`. The grids themselves are untouched — this stays the only override.
- Comment prose naming the `walk` state is updated; prose describing the Blair walk cycle as the
  reference for the stride stays.

### `source/ui/Sprites.mc`

```
ACTION_IDLE  = 0
ACTION_SLEEP = 1
ACTION_MOVE  = 2      // was ACTION_WALK
ACTION_FIGHT = 3
ACTION_COUNT = 4      // was 5
SLOT_FIGHT_LEFT = 4   // was 5
```

- `ACTION_RUN` and `SLOT_RUN_LEFT` are deleted.
- `slotFor` loses its `ACTION_RUN → SLOT_RUN_LEFT` branch; the `FACE_LEFT` remap is `fight` only.
- The module comment's "five two-frame action states" becomes four, and the `SLEEP_FRAME_MS`
  comment loses its closing sentence about running reading through distance travelled.

Slot numbers stay contiguous with `VARIANTS` order, which is the invariant that file's comment
guards. `ACTION_COUNT` and `SLOT_FIGHT_LEFT` must move together with the `VARIANTS` edit or
`slotFor` will silently index the wrong bitmap.

### `source/ui/Motion.mc`

`classify` becomes:

```
sinceStepMs >= SLEEP_AFTER_MS  -> ACTION_SLEEP
sinceStepMs >= WALK_QUIET_MS   -> ACTION_IDLE
steps3s >= MOVE_ENTER_STEPS    -> ACTION_MOVE
state == ACTION_MOVE           -> ACTION_MOVE
otherwise                      -> ACTION_IDLE
```

- The `steps5s` parameter is removed from the signature, and `sample()` stops calling
  `recentSteps(BUCKETS)`.
- `RUN_ENTER_SPM`, `RUN_EXIT_SPM`, `RUN_ENTER_STEPS`, `RUN_EXIT_STEPS` and `EXIT_MS` are deleted.
- `WALK_ENTER_SPM` / `WALK_ENTER_STEPS` / `WALK_QUIET_MS` are renamed `MOVE_ENTER_SPM` /
  `MOVE_ENTER_STEPS` / `MOVE_QUIET_MS`, for consistency with the slot rename.
- `BUCKETS` and the five-slot ring buffer stay: `MOVE_QUIET_MS` is 5000 ms and still needs five
  seconds of history. `ENTER_BUCKETS` stays at 3.
- The doc comment's six-item priority list becomes four items. The paragraph explaining why run
  entry outranks the run's own exit check is deleted; the paragraph explaining walk-coast
  hysteresis stays, since that is the one piece of hysteresis that survives.

### `source/battle/BattleView.mc`

Line 226 draws `Sprites.ACTION_MOVE` instead of `Sprites.ACTION_RUN`. The `FACE_LEFT` argument is
kept for readability at the call site even though `slotFor` now ignores it for movement. The
preceding comment is rewritten: the slide carries the charge, and the creature no longer leans into
it.

### `source/tests/MotionTests.mc`

- Every `Motion.classify(...)` call loses its `steps5s` argument.
- The run cases are deleted: run entry, run exit below threshold, run sustained above exit, run
  falling back to walk, and the two sampling tests seeded at `ACTION_RUN`.
- Sleep, wake, quiet-window, walk-entry and walk-coast cases stay, with `ACTION_WALK` renamed to
  `ACTION_MOVE` throughout.

### Debug and docs

- `tools/debug/gen_debug_config.py`: accepted pose names become `idle|sleep|move|fight`; `walk` and
  `run` are removed.
- `Makefile:74`: the `DEBUG_FORCE_ACTION` help line lists the four poses.
- `DEBUG.md`: the `DEBUG_FORCE_ACTION` table row and the worked examples use `move`.
- `CLAUDE.md` (root): the Sprites section's "five action states ... plus mirrored lunge and lean
  frames" becomes four states plus the mirrored lunge.
- `tools/sprites/CLAUDE.md`: the seven-row variant table becomes five rows; the 254-budget
  arithmetic is restated as 29 × 5 = 145 plus `LauncherIcon`; the per-state "what actually reads at
  this size" list drops its `run` entry; the *Walk follows Blair* section is retitled for `move`
  and keeps the Blair guidance.

## Verification

1. `python3 tools/sprites/generate_sprites.py` — expect 145 PNGs written or unchanged, and 87
   legacy files reported and removed.
2. The clamp notes must still be exactly five, and all five must name `walk`/`move` or `fight`:
   `pyrewarden fight`, `abyssward move`, `abyssward fight`, `gleammote move`, `gleammote fight`.
   None of today's five notes come from the run transform, so the count does not change — only the
   word `walk` becomes `move`. A sixth note, or one naming a species not on that list, means a grid
   was disturbed rather than that the collapse worked.
3. `python3 tools/sprites/generate_sprites.py --check` — clean.
4. `monkeyc -d fenix6pro -f monkey.jungle -o GMonster.prg -y developer_key.der -l 3` — clean. A
   stale `ACTION_RUN` reference is a compile error at `-l 3`, which is the main safety net for the
   rename.
5. Unit tests: build with `--unit-test`, run with `-t`. All pass.
6. `make run DEBUG_FORCE_ACTION=move` in the simulator: the partner animates. `DEBUG_FORCE_ACTION=run`
   must now fail validation with the expected-one-of message.
7. Trigger a battle intro and confirm the enemy still charges in — sliding, no longer leaning.

## Not doing

- No speed split between walking and running, for the timer reason above.
- No `move_left` mirror.
- No change to `emberling`'s four-frame authored cycle beyond its header rename.
- No change to `FRAME_MS`, `SLEEP_FRAME_MS`, or either view's redraw timer.
