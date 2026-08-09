# Debug flags

Switches for exercising the game without walking to an encounter. They are passed through the
**environment** and compiled in by the Makefile — nothing is hand-edited.

```bash
make run DEBUG_FORCE_ACTION=move
DEBUG_INSTANT_BATTLE=1 DEBUG_BATTLE_ENEMY=twinflare make run
make run DEBUG_EVENT_GAP=50
```

Unset means off, so a plain `make build` is always clean. Every build prints what is on:

```
$ make run DEBUG_FORCE_ACTION=move
debug: force-action=move
==> build fenix6pro
```

| Variable | Values | Default | Effect |
|---|---|---|---|
| `DEBUG_INSTANT_BATTLE` | `1`/`true`/`yes`/`on` | off | Boot straight into a battle instead of the pager. |
| `DEBUG_BATTLE_ENEMY` | a species key | `glacierjaw` | Which creature to fight there. Unknown key falls back to a roll. |
| `DEBUG_BATTLE_IS_BOSS` | `1`/`true`/`yes`/`on` | off | Show that battle as an area guardian. |
| `DEBUG_EVENT_GAP` | steps, e.g. `50` | `0` | Steps between trek events. `0` keeps the real 300/400/500 pacing. |
| `DEBUG_FORCE_ACTION` | `idle`\|`sleep`\|`move`\|`fight`\|`rock`\|`paper`\|`scissors` | off | Pin every creature to one pose instead of letting the pedometer choose. |
| `DEBUG_ALLY` | a species key | off | Lead the party with that species. Unknown key is ignored. Reads only — the save is untouched. |

Anything unparseable fails the build rather than compiling something unintended:

```
$ make build DEBUG_FORCE_ACTION=flying
debug config: DEBUG_FORCE_ACTION: expected one of fight, idle, move, sleep, got 'flying'
make: *** [debug-config] Error 2
```

Useful targets:

```bash
make debug-status    # what the current source/DebugConfig.mc has on
make debug-off       # clear every switch
```

## How it works

Monkey C has no preprocessor and no `-D` build define, and a watch app has no process environment to
read at runtime. So the switches cannot be read — they have to be *compiled in*.
`tools/debug/gen_debug_config.py` turns the `DEBUG_*` environment into `source/DebugConfig.mc`, and
the Makefile runs it before every build. The app just reads ordinary constants.

`source/DebugConfig.mc` is generated but **committed in its all-off form**, so building with
`monkeyc` directly, without make, still compiles. Do not hand-edit it; set the environment and
rebuild.

It is `(:background)` because `Journey` reads `EVENT_GAP` while the app is closed. That is also why
`FORCE_ACTION` is emitted as a bare integer rather than as `Sprites.ACTION_*` — referencing the
drawing layer would drag it into background scope. Those integers are slot indices and must keep
matching both `Sprites.ACTION_*` and the `VARIANTS` order in `tools/sprites/generate_sprites.py`.

> **`make release` and `make package` regenerate the config with `--off` first**, ignoring the
> environment entirely. A switch left exported in a shell therefore cannot ride into a store bundle.
> This replaces the old "remember to reset the constants" discipline.

## `DEBUG_EVENT_GAP`

Normal pacing rolls 300, 400 or 500 steps between events, which makes any change to battles or
rewards slow to test. Set this to something small — 50 is comfortable — to trigger events almost
immediately.

```bash
make run DEBUG_EVENT_GAP=50
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

Turning it off means simply not passing it. A save carrying a clamped gap rerolls into the
real range at its next event.

## `DEBUG_INSTANT_BATTLE`

Opens the battle scene on launch, zero steps required. Useful for looking at sprite work and the
turn animation.

```bash
make run DEBUG_INSTANT_BATTLE=1 DEBUG_BATTLE_ENEMY=twinflare
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

```bash
make run DEBUG_INSTANT_BATTLE=1 DEBUG_BATTLE_ENEMY=voidsentinel
```

### `DEBUG_BATTLE_IS_BOSS`

`true` marks the enemy name with `*` and uses the guardian intro string, for checking the boss
presentation without clearing an area.

## `DEBUG_FORCE_ACTION`

The ally on the ALLY page mirrors its tamer — `GMonsterView` draws it with `Motion.current()`, which
classifies pedometer cadence into idle, move or sleep. A simulator has no legs, so it sits at
`ACTION_IDLE` and the other two poses are unreachable without walking around wearing the watch.

Pin it to one pose instead:

```bash
make run DEBUG_FORCE_ACTION=move
```

Any of `idle`, `sleep`, `move`, `fight`, `rock`, `paper`, `scissors`. Omitting it hands control back
to the pedometer. Everything past `move` is reachable only this way on the ALLY page — the pedometer
never classifies any of them.

The three attacks are hand-drawn per species and most of the roster has none, so pinning one shows
the ally's name in text for every creature that does not have it. Pair it with `DEBUG_ALLY`:

```bash
make run DEBUG_ALLY=slime DEBUG_FORCE_ACTION=rock    # the hammer, without rolling for it in a battle
```

In a real battle the fallback is the fight stance rather than text — `BattleView` asks
`Sprites.hasAction` first, so a creature without attack art still throws its blow.

Only `Motion.current` consults it. `Motion.classify` stays pure and untouched, so `MotionTests` goes
on asserting the real `MOVE_ENTER_SPM` / `SLEEP_AFTER_MS` thresholds with the override on — the
suite is not quietly weakened to accommodate the cheat.

## `DEBUG_ALLY`

`DEBUG_BATTLE_ENEMY` can put any species on the enemy side of a battle, but there was no equivalent
for the player's own creature: seeing a species as the ally meant recruiting it and promoting it to
slot 0, which is a walk. This names the lead directly.

```bash
make run DEBUG_ALLY=slime
make run DEBUG_ALLY=slime DEBUG_FORCE_ACTION=move    # that creature's move cycle, on demand
```

Any key from `resources/data/creatures.json`. An unknown key is ignored and the real lead stands, so
a typo degrades to the normal game rather than to an empty party.

**It is read-only.** `Party.lead` returns the forced species without calling `setSlot`. That is the
whole design constraint: a build-time flag that wrote slot 0 would persist into the save and still be
there after a rebuild with the flag off, having replaced whatever the player actually led with.
Storage is never touched, so turning the flag off restores the real lead immediately.

The check sits in `Party.lead` rather than in the views because every consumer already resolves
through it — the ALLY page, the player side of a battle, and the evolve screen. One check covers all
three and no view has to know a debug switch exists.

Two consequences of it being an override rather than a real party change:

- **The PARTY page still shows the real slot 0.** It lists slots through `Party.slot`, not through
  `lead`. The discrepancy is deliberate — the page is about roster storage, which the flag does not
  alter.
- **Growth banked while it is on lands on the forced species.** `partnerExtraLevel` keys off
  `partnerKey`, which is `lead().key`. Levels earned under `DEBUG_ALLY=slime` are slime's, and they
  stay in the save after the flag goes away.

---

## Why not `(:debug)`?

Connect IQ has `(:debug)` / `(:release)` annotations that exclude code per build type. They are not
used here because **the unit-test build is a debug build** — `monkeyc --unit-test` would take the
debug path, so the suite would run against 50-step gaps and an instant battle rather than the real
game.

Generating the config instead keeps tests on the real values by default, and `make release` /
`make package` provide the shipping guarantee the annotations would have given.
