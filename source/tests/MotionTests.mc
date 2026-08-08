import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the movement classifier. Pure logic only — `Motion.classify` takes the numbers
//! the sampler would have measured, so none of this needs a pedometer or a clock.
//!
//! The table is a priority list, so each test names the rule it pins down. Ordering is behaviour
//! here, not style: sleep outranks silence, entry outranks coasting.

// ---------------------------------------------------------------- rule 1: sleep

//! A long enough gap since the last step is sleep, whatever the window holds.
(:test)
function testSleepsAfterALongStillStretch(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! Sleep outranks cadence: steps in the window with an old last-step time is stale measurement,
//! not someone both asleep and moving.
(:test)
function testSleepOutranksStaleCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 20, Motion.SLEEP_AFTER_MS + 1),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! One millisecond short of the threshold is still awake.
(:test)
function testDoesNotSleepJustBeforeTheThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS - 1),
                     Sprites.ACTION_IDLE);
    return true;
}

// ----------------------------------------------------------------- rule 2: quiet

//! Five seconds without a step ends a move. This is the slow half of "fast in, slow out".
(:test)
function testMoveEndsAfterFiveSecondsOfSilence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 0, Motion.MOVE_QUIET_MS),
                     Sprites.ACTION_IDLE);
    return true;
}

//! A step four seconds ago is a slow walk, not a stop.
(:test)
function testMoveSurvivesAGapUnderTheQuietThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 0, Motion.MOVE_QUIET_MS - 1),
                     Sprites.ACTION_MOVE);
    return true;
}

// ------------------------------------------------------------ rule 3: move entry

//! Two steps in the short window starts a move. This is the fast half of "fast in, slow out".
(:test)
function testEntersMoveOnTheEntryEvidence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.MOVE_ENTER_STEPS, 0),
                     Sprites.ACTION_MOVE);
    return true;
}

//! One step is not a move from a standing start.
(:test)
function testOneStepDoesNotStartAMove(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.MOVE_ENTER_STEPS - 1, 0),
                     Sprites.ACTION_IDLE);
    return true;
}

//! A running cadence is the same state as a walking one. There is one movement threshold, and
//! everything above it is the same pose — this is the test that would fail if a run state came
//! back without art of its own.
(:test)
function testARunningCadenceIsTheSameMoveState(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, Motion.MOVE_ENTER_STEPS * 4, 0),
                     Sprites.ACTION_MOVE);
    return true;
}

// ----------------------------------------------------------------- rule 4: coast

//! Already moving, one step every few seconds sustains it — below the cadence that would have
//! started it. Without this the state strobes at the threshold.
(:test)
function testMoveCoastsBelowTheEntryCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 1, 2000), Sprites.ACTION_MOVE);
    return true;
}

//! The same evidence from idle stays idle. Coasting sustains a state, it never starts one.
(:test)
function testIdleDoesNotCoastIntoAMove(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 1, 2000), Sprites.ACTION_IDLE);
    return true;
}

//! No rule fires on zero evidence, and the fallthrough is idle regardless of what state walked in
//! — it does not carry the previous state through. Start from sleep so a fallthrough of `state`
//! would answer wrong and this actually pins the fallthrough down.
(:test)
function testColdStartIsIdle(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_SLEEP, 0, 0), Sprites.ACTION_IDLE);
    return true;
}

// -------------------------------------------------------------------- scenarios

//! A stroll of one step every two seconds, sampled every second. Once it starts moving it must
//! keep moving: the gap never reaches the quiet threshold, even though the cadence keeps dipping
//! under the entry one. This is the anti-strobe test.
(:test)
function testStrollDoesNotStrobe(logger as Logger) as Boolean {
    var state = Sprites.ACTION_IDLE;

    // Two steps land three seconds apart at first, which is what starts the move.
    state = Motion.classify(state, 2, 0);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // Then it settles into one step every two seconds: the short window holds 1 or 2, and the
    // longest silence is 2s.
    for (var i = 0; i < 20; i += 1) {
        var steps3s = (i % 2 == 0) ? 1 : 2;
        state = Motion.classify(state, steps3s, (i % 2) * 1000);
        Test.assertEqual(state, Sprites.ACTION_MOVE);
    }
    return true;
}

//! A sprint stopped dead. One movement state means there is no intermediate rung to pass through:
//! it holds the move pose while the coast rule carries it, then goes idle when the silence rule
//! fires. It does not decelerate through a slower pose, because there is no longer a slower pose.
(:test)
function testSprintToDeadStopGoesStraightToIdle(logger as Logger) as Boolean {
    var state = Sprites.ACTION_MOVE;

    // 1s of silence, one straggling step: below the entry cadence, so coasting is what holds it.
    state = Motion.classify(state, 1, 1000);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // 3s of silence, no steps in the short window: still coasting, still under the quiet rule.
    state = Motion.classify(state, 0, 3000);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // 5s: the quiet rule ends it.
    state = Motion.classify(state, 0, Motion.MOVE_QUIET_MS);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}

//! Asleep, then a single step. Waking needs no rule of its own: the step resets the silence, and
//! one step is not yet a move, so the creature wakes to idle on the very next sample.
(:test)
function testOneStepWakesTheCreature(logger as Logger) as Boolean {
    var state = Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS);
    Test.assertEqual(state, Sprites.ACTION_SLEEP);

    state = Motion.classify(state, 1, 0);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}
