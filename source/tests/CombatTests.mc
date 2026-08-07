import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the combat engine. Excluded from release builds via the `test` annotation.
//! Run: monkeyc --unit-test ... && monkeydo GarminSample.prg fenix6pro -t

(:test)
function testTypeWheel(logger as Logger) as Boolean {
    Test.assert(Combat.BattleEngine.beats(Combat.ATTACK_CRUSH, Combat.ATTACK_ENERGY));
    Test.assert(Combat.BattleEngine.beats(Combat.ATTACK_ENERGY, Combat.ATTACK_ABILITY));
    Test.assert(Combat.BattleEngine.beats(Combat.ATTACK_ABILITY, Combat.ATTACK_CRUSH));

    // The wheel must not be symmetric.
    Test.assert(!Combat.BattleEngine.beats(Combat.ATTACK_ENERGY, Combat.ATTACK_CRUSH));
    Test.assert(!Combat.BattleEngine.beats(Combat.ATTACK_ABILITY, Combat.ATTACK_ENERGY));
    Test.assert(!Combat.BattleEngine.beats(Combat.ATTACK_CRUSH, Combat.ATTACK_ABILITY));

    // No attack beats itself.
    Test.assert(!Combat.BattleEngine.beats(Combat.ATTACK_ENERGY, Combat.ATTACK_ENERGY));
    return true;
}

(:test)
function testEnergyRankBuckets(logger as Logger) as Boolean {
    var low = new Combat.CombatStats(50, 19, 10, 10);
    var mid = new Combat.CombatStats(50, 20, 10, 10);
    var high = new Combat.CombatStats(50, 300, 10, 10);

    Test.assertEqual(low.energyRank(), 0);
    Test.assertEqual(mid.energyRank(), 1);
    Test.assertEqual(high.energyRank(), 15);
    return true;
}

(:test)
function testAttackDamageMapping(logger as Logger) as Boolean {
    var stats = new Combat.CombatStats(50, 11, 22, 33);
    Test.assertEqual(stats.attackDamage(Combat.ATTACK_ENERGY), 11);
    Test.assertEqual(stats.attackDamage(Combat.ATTACK_CRUSH), 22);
    Test.assertEqual(stats.attackDamage(Combat.ATTACK_ABILITY), 33);
    Test.assertEqual(stats.attackDamage(Combat.ATTACK_IDLE), 0);
    return true;
}

//! A same-attack clash inside the tie threshold must damage nobody.
(:test)
function testMirrorClashUnderThresholdIsTie(logger as Logger) as Boolean {
    // Crush 30 vs crush 28: a gap of 2, below the threshold of 5.
    var player = new Combat.Creature("p", "P", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 10, [100, 10, 30, 10], null);
    var enemy = new Combat.Creature("e", "E", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 10, [100, 10, 28, 10], null);

    var engine = new Combat.BattleEngine(player, 0, enemy, 10, new Combat.Rng(1));
    // Force the stats rather than relying on level scaling.
    engine.playerStats().crush = 30;
    engine.enemyStats().crush = 28;

    var hpBefore = engine.enemyStats().hp;
    var playerHpBefore = engine.playerStats().hp;

    // Drive resolution directly against a known enemy choice by replaying until crush is drawn.
    var result = null as Combat.TurnResult?;
    for (var i = 0; i < 200; i += 1) {
        result = engine.takeTurn(Combat.ATTACK_CRUSH);
        if (result.enemyAttack == Combat.ATTACK_CRUSH && !result.disobeyed) {
            break;
        }
        // Reset HP so the loop cannot end the battle before we see a mirror clash.
        engine.playerStats().hp = playerHpBefore;
        engine.enemyStats().hp = hpBefore;
        result = null;
    }

    Test.assert(result != null);
    var clash = result as Combat.TurnResult;
    Test.assertEqual(clash.winner, Combat.WINNER_TIE);
    Test.assertEqual(clash.damage, 0);
    Test.assertEqual(engine.enemyStats().hp, hpBefore);
    Test.assertEqual(engine.playerStats().hp, playerHpBefore);
    return true;
}

