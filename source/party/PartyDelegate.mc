import Toybox.Lang;
import Toybox.WatchUi;

//! Input for PartyView: UP/DOWN move between slots, START cycles the occupant, BACK returns.
class PartyDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PartyView;

    function initialize(view as PartyView) {
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
        _view.cycleSlot();
        return true;
    }

    function onBack() as Boolean {
        _view.dismiss();
        return true;
    }
}
