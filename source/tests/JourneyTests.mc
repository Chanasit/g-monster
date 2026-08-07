import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the step-driven journey. Pure logic only — nothing here touches Storage or the
//! pedometer, so a Trek is built by hand and driven with a seeded Rng.

//! A trek that walks a plain stretch consumes every step it is given.
(:test)
function testAdvanceConsumesAllStepsOnOpenRoad(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 1000, 500, 0, Journey.EVENT_NONE);
    var consumed = trek.advance(100, new Combat.Rng(1));

    Test.assertEqual(consumed, 100);
    Test.assertEqual(trek.distance, 900);
    Test.assertEqual(trek.stepsToNextEvent, 400);
    Test.assertEqual(trek.totalSteps, 100);
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_NONE);
    return true;
}

//! Hitting the encounter counter stops the walk exactly there and banks the rest.
(:test)
function testEncounterInterruptsAndBanksSurplus(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 1000, 40, 0, Journey.EVENT_NONE);
    var consumed = trek.advance(100, new Combat.Rng(1));

    Test.assertEqual(consumed, 40);
    Test.assertEqual(trek.distance, 960);
    Test.assertEqual(trek.totalSteps, 40);
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_ENCOUNTER);

    // The gap is rerolled into the documented range.
    Test.assert(trek.stepsToNextEvent >= Journey.eventGapMin());
    Test.assert(trek.stepsToNextEvent <= Journey.eventGapMax());
    return true;
}

//! While an event is pending nothing moves, so the caller's baseline stays put.
(:test)
function testPendingEventFreezesProgress(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 500, 200, 10, Journey.EVENT_ENCOUNTER);
    var consumed = trek.advance(300, new Combat.Rng(1));

    Test.assertEqual(consumed, 0);
    Test.assertEqual(trek.distance, 500);
    Test.assertEqual(trek.stepsToNextEvent, 200);
    Test.assertEqual(trek.totalSteps, 10);

    // Resolving it lets the same steps land on the next call.
    trek.resolveEvent();
    Test.assertEqual(trek.advance(300, new Combat.Rng(1)), 200);
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_ENCOUNTER);
    return true;
}

//! Reaching the end of an area queues the guardian and never walks past it.
(:test)
function testDistanceEndTriggersBoss(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 30, 5000, 0, Journey.EVENT_NONE);
    var consumed = trek.advance(500, new Combat.Rng(1));

    Test.assertEqual(consumed, 29);
    Test.assertEqual(trek.distance, 1);
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_BOSS);
    return true;
}

//! A boss left unbeaten re-arms itself: the trek is still parked at distance 1.
(:test)
function testUnbeatenBossRetriggers(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 1, 400, 0, Journey.EVENT_BOSS);
    trek.resolveEvent();
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_NONE);

    var consumed = trek.advance(50, new Combat.Rng(1));
    Test.assertEqual(consumed, 0);
    Test.assertEqual(trek.distance, 1);
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_BOSS);
    return true;
}

//! Beating the guardian moves the trek to the next area with a fresh distance.
(:test)
function testCompleteAreaAdvances(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 1, 400, 5000, Journey.EVENT_BOSS);
    Atlas.advanceToNextArea(trek, new Combat.Rng(9));

    Test.assertEqual(trek.area, 1);
    Test.assertEqual(trek.distance, Atlas.areaDistance(1));
    Test.assertEqual(trek.pendingEvent, Journey.EVENT_NONE);
    Test.assertEqual(trek.totalSteps, 5000); // lifetime steps survive the transition
    Test.assert(trek.stepsToNextEvent >= Journey.eventGapMin());
    return true;
}

//! The area chain wraps rather than running off the end.
(:test)
function testAreaChainWraps(logger as Logger) as Boolean {
    var last = Atlas.areaCount() - 1;
    var trek = new Journey.Trek(last, 1, 400, 0, Journey.EVENT_BOSS);
    Atlas.advanceToNextArea(trek, new Combat.Rng(3));

    Test.assertEqual(trek.area, 0);
    Test.assertEqual(trek.distance, Atlas.areaDistance(0));
    return true;
}

//! Every area must name a boss that actually exists in the Bestiary.
(:test)
function testEveryAreaHasARealBoss(logger as Logger) as Boolean {
    for (var area = 0; area < Atlas.areaCount(); area += 1) {
        Test.assert(Atlas.areaDistance(area) > 1);
        Test.assert(Atlas.areaName(area).length() > 0);
        Test.assert(Combat.Bestiary.get(Atlas.areaBoss(area)) != null);
    }
    return true;
}

//! Out-of-range area indices clamp instead of throwing.
(:test)
function testAreaLookupClamps(logger as Logger) as Boolean {
    Test.assertEqual(Atlas.clampArea(-5), 0);
    Test.assertEqual(Atlas.clampArea(9999), Atlas.areaCount() - 1);
    Test.assert(Atlas.areaName(9999).length() > 0);
    return true;
}