//! Equal levels mean full obedience — a level-matched partner never disobeys.
(:test)
function testObedienceAtParity(logger as Logger) as Boolean {
    var species = new Combat.Creature("p", "P", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 10, [100, 20, 20, 20], null);
    Test.assertEqual(species.obeyChance(10), 1.0);
    Test.assertEqual(species.obeyChance(20), 1.0);
    Test.assertEqual(species.actChance(10), 1.0);
    return true;
}

//! Obedience decays with the level gap and bottoms out at ten levels.
(:test)
function testObedienceDecay(logger as Logger) as Boolean {
    var species = new Combat.Creature("p", "P", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 20, [100, 20, 20, 20], null);

    // Gap of 5 => 1 - 25/100 = 0.75
    Test.assert((species.obeyChance(15) - 0.75).abs() < 0.0001);
    // Gap of 10 or more => never obeys.
    Test.assertEqual(species.obeyChance(10), 0.0);
    Test.assertEqual(species.obeyChance(1), 0.0);
    return true;
}

//! The corrected act-chance curve must stay a probability across its whole range.
(:test)
function testActChanceIsBounded(logger as Logger) as Boolean {
    var species = new Combat.Creature("p", "P", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 40, [100, 20, 20, 20], null);
    var previous = 1.1;
    for (var playerLevel = 40; playerLevel >= 20; playerLevel -= 1) {
        var chance = species.actChance(playerLevel);
        Test.assert(chance >= 0.0);
        Test.assert(chance <= 1.0);
        // Monotonically non-increasing as the gap widens.
        Test.assert(chance <= previous + 0.0001);
        previous = chance;
    }
    Test.assertEqual(species.actChance(20), 0.0);
    return true;
}

(:test)
function testLevelFromExperience(logger as Logger) as Boolean {
    Test.assertEqual(Combat.Progression.levelFromExperience(0), 1);
    Test.assertEqual(Combat.Progression.levelFromExperience(7), 1);
    Test.assertEqual(Combat.Progression.levelFromExperience(8), 2);
    Test.assertEqual(Combat.Progression.levelFromExperience(26), 2);
    Test.assertEqual(Combat.Progression.levelFromExperience(27), 3);
    Test.assertEqual(Combat.Progression.levelFromExperience(1000), 10);
    return true;
}

(:test)
function testLevelProgressSpansTheLevel(logger as Logger) as Boolean {
    // Level 3 runs from 27 to 64.
    Test.assert(Combat.Progression.levelProgress(27) < 0.0001);
    var mid = Combat.Progression.levelProgress(45);
    Test.assert(mid > 0.4 && mid < 0.6);
    Test.assert(Combat.Progression.levelProgress(63) > 0.9);
    return true;
}

//! Experience must fall off as the player outlevels the enemy, and rise with the enemy's level.
(:test)
function testExperienceCurveShape(logger as Logger) as Boolean {
    var evenFight = Combat.Progression.experienceForWin(20, 20);
    var punchingUp = Combat.Progression.experienceForWin(20, 30);
    var punchingDown = Combat.Progression.experienceForWin(20, 10);

    Test.assert(punchingUp > evenFight);
    Test.assert(evenFight > punchingDown);
    Test.assert(punchingDown >= 1);
    return true;
}

(:test)
function testExperienceLossIsSmallerThanGain(logger as Logger) as Boolean {
    var gain = Combat.Progression.experienceForWin(20, 20);
    var loss = Combat.Progression.experienceForLoss(20, 20);
    Test.assert(loss < gain);
    Test.assert(loss >= 1);
    return true;
}

//! Stat scaling: a partner at max extra level sits at 150% of base.
(:test)
function testFriendlyStatScaling(logger as Logger) as Boolean {
    var species = new Combat.Creature("p", "P", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 10, [100, 40, 20, 20], null);
    Test.assertEqual(species.maxExtraLevel(), 10);

    var base = species.friendlyStats(0);
    Test.assertEqual(base.hp, 100);
    Test.assertEqual(base.energy, 40);

    var maxed = species.friendlyStats(10);
    Test.assertEqual(maxed.hp, 150);
    Test.assertEqual(maxed.energy, 60);
    return true;
}

//! Apex forms are summoned at the player's level and gain no extra levels.
(:test)
function testApexScaling(logger as Logger) as Boolean {
    var apex = new Combat.Creature("a", "A", Combat.STAGE_APEX, Combat.RARITY_LEGENDARY, 40, [200, 100, 100, 100], null);
    Test.assertEqual(apex.maxExtraLevel(), 0);
    Test.assertEqual(apex.enemyLevel(5), 10);   // floored
    Test.assertEqual(apex.enemyLevel(50), 50);

    var weak = apex.enemyStats(10);
    var strong = apex.enemyStats(80);
    Test.assert(strong.hp > weak.hp);
    return true;
}

