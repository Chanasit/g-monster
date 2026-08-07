import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Mid-battle roster: pick a party slot to call onto the field. Shows what each call costs against
//! the points left, and why a slot is unavailable when it is.
class DDockView extends WatchUi.View {

    private var _battle as BattleView;
    private var _engine as Combat.BattleEngine;
    private var _selected as Number;

    function initialize(battle as BattleView) {
        View.initialize();
        _battle = battle;
        _engine = battle.battleEngine();
        _selected = 0;
    }

    function moveSelection(step as Number) as Void {
        _selected = (_selected + step + Party.SIZE) % Party.SIZE;
        WatchUi.requestUpdate();
    }

    //! Call the highlighted slot, if it can be called. An unavailable slot is simply inert.
    function confirm() as Void {
        var species = Party.member(_selected);
        if (species == null || !_engine.canSummon(species)) {
            return;
        }

        _battle.summon(species);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function dismiss() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var height = dc.getHeight();
        var centerX = dc.getWidth() / 2;

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.14, Graphics.FONT_XTINY,
                    (WatchUi.loadResource(Rez.Strings.PageDDock) as String)
                        + "  " + _engine.callPoints().toString() + "P",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        for (var i = 0; i < Party.SIZE; i += 1) {
            drawSlot(dc, centerX, height * (0.32 + (i * 0.15)), i);
        }
    }

    private function drawSlot(dc as Dc, centerX as Number, y as Numeric, index as Number) as Void {
        var selected = (index == _selected);
        var species = Party.member(index);

        if (selected) {
            Theme.muted(dc);
            dc.fillRectangle(centerX - (dc.getWidth() * 0.40).toNumber(), (y - 11).toNumber(),
                             (dc.getWidth() * 0.80).toNumber(), 22);
        }

        if (species == null) {
            Theme.muted(dc);
            dc.drawText(centerX, y, Graphics.FONT_XTINY, "-- empty --",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var cost = _engine.summonCost(species);
        var called = _engine.hasBeenCalled(species.key);
        var affordable = _engine.canSummon(species);

        var suffix = called ? " used" : (" " + cost.toString() + "P");
        var level = species.friendlyLevel(Party.extraLevel(species.key));

        // On a two-tone panel an unavailable row is faint rather than tinted; the suffix says why.
        if (selected) {
            Theme.inverted(dc);
        } else {
            Theme.inkIf(dc, affordable);
        }
        dc.drawText(centerX, y, Graphics.FONT_XTINY,
                    species.name + " L" + level.toString() + suffix,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
