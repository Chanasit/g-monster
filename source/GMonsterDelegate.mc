import Toybox.Lang;
import Toybox.WatchUi;

//! Maps physical buttons and swipes onto view page changes.
class GMonsterDelegate extends WatchUi.BehaviorDelegate {

    private var _view as GMonsterView;

    function initialize(view as GMonsterView) {
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

    //! START fights whatever the trek is waiting on. With nothing pending there is no fight to be
    //! had — battles are earned by walking, not by pressing the button again.
    function onSelect() as Boolean {
        Encounter.begin();
        return true;
    }

    //! MENU acts on whatever page is showing: the roster editor on PARTY, evolution on TAMER.
    function onMenu() as Boolean {
        if (_view.currentPage() == _view.PAGE_PARTY) {
            var party = new PartyView();
            WatchUi.pushView(party, new PartyDelegate(party), WatchUi.SLIDE_LEFT);
            return true;
        }

        // Evolution is only offered once the lead has actually earned the chance.
        if (!GameState.partnerCanEvolve()) {
            return true;
        }

        var partner = GameState.partner();
        var target = Evolution.target(partner);
        if (target == null) {
            return true;
        }

        var view = new EvolveView(partner, target, GameState.focus());
        WatchUi.pushView(view, new EvolveDelegate(view), WatchUi.SLIDE_LEFT);
        return true;
    }
}
