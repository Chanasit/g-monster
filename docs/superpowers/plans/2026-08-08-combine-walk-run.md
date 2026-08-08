# Combine Walk and Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the `walk` and `run` action states into a single `move` state, deleting the run's art, transform, `Sprites` constants and `Motion` state.

**Architecture:** Movement becomes one derived two-frame action, named `move`, produced by exactly the transform `walk` uses today. The run's forward-lean transform and its mirrored slot are deleted outright, which drops variants per species from 7 to 5 and drawables from 204 to 146. `Motion.classify` loses its run branch and its 5-second window argument, keeping only the walk-coast hysteresis.

**Tech Stack:** Monkey C (Garmin Connect IQ SDK 9.2.0), Python 3 stdlib for the sprite generator, no test runner beyond `monkeyc --unit-test` / `monkeydo -t`.

**Spec:** `docs/superpowers/specs/2026-08-08-combine-walk-run-design.md`

## Global Constraints

- Every Monkey C build uses `-l 3` (strict type check). Explicit types on declarations and returns are mandatory.
- The SDK path is not on `PATH`. Every task that builds must first:
  `export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"`
- `resources/drawables/**`, the `<bitmap>` block of `resources/drawables/drawables.xml`, and all of `source/ui/SpriteIndex.mc` are **generated**. Never hand-edit them; rerun `python3 tools/sprites/generate_sprites.py`.
- `source/DebugConfig.mc` is generated and committed in its all-off form. Never hand-edit it.
- `tools/sprites/generate_sprites.py` is **stdlib only**. Do not import a third-party image library.
- Doc comments use `//!` and explain *why*, not *what*. Private fields are `_underscored`; module-level constants are `SCREAMING_SNAKE`.
- Slot numbering is load-bearing: the order of `VARIANTS` in `generate_sprites.py` **is** the `ACTION_*`/slot numbering in `source/ui/Sprites.mc` and the integer values in `ACTIONS` in `tools/debug/gen_debug_config.py`. All three must move together in the same commit.
- Never commit or print `developer_key.der` / `developer_key.pem`.
- Do not run `git push`, open a PR, or merge. Committing locally is in scope; publishing is not.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `tools/sprites/generate_sprites.py` | Derives every action's frames from one authored grid; writes PNGs, `drawables.xml`, `SpriteIndex.mc` | Modify: `VARIANTS`, `frames_for`, delete `shear`, widen `superseded` |
| `tools/sprites/sprites.txt` | The only hand-authored art | Modify: header prose, `emberling.walk.*` override headers |
| `resources/drawables/**` | Generated PNGs + `drawables.xml` | Regenerated |
| `source/ui/SpriteIndex.mc` | Generated resource-id table | Regenerated |
| `source/ui/Sprites.mc` | Action constants, slot mapping, frame clock, draw | Modify |
| `source/ui/Motion.mc` | Pedometer cadence → action state | Modify |
| `source/battle/BattleView.mc` | Battle screen drawing | Modify line 226 only |
| `source/tests/MotionTests.mc` | Unit tests for `Motion.classify` | Modify |
| `tools/debug/gen_debug_config.py` | Turns env vars into `source/DebugConfig.mc` | Modify `ACTIONS` |
| `Makefile`, `DEBUG.md`, `CLAUDE.md`, `tools/sprites/CLAUDE.md` | Docs | Modify |

## Task Order and Why

Task 1 (generator orphan cleanup) lands first and alone, because it is a pre-existing bug fix that
must be provably correct *before* the variant set changes — once `VARIANTS` shrinks there is no way
to tell a working cleanup from a silent no-op.

Tasks 2–4 are one atomic rename across the generator, the art source and the Monkey C layer. They
are separate tasks for reviewability but **the build is broken between them** — `-l 3` will reject
`ACTION_RUN` references until Task 4 lands. Do not try to build at the end of Task 2 or 3; each of
those tasks states its own verification, which is not a build.

Tasks 5–7 are independently verifiable and could be reordered.

---

### Task 1: Teach the generator to delete orphaned variant PNGs

`superseded()` scans only the top level of `resources/drawables/`, because every earlier sprite
scheme put its files there. Today's PNGs live in per-species subdirectories, so a removed variant
leaves dead PNGs that neither the regeneration nor `--check` notices. No variant has ever been
removed before, so this has never been reachable — and the next task removes two.

Verified on its own first: after `VARIANTS` shrinks, a broken cleanup and a working one both look
like "no output".

**Files:**
- Modify: `tools/sprites/generate_sprites.py:380-393` (`LEGACY_PNG`, `superseded`)
- Test: none — this repo has no Python test runner. Verified by a manual orphan probe (Steps 1–2, 5).

**Interfaces:**
- Consumes: nothing.
- Produces: `superseded(names, keys, outdir)` — note the **new third parameter**. Returns a sorted
  `list[str]` of paths relative to `outdir`, each of which the caller deletes with
  `os.remove(os.path.join(OUTDIR, name))`. Task 2 relies on this signature; nothing else calls it.

- [ ] **Step 1: Plant an orphan PNG to prove the current cleanup misses it**

```bash
cd "$(git rev-parse --show-toplevel)"
cp resources/drawables/emberling/emberling_idle.png \
   resources/drawables/emberling/emberling_bogus.png
```

- [ ] **Step 2: Run the generator and confirm the orphan survives (the bug)**

Run:
```bash
python3 tools/sprites/generate_sprites.py
ls resources/drawables/emberling/emberling_bogus.png
```

Expected: the generator prints `29 species x 7 variants (2 frames each): 0 written, 203 already correct, 0 removed`, and `ls` still finds `emberling_bogus.png`. That "0 removed" alongside a surviving orphan is the bug.

- [ ] **Step 3: Widen `superseded` to walk the per-species directories**

Replace the `LEGACY_PNG` comment block and `superseded` (currently `generate_sprites.py:380-393`) with:

```python
#! Files from earlier sprite schemes, all of which sat at the top level of
#! drawables/: <key>_0.png from before actions existed, <key>_<action>_0.png
#! from before both frames shared one bitmap, and <key>_<action>.png from
#! before the per-species directories. Matched narrowly -- the numbered forms
#! by shape, the flat form only against a live species key -- so nothing else
#! in the directory is ever a deletion candidate.
LEGACY_PNG = re.compile(r"^[a-z]+(_[a-z]+)*_[01]\.png$")


def superseded(names, keys, outdir):
    """Every PNG under drawables/ that this run would not have written.

    Two scopes, because the layout has moved once. The top level holds only
    leftovers from the schemes above. A species directory holds exactly one
    file per live variant, so anything else in it is a variant that has since
    been dropped or renamed -- which is unreachable until a variant actually
    goes away, and is why this was for a long time only a top-level sweep.

    Names come back relative to outdir so the caller deletes and reports them
    the same way whichever scope they came from.
    """
    flat = tuple("%s_" % key for key in keys)
    dead = [n for n in names
            if n.endswith(".png") and (LEGACY_PNG.match(n) or n.startswith(flat))]

    live = frozenset(png_name(key, label)
                     for key in keys
                     for label, _action, _mirrored in VARIANTS)
    for key in keys:
        species = os.path.join(outdir, key)
        if not os.path.isdir(species):
            continue
        for name in os.listdir(species):
            rel = "%s/%s" % (key, name)
            if name.endswith(".png") and rel not in live:
                dead.append(rel)

    return sorted(dead)
```

