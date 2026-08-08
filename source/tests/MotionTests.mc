import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the movement classifier. Pure logic only — `Motion.classify` takes the numbers
//! the sampler would have measured, so none of this needs a pedometer or a clock.
//!
//! The table is a priority list, so each test names the rule it pins down. Ordering is behaviour
//! here, not style: sleep outranks entry, entry outranks coasting.
//!
//! The last argument is the gap since the window last held entry evidence. It can never be smaller
//! than the gap since the last step, so a test that passes a smaller one is describing a state the
//! sampler cannot produce.

// ---------------------------------------------------------------- rule 1: sleep

//! A long enough gap since the last step is sleep, whatever the window holds.
(:test)
function testSleepsAfterALongStillStretch(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS,
                                     Motion.SLEEP_AFTER_MS),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! Sleep outranks cadence: steps in the window with an old last-step time is stale measurement,
//! not someone both asleep and moving.
(:test)
function testSleepOutranksStaleCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 20, Motion.SLEEP_AFTER_MS + 1,
                                     Motion.SLEEP_AFTER_MS + 1),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! One millisecond short of the threshold is still awake.
(:test)
function testDoesNotSleepJustBeforeTheThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 0, Motion.SLEEP_AFTER_MS - 1,
                                     Motion.SLEEP_AFTER_MS - 1),
                     Sprites.ACTION_IDLE);
    return true;
}

// ------------------------------------------------------------ rule 2: move entry

//! Two steps in the short window starts a move. This is the fast half of "fast in, slow out".
(:test)
function testEntersMoveOnTheEntryEvidence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.MOVE_ENTER_STEPS, 0, 0),
                     Sprites.ACTION_MOVE);
    return true;
}

//! One step is not a move from a standing start.
(:test)
function testOneStepDoesNotStartAMove(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, Motion.MOVE_ENTER_STEPS - 1, 0, 0),
                     Sprites.ACTION_IDLE);
    return true;
}

//! A running cadence is the same state as a walking one. There is one movement threshold, and
//! everything above it is the same pose — this is the test that would fail if a run state came
//! back without art of its own.
(:test)
function testARunningCadenceIsTheSameMoveState(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, Motion.MOVE_ENTER_STEPS * 4, 0, 0),
                     Sprites.ACTION_MOVE);
    return true;
}

// ----------------------------------------------------------------- rule 3: coast

//! Already moving, a cadence that has only just lapsed sustains it — on evidence below the bar that
//! would have started it. Without this the state strobes at the threshold.
(:test)
function testMoveCoastsBelowTheEntryCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 1, 2000, 2000), Sprites.ACTION_MOVE);
    return true;
}

//! The coast expires. This is the rule that makes the move state escapable: five seconds without
//! the window ever clearing the entry bar ends it no matter what individual steps arrive.
(:test)
function testCoastExpiresAtTheQuietThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 1, 0, Motion.MOVE_QUIET_MS),
                     Sprites.ACTION_IDLE);
    return true;
}

//! One millisecond short of the threshold is still coasting.
(:test)
function testCoastSurvivesJustUnderTheQuietThreshold(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_MOVE, 0, 0, Motion.MOVE_QUIET_MS - 1),
                     Sprites.ACTION_MOVE);
    return true;
}

//! The same evidence from idle stays idle. Coasting sustains a state, it never starts one.
(:test)
function testIdleDoesNotCoastIntoAMove(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_IDLE, 1, 2000, 2000), Sprites.ACTION_IDLE);
    return true;
}

//! No rule fires on zero evidence, and the fallthrough is idle regardless of what state walked in
//! — it does not carry the previous state through. Start from sleep so a fallthrough of `state`
//! would answer wrong and this actually pins the fallthrough down.
(:test)
function testColdStartIsIdle(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(Sprites.ACTION_SLEEP, 0, 0, 0), Sprites.ACTION_IDLE);
    return true;
}

// -------------------------------------------------------------------- scenarios

//! A stroll of one step every two seconds, sampled every second. Once it starts moving it must
//! keep moving: the window keeps dipping under the entry bar but never stays under it for long
//! enough to expire the coast. This is the anti-strobe test.
(:test)
function testStrollDoesNotStrobe(logger as Logger) as Boolean {
    var state = Sprites.ACTION_IDLE;

    // Two steps land three seconds apart at first, which is what starts the move.
    state = Motion.classify(state, 2, 0, 0);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // Then it settles into one step every two seconds: the window holds 1 or 2, so the cadence
    // bar is cleared every other sample and the coast is renewed before it can expire.
    var sinceCadence = 0;
    for (var i = 0; i < 20; i += 1) {
        var steps3s = (i % 2 == 0) ? 1 : 2;
        sinceCadence = (steps3s >= Motion.MOVE_ENTER_STEPS) ? 0 : sinceCadence + 1000;
        state = Motion.classify(state, steps3s, (i % 2) * 1000, sinceCadence);
        Test.assertEqual(state, Sprites.ACTION_MOVE);
    }
    return true;
}

//! A sprint stopped dead. One movement state means there is no intermediate rung to pass through:
//! it holds the move pose while the coast rule carries it, then goes idle when the coast expires.
//! It does not decelerate through a slower pose, because there is no longer a slower pose.
(:test)
function testSprintToDeadStopGoesStraightToIdle(logger as Logger) as Boolean {
    var state = Sprites.ACTION_MOVE;

    // 1s past the last real cadence, one straggling step: coasting is what holds it.
    state = Motion.classify(state, 1, 1000, 1000);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // 3s: still coasting.
    state = Motion.classify(state, 0, 3000, 3000);
    Test.assertEqual(state, Sprites.ACTION_MOVE);

    // 5s: the coast expires.
    state = Motion.classify(state, 0, Motion.MOVE_QUIET_MS, Motion.MOVE_QUIET_MS);
    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}

//! Regression: the creature used to get stuck in the move pose forever.
//!
//! The coast was bounded by the gap since the last step rather than the gap since real cadence, so
//! anything that ticked the pedometer occasionally — a wrist knocked while driving, a gesture at a
//! desk — renewed it indefinitely at a fifth of the cadence entry demands. Nobody is walking here:
//! a lone step arrives every four seconds and the window never holds two, so the move must end.
(:test)
function testStrayStepsDoNotPinTheMoveState(logger as Logger) as Boolean {
    var state = Sprites.ACTION_MOVE;
    var sinceCadence = 0;

    // 60 samples at 1s: a step every 4th sample, never two inside one window.
    for (var i = 0; i < 60; i += 1) {
        var steps3s = (i % 4 == 0) ? 1 : 0;
        var sinceStep = (i % 4) * 1000;
        sinceCadence += 1000;
        state = Motion.classify(state, steps3s, sinceStep, sinceCadence);
    }

    Test.assertEqual(state, Sprites.ACTION_IDLE);
    return true;
}
