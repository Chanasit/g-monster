import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

//! Tests for the party roster and mid-battle summoning.
//!
//! The Party tests are storage-backed, so each one clears storage first and leaves the test binary's
//! own scratch state behind — never the real app's, since tests only run in the --unit-test build.

function freshEngine(playerKey as String, enemyKey as String, playerLevel as Number) as Combat.BattleEngine {
    var player = Combat.Bestiary.get(playerKey) as Combat.Creature;
    var enemy = Combat.Bestiary.get(enemyKey) as Combat.Creature;
    return new Combat.BattleEngine(player, 0, enemy, playerLevel, new Combat.Rng(4242));
}

//! A battle opens with the full call-point pool.
(:test)
function testBattleStartsWithFullCallPool(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    Test.assertEqual(engine.callPoints(), Combat.STARTING_CALL_POINTS);
    return true;
}

//! The creature already fighting counts as called, so it cannot be re-summoned to heal itself.
(:test)
function testActiveCreatureCannotBeRecalled(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var nonce = Combat.Bestiary.get("nonce") as Combat.Creature;

    Test.assert(engine.hasBeenCalled("nonce"));
    Test.assert(!engine.canSummon(nonce));

    // Damage it, then confirm a recall still cannot be used as a heal.
    engine.playerStats().applyDamage(10);
    var wounded = engine.playerStats().hp;
    Test.assert(!engine.summon(nonce, 0));
    Test.assertEqual(engine.playerStats().hp, wounded);
    return true;
}

//! Summoning swaps the fighter, spends its cost, and brings the newcomer in at full health.
(:test)
function testSummonSwapsFighterAndSpendsPoints(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var drizzlet = Combat.Bestiary.get("drizzlet") as Combat.Creature;

    var cost = engine.summonCost(drizzlet);
    Test.assert(cost <= Combat.STARTING_CALL_POINTS);

    Test.assert(engine.summon(drizzlet, 0));
    Test.assertEqual(engine.callPoints(), Combat.STARTING_CALL_POINTS - cost);
    Test.assertEqual(engine.playerSpecies().key, "drizzlet");

    var expected = drizzlet.friendlyStats(0);
    Test.assertEqual(engine.playerStats().hp, expected.hp);
    Test.assertEqual(engine.playerStats().hp, engine.playerStats().maxHp);
    return true;
}

//! The enemy keeps every point of damage it has taken across a swap.
(:test)
function testSummonDoesNotResetTheEnemy(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var drizzlet = Combat.Bestiary.get("drizzlet") as Combat.Creature;

    engine.enemyStats().applyDamage(15);
    var enemyHp = engine.enemyStats().hp;

    Test.assert(engine.summon(drizzlet, 0));
    Test.assertEqual(engine.enemyStats().hp, enemyHp);
    return true;
}

//! Calling costs points, not a turn.
(:test)
function testSummonCostsNoTurn(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var drizzlet = Combat.Bestiary.get("drizzlet") as Combat.Creature;

    var turnsBefore = engine.turnCount();
    Test.assert(engine.summon(drizzlet, 0));
    Test.assertEqual(engine.turnCount(), turnsBefore);
    return true;
}

//! Each species gets exactly one call per battle.
(:test)
function testEachSpeciesCallableOnce(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var drizzlet = Combat.Bestiary.get("drizzlet") as Combat.Creature;
    var sparkmite = Combat.Bestiary.get("sparkmite") as Combat.Creature;

    Test.assert(engine.summon(drizzlet, 0));
    Test.assert(engine.hasBeenCalled("drizzlet"));

    // Swap away, then try to come back to the one already used.
    Test.assert(engine.summon(sparkmite, 0));
    Test.assert(!engine.canSummon(drizzlet));
    Test.assert(!engine.summon(drizzlet, 0));
    Test.assertEqual(engine.playerSpecies().key, "sparkmite");
    return true;
}

//! Something far above the player's standing costs the whole pool and cannot be afforded twice.
(:test)
function testUnaffordableSummonIsRefused(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var apex = Combat.Bestiary.get("voidsentinel") as Combat.Creature;
    var drizzlet = Combat.Bestiary.get("drizzlet") as Combat.Creature;

    Test.assertEqual(engine.summonCost(apex), 10); // ratio 4.0 lands in the top band

    // Spend anything at all and the apex call is out of reach.
    Test.assert(engine.summon(drizzlet, 0));
    Test.assert(engine.callPoints() < 10);
    Test.assert(!engine.canSummon(apex));
    Test.assert(!engine.summon(apex, 0));
    Test.assertEqual(engine.playerSpecies().key, "drizzlet");
    return true;
}

//! Summon costs fall as the player grows, so the roster opens up over a run.
(:test)
function testSummonCostsFallWithPlayerLevel(logger as Logger) as Boolean {
    var apex = Combat.Bestiary.get("solmonarch") as Combat.Creature;

    var early = freshEngine("nonce", "tidecaller", 5).summonCost(apex);
    var late = freshEngine("nonce", "tidecaller", 50).summonCost(apex);

    Test.assert(late < early);
    Test.assert(late >= 0);
    return true;
}

