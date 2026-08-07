import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! First-run screen: pick the creature the save begins with.
//!
//! Candidates come from `resources/data/starters.json`, so the offered set is a data edit. Stats are
//! shown up front because the choice is a real one — the starters differ in what they are good at,
//! and the pick decides the first evolution line the player is on.
class CharacterSelectView extends WatchUi.View {

    private var _choices as Array<Combat.Creature>;
    private var _selected as Number;
    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();

        _choices = loadChoices();
        _selected = 0;
        _timer = null;
    }

    //! The sprite breathes, so this screen needs its own redraw tick — nothing else here changes
    //! on its own.
    function onShow() as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), Sprites.FRAME_MS, true);
        _timer = timer;
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    //! Starters that actually resolve to a species. Falls back to the whole roster if the data is
    //! unusable, so a bad starters.json can never leave the player with nothing to pick.
    private function loadChoices() as Array<Combat.Creature> {
        var keys = Combat.Bestiary.starters();
        var list = [] as Array<Combat.Creature>;

        for (var i = 0; i < keys.size(); i += 1) {
            var species = Combat.Bestiary.get(keys[i]);
            if (species != null) {
                list.add(species);
            }
        }

        if (list.size() == 0) {
            return Combat.Bestiary.all();
        }
        return list;
    }

    function cycle(step as Number) as Void {
        var count = _choices.size();
        _selected = (_selected + step + count) % count;
        WatchUi.requestUpdate();
    }

    //! Commit the choice and drop straight into the app proper.
    function confirm() as Void {
        GameState.createCharacter(_choices[_selected].key);

        var main = new GarminSampleView();
        WatchUi.switchToView(main, new GarminSampleDelegate(main), WatchUi.SLIDE_LEFT);
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var height = dc.getHeight();
        var centerX = dc.getWidth() / 2;
        var species = _choices[_selected];

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.11, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.PageChoose) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // A species with no art keeps its name in the sprite's place, so the layout never gaps.
        if (!Sprites.drawIdle(dc, centerX, height * 0.36, species.key)) {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.36, Graphics.FONT_SMALL, species.name,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Theme.ink(dc);
        dc.drawText(centerX, height * 0.60, Graphics.FONT_TINY,
                    species.name + "  L" + species.baseLevel.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawStats(dc, centerX, height, species);
        drawDots(dc, centerX, height);

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.91, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.HintChoose) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The four numbers that decide how it fights, on one line to leave the sprite its room.
    private function drawStats(dc as Dc, centerX as Number, height as Numeric,
                               species as Combat.Creature) as Void {
        Theme.muted(dc);
        dc.drawText(centerX, height * 0.71, Graphics.FONT_XTINY,
                    "HP" + species.baseHp.toString()
                        + " EN" + species.baseEnergy.toString()
                        + " CR" + species.baseCrush.toString()
                        + " AB" + species.baseAbility.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDots(dc as Dc, centerX as Number, height as Numeric) as Void {
        var count = _choices.size();
        var spacing = 12;
        var startX = centerX - ((count - 1) * spacing) / 2;

        for (var i = 0; i < count; i += 1) {
            Theme.inkIf(dc, i == _selected);
            dc.fillCircle(startX + (i * spacing), height * 0.82, 3);
        }
    }
}
