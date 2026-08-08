import Toybox.Lang;
import Toybox.Test;

//! Tests for the spirit model: the cost curve, the per-turn drain, and the collapse that hands the
//! borrowed form back to the creature underneath it.

function spiritEngine(playerKey as String, enemyKey as String, playerLevel as Number) as Combat.BattleEngine {
    var player = Combat.Bestiary.get(playerKey) as Combat.Creature;
    var enemy = Combat.Bestiary.get(enemyKey) as Combat.Creature;
    return new Combat.BattleEngine(player, 0, enemy, playerLevel, new Combat.Rng(31415));
}

//! Keep both sides alive so a multi-turn test is measuring the drain, not the fight ending.
function makeUnkillable(engine as Combat.BattleEngine) as Void {
    engine.playerStats().maxHp = 99999;
    engine.playerStats().hp = 99999;
    engine.enemyStats().maxHp = 99999;
    engine.enemyStats().hp = 99999;
}

//! The data's `spirit` field must land on the right form class.
(:test)
function testSpiritTypeParsing(logger as Logger) as Boolean {
    var flarewisp = Combat.Bestiary.get("flarewisp") as Combat.Creature;
    var elderflame = Combat.Bestiary.get("elderflame") as Combat.Creature;
    var nonce = Combat.Bestiary.get("nonce") as Combat.Creature;

    Test.assertEqual(flarewisp.spiritType, Combat.Spirit.TYPE_WARRIOR);
    Test.assertEqual(elderflame.spiritType, Combat.Spirit.TYPE_ANCIENT);
    Test.assertEqual(nonce.spiritType, Combat.Spirit.TYPE_NONE);

    Test.assert(flarewisp.isSpirit());
    Test.assert(!nonce.isSpirit());
    return true;
}

(:test)
function testUnknownSpiritNameIsNotASpirit(logger as Logger) as Boolean {
    Test.assertEqual(Combat.Spirit.typeFromName(null), Combat.Spirit.TYPE_NONE);
    Test.assertEqual(Combat.Spirit.typeFromName("nonsense"), Combat.Spirit.TYPE_NONE);
    Test.assertEqual(Combat.Spirit.typeFromName("ancient"), Combat.Spirit.TYPE_ANCIENT);
    return true;
}

//! Every form in the data is a spirit, and every spirit is in forms().
(:test)
function testFormsListIsExactlyTheSpirits(logger as Logger) as Boolean {
    var forms = Combat.Spirit.forms();
    Test.assert(forms.size() > 0);

    for (var i = 0; i < forms.size(); i += 1) {
        Test.assert(forms[i].isSpirit());
    }

    var spiritCount = 0;
    var all = Combat.Bestiary.all();
    for (var i = 0; i < all.size(); i += 1) {
        if (all[i].isSpirit()) {
            spiritCount += 1;
        }
    }
    Test.assertEqual(forms.size(), spiritCount);
    return true;
}

//! Spirits are transformations, never inhabitants — they must never be rolled as a wild encounter.
//! Without this the exclusion could be deleted and the rest of the suite would stay green.
(:test)
function testSpiritsAreNeverWildEncounters(logger as Logger) as Boolean {
    var rng = new Combat.Rng(8675309);

    for (var level = 1; level <= 60; level += 1) {
        for (var i = 0; i < 20; i += 1) {
            Test.assert(!Combat.Bestiary.randomEncounter(level, rng).isSpirit());
        }
    }
    return true;
}

//! Cost falls as the player grows, halving once per the form's decay span, and never reaches zero.
(:test)
function testSpiritCostDecaysWithLevel(logger as Logger) as Boolean {
    var warrior = Combat.Bestiary.get("flarewisp") as Combat.Creature;

    var atZero = Combat.Spirit.cost(warrior, 0);
    Test.assertEqual(atZero, Combat.Spirit.baseCost(Combat.Spirit.TYPE_WARRIOR));

    // One decay span (30 levels for a warrior form) should halve it.
    var atOneSpan = Combat.Spirit.cost(warrior, 30);
    Test.assertEqual(atOneSpan, atZero / 2);

    // Monotonically non-increasing, and floored at 1 rather than free.
    var previous = atZero;
    for (var level = 0; level <= 200; level += 1) {
        var cost = Combat.Spirit.cost(warrior, level);
        Test.assert(cost <= previous);
        Test.assert(cost >= 1);
        previous = cost;
    }
    return true;
}

//! Bigger forms cost more and discount more slowly, so the ancient one stays an investment.
(:test)
function testCostOrderingAcrossForms(logger as Logger) as Boolean {
    var minor = Combat.Bestiary.get("gleammote") as Combat.Creature;
    var ancient = Combat.Bestiary.get("elderflame") as Combat.Creature;

    Test.assert(Combat.Spirit.cost(ancient, 20) > Combat.Spirit.cost(minor, 20));
    Test.assert(Combat.Spirit.cost(ancient, 60) > Combat.Spirit.cost(minor, 60));
    return true;
}

