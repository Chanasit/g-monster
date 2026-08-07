import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Entry point. Owns the app lifecycle, the background registration, and the initial view.
(:background)
class GMonsterApp extends Application.AppBase {

    //! How often the system may wake the background service. Five minutes is the platform minimum.
    private const BACKGROUND_PERIOD_SECONDS = 300;

    function initialize() {
        AppBase.initialize();
    }

    //! Called once when the app is launched.
    function onStart(state as Dictionary?) as Void {
        registerBackgroundSync();
    }

    //! Called once when the app is exiting.
    function onStop(state as Dictionary?) as Void {
    }

    //! Keep the trek moving while the app is closed. Registration is idempotent, and devices
    //! without background support simply skip it.
    private function registerBackgroundSync() as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        if (!(System has :ServiceDelegate)) {
            return;
        }
        Background.registerForTemporalEvent(new Time.Duration(BACKGROUND_PERIOD_SECONDS));
    }

    //! The background service hands back the pending event it left us. Nothing to do with it
    //! directly — the view reads the trek from storage on its next tick.
    function onBackgroundData(data as Application.PersistableType) as Void {
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new BackgroundService()];
    }

    //! First view shown, plus the delegate that handles button/touch input.
    //!
    //! The app class is (:background) so it can host the service delegate, but this method only ever
    //! runs in the foreground — the background check is waived here rather than dragging the whole
    //! UI layer into background scope.
    (:typecheck(disableBackgroundCheck))
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        // A fresh save has to pick a starter before there is anything to show.
        if (!GameState.hasCharacter()) {
            var intro = new CharacterSelectView();
            return [intro, new CharacterSelectDelegate(intro)];
        }

        var view = new GMonsterView();
        return [view, new GMonsterDelegate(view)];
    }
}
