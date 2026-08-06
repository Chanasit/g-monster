import Toybox.Lang;
import Toybox.WatchUi;

//! Maps physical buttons and swipes onto view page changes.
class GarminSampleDelegate extends WatchUi.BehaviorDelegate {

    private var _view as GarminSampleView;

    function initialize(view as GarminSampleView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }

    //! Select (START) also advances, so touch-only devices can page through.
    function onSelect() as Boolean {
        _view.nextPage();
        return true;
    }
}
