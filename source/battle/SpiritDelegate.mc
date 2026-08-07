import Toybox.Lang;
import Toybox.WatchUi;

//! Input for SpiritView: UP/DOWN browse forms, START enters one, BACK returns to the fight.
class SpiritDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SpiritView;

    function initialize(view as SpiritView) {
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