//! A non-spirit costs nothing because it can never be invoked at all.
(:test)
function testOrdinaryCreatureHasNoSpiritCost(logger as Logger) as Boolean {
    var nonce = Combat.Bestiary.get("nonce") as Combat.Creature;
    Test.assertEqual(Combat.Spirit.cost(nonce, 10), 0);

    var engine = spiritEngine("nonce", "drizzlet", 10);
    engine.setSpiritPower(99);
    Test.assert(!engine.canInvokeSpirit(nonce));
    Test.assert(!engine.invokeSpirit(nonce, 0));
    return true;
}

//! Only the ancient form is exempt from upkeep.
(:test)
function testOnlyAncientFormIsDrainFree(logger as Logger) as Boolean {
    var forms = Combat.Spirit.forms();
    for (var i = 0; i < forms.size(); i += 1) {
        var form = forms[i];
        var expected = (form.spiritType != Combat.Spirit.TYPE_ANCIENT);
        Test.assertEqual(Combat.Spirit.drains(form), expected);
    }
    return true;
}

(:test)
function testSpiritPowerClamps(logger as Logger) as Boolean {
    var engine = spiritEngine("nonce", "drizzlet", 10);

    engine.setSpiritPower(500);
    Test.assertEqual(engine.spiritPower(), Combat.Spirit.MAX_POWER);

    engine.setSpiritPower(-20);
    Test.assertEqual(engine.spiritPower(), 0);
    return true;
}

//! Invoking swaps the fighter and bills the cost.
(:test)
function testInvokeSwapsFighterAndSpendsPower(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("flarewisp") as Combat.Creature;

    engine.setSpiritPower(99);
    var cost = engine.spiritCost(form);
    Test.assert(cost > 0);

    Test.assert(engine.invokeSpirit(form, 0));
    Test.assertEqual(engine.spiritPower(), 99 - cost);
    Test.assertEqual(engine.playerSpecies().key, "flarewisp");
    Test.assert(engine.isSpiritActive());

    // A spirit's stats come from the player's level, not the host's growth.
    var expected = Combat.Spirit.stats(form, 20);
    Test.assertEqual(engine.playerStats().maxHp, expected.maxHp);
    return true;
}

//! Not affordable, not available.
(:test)
function testUnaffordableSpiritIsRefused(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("elderflame") as Combat.Creature;

    engine.setSpiritPower(engine.spiritCost(form) - 1);
    Test.assert(!engine.canInvokeSpirit(form));
    Test.assert(!engine.invokeSpirit(form, 0));
    Test.assertEqual(engine.playerSpecies().key, "cinderfang");
    return true;
}

//! Forms do not stack — one at a time.
(:test)
function testSpiritsDoNotStack(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var first = Combat.Bestiary.get("flarewisp") as Combat.Creature;
    var second = Combat.Bestiary.get("stonefang") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(first, 0));
    Test.assert(!engine.canInvokeSpirit(second));
    Test.assert(!engine.invokeSpirit(second, 0));
    Test.assertEqual(engine.playerSpecies().key, "flarewisp");
    return true;
}

(:test)
function testNoSpiritAfterTheBattleEnds(logger as Logger) as Boolean {
    var engine = spiritEngine("nonce", "drizzlet", 3);
    var form = Combat.Bestiary.get("gleammote") as Combat.Creature;
    engine.setSpiritPower(99);

    while (!engine.isOver()) {
        engine.takeTurn(Combat.ATTACK_ENERGY);
    }

    Test.assert(!engine.canInvokeSpirit(form));
    Test.assert(!engine.invokeSpirit(form, 0));
    return true;
}

//! Holding a draining form costs power every turn.
(:test)
function testDrainingFormBurnsPowerPerTurn(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("flarewisp") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(form, 0));
    makeUnkillable(engine);

    var before = engine.spiritPower();
    engine.takeTurn(Combat.ATTACK_ENERGY);
    Test.assertEqual(engine.spiritPower(), before - Combat.Spirit.DRAIN_PER_TURN);
    Test.assert(engine.isSpiritActive());
    return true;
}

//! The ancient form pays once and then holds for free.
(:test)
function testAncientFormNeverDrains(logger as Logger) as Boolean {
    var engine = spiritEngine("pyrewarden", "grovekeeper", 40);
    var form = Combat.Bestiary.get("elderflame") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(form, 0));
    makeUnkillable(engine);

    var afterInvoke = engine.spiritPower();
    for (var i = 0; i < 10; i += 1) {
        engine.takeTurn(Combat.ATTACK_CRUSH);
    }

    Test.assertEqual(engine.spiritPower(), afterInvoke);
    Test.assert(engine.isSpiritActive());
    Test.assert(!engine.spiritCollapsed());
    return true;
}