- [ ] **Step 4: Update the one call site to pass `OUTDIR`**

In `main`, `generate_sprites.py:656`, change:

```python
    legacy = superseded(os.listdir(OUTDIR), sprites.keys())
```

to:

```python
    legacy = superseded(os.listdir(OUTDIR), sprites.keys(), OUTDIR)
```

- [ ] **Step 5: Run the generator and confirm the orphan is now removed**

Run:
```bash
python3 tools/sprites/generate_sprites.py
ls resources/drawables/emberling/emberling_bogus.png
```

Expected: the run reports `... 1 removed` and lists `resources/drawables/emberling/emberling_bogus.png (superseded)` in its stale output; `ls` exits non-zero with "No such file or directory".

- [ ] **Step 6: Confirm nothing real was deleted**

Run:
```bash
python3 tools/sprites/generate_sprites.py --check
find resources/drawables -name '*.png' | wc -l
git status --porcelain
```

Expected: `--check` prints `203 sprites up to date` and exits 0. The count is `204`. `git status --porcelain` shows only `tools/sprites/generate_sprites.py` as modified — no PNG is touched.

- [ ] **Step 7: Commit**

```bash
git add tools/sprites/generate_sprites.py
git commit -m "fix(sprites): delete orphaned PNGs inside species directories

superseded() only ever swept the top level of drawables/, which is where
every earlier sprite scheme put its files. Since the move to per-species
directories a dropped or renamed variant leaves dead PNGs that neither the
regeneration nor --check notices. No variant had been removed before, so
this was unreachable; collapsing walk and run removes two."
```

---

### Task 2: Rename the `walk` variant to `move` and delete `run` from the generator

**Files:**
- Modify: `tools/sprites/generate_sprites.py` — module docstring, `VARIANTS` comment and tuple, `shear` (delete), `frames_for`
- Modify: `tools/sprites/sprites.txt` — header comment, four override headers

**Interfaces:**
- Consumes: `superseded(names, keys, outdir)` from Task 1.
- Produces: `VARIANTS` of exactly 5 entries in this order — `("idle","idle",False)`, `("sleep","sleep",False)`, `("move","move",False)`, `("fight","fight",False)`, `("fight_left","fight",True)`. Task 4 hard-codes these positions as slot numbers, and Task 6 hard-codes them as `ACTIONS` integers.
- The override key namespace changes with the variant name: `frames_for` is dispatched on the *action* string, and `parse` rejects any `key.action.n:` header whose action is not in `VARIANTS`. So `emberling.walk.*` must be renamed in the same task or parsing fails.

**Do not build at the end of this task.** `source/ui/Sprites.mc` still names `ACTION_RUN` and the regenerated `SpriteIndex.mc` no longer has a slot for it. The build is expected to be broken until Task 4.

- [ ] **Step 1: Update `VARIANTS` and its comment**

In `generate_sprites.py:70-90`, replace the comment block and tuple with:

```python
#! Action order is load-bearing: Sprites.mc indexes each species' flat id array
#! as slot * 2 + frame, so a variant's position here is its slot number, and the
#! first four have to stay in the order of ACTION_*.
#!
#! Lunging is the only transform with a direction in it, so it is the only one
#! with a mirrored variant. In battle the player's creature commits to the right
#! and the enemy to the left; drawing both with the same rightward lunge would
#! have the enemy striking away from its target. Idle, sleep and move carry no
#! direction -- move swings both ways across its two frames -- so mirroring them
#! would cost resources to say nothing.
#!
#! (label, action, mirrored)
VARIANTS = (
    ("idle", "idle", False),
    ("sleep", "sleep", False),
    ("move", "move", False),
    ("fight", "fight", False),
    ("fight_left", "fight", True),
)
```

- [ ] **Step 2: Rename the walk transform and delete the run transform**

In `frames_for`, `generate_sprites.py:318`, change the branch header:

```python
    if action == "walk":
```

to:

```python
    if action == "move":
```

Leave that branch's body and its comment unchanged — the derivation is identical, only the name moved.

Then delete the entire `if action == "run":` branch, `generate_sprites.py:348-360`:

```python
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
```

- [ ] **Step 3: Delete `shear`, now unused**

Delete `generate_sprites.py:232-240` entirely:

```python
def shear(rows, amount):
    """Lean the silhouette right, ramping from 0 at the feet to amount at the top."""
    if amount == 0:
        return list(rows)
    out = []
    for i, row in enumerate(rows):
        dx = amount * (GRID - 1 - i) // (GRID - 1)
        out.append(("." * dx + row)[:GRID])
    return out
```

Confirm it has no other caller:

```bash
grep -n 'shear' tools/sprites/generate_sprites.py
```

Expected: no output.

- [ ] **Step 4: Update the module docstring**

In `generate_sprites.py:4-9`, replace:

```
The watch app wants five action states per species -- idle, sleep, walk, fight,
run -- two frames each. Only one grid per species is authored; every action's
frames are derived from it by grid transforms, the same way the idle breath was
always derived by dropping the whole silhouette one row. Deriving means the
artist maintains 29 grids instead of 145, a new species costs one grid rather
than five, and no species' poses can drift apart from each other.
```

with:

```
The watch app wants four action states per species -- idle, sleep, move, fight
-- two frames each. Only one grid per species is authored; every action's
frames are derived from it by grid transforms, the same way the idle breath was
always derived by dropping the whole silhouette one row. Deriving means the
artist maintains 29 grids instead of 116, a new species costs one grid rather
than four, and no species' poses can drift apart from each other.
```

Then in the same docstring, `generate_sprites.py:11-13`, replace `bob, waddle, lean, lunge` with `bob, waddle, lunge` — the lean went with the run.

- [ ] **Step 5: Rename the emberling walk override headers**

In `tools/sprites/sprites.txt`, rename exactly four header lines. They are at lines 796, 822, 848 and 874, and the grids under them are untouched:

```
emberling.walk.0:   ->  emberling.move.0:
emberling.walk.1:   ->  emberling.move.1:
emberling.walk.2:   ->  emberling.move.2:
emberling.walk.3:   ->  emberling.move.3:
```

