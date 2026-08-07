import Toybox.Lang;
import Toybox.Math;

module Combat {

    // Growth stages. APEX creatures are summoned forms — they never gain extra levels and their
    // stats are derived from the player's level instead of their own.
    enum {
        STAGE_BASIC = 0,
        STAGE_EVOLVED = 1,
        STAGE_PRIME = 2,
        STAGE_APEX = 3
    }

    // Encounter rarity. Drives both the weighted encounter roll and the reward tier.
    enum {
        RARITY_COMMON = 0,
        RARITY_RARE = 1,
        RARITY_EPIC = 2,
        RARITY_LEGENDARY = 3
    }

    //! A species definition. Immutable: instantiate CombatStats from it for an actual battle.
    class Creature {
        public var key as String;
        public var name as String;
        public var stage as Number;
        public var rarity as Number;
        public var baseLevel as Number;
        public var baseHp as Number;
        public var baseEnergy as Number;
        public var baseCrush as Number;
        public var baseAbility as Number;
        public var evolvesTo as String?;

        //! Spirit form class, or Spirit.TYPE_NONE for an ordinary creature. Assigned by the loader
        //! after construction rather than passed in, so the constructor stays inside Monkey C's
        //! nine-parameter limit.
        public var spiritType as Number;

        //! `baseStats` is [HP, energy, crush, ability]. Packed into one array because Monkey C
        //! caps a method at nine parameters.
        function initialize(
            key as String,
            name as String,
            stage as Number,
            rarity as Number,
            baseLevel as Number,
            baseStats as Array<Number>,
            evolvesTo as String?
        ) {
            self.key = key;
            self.name = name;
            self.stage = stage;
            self.rarity = rarity;
            self.baseLevel = baseLevel;
            self.baseHp = baseStats[0];
            self.baseEnergy = baseStats[1];
            self.baseCrush = baseStats[2];
            self.baseAbility = baseStats[3];
            self.evolvesTo = evolvesTo;
            self.spiritType = Spirit.TYPE_NONE;
        }

        function isSpirit() as Boolean {
            return spiritType != Spirit.TYPE_NONE;
        }

        //! How many levels this species can gain above its base level.
        //! BASIC creatures have the most headroom; APEX forms have none.
        function maxExtraLevel() as Number {
            if (stage == STAGE_APEX) {
                return 0;
            }
            var ceiling;
            if (stage == STAGE_BASIC) {
                ceiling = baseLevel * 2;
            } else {
                ceiling = Math.ceil(baseLevel * 1.5).toNumber();
            }
            return ceiling - baseLevel;
        }

        function friendlyLevel(extraLevel as Number) as Number {
            return baseLevel + extraLevel;
        }

        //! An enemy's effective level. APEX forms scale off the player so they stay threatening,
        //! with a floor so they are never trivial.
        function enemyLevel(playerLevel as Number) as Number {
            if (stage == STAGE_APEX) {
                return (playerLevel < 10) ? 10 : playerLevel;
            }
            return playerLevel;
        }

        //! Player-owned stats: 100% of base at 0 extra levels, interpolating to 150% at the cap.
        function friendlyStats(extraLevel as Number) as CombatStats {
            return new CombatStats(
                scaleFriendly(baseHp, extraLevel),
                scaleFriendly(baseEnergy, extraLevel),
                scaleFriendly(baseCrush, extraLevel),
                scaleFriendly(baseAbility, extraLevel)
            );
        }

        //! Enemy stats: 20% of base at level 0, reaching 100% at level 100. APEX forms start
        //! higher and climb slower, so they read as strong early and fair late.
        function enemyStats(playerLevel as Number) as CombatStats {
            var level = enemyLevel(playerLevel);
            return new CombatStats(
                scaleEnemy(baseHp, level),
                scaleEnemy(baseEnergy, level),
                scaleEnemy(baseCrush, level),
                scaleEnemy(baseAbility, level)
            );
        }

