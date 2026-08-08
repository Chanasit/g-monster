import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the movement classifier. Pure logic only — `Motion.classify` takes the numbers
//! the sampler would have measured, so none of this needs a pedometer or a clock.

//! Nothing measured yet, and no gap long enough to be sleep: the creature just stands there.
(:test)
function testClassifyIdleWhenStill(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(0, Motion.WINDOW_MS, 1000), Sprites.ACTION_IDLE);
    return true;
}

//! A few steps across the window is someone on their feet.
(:test)
function testClassifyWalkAtStrollingCadence(logger as Logger) as Boolean {
    // 10 steps in 10s is 60 spm — over the walk threshold, well under the run one.
    Test.assertEqual(Motion.classify(10, 10000, 0), Sprites.ACTION_WALK);
    return true;
}

//! Fast enough and it is a run.
(:test)
function testClassifyRunAtRunningCadence(logger as Logger) as Boolean {
    // 30 steps in 10s is 180 spm.
    Test.assertEqual(Motion.classify(30, 10000, 0), Sprites.ACTION_RUN);
    return true;
}

//! The thresholds are inclusive, and one step either side of them changes the answer.
(:test)
function testClassifyThresholdsAreInclusive(logger as Logger) as Boolean {
    var minute = 60000;

    Test.assertEqual(Motion.classify(Motion.WALK_SPM, minute, 0), Sprites.ACTION_WALK);
    Test.assertEqual(Motion.classify(Motion.WALK_SPM - 1, minute, 0), Sprites.ACTION_IDLE);
    Test.assertEqual(Motion.classify(Motion.RUN_SPM, minute, 0), Sprites.ACTION_RUN);
    Test.assertEqual(Motion.classify(Motion.RUN_SPM - 1, minute, 0), Sprites.ACTION_WALK);
    return true;
}

//! A long enough gap since the last step is sleep, whatever the window happened to hold.
(:test)
function testClassifySleepsAfterALongStillStretch(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(0, Motion.WINDOW_MS, Motion.SLEEP_AFTER_MS),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! Sleep outranks cadence: steps in the window with an old last-step time is stale measurement,
//! not a player who is both asleep and walking.
(:test)
function testClassifySleepWinsOverStaleCadence(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(50, 10000, Motion.SLEEP_AFTER_MS + 1),
                     Sprites.ACTION_SLEEP);
    return true;
}

//! A zero-length window would divide by zero. It reports idle instead.
(:test)
function testClassifyHandlesAnEmptyWindow(logger as Logger) as Boolean {
    Test.assertEqual(Motion.classify(5, 0, 0), Sprites.ACTION_IDLE);
    return true;
}