Leave `emberling.sleep.*` and `emberling.idle.*` alone.

- [ ] **Step 6: Update the prose above that block**

At `sprites.txt:770`, replace the first line of the override's comment:

```
# Walk cycle for emberling: four frames instead of the derived two, so the legs can actually
# step rather than the body just rocking.
```

with:

```
# Move cycle for emberling: four frames instead of the derived two, so the legs can actually
# step rather than the body just rocking. `move` is the one movement state -- walking and running
# both play it -- so this is drawn as a walk, which is what it reads as at either cadence.
```

Leave the rest of that comment as is, including every reference to Blair and to `assets/blair-walk.jpg`. What Blair specifies is a stride, and a stride is still what the state depicts.

- [ ] **Step 7: Regenerate**

Run:
```bash
python3 tools/sprites/generate_sprites.py
```

Expected output line:
```
29 species x 5 variants (2 frames each): 29 written, 116 already correct, 87 removed
```

The 29 written are the `move` PNGs, which are byte-identical to the old `walk` ones but under a new name. The 87 removed are 29 `*_walk.png` + 29 `*_run.png` + 29 `*_run_left.png` — Task 1 is what makes that number non-zero.

- [ ] **Step 8: Check the clamp notes did not change count**

The generator writes notes to stderr. Capture and compare:

```bash
python3 tools/sprites/generate_sprites.py 2>&1 >/dev/null | sort
```

Expected exactly five lines, and every one naming `move` or `fight`:
```
note: abyssward fight: no room for the lunge reach, using a bob instead
note: abyssward move: no room for the sideways swing, using a bob instead
note: gleammote fight: no room for the lunge reach, using a bob instead
note: gleammote move: no room for the sideways swing, using a bob instead
note: pyrewarden fight: no room for the lunge reach, using a bob instead
```

None of today's five notes come from the run transform, so only the word `walk` becomes `move`. A sixth note, or one naming a species not on this list, means a grid was disturbed — stop and investigate rather than continuing.

- [ ] **Step 9: Confirm the file count**

Run:
```bash
find resources/drawables -name '*.png' | wc -l
find resources/drawables \( -name '*_run*.png' -o -name '*_walk.png' \) | wc -l
python3 tools/sprites/generate_sprites.py --check
```

Expected: `146` (145 species PNGs + the hand-authored `launcher_icon.png`), then `0`, then `145 sprites up to date` and exit 0.

- [ ] **Step 10: Commit**

```bash
git add tools/sprites/generate_sprites.py tools/sprites/sprites.txt \
        resources/drawables source/ui/SpriteIndex.mc
git commit -m "feat(sprites): collapse walk and run into one move variant

Movement was 3 of 7 variants per species -- walk, run, run_left -- because
the run carries a direction and needs a mirror. Both animate at 500ms from
the same base grid, and at 72px a forward shear reads as a second waddle
rather than as a run.

One derived movement state, named move because it now answers for both.
204 drawables to 146, against a hard Rez.Drawables cap of 254.

Monkey C does not build at this commit; Sprites.mc follows."
```

---

### Task 3: Delete the run state from `Motion`

**Files:**
- Modify: `source/ui/Motion.mc`

**Interfaces:**
- Consumes: `Sprites.ACTION_MOVE` (renamed in Task 4 — this task references it before it exists, which is why the build stays broken until then).
- Produces:
  - `Motion.classify(state as Number, steps3s as Number, sinceStepMs as Number) as Number` — **three parameters, `steps5s` removed.** Task 5's tests call exactly this.
  - Renamed constants used by Task 5: `Motion.MOVE_ENTER_SPM`, `Motion.MOVE_ENTER_STEPS`, `Motion.MOVE_QUIET_MS`. `Motion.SLEEP_AFTER_MS`, `Motion.BUCKETS`, `Motion.ENTER_BUCKETS` and `Motion.BUCKET_MS` keep their names.
  - Deleted, and referenced nowhere afterwards: `RUN_ENTER_SPM`, `RUN_EXIT_SPM`, `RUN_ENTER_STEPS`, `RUN_EXIT_STEPS`, `EXIT_MS`.

- [ ] **Step 1: Replace the constants block**

Replace `Motion.mc:19-53` (from the `//! Cadences are the tunables` comment through `RUN_EXIT_STEPS`) with:

```monkey-c
    //! The cadence is the tunable; the step count below derives from it, so a reader sees the
    //! intent rather than a magic integer. The division is exact.

    //! Steps per minute that count as moving at all. Low, because two steps inside the entry
    //! window is already someone on their feet.
    //!
    //! There is one movement state and one threshold. An earlier version had a second, higher
    //! cadence that promoted a walk to a run, with its own lower exit threshold for hysteresis.
    //! Nothing could observe it: run and walk drew the same sheet at the same rate once their art
    //! was merged, so the whole ladder was untestable machinery.
    const MOVE_ENTER_SPM = 40;

    //! One slot per second, five of them. Five seconds is everything the rules read.
    const BUCKET_MS = 1000;
    const BUCKETS = 5;

    //! Entry is judged over the newest three slots. The remaining two exist for the quiet rule,
    //! which reads the gap since the last step rather than a sum.
    const ENTER_BUCKETS = 3;
    const ENTER_MS = ENTER_BUCKETS * BUCKET_MS;

    //! Silence that ends a move.
    const MOVE_QUIET_MS = 5000;

    //! No steps for this long and the creature settles down to sleep.
    const SLEEP_AFTER_MS = 300000;

    const MOVE_ENTER_STEPS = (MOVE_ENTER_SPM * ENTER_MS) / 60000;
```

- [ ] **Step 2: Replace `classify` and its doc comment**

Replace `Motion.mc:74-107` (from `//! Which action the player's movement calls for.` through the closing brace of `classify`) with:

```monkey-c
    //! Which action the player's movement calls for. Pure, so the whole table can be tested
    //! without a pedometer.
    //!
    //! A priority list, and the order is behaviour rather than style:
    //!
    //!   1. sleep and 2. silence are answered from the gap alone, so a single step resets the gap
    //!      and wakes the creature on the same sample — waking needs no rule of its own.
    //!   4. coasting sustains a move on evidence that would not have started one. That is the
    //!      hysteresis, and without it a stroll near the entry cadence flickers.
    function classify(state as Number, steps3s as Number, sinceStepMs as Number) as Number {
        if (sinceStepMs >= SLEEP_AFTER_MS) {
            return Sprites.ACTION_SLEEP;
        }
        if (sinceStepMs >= MOVE_QUIET_MS) {
            return Sprites.ACTION_IDLE;
        }
        if (steps3s >= MOVE_ENTER_STEPS) {
            return Sprites.ACTION_MOVE;
        }
        if (state == Sprites.ACTION_MOVE) {
            return Sprites.ACTION_MOVE;
        }
        return Sprites.ACTION_IDLE;
    }
```

