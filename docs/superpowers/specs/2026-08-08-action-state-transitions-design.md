# Action state transitions — design

**Date:** 2026-08-08
**Status:** approved, not yet implemented
**Scope:** `source/ui/Motion.mc`, `source/tests/MotionTests.mc`

## Problem

`Motion` decides what the creature on the main view is doing — idle, walk, run, sleep — from the
pedometer. The thresholds exist but the transitions between them were never designed:

- The state is only re-decided at a 10 s window boundary, so the creature is up to 10 s behind the
  wearer in both directions.
- Entry and exit use the same threshold, so a cadence sitting near 20 spm can flip the state every
  window.
- Nothing distinguishes starting an activity from ending one, which is the distinction that makes a
  creature look like it is following you rather than lagging you.

Fight and the left-facing slots are chosen by `BattleView` and are out of scope. This design covers
only the four states `Motion` owns.

## Constraints

Decided during brainstorming, and each one narrows the design:

- **Pedometer only.** No heart rate, no activity class, no clock. `classify` stays pure so the
  thresholds remain testable without a device, which is the existing contract `MotionTests` relies
  on.
- **Fast in, slow out.** Enter a livelier state on first evidence; leave it only once it has clearly
  ended. Asymmetry, not damping, is what stops the flicker.
- **Sleep unchanged at 5 min.** 300 s of no steps and the creature sleeps, wherever you are. Sitting
  through a meeting putting it under is accepted, not a bug.
- **Memory only.** No storage writes. State is thrown away on `onHide` as it is today.
- **Cold start is idle.** `reset()` on every `onShow` keeps its current behaviour: opening the app
  always shows idle, and sleep needs a fresh 5 min of stillness.
- **No new art.** Every `Sprites.ACTION_*` value, every drawable and the whole sprite pipeline are
  untouched.

## Approach

Bucket step deltas into one-second slots and run the transition table on every sample. Two window
sums come out of the buffer: a short one for entry evidence and a longer one for exit evidence. The
asymmetry the design needs is then a property of *which window a rule reads*, not of extra timers.

Two alternatives were considered and rejected:

- **EWMA cadence with dual thresholds.** Smallest state, but the smoothing constant is opaque, "two
  steps in three seconds" stops being expressible, and every threshold test has to simulate a ramp
  to reach the assertion.
- **Ring of step timestamps.** Cadence from the gaps between individual steps. The pedometer reports
  a delta per sample, not an event per step, so a burst of five steps in one tick has no individual
  times — the run threshold would be computed from invented data at exactly the cadence where it
  matters.

## The transition table

`classify` is a priority list evaluated top to bottom on every sample:

```
classify(state, steps3s, steps5s, sinceStepMs) -> state

1. sinceStepMs >= SLEEP_AFTER_MS   (300_000)  -> SLEEP
2. sinceStepMs >= WALK_QUIET_MS      (5_000)  -> IDLE
3. state == RUN                               -> steps5s >= RUN_EXIT_STEPS ? RUN : WALK
4. steps3s >= RUN_ENTER_STEPS                 -> RUN
5. steps3s >= WALK_ENTER_STEPS                -> WALK
6. state == WALK or state == RUN              -> WALK
   otherwise                                  -> IDLE
```

Why it is shaped this way:

- **Entry is judged over 3 s, exit over 5 s of silence.** That gap is the whole "fast in, slow out"
  behaviour. Starting to walk takes two steps in three seconds; stopping takes five seconds of
  nothing.
- **Rule 6 is the hysteresis.** Once walking, a single step every few seconds sustains the state,
  well below the cadence that would have started it. A 40 spm amble enters walk; a 20 spm shuffle
  can only sustain one.
- **Rule 3 is the run's hysteresis, and its dwell.** Enter at 120 spm over 3 s, leave below 96 spm
  over 5 s. The longer exit window *is* the dwell timer, so no separate timer exists to keep in
  sync.
- **Sleep and wake need one rule between them.** Sleep is a function of silence, so any step drops
  `sinceStepMs` to zero and rule 2 or rule 5 answers on the same sample. Waking is instant and has
  no case of its own.
- **Rules 4 and 5 do not care which state you were in**, so a standing start straight into a run
  reaches `RUN` without passing through `WALK`.

Two consequences worth stating:

- **A stop from a run is a deceleration, not a cut.** The 5 s exit sum decays as the sprint leaves
  the window, so a dead stop reads RUN → WALK after roughly three seconds and then IDLE at five.
  That is the intended shape — the creature slows down rather than snapping to a stand.
