# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

A Garmin Connect IQ watch-app written in **Monkey C**. A walking-driven creature-battler: real
pedometer steps advance a journey through areas, which queues encounters and guardian fights.
`README.md` documents the game rules (journey, combat wheel, evolution). `DTECTOR_SPEC.md` is the
reverse-engineered spec the mechanics derive from — reference only, clean-room; do not copy assets
or data from it.

## Build / run / test

No package manager, no test runner. Everything goes through the SDK's `monkeyc` / `monkeydo`.

```bash
export CIQ_SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"

# Compile. -l 3 is strict type check — always build with it.
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonster.prg -y developer_key.der -l 3

# Run: simulator must already be running in another process.
"$CIQ_SDK/bin/connectiq"
"$CIQ_SDK/bin/monkeydo" GMonster.prg fenix6pro

# Unit tests: separate build with --unit-test, run with -t.
"$CIQ_SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o GMonsterTest.prg -y developer_key.der -l 3 --unit-test
"$CIQ_SDK/bin/monkeydo" GMonsterTest.prg fenix6pro -t

# Store package: -e builds every product in manifest.xml.
"$CIQ_SDK/bin/monkeyc" -e -f monkey.jungle -o GMonster.iq -y developer_key.der -l 3
```

- `monkeydo` stays in the foreground while the app runs. That is not a hang.
- Tests are `(:test)`-annotated free functions in `source/tests/`; `monkeyc` drops them from
  non-`--unit-test` builds. There is no way to run a single test — the whole suite runs.
- Installed simulator targets: `ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Devices"`.

## Architecture

Layered so the game logic can be unit-tested without a device.

- **Pure logic** — `source/combat/*`, `source/journey/Journey.mc`, `source/tamer/Evolution.mc`.
  No `Storage`, no `WatchUi`. `Combat.BattleEngine` takes its `Rng` by injection, so a battle
  replays identically from a stored seed. Keep it that way; tests depend on it.
- **Persistence** — `source/GameState.mc` is the only wrapper over `Application.Storage` for player
  state; `source/journey/JourneyState.mc` for the trek. Storage keys are `KEY_*` consts at the top
  of those modules — add new keys there, never as inline string literals.
- **Views/Delegates** — one `XView.mc` + `XDelegate.mc` pair per screen, under a feature dir
  (`battle/`, `party/`, `journey/`, `tamer/`, `intro/`). The main view is a 4-page pager
  (`PAGE_STATS/JOURNEY/TAMER/PARTY`) with a 1 Hz redraw timer started in `onShow`, stopped in
  `onHide`.
- **Drawing** — go through `source/ui/Theme.mc`. Views never name a `Graphics.COLOR_*` directly;
  the app is deliberately two-tone and emphasis is inversion, not tint.

### Background scope

`(:background)` files: `GMonsterApp.mc`, `BackgroundService.mc`, `journey/{Journey,JourneyState,StepTracker}.mc`,
`combat/Rng.mc`. The background context only permits a restricted API subset, and the annotation is
viral — pulling a new dependency into a `(:background)` file drags that file into background scope
too, and `-l 3` will reject it. `GMonsterApp.getInitialView()` is the one deliberate escape
hatch, via `(:typecheck(disableBackgroundCheck))`.

Background sync runs every 300s (the platform minimum) and only calls
`Background.requestApplicationWake` when an event actually triggered. The foreground syncs on
`onShow` and every 10 ticks.

### Data

Creature roster, rarity tiers, worlds, and starters are JSON in `resources/data/`, registered as
`jsonData` in `resources/data/data.xml` and parsed lazily by `Combat.Bestiary` / `Atlas`. Re-tuning
or adding a species is a JSON edit, not a code edit. Strings go in `resources/strings.xml`.

### Sprites

`resources/drawables/*_0.png` / `*_1.png` are **generated** — do not hand-edit them. The art lives as
24x24 ASCII in `tools/sprites/sprites.txt` (`#` ink, `.` clear), one grid per species key:

```bash
python3 tools/sprites/generate_sprites.py           # rewrite the PNGs
python3 tools/sprites/generate_sprites.py --check    # fail if PNGs are stale
```

Only frame A is authored; frame B is derived by shifting the grid down one row, which is the idle
breath. That is why the last row of every grid must stay blank. Adding a species means a grid in
`sprites.txt`, a `<bitmap>` pair in `resources/drawables/drawables.xml`, and an entry in the
`Sprites.index()` table. `Sprites.draw` still returns false for an unknown key, so the text fallback
survives if any of the three is missed.

## Conventions

- Doc comments use `//!` and explain *why*, not what. Match that — the codebase is heavily
  rationale-commented and it is load-bearing for the game-balance code.
- Explicit types on declarations and returns (`as Number`, `as Void`, `as Array<Creature>?`);
  `-l 3` enforces it.
- Private fields are `_underscored`; module-level constants are `SCREAMING_SNAKE`.
- Modules for stateless/logic namespaces, classes for things with instance state or a UI lifecycle.

## Repo hygiene

- `DEBUG.md` documents the compile-time debug flags (instant battle, encounter pacing). They are
  plain constants, not `(:debug)` code, so they ship as written — check they are all off before
  packaging with `-e`.
- `developer_key.der` / `.pem` are signing keys, gitignored — never commit or print them.
- `gen/` and `external-mir/` are compiler artifacts. `external-mir/` is currently tracked in git;
  do not hand-edit `.mir` files, they are regenerated on every build.
- `*.prg`, `*.prg.debug.xml`, `*.iq` are gitignored build output.