- [ ] **Step 3: Drop the five-second sum from the sampler**

At `Motion.mc:183-184`, replace:

```monkey-c
        _action = classify(_action, recentSteps(ENTER_BUCKETS), recentSteps(BUCKETS),
                           now - _lastStepAt);
```

with:

```monkey-c
        _action = classify(_action, recentSteps(ENTER_BUCKETS), now - _lastStepAt);
```

- [ ] **Step 4: Update the module doc comment**

At `Motion.mc:9-12`, replace:

```
//! The rules are deliberately asymmetric: a state is entered on three seconds of evidence and left
//! only after five seconds of silence. That gap is what makes the creature look like it is
//! following the wearer rather than lagging them, and it is also what stops a cadence sitting near
//! a threshold from strobing the state every sample.
```

with:

```
//! The rules are deliberately asymmetric: the move state is entered on three seconds of evidence
//! and left only after five seconds of silence. That gap is what makes the creature look like it
//! is following the wearer rather than lagging them, and it is also what stops a cadence sitting
//! near the threshold from strobing the state every sample.
```

- [ ] **Step 5: Confirm no run reference survives in this file**

Run:
```bash
grep -n 'RUN_\|ACTION_RUN\|ACTION_WALK\|WALK_\|EXIT_MS\|recentSteps(BUCKETS)' source/ui/Motion.mc
```

Expected: no output. `BUCKETS` itself still appears in the ring-buffer code, which is correct — the quiet rule still needs five seconds of history; only the *sum* over five slots is gone.

- [ ] **Step 6: Commit**

```bash
git add source/ui/Motion.mc
git commit -m "refactor(motion): delete the run state and its hysteresis ladder

Motion.current() feeds one draw site. With run and walk sharing one sheet
at one rate, nothing can observe the difference between them, which makes
RUN_ENTER_SPM, RUN_EXIT_SPM and the run's exit hysteresis machinery that no
test can meaningfully assert against.

classify() loses its steps5s window with them. WALK_* becomes MOVE_*, since
the surviving state answers for a run too.

Monkey C does not build at this commit; Sprites.mc follows."
```

---

### Task 4: Rename the action slot in `Sprites` and repoint the battle intro

The build comes back at the end of this task. `-l 3` is the safety net for the whole rename: any
surviving `ACTION_RUN` or `ACTION_WALK` reference anywhere in `source/` is a compile error, not a
runtime surprise.

**Files:**
- Modify: `source/ui/Sprites.mc:6-39` (module comment, `SLEEP_FRAME_MS` comment, action constants, facing comment), `source/ui/Sprites.mc:85-95` (`slotFor`)
- Modify: `source/battle/BattleView.mc:222-227`

**Interfaces:**
- Consumes: the 5-entry `VARIANTS` order from Task 2; `Motion.classify`'s new arity from Task 3.
- Produces: `Sprites.ACTION_IDLE = 0`, `ACTION_SLEEP = 1`, `ACTION_MOVE = 2`, `ACTION_FIGHT = 3`, `ACTION_COUNT = 4`, `SLOT_FIGHT_LEFT = 4`, `FACE_RIGHT = 0`, `FACE_LEFT = 1`. Task 5 asserts against `ACTION_MOVE`; Task 6 hard-codes these integers.
- Deleted: `Sprites.ACTION_RUN`, `Sprites.ACTION_WALK`, `Sprites.SLOT_RUN_LEFT`.

- [ ] **Step 1: Replace the constants block**

Replace `Sprites.mc:24-39` with:

```monkey-c
    //! Action states. These are slot numbers in the generated table, so their values have to keep
    //! matching the variant order in tools/sprites/generate_sprites.py.
    //!
    //! One movement state, not two. Walking and running both draw ACTION_MOVE: they animated at
    //! the same rate from the same base grid, and a forward shear at 72px read as a second waddle
    //! rather than as a run. Giving the run a real cadence would mean retiming the views' redraw
    //! timer, which is battery this animation does not justify.
    const ACTION_IDLE = 0;
    const ACTION_SLEEP = 1;
    const ACTION_MOVE = 2;
    const ACTION_FIGHT = 3;
    const ACTION_COUNT = 4;

    //! Which way the creature is pointed. Only the lunge has a direction in it, so it is the only
    //! action carrying a mirrored slot; every other action ignores facing entirely.
    const FACE_RIGHT = 0;
    const FACE_LEFT = 1;

    const SLOT_FIGHT_LEFT = 4;
```

- [ ] **Step 2: Update the module comment and the sleep-timing comment**

At `Sprites.mc:6`, replace:

```
//! Creature artwork: five two-frame action states per species, looked up by species key.
```

with:

```
//! Creature artwork: four two-frame action states per species, looked up by species key.
```

At `Sprites.mc:18-22`, replace all five lines — the four-line comment **and** the `const` under it:

```
    //! Sleep breathes slower than everything else. Kept a multiple of FRAME_MS so the existing
    //! redraw timer still lands on every frame change — a faster action would mean a faster timer,
    //! which is battery the animation is not worth. Running reads quick through how far the body
    //! moves between frames, not through how often they swap.
```

with:

```
    //! Sleep breathes slower than everything else. Kept a multiple of FRAME_MS so the existing
    //! redraw timer still lands on every frame change — a faster action would mean a faster timer,
    //! which is battery the animation is not worth. That is also why there is no separate running
    //! cadence: a 250 ms frame sampled by a 500 ms timer lands on the same frame every tick.
    const SLEEP_FRAME_MS = 1500;
```

- [ ] **Step 3: Drop the run branch from `slotFor`**

Replace `Sprites.mc:83-95` with:

```monkey-c
    //! Which of a species' bitmaps an action and facing want. Anything out of range falls back to
    //! idle rather than running off the end of the array.
    function slotFor(action as Number, facing as Number) as Number {
        var slot = (action >= 0 && action < ACTION_COUNT) ? action : ACTION_IDLE;
        if (facing == FACE_LEFT && slot == ACTION_FIGHT) {
            slot = SLOT_FIGHT_LEFT;
        }
        return slot;
    }
```

- [ ] **Step 4: Repoint the battle-intro charge-in**

Replace `BattleView.mc:222-227` with:

```monkey-c
        if (!flash) {
            // It is charging in from off screen. The slide is the whole charge now: movement is one
            // bidirectional state, so there is no leftward lean left to point the way it travels.
            Sprites.drawAction(dc, enemyX(dc) + slide, height * 0.40,
                               _engine.enemySpecies().key, Sprites.ACTION_MOVE, Sprites.FACE_LEFT);
        }
```