//! When the power runs out the form breaks and the host comes back.
(:test)
function testFormCollapsesWhenPowerRunsOut(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("flarewisp") as Combat.Creature;

    // Exactly one turn of upkeep left after paying to enter.
    engine.setSpiritPower(engine.spiritCost(form) + Combat.Spirit.DRAIN_PER_TURN);
    Test.assert(engine.invokeSpirit(form, 0));
    makeUnkillable(engine);

    engine.takeTurn(Combat.ATTACK_ENERGY);

    Test.assertEqual(engine.spiritPower(), 0);
    Test.assert(!engine.isSpiritActive());
    Test.assert(engine.spiritCollapsed());
    Test.assertEqual(engine.playerSpecies().key, "cinderfang");
    return true;
}

//! The collapse flag is for the turn it happened, not a sticky state.
(:test)
function testCollapseFlagClearsOnTheNextTurn(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("flarewisp") as Combat.Creature;

    engine.setSpiritPower(engine.spiritCost(form) + Combat.Spirit.DRAIN_PER_TURN);
    Test.assert(engine.invokeSpirit(form, 0));
    makeUnkillable(engine);

    engine.takeTurn(Combat.ATTACK_ENERGY);
    Test.assert(engine.spiritCollapsed());

    engine.takeTurn(Combat.ATTACK_ENERGY);
    Test.assert(!engine.spiritCollapsed());
    return true;
}

//! The host returns holding the same share of its health the spirit had left — so a form can
//! neither be used to heal nor to soak a beating for free.
(:test)
function testCollapseCarriesTheHealthFraction(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("flarewisp") as Combat.Creature;
    var host = Combat.Bestiary.get("cinderfang") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(form, 0));

    // Take the spirit to exactly half health, then drop the form.
    engine.playerStats().hp = engine.playerStats().maxHp / 2;
    engine.breakSpirit();

    Test.assert(!engine.isSpiritActive());
    Test.assertEqual(engine.playerSpecies().key, "cinderfang");

    var hostMax = host.friendlyStats(0).maxHp;
    Test.assertEqual(engine.playerStats().maxHp, hostMax);

    var expected = hostMax / 2;
    Test.assert((engine.playerStats().hp - expected).abs() <= 1);
    return true;
}

//! Transforming at full health and collapsing untouched must return the host at full health —
//! no free damage for having used a form.
(:test)
function testCollapseAtFullHealthRestoresFullHealth(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("stonefang") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(form, 0));
    engine.breakSpirit();

    Test.assertEqual(engine.playerStats().hp, engine.playerStats().maxHp);
    return true;
}

//! A collapse must never be lethal by itself; the host comes back on at least one point.
(:test)
function testCollapseNeverKillsTheHost(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);
    var form = Combat.Bestiary.get("stonefang") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(form, 0));

    engine.playerStats().hp = 1;   // spirit on its last legs
    engine.breakSpirit();

    Test.assert(engine.playerStats().hp >= 1);
    Test.assert(!engine.playerStats().isDown());
    return true;
}

//! Breaking a form that was never entered is a no-op, not a crash.
(:test)
function testBreakWithoutASpiritIsHarmless(logger as Logger) as Boolean {
    var engine = spiritEngine("cinderfang", "thornmane", 20);

    var hp = engine.playerStats().hp;
    engine.breakSpirit();

    Test.assertEqual(engine.playerSpecies().key, "cinderfang");
    Test.assertEqual(engine.playerStats().hp, hp);
    Test.assert(!engine.isSpiritActive());
    return true;
}

//! The host's own growth survives the round trip — it is set aside, not rebuilt from base.
(:test)
function testHostGrowthSurvivesTheForm(logger as Logger) as Boolean {
    var host = Combat.Bestiary.get("mosscub") as Combat.Creature;
    var grown = host.maxExtraLevel();
    Test.assert(grown > 0);

    var enemy = Combat.Bestiary.get("thornmane") as Combat.Creature;
    var engine = new Combat.BattleEngine(host, grown, enemy, 20, new Combat.Rng(11));
    var form = Combat.Bestiary.get("flarewisp") as Combat.Creature;

    engine.setSpiritPower(99);
    Test.assert(engine.invokeSpirit(form, grown));
    engine.breakSpirit();

    Test.assertEqual(engine.playerStats().maxHp, host.friendlyStats(grown).maxHp);
    Test.assert(host.friendlyStats(grown).maxHp > host.friendlyStats(0).maxHp);
    return true;
}
