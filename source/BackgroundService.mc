import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

//! Accrues steps while the app is closed. The system runs this on a five-minute cadence — the
//! shortest interval Connect IQ allows — so the journey keeps moving during an ordinary day.
(:background)
class BackgroundService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var pending = StepTracker.sync();

        // Only interrupt the wearer when something is actually waiting for them.
        if (pending != Journey.EVENT_NONE) {
            Background.requestApplicationWake(
                (pending == Journey.EVENT_BOSS) ? "A guardian blocks the way!" : "Something found you!"
            );
        }

        Background.exit(pending);
    }
}