`FACE_LEFT` is kept at the call site for readability even though `slotFor` now ignores facing for movement — the enemy is still the left-facing participant, and the argument would have to come back if movement ever regains a direction.

- [ ] **Step 5: Confirm no stale reference survives anywhere in `source/`**

Run:
```bash
grep -rn 'ACTION_RUN\|ACTION_WALK\|SLOT_RUN_LEFT' source/
```

Expected: matches in `source/tests/MotionTests.mc` **only**. Those are fixed in Task 5. Any match outside `source/tests/` must be fixed now.

- [ ] **Step 6: Build and verify it compiles**

Run:
```bash
export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonster.prg -y developer_key.der -l 3
```

Expected: exit 0, no ERROR lines. The non-test build excludes `source/tests/`, so its stale `ACTION_WALK` references do not break this.

- [ ] **Step 7: Commit**

```bash
git add source/ui/Sprites.mc source/battle/BattleView.mc
git commit -m "feat(sprites): one movement slot, ACTION_MOVE

ACTION_RUN and SLOT_RUN_LEFT go; ACTION_WALK becomes ACTION_MOVE and
ACTION_COUNT drops to 4, keeping the constants contiguous with VARIANTS.

The battle intro loses its lean: run_left was what pointed the charging
enemy the way its slide travelled, and movement carries no direction. The
slide alone reads as the charge."
```

---

### Task 5: Rewrite the motion tests for one movement state

The suite currently asserts a four-rung ladder — run entry, run exit, walk entry, coast — through
`classify`'s four-argument signature. Six cases exist only to pin the run's thresholds and go with
them. Everything else keeps its coverage, minus the removed argument.

**Files:**
- Modify: `source/tests/MotionTests.mc`

**Interfaces:**
- Consumes: `Motion.classify(state, steps3s, sinceStepMs)`, `Motion.MOVE_ENTER_STEPS`, `Motion.MOVE_QUIET_MS`, `Motion.SLEEP_AFTER_MS`, `Sprites.ACTION_MOVE`, `Sprites.ACTION_IDLE`, `Sprites.ACTION_SLEEP` — all from Tasks 3 and 4.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Delete the six run-only tests**

Remove these functions entirely, along with their `//!` comments and the two section banners
`// ------- rule 3: run entry` and `// ------- rule 4: run exit`:

- `testRunEndsAtTheSameSilence` (`MotionTests.mc:55-61`)
- `testEntersRunFromStandingStart` (`:65-72`)
- `testJustUnderTheRunThresholdIsAWalk` (`:74-81`)
- `testRunOnsetDoesNotBounceOffTheExitSum` (`:83-91`)
- `testRunContinuesAboveTheExitSum` (`:95-102`)
- `testRunDropsToWalkUnderTheExitSum` (`:104-111`)

`testRunEndsAtTheSameSilence` gets no replacement: with one movement state it would be
character-for-character identical to `testMoveEndsAfterFiveSecondsOfSilence`, which stays.

Also delete these two scenario tests, which exist to assert the run's deceleration ladder:

- `testSprintToDeadStopDecelerates` (`:180-198`)
- `testRunSlowingIntoAWalkCrossesOnce` (`:200-216`)

- [ ] **Step 2: Rewrite the remaining tests against the new signature**

The file after Step 1 should read exactly as follows. Renumber the section banners, since rules 3
and 4 are gone:

```monkey-c
import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the movement classifier. Pure logic only — `Motion.classify` takes the numbers
//! the sampler would have measured, so none of this needs a pedometer or a clock.
//!
//! The table is a priority list, so each test names the rule it pins down. Ordering is behaviour
//! here, not style: sleep outranks silence, entry outranks coasting.

// ---------------------------------------------------------------- rule 1: sleep

//! A long enough gap since the last step is sleep, whatever the window holds.
(:test)
function testSleepsAfterALongStillStretch(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! Sleep outranks cadence: steps in the window with an old last-step time is stale measurement,
//! not someone both asleep and moving.
(:test)
function testSleepOutranksStaleCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 20, Motion.SLEEP_AFTER_MS + 1),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! One millisecond short of the threshold is still awake.
(:test)
function testDoesNotSleepJustBeforeTheThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS - 1),
                     Sprites.ACTION_IDLE);
    return true;
}

// ----------------------------------------------------------------- rule 2: quiet

//! Five seconds without a step ends a move. This is the slow half of "fast in, slow out".
(:test)
function testMoveEndsAfterFiveSecondsOfSilence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 0, Motion.MOVE_QUIET_MS),
                     Sprites.ACTION_IDLE);
    return true;
}

//! A step four seconds ago is a slow walk, not a stop.
(:test)
function testMoveSurvivesAGapUnderTheQuietThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 0, Motion.MOVE_QUIET_MS - 1),
                     Sprites.ACTION_MOVE);
    return true;
}

// ------------------------------------------------------------ rule 3: move entry

//! Two steps in the short window starts a move. This is the fast half of "fast in, slow out".
(:test)
function testEntersMoveOnTheEntryEvidence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.MOVE_ENTER_STEPS, 0),
                     Sprites.ACTION_MOVE);
    return true;
}

//! One step is not a move from a standing start.
(:test)
function testOneStepDoesNotStartAMove(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.MOVE_ENTER_STEPS - 1, 0),
                     Sprites.ACTION_IDLE);
    return true;
}

//! A running cadence is the same state as a walking one. There is one movement threshold, and
//! everything above it is the same pose — this is the test that would fail if a run state came
//! back without art of its own.
(:test)
function testARunningCadenceIsTheSameMoveState(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, Motion.MOVE_ENTER_STEPS * 4, 0),
                     Sprites.ACTION_MOVE);
    return true;
}

// ----------------------------------------------------------------- rule 4: coast

//! Already moving, one step every few seconds sustains it — below the cadence that would have
//! started it. Without this the state strobes at the threshold.
(:test)
function testMoveCoastsBelowTheEntryCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 1, 2000), Sprites.ACTION_MOVE);
    return true;
}

//! The same evidence from idle stays idle. Coasting sustains a state, it never starts one.
(:test)
function testIdleDoesNotCoastIntoAMove(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 1, 2000), Sprites.ACTION_IDLE);
    return true;
}

//! Opening the app measures nothing, and nothing is idle — never mid-stride.
(:test)
function testColdStartIsIdle(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, 0), Sprites.ACTION_IDLE);
    return true;
}

// -------------------------------------------------------------------- scenarios

//! A stroll of one step every two seconds, sampled every second. Once it starts moving it must
//! keep moving: the gap never reaches the quiet threshold, even though the cadence keeps dipping
//! under the entry one. This is the anti-strobe test.
(:test)
function testStrollDoesNotStrobe(logger as Logger) as Boolean {
    var state = Sprites.ACTION_IDLE;

    // Two steps land three seconds apart at first, which is what starts the move.
    state = Motion.classify(state, 2, 0);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // Then it settles into one step every two seconds: the short window holds 1 or 2, and the
    // longest silence is 2s.
    for (var i = 0; i < 20; i += 1) {
        var steps3s = (i % 2 == 0) ? 1 : 2;
        state = Motion.classify(state, steps3s, (i % 2) * 1000);
        Test.assertEqual(state, Sprites.ACTION_MOVE);
    }
    return true;
}

//! A sprint stopped dead. One movement state means there is no intermediate rung to pass through:
//! it holds the move pose while the coast rule carries it, then goes idle when the silence rule
//! fires. It does not decelerate through a slower pose, because there is no longer a slower pose.
(:test)
function testSprintToDeadStopGoesStraightToIdle(logger as Logger) as Boolean {
    var state = Sprites.ACTION_MOVE;

    // 1s of silence: coasting holds it.
    state = Motion.classify(state, 4, 1000);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // 3s of silence, no steps in the short window: still coasting, still under the quiet rule.
    state = Motion.classify(state, 0, 3000);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // 5s: the quiet rule ends it.
    state = Motion.classify(state, 0, Motion.MOVE_QUIET_MS);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}

//! Asleep, then a single step. Waking needs no rule of its own: the step resets the silence, and
//! one step is not yet a move, so the creature wakes to idle on the very next sample.
(:test)
function testOneStepWakesTheCreature(logger as Logger) as Boolean {
    var state = Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS);
    Test.assertEqual(state, Sprites.ACTION_SLEEP);

    state = Motion.classify(state, 1, 0);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}
```

