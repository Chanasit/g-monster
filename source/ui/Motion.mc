import Toybox.Lang;
import Toybox.System;

//! What the player's body is doing, so the creature on screen can do the same thing.
//!
//! The pedometer is the only signal — the watch already counts steps for the journey, and a
//! creature that walks when its tamer walks is the whole point of the game. Cadence over a short
//! window separates a stroll from a run; a long gap with no steps at all is sleep.
//!
//! State lives in memory and is thrown away when the view hides. Persisting it would mean a
//! storage write per sample for something that is only ever true right now, and the journey
//! already owns the durable step accounting.
module Motion {

    //! Steps per minute at which a walk becomes a run. Deliberately clear of a brisk walk (~110)
    //! so the run state means running rather than hurrying.
    const RUN_SPM = 120;

    //! Steps per minute that count as walking at all. Low, because the window is short and a
    //! handful of steps across it is still someone on their feet.
    const WALK_SPM = 20;

    //! No steps for this long and the creature settles down to sleep.
    const SLEEP_AFTER_MS = 300000;

    //! Cadence is averaged over this long. Short enough to react inside a page view, long enough
    //! that the arm swing between two steps does not read as a sprint.
    const WINDOW_MS = 10000;

    var _lastRaw as Number = -1;
    var _windowStart as Number = 0;
    var _windowSteps as Number = 0;
    var _lastStepAt as Number = 0;
    var _action as Number = Sprites.ACTION_IDLE;

    //! Forget everything and start measuring again. Called when a view appears, since whatever was
    //! measured before it was hidden says nothing about now.
    function reset() as Void {
        _lastRaw = -1;
        _windowSteps = 0;
        _action = Sprites.ACTION_IDLE;
    }

    //! Which action the player's movement calls for. Pure, so the thresholds can be tested without
    //! a pedometer.
    //!
    //! Sleep is checked first and against the time since the last step rather than the window: a
    //! window with no steps in it only means the last ten seconds were still.
    function classify(steps as Number, windowMs as Number, sinceStepMs as Number) as Number {
        if (sinceStepMs >= SLEEP_AFTER_MS) {
            return Sprites.ACTION_SLEEP;
        }
        if (windowMs <= 0) {
            return Sprites.ACTION_IDLE;
        }

        var cadence = (steps * 60000) / windowMs;
        if (cadence >= RUN_SPM) {
            return Sprites.ACTION_RUN;
        }
        if (cadence >= WALK_SPM) {
            return Sprites.ACTION_WALK;
        }
        return Sprites.ACTION_IDLE;
    }

    //! Fold the current pedometer reading in. Cheap enough to call on every redraw tick: it reads
    //! the step count and does arithmetic, and only re-decides at a window boundary.
    function sample() as Void {
        var now = System.getTimer();
        var raw = StepTracker.rawSteps();

        // First sample, or the millisecond clock wrapped. Either way there is no usable history:
        // seed from here rather than treat the whole step count as one instant of walking.
        if (_lastRaw < 0 || now < _windowStart) {
            _lastRaw = raw;
            _windowStart = now;
            _windowSteps = 0;
            _lastStepAt = now;
            return;
        }

        // A reading below the last one is the midnight reset, not un-walking.
        var delta = raw - _lastRaw;
        if (delta < 0) {
            delta = raw;
        }
        _lastRaw = raw;

        if (delta > 0) {
            _windowSteps += delta;
            _lastStepAt = now;
        }

        var elapsed = now - _windowStart;
        if (elapsed >= WINDOW_MS) {
            _action = classify(_windowSteps, elapsed, now - _lastStepAt);
            _windowStart = now;
            _windowSteps = 0;
        } else if (now - _lastStepAt >= SLEEP_AFTER_MS) {
            // Falling asleep should not have to wait for a window to close.
            _action = Sprites.ACTION_SLEEP;
        }
    }

    //! What the creature should be doing right now.
    //!
    //! DebugConfig.FORCE_ACTION pins this to one pose when set, because a simulator has no legs:
    //! without it the ally sits at ACTION_IDLE and the walk, run and sleep poses are unreachable
    //! without walking around wearing the watch.
    //!
    //! Only this function consults the override. `classify` stays pure and unaffected, so
    //! MotionTests goes on asserting the real thresholds with the override on.
    function current() as Number {
        if (DebugConfig.FORCE_ACTION >= 0) {
            return DebugConfig.FORCE_ACTION;
        }
        return _action;
    }
}
