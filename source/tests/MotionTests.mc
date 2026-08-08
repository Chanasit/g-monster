import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the movement classifier. Pure logic only — `Motion.classify` takes the numbers
//! the sampler would have measured, so none of this needs a pedometer or a clock.
//!
//! The table is a priority list, so each test names the rule it pins down. Ordering is behaviour
//! here, not style: entry outranks the run's exit check, and both outrank coasting.

// ---------------------------------------------------------------- rule 1: sleep

//! A long enough gap since the last step is sleep, whatever the windows hold.
(:test)
function testSleepsAfterALongStillStretch(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, 0, Motion.SLEEP_AFTER_MS),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! Sleep outranks cadence: steps in the window with an old last-step time is stale measurement,
//! not someone both asleep and running.
(:test)
function testSleepOutranksStaleCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_RUN, 20, 40, Motion.SLEEP_AFTER_MS + 1),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! One millisecond short of the threshold is still awake.
(:test)
function testDoesNotSleepJustBeforeTheThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, 0, Motion.SLEEP_AFTER_MS - 1),
                     Sprites.ACTION_IDLE);
    return true;
}

// ----------------------------------------------------------------- rule 2: quiet

//! Five seconds without a step ends a walk. This is the slow half of "fast in, slow out".
(:test)
function testWalkEndsAfterFiveSecondsOfSilence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_WALK, 0, 0, Motion.WALK_QUIET_MS),
                     Sprites.ACTION_IDLE);
    return true;
}

//! A step four seconds ago is a slow walk, not a stop.
(:test)
function testWalkSurvivesAGapUnderTheQuietThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_WALK, 0, 1, Motion.WALK_QUIET_MS - 1),
                     Sprites.ACTION_WALK);
    return true;
}

//! Silence ends a run the same way it ends a walk, without waiting for the exit sum to decay.
(:test)
function testRunEndsAtTheSameSilence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_RUN, 0, 0, Motion.WALK_QUIET_MS),
                     Sprites.ACTION_IDLE);
    return true;
}

// ------------------------------------------------------------- rule 3: run entry

//! Enough steps in the short window and it is a run, from any state.
(:test)
function testEntersRunFromStandingStart(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.RUN_ENTER_STEPS,
                                     Motion.RUN_ENTER_STEPS, 0),
                     Sprites.ACTION_RUN);
    return true;
}

//! One step short of the run threshold is a walk.
(:test)
function testJustUnderTheRunThresholdIsAWalk(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_WALK, Motion.RUN_ENTER_STEPS - 1,
                                     Motion.RUN_ENTER_STEPS - 1, 0),
                     Sprites.ACTION_WALK);
    return true;
}

//! Entry outranks the exit check, so the first seconds of a run do not flicker: the five-second
//! sum is still low then, because two of its seconds were spent standing still.
(:test)
function testRunOnsetDoesNotBounceOffTheExitSum(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_RUN, Motion.RUN_ENTER_STEPS,
                                     Motion.RUN_EXIT_STEPS - 1, 0),
                     Sprites.ACTION_RUN);
    return true;
}

// -------------------------------------------------------------- rule 4: run exit

//! Below the entry cadence but above the exit one, the run continues. That gap is the hysteresis.
(:test)
function testRunContinuesAboveTheExitSum(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_RUN, Motion.RUN_ENTER_STEPS - 1,
                                     Motion.RUN_EXIT_STEPS, 0),
                     Sprites.ACTION_RUN);
    return true;
}

//! One step below the exit sum and the run is over.
(:test)
function testRunDropsToWalkUnderTheExitSum(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_RUN, Motion.RUN_ENTER_STEPS - 1,
                                     Motion.RUN_EXIT_STEPS - 1, 0),
                     Sprites.ACTION_WALK);
    return true;
}

// ------------------------------------------------------------- rule 5: walk entry

//! Two steps in the short window starts a walk. This is the fast half of "fast in, slow out".
(:test)
function testEntersWalkOnTheEntryEvidence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.WALK_ENTER_STEPS,
                                     Motion.WALK_ENTER_STEPS, 0),
                     Sprites.ACTION_WALK);
    return true;
}

//! One step is not a walk from a standing start.
(:test)
function testOneStepDoesNotStartAWalk(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.WALK_ENTER_STEPS - 1,
                                     Motion.WALK_ENTER_STEPS - 1, 0),
                     Sprites.ACTION_IDLE);
    return true;
}

