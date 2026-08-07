import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Shows what the road turned up. The outcome is rolled and applied on construction, so the screen
//! reports something that has already happened rather than deciding it while being drawn.
class RewardView extends WatchUi.View {

    private var _headline as String;

    function initialize() {
        View.initialize();

        var rng = new Combat.Rng(GameState.nextSeed());
        var kind = Reward.roll(rng);

        _headline = Reward.apply(kind, rng);

        // The event is spent the moment it is applied — walking resumes on the next sync.
        JourneyState.resolveEvent();
    }

    function dismiss() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var height = dc.getHeight();
        var centerX = dc.getWidth() / 2;

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.28, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.PageFound) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        Theme.banner(dc, centerX, height * 0.50, _headline, Graphics.FONT_TINY);

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.74, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.HintDismiss) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
