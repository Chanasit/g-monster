import Toybox.Lang;
import Toybox.WatchUi;

//! Input for BattleActionView: UP/DOWN pick an action, START opens it, BACK returns to the fight.
class BattleActionDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BattleActionView;

    function initialize(view as BattleActionView) {
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
