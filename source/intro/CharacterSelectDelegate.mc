import Toybox.Lang;
import Toybox.WatchUi;

//! Input for CharacterSelectView: UP/DOWN browse the starters, START commits.
//!
//! BACK is deliberately not handled — there is no app behind this screen to go back to, and the
//! save cannot proceed without a choice.
class CharacterSelectDelegate extends WatchUi.BehaviorDelegate {

    private var _view as CharacterSelectView;

    function initialize(view as CharacterSelectView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.cycle(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.cycle(-1);
        return true;
    }

    function onSelect() as Boolean {
        _view.confirm();
        return true;
    }
}