- [ ] **Step 3: Build the test binary**

Run:
```bash
export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonsterTest.prg -y developer_key.der -l 3 --unit-test
```

Expected: exit 0, no ERROR lines. A surviving `ACTION_WALK` or a four-argument `classify` call is a compile error here.

- [ ] **Step 4: Run the suite**

The simulator must already be running in another process. Start it first if it is not:

```bash
"$CIQ_SDK/bin/connectiq" &
"$CIQ_SDK/bin/monkeydo" GMonsterTest.prg fenix6pro -t
```

Expected: every test passes, ending in a `PASS` summary with no `FAILED` lines. There is no way to run a single test — the whole suite runs, so a failure elsewhere in the repo is also visible here and must be investigated, not ignored.

- [ ] **Step 5: Commit**

```bash
git add source/tests/MotionTests.mc
git commit -m "test(motion): drop the run rungs, keep the coast hysteresis

Six cases pinned RUN_ENTER_STEPS / RUN_EXIT_STEPS and two scenarios walked
the run-to-walk deceleration ladder. Neither threshold exists now.

Replaced with a case asserting the thing that changed: a running cadence
classifies as the same move state a walking one does. That is what fails if
a run state ever comes back without art of its own."
```

---

### Task 6: Update the debug force-action switch

**Files:**
- Modify: `tools/debug/gen_debug_config.py:30-42` (`ACTIONS`)
- Modify: `Makefile:36`, `Makefile:74`, `Makefile:76`
- Modify: `DEBUG.md`

**Interfaces:**
- Consumes: the slot integers from Task 4.
- Produces: `DEBUG_FORCE_ACTION` accepting `idle|sleep|move|fight`.

`source/DebugConfig.mc` is generated and committed all-off, so this task does not edit it and does
not change it — `FORCE_ACTION = -1` either way.

- [ ] **Step 1: Update the accepted pose names**

In `gen_debug_config.py`, replace the `ACTIONS` dict:

```python
ACTIONS = {
    "idle": 0,
    "sleep": 1,
    "walk": 2,
    "fight": 3,
    "run": 4,
}
```

with:

```python
ACTIONS = {
    "idle": 0,
    "sleep": 1,
    "move": 2,
    "fight": 3,
}
```

Leave the `#!` comment above it unchanged — it already says these are slot indices that must keep matching `Sprites.ACTION_*` and `VARIANTS`, which is still true.

- [ ] **Step 2: Verify the switch accepts `move` and rejects `walk` and `run`**

Use `--check`. It renders the config and compares it against `source/DebugConfig.mc` without ever
writing, so this probe cannot dirty the committed all-off file. Its exit code is the answer: `2`
means the pose name was rejected during parsing, `1` means it was accepted and produced a config
differing from the committed one, `0` means accepted and identical.

Run:
```bash
DEBUG_FORCE_ACTION=move python3 tools/debug/gen_debug_config.py --check; echo "exit=$?"
DEBUG_FORCE_ACTION=run  python3 tools/debug/gen_debug_config.py --check; echo "exit=$?"
DEBUG_FORCE_ACTION=walk python3 tools/debug/gen_debug_config.py --check; echo "exit=$?"
```

Expected:
```
debug config: source/DebugConfig.mc is stale
exit=1
debug config: DEBUG_FORCE_ACTION: expected one of fight, idle, move, sleep, got 'run'
exit=2
debug config: DEBUG_FORCE_ACTION: expected one of fight, idle, move, sleep, got 'walk'
exit=2
```

`exit=1` for `move` is the pass condition here, not a failure: the committed config is all-off, so
a forced pose is *supposed* to differ from it.

- [ ] **Step 2b: Confirm the committed config was not touched**

Run:
```bash
git status --porcelain source/DebugConfig.mc
```

Expected: no output.

- [ ] **Step 3: Update the Makefile help and example**

At `Makefile:36`, in the debug-switch comment block, change:

```
#   make run DEBUG_FORCE_ACTION=walk
```

to:

```
#   make run DEBUG_FORCE_ACTION=move
```

At `Makefile:74`, change:

```
	@echo "  DEBUG_FORCE_ACTION=<pose>     idle|sleep|walk|fight|run"
```

to:

```
	@echo "  DEBUG_FORCE_ACTION=<pose>     idle|sleep|move|fight"
```

At `Makefile:76`, change:

```
	@echo "  e.g.  make run DEBUG_FORCE_ACTION=walk"
```

to:

```
	@echo "  e.g.  make run DEBUG_FORCE_ACTION=move"
```

- [ ] **Step 4: Update `DEBUG.md`**

Four edits.

Line 7 and line 15-16, in the two example blocks, change `DEBUG_FORCE_ACTION=walk` to `DEBUG_FORCE_ACTION=move` and the printed `debug: force-action=walk` to `debug: force-action=move`.

Line 26, the table row, change:

