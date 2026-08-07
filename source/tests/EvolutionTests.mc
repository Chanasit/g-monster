import Toybox.Lang;
import Toybox.Test;

//! Unit tests for partner evolution. Pure logic only — storage-backed helpers on GameState are
//! exercised through the app, not here, so the tests leave no persisted state behind.

//! A partner short of its growth cap cannot evolve, however much focus is banked.
(:test)
function testEvolutionNeedsMaxedGrowth(logger as Logger) as Boolean {
    var partner = Combat.Bestiary.get("emberling") as Combat.Creature;
    var cap = partner.maxExtraLevel();

    Test.assert(!Evolution.isReady(partner, 0, Evolution.MAX_FOCUS));
    Test.assert(!Evolution.isReady(partner, cap - 1, Evolution.MAX_FOCUS));
    Test.assert(Evolution.isReady(partner, cap, 1));
    return true;
}

//! Focus is the other half of the gate.
(:test)
function testEvolutionNeedsFocus(logger as Logger) as Boolean {
    var partner = Combat.Bestiary.get("emberling") as Combat.Creature;
    var cap = partner.maxExtraLevel();

    Test.assert(!Evolution.isReady(partner, cap, 0));
    Test.assert(Evolution.isReady(partner, cap, 1));
    return true;
}

//! A final form never qualifies, no matter how maxed out or well-funded it is.
(:test)
function testFinalFormsCannotEvolve(logger as Logger) as Boolean {
    var finalForm = Combat.Bestiary.get("galewing") as Combat.Creature;
    Test.assert(finalForm.evolvesTo == null);
    Test.assert(Evolution.target(finalForm) == null);
    Test.assert(!Evolution.isReady(finalForm, 99, Evolution.MAX_FOCUS));
    return true;
}

//! Every evolution target must resolve to a real species.
(:test)
function testEvolutionTargetsResolve(logger as Logger) as Boolean {
    var all = Combat.Bestiary.all();
    for (var i = 0; i < all.size(); i += 1) {
        var species = all[i];
        if (species.evolvesTo != null) {
            var target = Evolution.target(species);
            Test.assert(target != null);
            // Growth must go somewhere stronger, or the chain is pointless.
            Test.assert((target as Combat.Creature).baseLevel > species.baseLevel);
        }
    }
    return true;
}

//! Committing more focus never lowers the odds, and the odds stay a probability.
(:test)
function testMoreFocusNeverHurts(logger as Logger) as Boolean {
    var target = Combat.Bestiary.get("cinderfang") as Combat.Creature;
    var playerLevel = 6;

    var previous = 0.0;
    for (var focus = 1; focus <= Evolution.MAX_FOCUS; focus += 1) {
        var odds = Evolution.chance(target, playerLevel, focus);
        Test.assert(odds >= 0.0);
        Test.assert(odds <= 1.0);
        Test.assert(odds >= previous - 0.0001);
        previous = odds;
    }
    return true;
}

//! An underlevelled player still has a floor chance rather than a locked door.
(:test)
function testLongShotStillPossible(logger as Logger) as Boolean {
    var target = Combat.Bestiary.get("solmonarch") as Combat.Creature;
    Test.assert(Evolution.chance(target, 1, 1) >= 0.05);
    return true;
}

//! An outlevelled target is a certainty, and the roll must agree.
(:test)
function testGuaranteedEvolutionAlwaysLands(logger as Logger) as Boolean {
    var target = Combat.Bestiary.get("cinderfang") as Combat.Creature;
    var playerLevel = target.baseLevel + 5;

    Test.assertEqual(Evolution.chance(target, playerLevel, 1), 1.0);

    var rng = new Combat.Rng(1234);
    for (var i = 0; i < 50; i += 1) {
        Test.assert(Evolution.attempt(target, playerLevel, 1, rng));
    }
    return true;
}

//! The attempt is a seeded roll, so the same seed and inputs replay identically.
(:test)
function testAttemptIsDeterministic(logger as Logger) as Boolean {
    var target = Combat.Bestiary.get("stormcrown") as Combat.Creature;

    var first = [] as Array<Boolean>;
    var rngA = new Combat.Rng(4242);
    for (var i = 0; i < 30; i += 1) {
        first.add(Evolution.attempt(target, 24, 5, rngA));
    }

    var rngB = new Combat.Rng(4242);
    for (var i = 0; i < 30; i += 1) {
        Test.assertEqual(Evolution.attempt(target, 24, 5, rngB), first[i]);
    }
    return true;
}

//! A marginal attempt must actually be uncertain — not a disguised always or never.
(:test)
function testMarginalAttemptIsUncertain(logger as Logger) as Boolean {
    var target = Combat.Bestiary.get("cinderfang") as Combat.Creature;
    var playerLevel = 6; // well under the target's base level of 12

    var odds = Evolution.chance(target, playerLevel, 1);
    Test.assert(odds > 0.0);
    Test.assert(odds < 1.0);

    var successes = 0;
    var rng = new Combat.Rng(99);
    for (var i = 0; i < 200; i += 1) {
        if (Evolution.attempt(target, playerLevel, 1, rng)) {
            successes += 1;
        }
    }

    Test.assert(successes > 0);
    Test.assert(successes < 200);
    return true;
}

//! The whole chain must be walkable: every starter reaches a final form in finite steps.
(:test)
function testEvolutionChainsTerminate(logger as Logger) as Boolean {
    var all = Combat.Bestiary.all();
    for (var i = 0; i < all.size(); i += 1) {
        var species = all[i];
        var hops = 0;
        while (species.evolvesTo != null && hops < 20) {
            species = Evolution.target(species) as Combat.Creature;
            hops += 1;
        }
        Test.assert(species.evolvesTo == null); // terminated rather than hitting the hop guard
    }
    return true;
}
