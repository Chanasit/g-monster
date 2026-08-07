import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Roster editor. Each slot cycles through the species the player has unlocked, so a party can be
//! rebuilt between fights without ever losing a creature's accumulated growth.
class PartyView extends WatchUi.View {

    private var _selected as Number;

    function initialize() {
        View.initialize();
        _selected = 0;
    }

    function moveSelection(step as Number) as Void {
        _selected = (_selected + step + Party.SIZE) % Party.SIZE;
        WatchUi.requestUpdate();
    }

    //! Cycle this slot to the next unlocked species that is not already fielded elsewhere.
    //! Slot 0 must always hold someone; the others may be emptied.
    function cycleSlot() as Void {
        var options = availableFor(_selected);
        if (options.size() == 0) {
            return;
        }

        var current = Party.slot(_selected);
        var next = options[0];
        for (var i = 0; i < options.size(); i += 1) {
            if (options[i].equals(current)) {
                next = options[(i + 1) % options.size()];
                break;
            }
        }

        Party.setSlot(_selected, next);
        WatchUi.requestUpdate();
    }

    //! What this slot may hold: its current occupant, anything unlocked and not fielded elsewhere,
    //! and — for the non-lead slots — empty.
    private function availableFor(index as Number) as Array<String> {
        var options = [] as Array<String>;
        var current = Party.slot(index);

        if (!current.equals(Party.EMPTY)) {
            options.add(current);
        }

        var unlocked = Party.unlocked();
        for (var i = 0; i < unlocked.size(); i += 1) {
            var key = unlocked[i];
            if (!key.equals(current) && !Party.isInParty(key)) {
                options.add(key);
            }
        }

        if (index != Party.LEAD_SLOT && !current.equals(Party.EMPTY)) {
            options.add(Party.EMPTY);
        }

        return options;
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
                    WatchUi.loadResource(Rez.Strings.PageParty) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        for (var i = 0; i < Party.SIZE; i += 1) {
            drawSlot(dc, centerX, height * (0.30 + (i * 0.14)), i);
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.89, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.HintPartySwap) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawSlot(dc as Dc, centerX as Number, y as Numeric, index as Number) as Void {
        var selected = (index == _selected);
        var species = Party.member(index);

        if (selected) {
            Theme.selectionBand(dc, centerX, y, 0.80, 20);
        }

        var label;
        if (species == null) {
            label = "-- empty --";
        } else {
            var level = species.friendlyLevel(Party.extraLevel(species.key));
            label = species.name + " L" + level.toString();
            // The lead is what every battle opens with; mark it so the ordering means something.
            if (index == Party.LEAD_SLOT) {
                label = "> " + label;
            }
        }

        if (selected) { Theme.inverted(dc); } else { Theme.ink(dc); }
        dc.drawText(centerX, y, Graphics.FONT_XTINY, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
