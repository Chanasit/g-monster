import Toybox.Lang;
import Toybox.WatchUi;

//! Input for RewardView. The outcome is already applied, so every button just acknowledges it.
class RewardDelegate extends WatchUi.BehaviorDelegate {

    private var _view as RewardView;

    function initialize(view as RewardView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.dismiss();
        return true;
    }

    function onBack() as Boolean {
        _view.dismiss();
        return true;
    }
}
