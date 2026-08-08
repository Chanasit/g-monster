import Toybox.Lang;
import Toybox.System;

//! What the player's body is doing, so the creature on screen can do the same thing.
//!
//! The pedometer is the only signal — the watch already counts steps for the journey, and a
//! creature that walks when its tamer walks is the whole point of the game.
//!
//! The rules are deliberately asymmetric: the move state is entered on three seconds of evidence
//! and left only after five seconds of silence. That gap is what makes the creature look like it
//! is following the wearer rather than lagging them, and it is also what stops a cadence sitting
//! near the threshold from strobing the state every sample.
//!
//! State lives in memory and is thrown away when the view hides. Persisting it would mean a
//! storage write for something that is only ever true right now, and the journey already owns the
//! durable step accounting.
module Motion {

    //! The cadence is the tunable; the step count below derives from it, so a reader sees the
    //! intent rather than a magic integer. The division is exact.

    //! Steps per minute that count as moving at all. Low, because two steps inside the entry
    //! window is already someone on their feet.
    //!
    //! There is one movement state and one threshold. An earlier version had a second, higher
    //! cadence that promoted a walk to a run, with its own lower exit threshold for hysteresis.
    //! Nothing could observe it: run and walk drew the same sheet at the same rate once their art
    //! was merged, so the whole ladder was untestable machinery.
    const MOVE_ENTER_SPM = 40;

    //! One slot per second, three of them. The entry rule is the only one that reads a sum over
    //! the buffer; the quiet and sleep rules each read `sinceStepMs` — the gap since the last step
    //! — so they need no slots of their own, and the buffer holds no more than entry ever asks for.
    const BUCKET_MS = 1000;
    const BUCKETS = 3;

    //! Entry is judged over the newest three slots. BUCKETS and ENTER_BUCKETS carry the same
    //! number today, but they answer different questions: BUCKETS is how much history the ring
    //! buffer can hold, ENTER_BUCKETS is how much of that history the entry rule consumes. They
    //! coincide because entry is the buffer's only reader, not because they are the same constant
    //! wearing two names — a future rule that needs a longer sum would grow BUCKETS without
    //! touching this one.
    const ENTER_BUCKETS = 3;
    const ENTER_MS = ENTER_BUCKETS * BUCKET_MS;

    //! Silence that ends a move.
    const MOVE_QUIET_MS = 5000;

    //! No steps for this long and the creature settles down to sleep.
    const SLEEP_AFTER_MS = 300000;

    const MOVE_ENTER_STEPS = (MOVE_ENTER_SPM * ENTER_MS) / 60000;

    var _buckets as Array<Number> = [0, 0, 0];
    var _cursor as Number = 0;
    var _bucketStart as Number = 0;
    var _lastRaw as Number = -1;
    var _lastStepAt as Number = 0;
    var _action as Number = Sprites.ACTION_IDLE;

    //! Forget everything and start measuring again. Called when a view appears, since whatever was
    //! measured before it was hidden says nothing about now — which is also why an opened app
    //! always shows an idle creature and needs a fresh five minutes of stillness to sleep.
    function reset() as Void {
        for (var i = 0; i < BUCKETS; i += 1) {
            _buckets[i] = 0;
        }
        _cursor = 0;
        _lastRaw = -1;
        _action = Sprites.ACTION_IDLE;
    }

    //! Which action the player's movement calls for. Pure, so the whole table can be tested
    //! without a pedometer.
    //!
    //! A priority list, and the order is behaviour rather than style:
    //!
    //!   1. sleep and 2. silence are answered from the gap alone, so a single step resets the gap
    //!      and wakes the creature on the same sample — waking needs no rule of its own.
    //!   3. entry starts a move once evidence clears the threshold.
    //!   4. coasting sustains a move on evidence that would not have started one. That is the
    //!      hysteresis, and without it a stroll near the entry cadence flickers.
    function classify(state as Number, steps3s as Number, sinceStepMs as Number) as Number {
        if (sinceStepMs >= SLEEP_AFTER_MS) {
            return Sprites.ACTION_SLEEP;
        }
        if (sinceStepMs >= MOVE_QUIET_MS) {
            return Sprites.ACTION_IDLE;
        }
        if (steps3s >= MOVE_ENTER_STEPS) {
            return Sprites.ACTION_MOVE;
        }
        if (state == Sprites.ACTION_MOVE) {
            return Sprites.ACTION_MOVE;
        }
        return Sprites.ACTION_IDLE;
    }

    //! Steps across the newest `count` slots.
    function recentSteps(count as Number) as Number {
        var total = 0;
        for (var i = 0; i < count; i += 1) {
            var slot = _cursor - i;
            if (slot < 0) {
                slot += BUCKETS;
            }
            total += _buckets[slot];
        }
        return total;
    }

    //! Move the cursor on to the second `now` falls in, clearing every slot passed over.
    //!
    //! Slots are indexed by wall-clock second rather than by sample, so the sums stay windows over
    //! real time even when the redraw tick arrives late or in bursts.
    function advance(now as Number) as Void {
        var slots = (now - _bucketStart) / BUCKET_MS;
        if (slots <= 0) {
            return;
        }

        if (slots >= BUCKETS) {
            // The view was hidden or the tick starved. Nothing in the buffer describes now.
            for (var i = 0; i < BUCKETS; i += 1) {
                _buckets[i] = 0;
            }
            _cursor = 0;
        } else {
            for (var i = 0; i < slots; i += 1) {
                _cursor = (_cursor + 1) % BUCKETS;
                _buckets[_cursor] = 0;
            }
        }
        _bucketStart += slots * BUCKET_MS;
    }

    //! Fold the current pedometer reading in. Cheap enough to call on every redraw tick: it reads
    //! the step count and does integer arithmetic over three slots.
    //!
    //! The state is re-decided here on every sample. An earlier version only decided at a ten
    //! second window boundary, and that boundary was the whole of the creature's lag.
    function sample() as Void {
        var now = System.getTimer();
        var raw = StepTracker.rawSteps();

        // First sample, or the millisecond clock wrapped. Either way there is no usable history:
        // seed from here rather than treat the whole step count as one instant of walking.
        if (_lastRaw < 0 || now < _bucketStart) {
            _lastRaw = raw;
            _bucketStart = now;
            _lastStepAt = now;
            _cursor = 0;
            for (var i = 0; i < BUCKETS; i += 1) {
                _buckets[i] = 0;
            }
            return;
        }

        // A reading below the last one is the midnight reset, not un-walking.
        var delta = raw - _lastRaw;
        if (delta < 0) {
            delta = raw;
        }
        _lastRaw = raw;

        advance(now);

        if (delta > 0) {
            _buckets[_cursor] += delta;
            _lastStepAt = now;
        }

        _action = classify(_action, recentSteps(ENTER_BUCKETS), now - _lastStepAt);
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
