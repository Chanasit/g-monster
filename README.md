# g-monster

A step-driven creature companion for Garmin Connect IQ. Walking is the game: real pedometer steps
carry your ally across a chain of areas, turning up encounters and guardians along the way.

Four pages, UP / DOWN to move between them:

- **ALLY** — your creature, its standing, and whatever the road is holding. The app opens here.
- **STATS** — steps, distance, calories, step-goal bar.
- **JOURNEY** — current area, distance left, what is waiting.
- **TAMER** — player level, focus, battle record.

START fights whatever the journey is waiting on. MENU opens the roster editor on PARTY, or
evolution on TAMER.

## Journey

Walking drives the game. Real pedometer steps (`ActivityMonitor`) cross a chain of six areas:

- Every step spends one unit of area distance and one off the encounter counter.
- The counter hitting zero queues an ambush, then rerolls to 300–500 steps.
- Distance reaching the end of the area queues its guardian.
- A pending event freezes progress. Steps walked meanwhile stay banked and land the moment the
  player resolves it, so nothing walked is ever lost.
- Beating the guardian moves on to the next area. Losing to it leaves the trek parked at the
  boundary, so the fight re-triggers.

A background service syncs steps every five minutes while the app is closed and wakes the watch only
when an event actually triggers. The foreground syncs on open and every ten seconds. Pedometer
readings reset at midnight; a reading below the stored baseline is treated as a new day, not as lost
ground.

## Layout

```
manifest.xml                        app id, type, target products, min API level
monkey.jungle                       build config
source/GMonsterApp.mc               AppBase entry point
source/GMonsterView.mc              rendering + refresh timer
source/GMonsterDelegate.mc          button/swipe handling
source/GameState.mc                 persistent player state (Storage)
source/BackgroundService.mc         5-minute step accrual while the app is closed
source/journey/Journey.mc           area table + Trek state machine (pure)
source/journey/JourneyState.mc      trek persistence, background-scoped
source/journey/StepTracker.mc       pedometer deltas, midnight-reset handling
source/battle/Encounter.mc          picks the fight the journey is waiting on
source/tamer/Evolution.mc           evolution gating and odds (pure)
source/tamer/EvolveView.mc          evolution screen
source/tamer/EvolveDelegate.mc      evolution input
source/combat/CombatStats.mc        live stats, attack indices, energy ranks
source/combat/Creature.mc           species record + level/stat/obedience scaling
source/combat/Bestiary.mc           species table + weighted encounter roll
source/combat/Progression.mc        experience and level math
source/combat/BattleEngine.mc       turn resolution, enemy AI, disobedience
source/combat/Rng.mc                seedable LCG (deterministic battles)
source/battle/BattleView.mc         battle screen
source/battle/BattleDelegate.mc     battle input
source/tests/CombatTests.mc         unit tests, (:test) annotated
resources/strings.xml               localized strings
resources/drawables/                launcher icon
```

## Combat model

Rock-paper-scissors over three attacks — **Crush > Energy > Ability > Crush**. The winner of an
exchange deals its own attack stat as damage. Same-attack clashes are settled on stats instead of the
wheel: energy compares a 16-step rank first, otherwise the side ahead by 5+ damage wins and deals only
the gap; anything closer is a no-damage stalemate.

A partner far above your own level may ignore the attack you picked, or refuse to act at all. Enemy
attack choice is a seeded PRNG weighted by its own stats, so a battle replays identically from a stored
seed. `Combat.BattleEngine` is pure logic — no UI, no storage — and takes its `Rng` by injection.

Design notes and the mechanics this was derived from are in `DTECTOR_SPEC.md`.

## Partner growth

Two currencies, earned differently, so both kinds of fight matter:

- **Growth** comes only from area guardians. Beating one hardens the partner by a level; losing to
  one sets it back. Ordinary encounters move the player's own level, not the partner's.
- **Focus** comes from any win, capped at 10.

Once a partner is maxed out for its form and has focus banked, MENU opens the evolution screen.
Committing more focus fakes a higher player level for the roll, so a long jump needs the whole pool.
Focus is spent whether or not the roll lands — that is the cost of trying early. A partner far below
its target still keeps a 5% floor rather than being locked out.

## Build

```bash
export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"

# Compile (-l 3 = strict type check)
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonster.prg -y developer_key.der -l 3
```

## Run

```bash
# 1. Start the simulator (leave it running)
"$CIQ_SDK/bin/connectiq"

# 2. Side-load the built app into it
"$CIQ_SDK/bin/monkeydo" GMonster.prg fenix6pro
```

`monkeydo` stays in the foreground for as long as the app runs — that is normal, not a hang.

## Test

Tests are `(:test)`-annotated, so `monkeyc` only compiles them into `--unit-test` builds.
The simulator must already be running.

```bash
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonsterTest.prg -y developer_key.der -l 3 --unit-test
"$CIQ_SDK/bin/monkeydo" GMonsterTest.prg fenix6pro -t
```

## Package for the store

```bash
"$CIQ_SDK/bin/monkeyc" -e -f monkey.jungle -o GMonster.iq -y developer_key.der -l 3
```

`-e` builds for every product listed in `manifest.xml`.

## Notes

- `developer_key.der` is the signing key. Keep it out of version control.
- Targets installed in the simulator: `ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Devices"`.
- `main.mc.bak` is the original stub, superseded by `source/`. Safe to delete.

## Powered by ASCII Arts
```
........................
........................
........................
........................
........................
............######......
...........########.....
..........#########.....
..........##########....
.........###########....
.........############...
........#############...
........##############..
.......####..#####..##..
.......####..#####..###.
......#####..#####..###.
......#####..#####..###.
.....##################.
....###################.
....###################.
...###################..
....#################...
....################....
........................
