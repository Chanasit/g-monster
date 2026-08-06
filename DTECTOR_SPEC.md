# D-Tector v2 — reverse-engineered mechanics spec

Source: `github.com/kaisadilla/D-Tector-v2` (Unity 2019-era C#, `Kaisa.Digivice` namespace, version string `0.20.0513a`).
No LICENSE file in the repo — assume all rights reserved. Game *rules* below are safe to reimplement;
sprites, audio, `digimonDB.json`, and the C# source are not. A Garmin port must be a clean-room rewrite
with its own creature data and art.

## 1. Platform model

Simulates a Digivice: a 32x32 logical pixel screen (`Constants.SCREEN_WIDTH/HEIGHT = 32`, each logical
pixel drawn at `PIXEL_SIZE = 24` real px), 4 buttons (A, B, Left, Right), and an accelerometer.

Screen is built from composable `ScreenElement` builders — `SpriteBuilder`, `TextBoxBuilder`,
`RectangleBuilder`, `ContainerBuilder` — all positioned in the 32x32 grid. `Animations.cs` (2900 lines)
is a library of scripted animation coroutines enqueued onto `ScreenManager`.

### Input
`LogicManager.InputA/B/Left/Right` (plus Down/Up variants for hold detection) dispatch to whichever
`IAppController` is loaded, or to the menu when none is.

### Step counting (the core loop driver)
`ShakeDetector` runs a low-pass filter on accelerometer input:
- `accelUpdateInterval = 1/60`, `lowPassKernelWidthInSeconds = 1.0`, threshold `2.0` (squared before compare)
- `lowPassValue = Lerp(lowPassValue, acceleration, interval/kernelWidth)`; shake when `(accel - lowPassValue).sqrMagnitude >= threshold²`
- Debounce: **6 shakes = 1 step** (`nextStep` counts to 5, then emits)
- 150 idle frames without a shake sets `isCharacterWalking = false`

Each step calls `GameManager.TakeAStep()` → `WorldMgr.TakeSteps(1)` + `WorldMgr.ReduceDistance(1)`.

> **Garmin port note:** this is the one subsystem you should *not* copy. Connect IQ gives you a real
> pedometer via `ActivityMonitor.getInfo().steps`. Drive the loop off the step delta since last tick and
> delete the shake filter entirely.

## 2. Persistent state (`SavedGame`)

Stored in `EncryptedPlayerPrefs`. Fields that matter:

| Field | Meaning |
|---|---|
| `name`, `gameChar` | player name, chosen character |
| `playerExperience` | drives level; capped at 1,000,000 |
| `spiritPower` | 0–99 (`MAX_SPIRIT_POWER`) |
| `currentMap`, `currentArea`, `currentDistance` | world position |
| `steps`, `stepsToNextEvent` | pedometer state |
| `pendingEvent` | 0 none, 1 regular event, 2 boss (distance hit 1) |
| `battleSeed[3]` | saved RNG seeds for deterministic enemy AI |
| `totalBattles`, `totalWins` | stats |
| `ddockDigimon[4]` | the 4 party slots ("D-Docks") |
| `areasCompleted[map][area]`, `bosses[][]`, `semibossGroup[]` | world progress |
| `isPlayerInsured` | one-shot protection against XP loss |
| `isLeaverBusterActive`, `leaverBusterExpLoss`, `leaverBusterDigimonLoss` | penalty for force-quitting a battle |
| `jackpotValue` | jackpot minigame pot |

Per-creature: an unlock level integer. `unlocked == level > 0`; `extraLevel == level - 1`.

## 3. Progression math

**Player level** — pure cube root of XP:
```
level = floor(xp ^ (1/3))          // xp 0 => level 1
levelFloorXp  = level³
levelTopXp    = (level+1)³
progress      = (xp - levelFloorXp) / (levelTopXp - levelFloorXp)
```
Level up forcibly: set `xp = ceil((level+1)³)`. Level down: subtract `(level+1)³ - level³`, clamped
to `(level-1)³`.

**Insurance** — losing XP while `isPlayerInsured` consumes the flag instead of deducting. Dropping a
level *sets* the flag, so you can never lose two levels back to back. Gaining XP clears it.

**XP awarded per win** (`friendlyLevel` = your creature, `enemyLevel` = defeated):
```
a = 30 * enemyLevel
b = (2*enemyLevel + 10) ^ 2.5
c = (enemyLevel + friendlyLevel + 10) ^ 2.5
d = min(0.5, 0.025 + 0.025 * friendlyLevel)
xp = ceil((a * (b/c) + 1) * d)
```
Pokémon-style: `b/c` decays hard when you outlevel the enemy, `d` scales the award with your own level.

## 4. Creature data model

`digimonDB.json` — 593 entries:
```json
{"number":8,"order":1,"name":"agumon","stage":0,"spiritType":6,"abilityName":"flames_1",
 "element":0,"evolution":"greymon","extraEvolutions":["geogreymon","centarumon",...],
 "disabled":false,"baseLevel":4,"stats":{"HP":40,"EN":25,"CR":15,"AB":20},
 "bossStats":null,"isPseudo":false,"code":"vsjk1"}
```
- `Stage`: Rookie, Champion, Perfect, Mega, Ultimate, Armor, Spirit
- `SpiritType`: Human, Animal, Hybrid, Ancient, Fusion, Child
- `Element`: Fire, Light, Thunder, Wind, Ice, Dark, Earth, Wood, Metal, Water
- `code` — a 5-char digicode the player can type in the Digits app to unlock the creature
- `isPseudo` — exists for battles but doesn't count toward the collection

`frontier_rarities.json` maps each name to `Rarity` (Common / Rare / Epic / Legendary / Boss) plus an
`exclusive` flag. Only the first four rarities are `EligibleForBattle`.

**Stat block:** HP, EN (energy attack), CR (crush attack), AB (ability attack). EN/CR/AB double as both
attack-selection weights and raw damage.

### Level ceilings
```
Rookie:            maxLevel = baseLevel * 2
Spirit / Armor:    maxLevel = baseLevel        (no extra levels)
everything else:   maxLevel = ceil(baseLevel * 1.5)
maxExtraLevel = maxLevel - baseLevel
```

### Stat scaling
```
friendly:      stat * (1 + 0.5 * extraLevel/maxExtraLevel), ceil     // 100% -> 150% at cap
regular boss:  stat * (0.20 + 0.008 * bossLevel), round             // 20% -> 100% at lvl 100
spirit boss, by spiritType:
  Human:       stat * (0.25 + 0.005 * bossLevel)                    // 25% -> 75%
  Ancient:     stat * (0.20 + 0.008 * bossLevel)
  other:       stat * (0.30 + 0.007 * bossLevel)
```
Boss level = player level, except Ancient spirits (`round(20 + 0.8 * playerLevel)`) and Armor
(`max(10, playerLevel)`).

## 5. Battle system

Rock-paper-scissors over three attacks, indexed **0 = Energy, 1 = Crush, 2 = Ability** (3 = idle/no attack).

**Type wheel:** Crush beats Energy, Energy beats Ability, Ability beats Crush. Winner deals its own
attack stat as damage.

**Mirror match** (same attack chosen):
- Energy vs Energy: compare `GetEnergyRank()` first — a 16-step bucketing of EN
  (`<20, <30, <45, <60, <75, <90, <105, <120, <135, <150, <175, <200, <225, <250, <275, else`).
  Different rank ⇒ the higher rank wins outright, regardless of raw difference.
- Otherwise compare raw damage. `|difference| < 5` (`TIE_DAMAGE_THRESHOLD`) ⇒ **tie, no damage**.
  Else the higher side wins and deals `|difference|` as damage.

**Enemy AI** — `AttackChooser` is a seeded PRNG: `seed = savedBattleSeed * digimonName.GetHashCode()`.
Attack picked by weight `30 + EN : 30 + CR : 30 + AB`. Deterministic per (seed, creature), so a battle
replays identically — this is how the saved-seed anti-cheat works.

**Disobedience** — checked before every player attack, using the *originally summoned* creature's base
level, not its evolved form:
```
levelDiff = creatureLevel - playerLevel        // >0 means it outranks you

obeyChance:  1.0 if levelDiff <= 0;  0.0 if levelDiff >= 10
             else 1 - levelDiff²/100

idleChance:  1.0 if levelDiff <= 0;  0.0 if levelDiff >= 20
             else (10^1.5 - (levelDiff/2)^1.5) / 10^-0.5
```
Roll `> idleChance` ⇒ the creature does nothing that turn (attack index 3, auto-loses the exchange).
Roll `> obeyChance` ⇒ it attacks, but with a random attack instead of yours.

> The `idleChance` formula divides by `10^-0.5`, i.e. multiplies by ~3.16, so it returns values well
> above 1.0 for small `levelDiff`. Effectively idling only kicks in near `levelDiff ≈ 20`. Looks like a
> bug in the original (the divisor was probably meant to be `10^1.5`); decide deliberately whether to
> port it or fix it.

**Battle menu:** Battle Call (summon from a D-Dock), Spirit On (spirit evolution, costs Spirit Power),
Digits (type a digicode), Escape. Each D-Dock is usable once per battle.

**Call cost** — summoning costs call points (out of 10 per battle), from the level ratio
`perc = baseLevel/playerLevel` and gap `diff = playerLevel - baseLevel`:
```
perc<0.55 && diff>=10 -> 0     perc<0.75 && diff>=5 -> 1
perc<0.90 && diff>=2  -> 2     perc<1.00 && diff>=1 -> 3
perc==1.00            -> 4     perc<1.30            -> 5
perc<1.60             -> 6     perc<2.00            -> 7
perc<3.00             -> 8     perc<4.00            -> 9
else                  -> 10
```

**Spirit cost** (Spirit Power spent to spirit-evolve) decays with player level:
```
cost = floor(baseCost * 0.5 ^ (playerLevel / decay))

Armor  base 10 decay 20      Human   base 20 decay 30
Animal base 30 decay 30      Hybrid  base 35 decay 40
Ancient base 40 decay 50     Fusion  base 55 decay 60
susanoomon base 95 decay 50
```

**Evolution chance** — called on the *target* form, with `extraPoints` = call points spent (1–10):
```
multiplier  = (extraPoints - 1) / 20            // 0 .. 0.45
extraLevel  = max(floor(playerLevel * multiplier), extraPoints if below extraPoints-1)
effective   = playerLevel + extraLevel
levelDiff   = targetBaseLevel - effective
chance = 1.0                                  if levelDiff <= 0
       = 0.05                                 if levelDiff >= 10
       = max(0.05, 1 - levelDiff²/100 + 0.005*levelDiff)
```

## 6. World / encounter loop

`worlds.json` — 9 worlds, each with 1 or 4 maps and a list of areas:
```json
{"number":0,"multiMap":true,"worldSprite":"frontier_initial","shuffle":true,
 "areas":[{"number":0,"map":0,"distance":6000,"coords":{"x":18,"y":21}}, ...]}
```
`distance` = steps required to cross the area (6000–11000 typical). `coords` place the area marker on the
32x32 map sprite. `shuffle` randomizes boss placement at new-game time; `bossMode` / `semibossMode` /
`lockTravel` / `removePlayer` / `showEyes` are per-world rule switches.

**Event pacing:**
```
each step:  stepsToNextEvent -= 1;  currentDistance -= 1;  steps += 1
if stepsToNextEvent <= 0 && currentDistance > 1:
     stepsToNextEvent = randInt(3,6) * 100      // 300..500 steps
     pendingEvent = 1                            // regular event
if currentDistance == 1:
     pendingEvent = 2                            // area boss
```
Initial `stepsToNextEvent` on a new game is 300.

**Regular event roll:** 85% random battle, 15% Data Storm (teleports the player to a different area).

**Random encounter selection** (`Database.GetRandomDigimonForBattle`):
```
threshold by player level:  <=2 -> 3,  <=4 -> 4,  <=10 -> 7,  <=60 -> 10,  <=80 -> 20,  else 40
candidates = battle-eligible creatures with (playerLevel - threshold) < baseLevel < (playerLevel + threshold)
baseWeight = Common 10, Rare 6, Epic 3, Legendary 1
weight     = (1.1 - |playerLevel - baseLevel| / threshold) * baseWeight
pick by weighted roll over the candidate list
```
So level-matched Commons dominate, and the `1.1 -` term keeps a small chance for edge-of-band creatures.

## 7. Apps (the menu)

`MainMenu`: Map, Status, Game, Database, Digits, Camp, Connect.

`Game` splits into **Reward** games (FindBattle, JackpotBox, EnergyWars, DigiCatch) and **Travel** games
(SpeedRunner, Asteroids, DigiHunter, Maze). Travel games convert score into distance:
```
distance -= score;  steps += round(score / 5)
```

Implemented app controllers: `Battle`, `Maze`, `SpeedRunner`, `JackpotBox`, `DigiHunter`, `Finder`,
`Map`, `Status`, `Camp`, `DatabaseApp`, `CodeInput`. All implement `IAppController` and are instantiated
by `AppLoader`; `LogicManager` holds at most one `loadedApp` and forwards input to it.

**Reward table** (`Reward` enum, granted by reward games / jackpot):
Empty, IncreaseDistance 300/500/2000, ReduceDistance 500/1000, PunishDigimon, RewardDigimon,
UnlockDigicodeOwned, UnlockDigicodeNotOwned, DataStorm, LoseSpiritPower 10/50, GainSpiritPower 10/Max,
LevelDown, LevelUp, ForceLevelDown, ForceLevelUp, TriggerBattle.

## 8. Porting to Connect IQ — what changes

| Original | Garmin equivalent |
|---|---|
| Shake detector, 6 shakes = 1 step | `ActivityMonitor.getInfo().steps` delta; no filtering needed |
| 32x32 grid at 24 px/cell (768x768) | 240–280 px round display; either a 32x32 scaled buffer or native `Dc` drawing |
| 4 physical buttons | UP / DOWN / START / BACK via `BehaviorDelegate` |
| Unity coroutine animation library | `Timer` + a small frame-index state machine per animation |
| `EncryptedPlayerPrefs` | `Application.Storage` / `Application.Properties` |
| 593-entry JSON + hundreds of sprites | Hard budget problem — watch apps get ~128–1024 KB. Cut to a few dozen creatures, pack sprites as a small number of bitmap strips |
| Frame-driven `Update()` | Background-service tick for step accrual while the app is closed; foreground `Timer` at 1 Hz |

Biggest constraints to design around, in order:
1. **Memory.** The whole creature DB, sprites, and save must fit in the device app budget. Store the DB
   as a compact resource-encoded array, not JSON.
2. **Background steps.** Connect IQ background services run at most every 5 minutes and get a tiny
   memory budget. Accrue `steps` and event triggers there, resolve battles in the foreground.
3. **The RPS + tie-threshold combat** is the part worth keeping verbatim — it's cheap, deterministic,
   and reads well on a small screen. The seeded `AttackChooser` maps directly onto a stored seed in
   `Storage`.