(:test)
function testEvolveChanceBounds(logger as Logger) as Boolean {
    var target = new Combat.Creature("t", "T", Combat.STAGE_EVOLVED, Combat.RARITY_COMMON, 20, [100, 20, 20, 20], null);

    // Player already at or above the target level: guaranteed.
    Test.assertEqual(target.evolveChance(20, 1), 1.0);
    Test.assertEqual(target.evolveChance(40, 1), 1.0);

    // Far below: floored, never impossible.
    Test.assertEqual(target.evolveChance(1, 1), 0.05);

    // More focus never hurts.
    Test.assert(target.evolveChance(14, 10) >= target.evolveChance(14, 1));
    return true;
}

(:test)
function testSummonCostOrdering(logger as Logger) as Boolean {
    var weak = new Combat.Creature("w", "W", Combat.STAGE_BASIC, Combat.RARITY_COMMON, 3, [40, 20, 20, 20], null);
    var strong = new Combat.Creature("s", "S", Combat.STAGE_PRIME, Combat.RARITY_EPIC, 60, [200, 80, 80, 80], null);

    Test.assertEqual(weak.summonCost(30), 0);   // far below the player: free
    Test.assertEqual(weak.summonCost(3), 4);    // exact parity
    Test.assertEqual(strong.summonCost(20), 9); // ratio exactly 3.0 lands in the 4.0 band
    Test.assertEqual(strong.summonCost(21), 8); // ratio just under 3.0 lands in the 3.0 band
    Test.assertEqual(strong.summonCost(10), 10); // ratio 6.0: full pool

    // Cost must never increase as the player grows.
    var previous = 10;
    for (var playerLevel = 1; playerLevel <= 80; playerLevel += 1) {
        var cost = strong.summonCost(playerLevel);
        Test.assert(cost <= previous);
        previous = cost;
    }
    return true;
}

//! The same seed must produce the same battle, and different seeds must diverge.
(:test)
function testRngDeterminism(logger as Logger) as Boolean {
    var a = new Combat.Rng(12345);
    var b = new Combat.Rng(12345);
    var c = new Combat.Rng(999);

    var sameCount = 0;
    var divergeCount = 0;
    for (var i = 0; i < 50; i += 1) {
        var left = a.nextInt(1000);
        if (left == b.nextInt(1000)) {
            sameCount += 1;
        }
        if (left != c.nextInt(1000)) {
            divergeCount += 1;
        }
    }

    Test.assertEqual(sameCount, 50);
    Test.assert(divergeCount > 40);
    return true;
}

(:test)
function testRngStaysInRange(logger as Logger) as Boolean {
    var rng = new Combat.Rng(7);
    for (var i = 0; i < 500; i += 1) {
        var value = rng.nextInt(10);
        Test.assert(value >= 0);
        Test.assert(value < 10);

        var f = rng.nextFloat();
        Test.assert(f >= 0.0);
        Test.assert(f < 1.0);
    }
    Test.assertEqual(rng.nextInt(0), 0);
    return true;
}

//! Encounters must respect the level band around the player.
(:test)
function testEncounterStaysInBand(logger as Logger) as Boolean {
    var rng = new Combat.Rng(4242);
    var playerLevel = 12;
    var band = Combat.Bestiary.encounterBand(playerLevel);

    for (var i = 0; i < 100; i += 1) {
        var species = Combat.Bestiary.randomEncounter(playerLevel, rng);
        var distance = (species.baseLevel - playerLevel).abs();
        Test.assert(distance < band);
    }
    return true;
}

//! Low-level players must still get an encounter, and it must be a weak one.
(:test)
function testEncounterAtLevelOne(logger as Logger) as Boolean {
    var rng = new Combat.Rng(11);
    for (var i = 0; i < 50; i += 1) {
        var species = Combat.Bestiary.randomEncounter(1, rng);
        Test.assert(species.baseLevel <= 4);
    }
    return true;
}