```
| `DEBUG_FORCE_ACTION` | `idle`\|`sleep`\|`walk`\|`fight`\|`run` | off | Pin every creature to one pose instead of letting the pedometer choose. |
```

to:

```
| `DEBUG_FORCE_ACTION` | `idle`\|`sleep`\|`move`\|`fight` | off | Pin every creature to one pose instead of letting the pedometer choose. |
```

Line 32, the failure example, change:

```
debug config: DEBUG_FORCE_ACTION: expected one of fight, idle, run, sleep, walk, got 'flying'
```

to:

```
debug config: DEBUG_FORCE_ACTION: expected one of fight, idle, move, sleep, got 'flying'
```

Then replace the whole `## DEBUG_FORCE_ACTION` section body (`DEBUG.md:133-150`) with:

```markdown
## `DEBUG_FORCE_ACTION`

The ally on the ALLY page mirrors its tamer — `GMonsterView` draws it with `Motion.current()`, which
classifies pedometer cadence into idle, move or sleep. A simulator has no legs, so it sits at
`ACTION_IDLE` and the other two poses are unreachable without walking around wearing the watch.

Pin it to one pose instead:

```bash
make run DEBUG_FORCE_ACTION=move
```

Any of `idle`, `sleep`, `move`, `fight`. Omitting it hands control back to the pedometer. `fight` is
reachable only this way on the ALLY page — the pedometer never classifies it.

Only `Motion.current` consults it. `Motion.classify` stays pure and untouched, so `MotionTests` goes
on asserting the real `MOVE_ENTER_SPM` / `SLEEP_AFTER_MS` thresholds with the override on — the
suite is not quietly weakened to accommodate the cheat.
```

- [ ] **Step 5: Confirm no stale pose name survives**

Run:
```bash
grep -rn 'FORCE_ACTION=walk\|FORCE_ACTION=run\|"walk"\|"run"' Makefile DEBUG.md tools/debug/
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add tools/debug/gen_debug_config.py Makefile DEBUG.md
git commit -m "chore(debug): DEBUG_FORCE_ACTION poses are idle|sleep|move|fight

The slot integers track Sprites.ACTION_*, which lost run and renamed walk."
```

---

### Task 7: Update the sprite documentation

Both `CLAUDE.md` files describe a seven-variant, five-state pipeline that no longer exists, and the
254-budget arithmetic is now wrong in a way that would mislead whoever adds the next species —
it currently says there is room for about seven more.

**Files:**
- Modify: `CLAUDE.md` (repo root) — the **Sprites** section
- Modify: `tools/sprites/CLAUDE.md` — variant table, budget arithmetic, per-state prose, Blair section title

**Interfaces:**
- Consumes: the final variant set and counts from Tasks 2 and 4.
- Produces: nothing.

- [ ] **Step 1: Update the root `CLAUDE.md` Sprites section**

In the **Sprites** section, replace:

```
One grid per species is authored. Everything else is derived from it: five action states (idle,
sleep, walk, fight, run), two frames each, plus mirrored lunge and lean frames for a creature facing
left. Several transforms shift the body down, which is why the last row of every grid must stay
blank.
```

with:

```
One grid per species is authored. Everything else is derived from it: four action states (idle,
sleep, move, fight), two frames each, plus a mirrored lunge for a creature facing left. `move` is
the one movement state — walking and running both play it. Several transforms shift the body down,
which is why the last row of every grid must stay blank.
```

Then, in the same section, replace:

```
- **`Rez.Drawables` takes at most 254 members.** A bitmap per frame would need 406. Both frames of a
  state therefore share one file, stacked, and `Sprites.draw` clips to the half it wants. Do not
  split them back out.
```

with:

```
- **`Rez.Drawables` takes at most 254 members.** A bitmap per frame would need 290. Both frames of a
  state therefore share one file, stacked, and `Sprites.draw` clips to the half it wants. Do not
  split them back out.
```

- [ ] **Step 2: Update the variant table in `tools/sprites/CLAUDE.md`**

Replace the seven-row table under **The five action states** — including that heading and its
intro paragraph — with:

```markdown
## The four action states

Only the base grid is authored. `generate_sprites.py` derives every state from it, so the artist
maintains 29 grids instead of 116 and a new species costs one grid rather than four.

| Slot | Variant | Derivation |
|---|---|---|
| 0 | `idle` | frame A neutral, frame B whole body down 1 — the breath |
| 1 | `sleep` | squashed to 60% height, resting on row 21, then down 1 |
| 2 | `move` | body shifts ±d, legs counter-shift ∓2d (d ≤ 2) — a two-frame stand-in for Blair, not a walk |
| 3 | `fight` | frame A neutral, frame B shifted forward f and lifted 1 (f ≤ 2) — a lunge that snaps back |
| 4 | `fight_left` | slot 3 mirrored |

Slot order is load-bearing: it is the `ACTION_*` numbering in `source/ui/Sprites.mc`, indexed as
a flat array. Reorder `VARIANTS` and every creature plays the wrong animation.

`move` is the one movement state: walking and running both draw it. There was a separate `run`,
sheared forward with its legs split, plus a `run_left` mirror. Both animated at `FRAME_MS`, so at
72px the shear read as a second waddle rather than as a run, and giving it a real cadence would
have meant retiming the views' redraw timer for as long as someone was running. Three of seven
variants were spent on movement; now it is one of five.

Only the lunge has a direction in it, which is why only it is mirrored. In battle the player's
creature commits right and the enemy left; a shared rightward lunge would have the enemy striking
away from its target. Idle, sleep and move carry no direction — move swings both ways across its
two frames — so mirroring them would cost resources to say nothing.

Legs are rows 17–22. The move shift is doubled on those rows because the body shift already moved
them; at 1x the two cancel and the feet stay planted, which reads as a wobble rather than a step.

What a derived pose can be is limited and the transforms are honest about it: these are motion
cues built from one silhouette — bob, waddle, lunge. A sleeping creature here is a squashed
creature, not a curled-up one. If a species needs a real pose, hand-author it.
```

- [ ] **Step 3: Update the clamping note list**

In the **Clamping** subsection, replace the example block and the paragraph under it:

```
note: pyrewarden fight: no room for the lunge reach, using a bob instead
note: abyssward walk: no room for the sideways swing, using a bob instead
note: gleammote walk: no room for the sideways swing, using a bob instead
```

Five notes are expected today (pyrewarden fight; abyssward walk + fight; gleammote walk + fight).
```

with:

```
note: pyrewarden fight: no room for the lunge reach, using a bob instead
note: abyssward move: no room for the sideways swing, using a bob instead
note: gleammote move: no room for the sideways swing, using a bob instead
```

Five notes are expected today (pyrewarden fight; abyssward move + fight; gleammote move + fight).
```

