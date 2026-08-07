import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Spirit chooser: pick a form to enter with the power currently banked.
//!
//! Costs shown here are the discounted ones — a form gets cheaper as the player levels, so the
//! same screen reads very differently early and late in a run.
class SpiritView extends WatchUi.View {

    private var _battle as BattleView;
    private var _engine as Combat.BattleEngine;
    private var _forms as Array<Combat.Creature>;
    private var _selected as Number;

    function initialize(battle as BattleView) {
        View.initialize();
        _battle = battle;
        _engine = battle.battleEngine();
        _forms = Combat.Spirit.forms();
        _selected = 0;
    }

    function moveSelection(step as Number) as Void {
        var count = _forms.size();
        if (count == 0) {
            return;
        }
        _selected = (_selected + step + count) % count;
        WatchUi.requestUpdate();
    }

    //! Enter the highlighted form, if it can be afforded. An unavailable one is inert.
    function confirm() as Void {
        if (_forms.size() == 0) {
            return;
        }

        var form = _forms[_selected];
        if (!_engine.canInvokeSpirit(form)) {
            return;
        }

        _battle.invokeSpirit(form);
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
        dc.drawText(centerX, height * 0.13, Graphics.FONT_XTINY,
                    (WatchUi.loadResource(Rez.Strings.PageSpirit) as String)
                        + "  SP " + _engine.spiritPower().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_forms.size() == 0) {
            Theme.muted(dc);
            dc.drawText(centerX, height * 0.5, Graphics.FONT_XTINY, "no forms",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // A form already held blocks all the others; say so rather than greying everything silently.
        if (_engine.isSpiritActive()) {
            Theme.banner(dc, centerX, height * 0.5,
                         WatchUi.loadResource(Rez.Strings.SpiritHeld) as String,
                         Graphics.FONT_XTINY);
            return;
        }

        for (var i = 0; i < _forms.size(); i += 1) {
            drawForm(dc, centerX, height * (0.28 + (i * 0.13)), i);
        }
    }

    private function drawForm(dc as Dc, centerX as Number, y as Numeric, index as Number) as Void {
        var form = _forms[index];
        var selected = (index == _selected);
        var affordable = _engine.canInvokeSpirit(form);

        if (selected) {
            Theme.selectionBand(dc, centerX, y, 0.84, 20);
        }

        // The ancient form is the one that does not drain; mark it, since that is the whole reason
        // to save for it.
        var mark = Combat.Spirit.drains(form) ? "" : "*";

        if (selected) {
            Theme.inverted(dc);
        } else {
            Theme.inkIf(dc, affordable);
        }
        dc.drawText(centerX, y, Graphics.FONT_XTINY,
                    form.name + mark + "  " + _engine.spiritCost(form).toString() + "SP",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