(:test)
function testBestiaryLookup(logger as Logger) as Boolean {
    var species = Combat.Bestiary.get("emberling");
    Test.assert(species != null);
    Test.assertEqual((species as Combat.Creature).name, "Emberling");
    Test.assert(Combat.Bestiary.get("no_such_creature") == null);

    // Every declared evolution target must exist.
    var all = Combat.Bestiary.all();
    for (var i = 0; i < all.size(); i += 1) {
        var target = all[i].evolvesTo;
        if (target != null) {
            Test.assert(Combat.Bestiary.get(target) != null);
        }
    }
    return true;
}

//! A full battle must terminate and produce exactly one winner.
(:test)
function testBattleTerminates(logger as Logger) as Boolean {
    var player = Combat.Bestiary.get("cinderfang") as Combat.Creature;
    var enemy = Combat.Bestiary.get("tidecaller") as Combat.Creature;

    var engine = new Combat.BattleEngine(player, 0, enemy, 12, new Combat.Rng(2024));

    var turns = 0;
    while (!engine.isOver() && turns < 500) {
        engine.takeTurn(Combat.ATTACK_CRUSH);
        turns += 1;
    }

    Test.assert(engine.isOver());
    Test.assert(turns < 500);

    var outcome = engine.outcome();
    Test.assert(outcome == Combat.WINNER_PLAYER || outcome == Combat.WINNER_ENEMY);

    // Exactly one side is down.
    Test.assert(engine.playerStats().isDown() != engine.enemyStats().isDown());
    return true;
}

//! Turns taken after the battle has ended must be inert.
(:test)
function testTurnsAfterBattleEndAreInert(logger as Logger) as Boolean {
    var player = Combat.Bestiary.get("emberling") as Combat.Creature;
    var enemy = Combat.Bestiary.get("drizzlet") as Combat.Creature;

    var engine = new Combat.BattleEngine(player, 0, enemy, 3, new Combat.Rng(5));
    while (!engine.isOver()) {
        engine.takeTurn(Combat.ATTACK_ENERGY);
    }

    var playerHp = engine.playerStats().hp;
    var enemyHp = engine.enemyStats().hp;
    var turnsBefore = engine.turnCount();

    var result = engine.takeTurn(Combat.ATTACK_ENERGY);
    Test.assert(result.battleOver);
    Test.assertEqual(engine.playerStats().hp, playerHp);
    Test.assertEqual(engine.enemyStats().hp, enemyHp);
    Test.assertEqual(engine.turnCount(), turnsBefore);
    return true;
}

//! Same seed, same script of inputs => byte-identical battle. This is what makes a stored seed
//! enough to replay a fight.
(:test)
function testBattleReplaysFromSeed(logger as Logger) as Boolean {
    var player = Combat.Bestiary.get("voltcrest") as Combat.Creature;
    var enemy = Combat.Bestiary.get("thornmane") as Combat.Creature;

    var first = new Combat.BattleEngine(player, 2, enemy, 15, new Combat.Rng(31337));
    var second = new Combat.BattleEngine(player, 2, enemy, 15, new Combat.Rng(31337));

    for (var i = 0; i < 40; i += 1) {
        if (first.isOver()) {
            Test.assert(second.isOver());
            break;
        }
        var attack = i % 3;
        var a = first.takeTurn(attack);
        var b = second.takeTurn(attack);

        Test.assertEqual(a.enemyAttack, b.enemyAttack);
        Test.assertEqual(a.playerAttack, b.playerAttack);
        Test.assertEqual(a.winner, b.winner);
        Test.assertEqual(a.damage, b.damage);
    }

    Test.assertEqual(first.playerStats().hp, second.playerStats().hp);
    Test.assertEqual(first.enemyStats().hp, second.enemyStats().hp);
    return true;
}

//! HP must never render outside 0.0 .. 1.0.
(:test)
function testHpFractionClamps(logger as Logger) as Boolean {
    var stats = new Combat.CombatStats(50, 10, 10, 10);
    Test.assertEqual(stats.hpFraction(), 1.0);

    stats.applyDamage(25);
    Test.assert((stats.hpFraction() - 0.5).abs() < 0.0001);

    stats.applyDamage(1000);
    Test.assertEqual(stats.hp, 0);
    Test.assertEqual(stats.hpFraction(), 0.0);
    Test.assert(stats.isDown());
    return true;
}
