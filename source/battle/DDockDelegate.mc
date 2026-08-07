import Toybox.Lang;
import Toybox.WatchUi;

//! Input for DDockView: UP/DOWN move between slots, START calls, BACK returns to the fight.
class DDockDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DDockView;

    function initialize(view as DDockView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.moveSelection(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.moveSelection(-1);
        return true;
    }

    function onSelect() as Boolean {
        _view.confirm();
        return true;
    }

    function onBack() as Boolean {
        _view.dismiss();
        return true;
    }
}
