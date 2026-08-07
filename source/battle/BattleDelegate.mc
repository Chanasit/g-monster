import Toybox.Lang;
import Toybox.WatchUi;

//! Input for BattleView: UP/DOWN pick an attack, START commits, BACK leaves.
class BattleDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BattleView;

    function initialize(view as BattleView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.cycleAttack(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.cycleAttack(-1);
        return true;
    }

    function onSelect() as Boolean {
        _view.confirm();
        return true;
    }

    //! MENU opens the action menu: call an ally, or spend spirit power.
    function onMenu() as Boolean {
        if (!_view.canOpenDDock()) {
            return true;
        }
        var actions = new BattleActionView(_view);
        WatchUi.pushView(actions, new BattleActionDelegate(actions), WatchUi.SLIDE_LEFT);
        return true;
    }

    //! Fleeing mid-battle forfeits nothing — the encounter is simply abandoned.
    function onBack() as Boolean {
        _view.popView();
        return true;
    }
}