- [ ] **Step 4: Update the Blair section and the per-state list**

Retitle **Walk follows Blair** to **Move follows Blair**, and change its first sentence from:

```
`assets/blair-walk.jpg` is the spec for the `walk` state.
```

to:

```
`assets/blair-walk.jpg` is the spec for the `move` state. A stride is what it specifies, and a
stride is what the state depicts at either cadence.
```

Rename the subsection **Stop-motion rules that come out of `emberling.walk`** to **... `emberling.move`**, and update the `emberling.walk` reference inside it.

In the per-state **what actually reads at this size** list, replace the `walk` and `run` bullets:

```
- **walk** — Blair. Feet must change *which* foot is forward, not merely translate; the body dips
  and lifts one row between contacts. See *Walk follows Blair* above.
```
```
- **run** — reads through *distance travelled between frames*, not frame rate. Lean, then leave
  the ground.
```

with the single bullet:

```
- **move** — Blair. Feet must change *which* foot is forward, not merely translate; the body dips
  and lifts one row between contacts. See *Move follows Blair* above.
```

- [ ] **Step 5: Update the 254 budget section**

Replace the body of **The 254 budget** with:

```markdown
`Rez.Drawables` takes at most 254 members. Both frames of a derived state therefore share one
stacked bitmap and `Sprites.draw` clips to the half it wants — one `setClip` per draw. A bitmap
per frame would need 290 and would not build.

Current spend: 29 species x 5 variants = 145, plus `LauncherIcon` = 146. Each new species costs 5,
so there is room for about 21 more. Past that, the fix is fewer variants per species, not more
drawables. Do not split stacked frames back out.
```

- [ ] **Step 6: Update the "What lives here" file count**

At the top of `tools/sprites/CLAUDE.md`, change:

```
- `resources/drawables/<species>/<species>_<variant>.png` — 203 files today
```

to:

```
- `resources/drawables/<species>/<species>_<variant>.png` — 145 files today
```

- [ ] **Step 7: Confirm no stale count or state name survives in the docs**

Run:
```bash
grep -rn 'run_left\|five action states\|203 files\|x 7 variants\|406\|about 7 more\|about seven more' \
  CLAUDE.md tools/sprites/CLAUDE.md
```

Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add CLAUDE.md tools/sprites/CLAUDE.md
git commit -m "docs(sprites): four action states, 146 drawables

The budget arithmetic was the load-bearing part: it said room for about
seven more species, which is now about twenty-one."
```

---

### Task 8: Full verification

Everything above is committed. This task proves the whole change holds together and touches no
source — if a step here fails, fix it in the task that owns the file and re-run this one.

**Files:** none modified.

**Interfaces:** consumes everything from Tasks 1–7.

- [ ] **Step 1: Generator is clean and the counts are right**

Run:
```bash
python3 tools/sprites/generate_sprites.py --check
find resources/drawables -name '*.png' | wc -l
grep -c '<bitmap' resources/drawables/drawables.xml
```

Expected: `145 sprites up to date` and exit 0; `146`; `146`.

Both 146s count the hand-authored launcher icon, which is a `<bitmap id="LauncherIcon">` entry in
`drawables.xml` and a top-level `launcher_icon.png` that the generator neither writes nor sweeps.
145 of each are generated. `<bitmap>` count is the number that matters: it is the `Rez.Drawables`
spend, against a hard cap of 254, and it was 204 before this change.

- [ ] **Step 2: Release build passes strict type check**

Run:
```bash
export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonster.prg -y developer_key.der -l 3
```

Expected: exit 0, no ERROR lines.

- [ ] **Step 3: Unit tests pass**

Run:
```bash
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonsterTest.prg -y developer_key.der -l 3 --unit-test
"$CIQ_SDK/bin/monkeydo" GMonsterTest.prg fenix6pro -t
```

Expected: every test passes; no `FAILED` lines. `monkeydo` stays in the foreground while the app runs — that is not a hang.

- [ ] **Step 4: No stale identifier anywhere in the repo**

Run:
```bash
grep -rn 'ACTION_RUN\|ACTION_WALK\|SLOT_RUN_LEFT\|RUN_ENTER\|RUN_EXIT\|WALK_ENTER\|WALK_QUIET' \
  source/ tools/ Makefile DEBUG.md CLAUDE.md
```

Expected: no output. The design doc under `docs/superpowers/specs/` legitimately names these — it is the record of removing them — so it is excluded from this sweep.

- [ ] **Step 5: The forced poses work in the simulator**

The simulator must already be running. Then:

```bash
make run DEBUG_FORCE_ACTION=move
```

Expected: the build prints `debug: force-action=move`, and the ally on the ALLY page animates its two-frame movement — emberling shows its four-frame cycle. Then:

```bash
make run DEBUG_FORCE_ACTION=run
```

Expected: the build fails before compiling, with `debug config: DEBUG_FORCE_ACTION: expected one of fight, idle, move, sleep, got 'run'`.

- [ ] **Step 6: The battle intro still reads as a charge**

Run:
```bash
make run DEBUG_INSTANT_BATTLE=1 DEBUG_BATTLE_ENEMY=glacierjaw
```

Expected: the encounter intro plays, the enemy slides in from off screen to its resting position, and it animates while sliding. It no longer leans into the slide — that is the accepted loss, not a bug. Confirm nothing is drawn clipped or mispositioned.

- [ ] **Step 7: Clear the debug build and confirm the committed config is untouched**

Run:
```bash
make debug-off
git status --porcelain
```

Expected: `git status --porcelain` is empty. Everything is committed and `source/DebugConfig.mc` is back to its all-off committed form.

- [ ] **Step 8: Review the whole change as one diff**

The first implementation commit is Task 1's. Find it and diff from its parent:

```bash
BASE=$(git log --format=%H --grep='delete orphaned PNGs inside species directories' -1)^
git log --oneline "$BASE"..HEAD
git diff --stat "$BASE"..HEAD -- . ':!docs/superpowers'
```

Expected: seven commits, one per task. The diff shows 87 PNG deletions and 29 PNG additions, and touches no file this plan does not name. The `:!docs/superpowers` exclusion keeps the spec and this plan out of the count — they are the record of the change, not part of it.

## Not doing

- No speed split between walking and running. `FRAME_MS` is also the views' redraw timer period, so a 250 ms frame sampled by a 500 ms timer freezes a two-frame animation.
- No `move_left` mirror.
- No change to `emberling`'s four-frame authored cycle beyond its header rename, or to its `sleep` and `idle` overrides.
- No change to `FRAME_MS`, `SLEEP_FRAME_MS`, `GMonsterView.mc:51`, or `CharacterSelectView.mc:29`.
- No `git push`, PR, or merge.
