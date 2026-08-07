# Debug flags

Switches for exercising the game without walking to an encounter. All are plain compile-time
constants — flip one, rebuild, relaunch.

> **Reset every flag to its default before packaging a release.** These are constants, not
> `(:debug)`-annotated code, so they compile into store builds exactly as written. See
> [Why not `(:debug)`?](#why-not-debug) below.

## Current defaults

| Flag | File | Default | Effect when changed |
|---|---|---|---|
| `DEBUG_EVENT_GAP` | `source/journey/Journey.mc:35` | `0` (off) | Steps between trek events. Non-zero collapses every gap to that many steps. |
| `DEBUG_INSTANT_BATTLE` | `source/GMonsterApp.mc:22` | `false` | `true` launches straight into a battle instead of the pager. |
| `DEBUG_BATTLE_ENEMY` | `source/GMonsterApp.mc:26` | `"glacierjaw"` | Species fought in that battle. Only read when `DEBUG_INSTANT_BATTLE` is on. |
| `DEBUG_BATTLE_IS_BOSS` | `source/GMonsterApp.mc:29` | `false` | Shows that battle as an area guardian. Only read when `DEBUG_INSTANT_BATTLE` is on. |

Verify they are all off before a release build:

```bash
grep -rn "DEBUG_EVENT_GAP = \|DEBUG_INSTANT_BATTLE = " source/
# expect: DEBUG_EVENT_GAP = 0   /   DEBUG_INSTANT_BATTLE = false
```

---

## `DEBUG_EVENT_GAP`

Normal pacing rolls 300, 400 or 500 steps between events, which makes any change to battles or
rewards slow to test. Set this to something small — 50 is comfortable — to trigger events almost
immediately.

```monkeyc
const DEBUG_EVENT_GAP = 50;   // source/journey/Journey.mc
```

Three things make it behave:

- **Every gap path goes through `rollEventGap`** — `Atlas.ensureTrek`, `Atlas.advanceToNextArea`,
  the `Reward` area jump, and the reroll inside `Trek.advance`. There is no fourth way to set a gap.
- **`clampEventGap` is applied in `JourneyState.peekTrek`**, so a save persisted *before* the flag
  was switched on does not have to walk down its stored gap first. Without it a save sitting on 380
  steps would still owe all 380.
- **The generator is consumed either way.** `rollEventGap` performs the roll and then discards it,
  so a seeded trek replays step-for-step with the flag on or off. The `Rng`-injection design in
  `Combat.BattleEngine` depends on that.

`Journey.eventGapMin()` / `eventGapMax()` follow the override rather than restating 300/500, which
is why `JourneyTests` stays green with the flag on instead of having to be loosened.

Turning it off is a single edit — set it back to `0`. A save carrying a clamped gap rerolls into the
real range at its next event.

## `DEBUG_INSTANT_BATTLE`

Opens the battle scene on launch, zero steps required. Useful for looking at sprite work and the
turn animation.

```monkeyc
private const DEBUG_INSTANT_BATTLE = true;    // source/GMonsterApp.mc
private const DEBUG_BATTLE_ENEMY = "twinflare";
private const DEBUG_BATTLE_IS_BOSS = false;
```

**The preview writes nothing.** `Encounter.preview` calls `BattleView.markPreview()`, which sets
`_settled = true` up front — reusing the guard that already stops a battle paying out twice, so
`settleBattle` becomes a no-op. No experience, focus, recruits, spirit power, party levels or trek
changes. It also uses a fixed `Encounter.PREVIEW_SEED` rather than `GameState.nextSeed()`, which
persists the advanced seed and would have made the preview a Storage write; that also means the
fight replays identically on every launch, so an animation change is the only thing that differs
between two runs.

Consequences worth knowing:

- **The payout screen reads `+0 XP`.** Correct, not a bug — a preview earns nothing.
- **The rest of the app is unreachable** while the flag is on. That is the point.
- **BACK, or dismissing the payout, exits the app** rather than returning to the pager, because the
  battle is the only view on the stack.
- **It deliberately bypasses `Encounter.canBegin`**, the gate that keeps battles earned by walking.
  Safe only because the preview pays out nothing.
- The flag is checked *after* the starter gate, since a battle needs a partner to field and a fresh
  save has not chosen one yet.

### `DEBUG_BATTLE_ENEMY`

Any species key from `resources/data/creatures.json`. An unrecognised key falls back to a
level-appropriate random encounter, so this doubles as a way to eyeball any creature's sprite in the
battle scene:

```monkeyc
private const DEBUG_BATTLE_ENEMY = "voidsentinel";
```

### `DEBUG_BATTLE_IS_BOSS`

`true` marks the enemy name with `*` and uses the guardian intro string, for checking the boss
presentation without clearing an area.

---

## Why not `(:debug)`?

Connect IQ has `(:debug)` / `(:release)` annotations that would make these structurally unshippable.
They are not used here because **the unit-test build is a debug build** — `monkeyc --unit-test`
would take the debug path, so the suite would run against 50-step gaps and an instant battle rather
than the real game.

The tradeoff is that nothing stops a flag reaching a store package except remembering to reset it.
Hence the check at the top of this file.