//! A huge batch is capped, and the surplus stays banked for the next sync.
(:test)
function testCatchupIsCapped(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 999999, 999999, 0, Journey.EVENT_NONE);
    var consumed = trek.advance(999999, new Combat.Rng(1));

    Test.assertEqual(consumed, Journey.MAX_CATCHUP_STEPS);
    Test.assertEqual(trek.totalSteps, Journey.MAX_CATCHUP_STEPS);
    return true;
}

(:test)
function testAdvanceIgnoresNonPositiveSteps(logger as Logger) as Boolean {
    var trek = new Journey.Trek(0, 500, 200, 0, Journey.EVENT_NONE);
    Test.assertEqual(trek.advance(0, new Combat.Rng(1)), 0);
    Test.assertEqual(trek.advance(-50, new Combat.Rng(1)), 0);
    Test.assertEqual(trek.distance, 500);
    return true;
}

(:test)
function testAreaProgressSpansTheArea(logger as Logger) as Boolean {
    var total = Atlas.areaDistance(0);
    var fresh = new Journey.Trek(0, total, 400, 0, Journey.EVENT_NONE);
    Test.assert(fresh.areaProgress(total) < 0.0001);

    var half = new Journey.Trek(0, total / 2, 400, 0, Journey.EVENT_NONE);
    Test.assert((half.areaProgress(total) - 0.5).abs() < 0.01);

    var done = new Journey.Trek(0, 1, 400, 0, Journey.EVENT_BOSS);
    Test.assert(done.areaProgress(total) > 0.99);
    return true;
}

//! Walking a whole area end to end must produce encounters and then exactly one boss.
(:test)
function testFullAreaWalkProducesEventsThenBoss(logger as Logger) as Boolean {
    var rng = new Combat.Rng(777);
    var trek = new Journey.Trek(0, Atlas.areaDistance(0), Journey.rollEventGap(rng), 0, Journey.EVENT_NONE);

    var encounters = 0;
    var bosses = 0;

    for (var i = 0; i < 500; i += 1) {
        trek.advance(100, rng);
        if (trek.pendingEvent == Journey.EVENT_ENCOUNTER) {
            encounters += 1;
            trek.resolveEvent();
        } else if (trek.pendingEvent == Journey.EVENT_BOSS) {
            bosses += 1;
            break;
        }
    }

    Test.assertEqual(bosses, 1);
    Test.assert(encounters >= 2); // 1500 steps at a 300..500 gap
    Test.assertEqual(trek.distance, 1);
    return true;
}

//! Battles are earned by walking. With nothing pending there must be no fight available — this is
//! what stops START from being an unlimited source of experience, focus, recruits and spirit power.
(:test)
function testBattlesRequireAPendingEvent(logger as Logger) as Boolean {
    Storage.clearValues();

    // A trek mid-stride, nothing triggered: no battle.
    var walking = new Journey.Trek(0, 900, 250, 100, Journey.EVENT_NONE);
    JourneyState.saveTrek(walking);
    Test.assert(!Encounter.canBegin());
    Test.assert(!Encounter.begin());

    // An ambush is a battle.
    var ambushed = new Journey.Trek(0, 900, 250, 100, Journey.EVENT_ENCOUNTER);
    JourneyState.saveTrek(ambushed);
    Test.assert(Encounter.canBegin());

    // So is a guardian.
    var atGuardian = new Journey.Trek(0, 1, 250, 100, Journey.EVENT_BOSS);
    JourneyState.saveTrek(atGuardian);
    Test.assert(Encounter.canBegin());

    // Resolving it closes the door again until more walking happens.
    JourneyState.resolveEvent();
    Test.assert(!Encounter.canBegin());
    return true;
}

//! With no trek started at all there is nothing to fight either.
(:test)
function testNoBattleBeforeTheJourneyStarts(logger as Logger) as Boolean {
    Storage.clearValues();

    Test.assert(JourneyState.peekTrek() == null);
    Test.assert(!Encounter.canBegin());
    Test.assert(!Encounter.begin());
    return true;
}

//! The pedometer resets to zero at midnight; the delta must read that as new progress, not a
//! negative jump, and must measure from zero afterwards.
(:test)
function testStepDeltaHandlesMidnightReset(logger as Logger) as Boolean {
    Test.assertEqual(StepTracker.deltaFrom(1000, 1500), 500);
    Test.assertEqual(StepTracker.deltaFrom(1000, 1000), 0);

    // Reading dropped below the baseline: the day rolled over.
    Test.assertEqual(StepTracker.deltaFrom(9000, 120), 120);
    Test.assertEqual(StepTracker.originFor(9000, 120), 0);
    Test.assertEqual(StepTracker.originFor(1000, 1500), 1000);
    return true;
}