        private function scaleFriendly(stat as Number, extraLevel as Number) as Number {
            var headroom = maxExtraLevel();
            if (extraLevel <= 0 || headroom <= 0) {
                return stat;
            }
            var multiplier = 1.0 + (0.5 * (extraLevel.toFloat() / headroom.toFloat()));
            return Math.ceil(stat * multiplier).toNumber();
        }

        private function scaleEnemy(stat as Number, level as Number) as Number {
            var multiplier = (stage == STAGE_APEX)
                ? 0.30 + (0.007 * level)
                : 0.20 + (0.008 * level);
            var scaled = Math.round(stat * multiplier).toNumber();
            return (scaled < 1) ? 1 : scaled;
        }

        //! Probability this creature follows the attack the player picked.
        //! Outlevel it and it always obeys; fall 10 levels behind and it never does.
        function obeyChance(playerLevel as Number) as Float {
            var levelDiff = effectiveLevel(playerLevel) - playerLevel;
            if (levelDiff <= 0) {
                return 1.0;
            }
            if (levelDiff >= 10) {
                return 0.0;
            }
            return 1.0 - ((levelDiff * levelDiff) / 100.0);
        }

        //! Probability this creature attacks at all. Falls to zero 20 levels out of your depth.
        //!
        //! The original divided by 10^-0.5 here, which made the result exceed 1.0 across almost the
        //! whole range and left idling effectively dead code. Dividing by 10^1.5 gives the curve the
        //! surrounding code clearly expects: 1.0 at parity, decaying to 0.0 at a 20-level gap.
        function actChance(playerLevel as Number) as Float {
            var levelDiff = effectiveLevel(playerLevel) - playerLevel;
            if (levelDiff <= 0) {
                return 1.0;
            }
            if (levelDiff >= 20) {
                return 0.0;
            }
            var ceiling = Math.pow(10.0, 1.5);
            return ((ceiling - Math.pow(levelDiff / 2.0, 1.5)) / ceiling).toFloat();
        }

        //! Obedience is judged against the summoned form's own standing, which for APEX forms is
        //! their scaled level rather than the base level on the species record.
        private function effectiveLevel(playerLevel as Number) as Number {
            return (stage == STAGE_APEX) ? enemyLevel(playerLevel) : baseLevel;
        }

        //! Chance for a creature to evolve into this species. `focus` is the number of focus points
        //! committed (1..10) — more points fake a higher player level for the attempt.
        function evolveChance(playerLevel as Number, focus as Number) as Float {
            var points = focus;
            if (points < 1) {
                points = 1;
            }
            if (points > 10) {
                points = 10;
            }

            var multiplier = (points - 1) / 20.0; // 0.0 .. 0.45
            var bonusLevels = Math.floor(playerLevel * multiplier).toNumber();
            if (bonusLevels < points - 1) {
                bonusLevels = points - 1;
            }

            var levelDiff = baseLevel - (playerLevel + bonusLevels);
            if (levelDiff <= 0) {
                return 1.0;
            }
            if (levelDiff >= 10) {
                return 0.05;
            }

            var chance = 1.0 - ((levelDiff * levelDiff) / 100.0) + (0.005 * levelDiff);
            return (chance < 0.05) ? 0.05 : chance.toFloat();
        }

        //! Focus points (out of 10) needed to summon this species, from how far above or below the
        //! player it sits. Far weaker creatures are free; far stronger ones cost the full pool.
        function summonCost(playerLevel as Number) as Number {
            if (playerLevel <= 0) {
                return 10;
            }
            var ratio = baseLevel.toFloat() / playerLevel.toFloat();
            var gap = playerLevel - baseLevel;

            if (ratio < 0.55 && gap >= 10) { return 0; }
            if (ratio < 0.75 && gap >= 5) { return 1; }
            if (ratio < 0.90 && gap >= 2) { return 2; }
            if (ratio < 1.00 && gap >= 1) { return 3; }
            if (ratio == 1.00) { return 4; }
            if (ratio < 1.30) { return 5; }
            if (ratio < 1.60) { return 6; }
            if (ratio < 2.00) { return 7; }
            if (ratio < 3.00) { return 8; }
            if (ratio < 4.00) { return 9; }
            return 10;
        }
    }
}
