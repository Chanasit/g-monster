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

    //! Debug: launch straight into a battle instead of the pager, so the battle scene can be looked
    //! at without walking to an encounter — zero steps required.
    //!
    //! The fight is a preview (see Encounter.preview): it pays out nothing and never touches the
    //! trek, so this can be relaunched as often as you like without inflating a save. While it is on
    //! the rest of the app is unreachable, which is the point. Set to false for normal play, and
    //! reset it before packaging a release.
    private const DEBUG_INSTANT_BATTLE = false;

    //! Which species to fight in that preview. An unrecognised key falls back to a random encounter,
    //! so this doubles as a way to eyeball any creature's sprite.
    private const DEBUG_BATTLE_ENEMY = "glacierjaw";

    //! Show it as an area guardian — marks the name and uses the boss intro string.
    private const DEBUG_BATTLE_IS_BOSS = false;

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

        // Checked after the starter gate: a battle needs a partner to field, and a fresh save has
        // not chosen one yet.
        if (DEBUG_INSTANT_BATTLE) {
            return Encounter.preview(DEBUG_BATTLE_ENEMY, DEBUG_BATTLE_IS_BOSS);
        }

        var view = new GMonsterView();
        return [view, new GMonsterDelegate(view)];
    }
}
