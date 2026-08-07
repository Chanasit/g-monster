import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The mid-battle action menu, reached with MENU. Two ways to change the shape of a fight: call in
//! a party member, or spend spirit power to transform the one already out there.
class BattleActionView extends WatchUi.View {

    public const ACTION_CALL = 0;
    public const ACTION_SPIRIT = 1;
    private const ACTION_COUNT = 2;

    private var _battle as BattleView;
    private var _selected as Number;

    function initialize(battle as BattleView) {
        View.initialize();
        _battle = battle;
        _selected = ACTION_CALL;
    }

    function moveSelection(step as Number) as Void {
        _selected = (_selected + step + ACTION_COUNT) % ACTION_COUNT;
        WatchUi.requestUpdate();
    }

    //! Open the chosen sub-screen, replacing this menu so BACK returns to the fight.
    function confirm() as Void {
        if (_selected == ACTION_CALL) {
            var dock = new DDockView(_battle);
            WatchUi.switchToView(dock, new DDockDelegate(dock), WatchUi.SLIDE_LEFT);
            return;
        }

        var spirits = new SpiritView(_battle);
        WatchUi.switchToView(spirits, new SpiritDelegate(spirits), WatchUi.SLIDE_LEFT);
    }

    function dismiss() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var height = dc.getHeight();
        var centerX = dc.getWidth() / 2;
        var engine = _battle.battleEngine();

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.22, Graphics.FONT_XTINY,
                    engine.callPoints().toString() + "P   SP "
                        + engine.spiritPower().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawAction(dc, centerX, height * 0.45, ACTION_CALL,
                   WatchUi.loadResource(Rez.Strings.ActionCall) as String);
        drawAction(dc, centerX, height * 0.62, ACTION_SPIRIT,
                   WatchUi.loadResource(Rez.Strings.ActionSpirit) as String);
    }

    private function drawAction(dc as Dc, centerX as Number, y as Numeric,
                                action as Number, label as String) as Void {
        var selected = (action == _selected);

        if (selected) {
            Theme.selectionBand(dc, centerX, y, 0.76, 26);
            Theme.inverted(dc);
        } else {
            Theme.ink(dc);
        }
        dc.drawText(centerX, y, Graphics.FONT_TINY, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