// ----------------------------------------------------------------- rule 6: coast

//! Already walking, one step every few seconds sustains it — below the cadence that would have
//! started it. Without this the state strobes at the threshold.
(:test)
function testWalkCoastsBelowTheEntryCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_WALK, 1, 1, 2000), Sprites.ACTION_WALK);
    return true;
}

//! The same evidence from idle stays idle. Coasting sustains a state, it never starts one.
(:test)
function testIdleDoesNotCoastIntoAWalk(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 1, 1, 2000), Sprites.ACTION_IDLE);
    return true;
}

//! Opening the app measures nothing, and nothing is idle — never mid-stride.
(:test)
function testColdStartIsIdle(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, 0, 0), Sprites.ACTION_IDLE);
    return true;
}

// -------------------------------------------------------------------- scenarios

//! A stroll of one step every two seconds, sampled every second. Once it starts walking it must
//! stay walking: the gap never reaches the quiet threshold, even though the cadence keeps dipping
//! under the entry one. This is the anti-strobe test.
(:test)
function testStrollDoesNotStrobe(logger as Logger) as Boolean {
    var state = Sprites.ACTION_IDLE;

    // Two steps land three seconds apart at first, which is what starts the walk.
    state = Motion.classify(state, 2, 2, 0);
    Test.assertEqual(state, Sprites.ACTION_WALK);

    // Then it settles into one step every two seconds: the short window holds 1 or 2, and the
    // longest silence is 2s.
    for (var i = 0; i < 20; i += 1) {
        var steps3s = (i % 2 == 0) ? 1 : 2;
        state = Motion.classify(state, steps3s, 3, (i % 2) * 1000);
        Test.assertEqual(state, Sprites.ACTION_WALK);
    }
    return true;
}

//! A sprint stopped dead. The five-second sum decays as the sprint leaves the window, so the run
//! becomes a walk first and only then an idle — the creature decelerates rather than snapping.
(:test)
function testSprintToDeadStopDecelerates(logger as Logger) as Boolean {
    var state = Sprites.ACTION_RUN;

    // 1s of silence: the window still holds most of the sprint.
    state = Motion.classify(state, 4, Motion.RUN_EXIT_STEPS + 2, 1000);
    Test.assertEqual(state, Sprites.ACTION_RUN);

    // 3s of silence: only the tail of the sprint is left in the five-second window.
    state = Motion.classify(state, 0, Motion.RUN_EXIT_STEPS - 2, 3000);
    Test.assertEqual(state, Sprites.ACTION_WALK);

    // 5s: the quiet rule ends it.
    state = Motion.classify(state, 0, 0, Motion.WALK_QUIET_MS);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}

//! Slowing from a run into a walk without ever stopping. The exit is a lower cadence than the
//! entry, so the state changes once rather than oscillating across a single threshold.
(:test)
function testRunSlowingIntoAWalkCrossesOnce(logger as Logger) as Boolean {
    var state = Sprites.ACTION_RUN;

    state = Motion.classify(state, Motion.RUN_ENTER_STEPS - 1, Motion.RUN_EXIT_STEPS, 500);
    Test.assertEqual(state, Sprites.ACTION_RUN);

    state = Motion.classify(state, Motion.RUN_ENTER_STEPS - 2, Motion.RUN_EXIT_STEPS - 1, 500);
    Test.assertEqual(state, Sprites.ACTION_WALK);

    // Still walking at that cadence — it does not climb back into a run.
    state = Motion.classify(state, Motion.RUN_ENTER_STEPS - 2, Motion.RUN_EXIT_STEPS - 1, 500);
    Test.assertEqual(state, Sprites.ACTION_WALK);
    return true;
}

//! Asleep, then a single step. Waking needs no rule of its own: the step resets the silence, and
//! one step is not yet a walk, so the creature wakes to idle on the very next sample.
(:test)
function testOneStepWakesTheCreature(logger as Logger) as Boolean {
    var state = Motion.classify(Sprites.ACTION_IDLE, 0, 0, Motion.SLEEP_AFTER_MS);
    Test.assertEqual(state, Sprites.ACTION_SLEEP);

    state = Motion.classify(state, 1, 1, 0);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}
