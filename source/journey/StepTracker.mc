import Toybox.ActivityMonitor;
import Toybox.Lang;

//! Turns the watch's own pedometer into journey progress. This replaces the shake-counting the
//! original device relied on: the hardware already counts steps, so the app just reads deltas.
(:background)
module StepTracker {

    //! Today's step count, or 0 if the device has not reported one yet.
    function rawSteps() as Number {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        return (steps == null) ? 0 : steps;
    }

    //! Steps walked since the baseline.
    //!
    //! ActivityMonitor resets to zero at midnight, so a reading below the baseline means the day
    //! rolled over rather than that the player un-walked: everything on the clock is new progress.
    function deltaFrom(baseline as Number, raw as Number) as Number {
        if (raw < baseline) {
            return raw;
        }
        return raw - baseline;
    }

    //! The baseline a delta was measured against — zero after a midnight rollover.
    function originFor(baseline as Number, raw as Number) as Number {
        return (raw < baseline) ? 0 : baseline;
    }

    //! Fold any new steps into the trek and persist the result. Returns the pending event, which is
    //! EVENT_NONE when the player can keep walking.
    //!
    //! Only the steps the trek actually consumed advance the baseline, so steps walked while an
    //! event is pending stay banked and land as soon as the player resolves it.
    function sync() as Number {
        // The foreground starts the journey; until it has, there is nothing to advance.
        var trek = JourneyState.peekTrek();
        if (trek == null) {
            return Journey.EVENT_NONE;
        }

        var raw = rawSteps();
        var baseline = stepBaselineFor(raw);
        var delta = deltaFrom(baseline, raw);

        if (delta > 0) {
            var consumed = trek.advance(delta, new Combat.Rng(JourneyState.nextSeed()));
            JourneyState.saveTrek(trek);
            JourneyState.setStepBaseline(originFor(baseline, raw) + consumed);
        }

        return trek.pendingEvent;
    }

    //! Reconcile the stored baseline against the current reading, handling the midnight reset.
    function stepBaselineFor(raw as Number) as Number {
        var baseline = JourneyState.stepBaseline();
        if (raw < baseline) {
            // Day rolled over; start measuring from zero again.
            JourneyState.setStepBaseline(0);
            return 0;
        }
        return baseline;
    }

    //! Steps banked but not yet applied, because an event is blocking progress.
    function bankedSteps() as Number {
        var raw = rawSteps();
        var baseline = JourneyState.stepBaseline();
        var delta = deltaFrom(baseline, raw);
        return (delta < 0) ? 0 : delta;
    }
}
