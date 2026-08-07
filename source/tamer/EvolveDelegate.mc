import Toybox.Lang;
import Toybox.WatchUi;

//! Input for EvolveView: UP/DOWN set the focus committed, START rolls, BACK walks away.
class EvolveDelegate extends WatchUi.BehaviorDelegate {

    private var _view as EvolveView;

    function initialize(view as EvolveView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.adjustFocus(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.adjustFocus(-1);
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
