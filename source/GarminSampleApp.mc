import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Entry point. Owns the app lifecycle and hands back the initial view/delegate pair.
class GarminSampleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    //! Called once when the app is launched.
    function onStart(state as Dictionary?) as Void {
    }

    //! Called once when the app is exiting.
    function onStop(state as Dictionary?) as Void {
    }

    //! First view shown, plus the delegate that handles button/touch input.
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new GarminSampleView();
        return [view, new GarminSampleDelegate(view)];
    }
}