//! Nothing can be called once the battle is decided.
(:test)
function testNoSummoningAfterTheBattleEnds(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "drizzlet", 3);
    var sparkmite = Combat.Bestiary.get("sparkmite") as Combat.Creature;

    while (!engine.isOver()) {
        engine.takeTurn(Combat.ATTACK_ENERGY);
    }

    Test.assert(!engine.canSummon(sparkmite));
    Test.assert(!engine.summon(sparkmite, 0));
    return true;
}

//! A called creature fights with its own growth, not the lead's.
(:test)
function testSummonUsesItsOwnGrowth(logger as Logger) as Boolean {
    var engine = freshEngine("nonce", "tidecaller", 12);
    var mosscub = Combat.Bestiary.get("mosscub") as Combat.Creature;

    Test.assert(engine.summon(mosscub, mosscub.maxExtraLevel()));

    var maxed = mosscub.friendlyStats(mosscub.maxExtraLevel());
    Test.assertEqual(engine.playerStats().hp, maxed.hp);
    Test.assert(maxed.hp > mosscub.baseHp); // growth actually applied
    return true;
}

//! A fresh save fields the starter and nothing else.
(:test)
function testDefaultRoster(logger as Logger) as Boolean {
    Storage.clearValues();

    Test.assertEqual(Party.lead().key, "nonce");
    Test.assert(Party.isUnlocked("nonce"));
    Test.assert(!Party.isUnlocked("mosscub"));

    for (var i = 1; i < Party.SIZE; i += 1) {
        Test.assert(Party.member(i) == null);
    }
    return true;
}

//! Beating something new recruits it into the first empty slot; beating it again changes nothing.
(:test)
function testUnlockFillsAnEmptySlot(logger as Logger) as Boolean {
    Storage.clearValues();

    Test.assert(Party.unlock("mosscub"));
    Test.assert(Party.isUnlocked("mosscub"));
    Test.assertEqual(Party.slot(1), "mosscub");

    Test.assert(!Party.unlock("mosscub"));   // already known
    Test.assertEqual(Party.slot(2), Party.EMPTY);
    return true;
}

//! Once the roster is full, further recruits are still unlocked but wait for a free slot.
(:test)
function testUnlockBeyondAFullRoster(logger as Logger) as Boolean {
    Storage.clearValues();

    Test.assert(Party.unlock("mosscub"));
    Test.assert(Party.unlock("drizzlet"));
    Test.assert(Party.unlock("sparkmite"));
    Test.assertEqual(Party.firstEmptySlot(), -1);

    Test.assert(Party.unlock("gustling"));
    Test.assert(Party.isUnlocked("gustling"));
    Test.assert(!Party.isInParty("gustling"));
    return true;
}

//! Growth belongs to the creature, so moving it between slots never loses progress.
(:test)
function testGrowthSurvivesSlotMoves(logger as Logger) as Boolean {
    Storage.clearValues();
    Party.unlock("mosscub");

    Party.addExtraLevel("mosscub", 2);
    Test.assertEqual(Party.extraLevel("mosscub"), 2);

    Party.setSlot(1, Party.EMPTY);
    Party.setSlot(3, "mosscub");
    Test.assertEqual(Party.extraLevel("mosscub"), 2);
    return true;
}

//! Growth is capped at the species ceiling and floored at zero.
(:test)
function testGrowthClamps(logger as Logger) as Boolean {
    Storage.clearValues();

    var mosscub = Combat.Bestiary.get("mosscub") as Combat.Creature;
    Party.addExtraLevel("mosscub", 999);
    Test.assertEqual(Party.extraLevel("mosscub"), mosscub.maxExtraLevel());

    Party.addExtraLevel("mosscub", -999);
    Test.assertEqual(Party.extraLevel("mosscub"), 0);
    return true;
}

//! Evolving replaces the lead and starts the new form fresh, leaving the rest of the roster alone.
(:test)
function testEvolvingReplacesOnlyTheLead(logger as Logger) as Boolean {
    Storage.clearValues();
    Party.unlock("mosscub");
    Party.addExtraLevel("mosscub", 1);

    Party.replaceLead("cinderfang");

    Test.assertEqual(Party.lead().key, "cinderfang");
    Test.assertEqual(Party.extraLevel("cinderfang"), 0);
    Test.assert(Party.isUnlocked("cinderfang"));

    // The rest of the party is untouched.
    Test.assertEqual(Party.slot(1), "mosscub");
    Test.assertEqual(Party.extraLevel("mosscub"), 1);
    return true;
}

//! Growth for an unknown key is ignored rather than persisted as junk.
(:test)
function testUnknownSpeciesGrowthIsIgnored(logger as Logger) as Boolean {
    Storage.clearValues();

    Party.addExtraLevel("not_a_creature", 3);
    Test.assertEqual(Party.extraLevel("not_a_creature"), 0);
    return true;
}