- **You cannot fall asleep from `RUN` or `WALK`.** Rule 2 has already moved the state to IDLE 295
  seconds before rule 1 can fire. Sleep still lands exactly 300 s after the last step, because both
  rules count from it.

## Constants

Cadences stay the tunables; the step counts derive from them, so a reader sees the intent rather
than a magic integer.

| Constant | Value | Derived | Meaning |
|---|---|---|---|
| `WALK_ENTER_SPM` | 40 | 2 steps / 3 s | evidence that a walk started |
| `RUN_ENTER_SPM` | 120 | 6 steps / 3 s | clear of a brisk walk, as today |
| `RUN_EXIT_SPM` | 96 | 8 steps / 5 s | below this for 5 s and the run is over |
| `WALK_QUIET_MS` | 5000 | — | silence that ends a walk |
| `SLEEP_AFTER_MS` | 300000 | — | unchanged |
| `BUCKET_MS` | 1000 | — | one slot per second |
| `BUCKETS` | 5 | — | 5 s of history, all the table reads |

`WINDOW_MS`, `RUN_SPM` and `WALK_SPM` are removed. Integer division is exact at every value above
(`120 * 3 / 60 = 6`, `96 * 5 / 60 = 8`, `40 * 3 / 60 = 2`), so the derivations need no rounding
rationale.

## Sampling

`sample()` keeps its shape and its guards; only the decision point moves.

```
now  = System.getTimer()
raw  = StepTracker.rawSteps()

lastRaw < 0                 -> first sample: seed lastRaw/lastStepAt/bucketStart, return
now < bucketStart           -> millisecond clock wrapped: reset as above, return

delta = raw - lastRaw
delta < 0                   -> midnight reset, delta = raw
lastRaw = raw

advance buckets by (now - bucketStart) / BUCKET_MS, zeroing each slot passed;
  a gap of >= BUCKETS slots clears the whole buffer
delta > 0                   -> add delta to the current bucket, lastStepAt = now

state = classify(state, steps3s, steps5s, now - lastStepAt)
```

The one behavioural change is the last line: `classify` runs on every sample instead of at a window
boundary. The old 10 s boundary was the latency, and deleting it is most of the responsiveness win.

The view's redraw timer is 1 Hz, which is where `BUCKET_MS` comes from, but nothing breaks if ticks
arrive slower or in bursts: slots are indexed by wall-clock second, so the sums stay windows over
real time rather than over sample counts.

`reset()` clears the buffer, sets `state = IDLE` and seeds `lastStepAt = now`.

`current()` is untouched, including the `DebugConfig.FORCE_ACTION` override, which continues to
bypass `_action` without affecting `classify`.

## Testing

`classify` stays pure, so the table is asserted directly.

**Per-rule tests** — one per numbered rule, including both sides of each threshold: 119 spm is not a
run, 120 spm is; 4 999 ms of silence is still a walk, 5 000 is not.

**Scenario tests** — `classify` called in sequence with hand-computed sums:

| Scenario | Asserts |
|---|---|
| stroll, one step every 2 s | enters WALK and never returns to IDLE — the anti-strobe test |
| sprint, then a dead stop | RUN → WALK once the 5 s sum falls under the exit, then IDLE at exactly 5 s of silence |
| run slowing to a walk | leaves RUN at the 96 spm exit and not at 119 spm |
| still 5 min, then one step | IDLE → SLEEP at 300 s, SLEEP → IDLE on the next sample |
| cold start | `classify(IDLE, 0, 0, 0)` is IDLE, so an opened app is never mid-stride |

`sample()` remains untested: it reads `StepTracker` and `System` directly, exactly as it does today,
and the logic worth testing has been kept out of it.

Run with:

```bash
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonsterTest.prg -y developer_key.der -l 3 --unit-test
"$CIQ_SDK/bin/monkeydo" GMonsterTest.prg fenix6pro -t
```

The simulator has no legs, so on-screen poses stay verified the existing way —
`make run DEBUG_FORCE_ACTION=walk`.

## Risks

- **Retuning is guesswork until it is worn.** Every number here is reasoned from cadence, not
  measured on a wrist. The constants are the tuning surface; the table should not need to change
  when they do.
- **Faster classification costs a little CPU per redraw.** It is integer arithmetic over five slots
  on a timer that already runs at 1 Hz, so the cost is far below the redraw it rides on.
- **`MotionTests` is rewritten, not extended.** The signature of `classify` changes, so the old
  assertions cannot be kept as a regression net. The per-rule tests above are their replacement and
  should be written first.
