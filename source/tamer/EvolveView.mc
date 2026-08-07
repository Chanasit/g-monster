import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! Evolution screen: commit some of the banked focus and roll for the partner's next form.
class EvolveView extends WatchUi.View {

    private const STATE_CHOOSE = 0;
    private const STATE_RESULT = 1;

    private var _partner as Combat.Creature;
    private var _target as Combat.Creature;
    private var _available as Number;
    private var _committed as Number;
    private var _state as Number;
    private var _succeeded as Boolean;

    //! Caller must check GameState.partnerCanEvolve() first — this view assumes a valid target.
    function initialize(partner as Combat.Creature, target as Combat.Creature, available as Number) {
        View.initialize();

        _partner = partner;
        _target = target;
        _available = available;
        _committed = available;   // default to the best odds the player can afford
        _state = STATE_CHOOSE;
        _succeeded = false;
    }

    //! Raise or lower the focus committed to the attempt, within what is banked.
    function adjustFocus(step as Number) as Void {
        if (_state != STATE_CHOOSE) {
            return;
        }
        _committed += step;
        if (_committed < 1) {
            _committed = _available;      // wrap, so one button reaches both ends
        }
        if (_committed > _available) {
            _committed = 1;
        }
        WatchUi.requestUpdate();
    }

    //! Commit the attempt, or dismiss the result.
    function confirm() as Void {
        if (_state == STATE_RESULT) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }

        var rng = new Combat.Rng(GameState.nextSeed());
        _succeeded = Evolution.attempt(_target, GameState.level(), _committed, rng);

        // Focus is spent whether or not the roll lands.
        GameState.addFocus(-_committed);
        if (_succeeded) {
            GameState.evolvePartner();
        }

        _state = STATE_RESULT;
        WatchUi.requestUpdate();
    }

    function dismiss() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.18, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.PageEvolve) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_state == STATE_CHOOSE) {
            drawAttempt(dc, centerX, height);
        } else {
            drawResult(dc, centerX, height);
        }
    }

    private function drawAttempt(dc as Dc, centerX as Number, height as Numeric) as Void {
        Theme.ink(dc);
        dc.drawText(centerX, height * 0.33, Graphics.FONT_XTINY, _partner.name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(centerX, height * 0.44, Graphics.FONT_TINY, _target.name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var odds = Evolution.chance(_target, GameState.level(), _committed);
        var percent = (odds * 100).toNumber();

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.60, Graphics.FONT_XTINY,
                    "FOCUS " + _committed.toString() + "/" + _available.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (percent >= 60) {
            Theme.banner(dc, centerX, height * 0.72, percent.toString() + "%", Graphics.FONT_SMALL);
        } else {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.72, Graphics.FONT_SMALL, percent.toString() + "%",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.86, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.HintEvolveCommit) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawResult(dc as Dc, centerX as Number, height as Numeric) as Void {
        if (_succeeded) {
            Theme.banner(dc, centerX, height * 0.45, "EVOLVED", Graphics.FONT_SMALL);
        } else {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.45, Graphics.FONT_SMALL, "FAILED",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Theme.ink(dc);
        dc.drawText(centerX, height * 0.60, Graphics.FONT_TINY,
                    _succeeded ? _target.name : _partner.name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.74, Graphics.FONT_XTINY,
                    "-" + _committed.toString() + " FOCUS",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
