import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! Two-page data view. Page 0 shows activity stats, page 1 shows device state.
//! A 1 Hz timer drives redraws while the view is on screen.
class GarminSampleView extends WatchUi.View {

    public const PAGE_PET = 0;
    public const PAGE_STATS = 1;
    public const PAGE_JOURNEY = 2;
    public const PAGE_TAMER = 3;
    public const PAGE_PARTY = 4;
    private const PAGE_COUNT = 5;

    //! Ticks between pedometer syncs while the app is open. Every tick would mean a storage write
    //! per second for no visible benefit; the background service covers the app-closed case.
    private const SYNC_EVERY_TICKS = 20;

    private var _page as Number;
    private var _timer as Timer.Timer?;
    private var _ticksToSync as Number;

    function initialize() {
        View.initialize();
        _page = PAGE_PET;
        _timer = null;
        _ticksToSync = 0;
    }

    function onLayout(dc as Dc) as Void {
    }

    //! Start the refresh timer only while the view is visible, to save battery. Sync immediately so
    //! steps walked since the app was last open land right away, including any the background
    //! service banked behind an event the player has now cleared.
    function onShow() as Void {
        // The foreground owns first-run setup: the background service only advances a trek that
        // already exists, so starting one here is what gets the journey going.
        Atlas.ensureTrek();

        StepTracker.sync();
        _ticksToSync = SYNC_EVERY_TICKS;

        _timer = new Timer.Timer();
        _timer.start(method(:onTick), Sprites.FRAME_MS, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    //! Which page is showing, so the delegate can route MENU to the right screen.
    function currentPage() as Number {
        return _page;
    }

    function onTick() as Void {
        _ticksToSync -= 1;
        if (_ticksToSync <= 0) {
            StepTracker.sync();
            _ticksToSync = SYNC_EVERY_TICKS;
        }
        WatchUi.requestUpdate();
    }

    //! Advance to the next page and redraw immediately.
    function nextPage() as Void {
        _page = (_page + 1) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function previousPage() as Void {
        _page = (_page + PAGE_COUNT - 1) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        drawHeader(dc, centerX, height);

        if (_page == PAGE_PET) {
            drawPetPage(dc, centerX, height);
        } else if (_page == PAGE_STATS) {
            drawStatsPage(dc, centerX, height);
        } else if (_page == PAGE_JOURNEY) {
            drawJourneyPage(dc, centerX, height);
        } else if (_page == PAGE_TAMER) {
            drawTamerPage(dc, centerX, height);
        } else {
            drawPartyPage(dc, centerX, height);
        }

    }

    //! Title plus current clock time.
    private function drawHeader(dc as Dc, centerX as Number, height as Number) as Void {
        var titleId;
        if (_page == PAGE_PET) {
            titleId = Rez.Strings.PagePet;
        } else if (_page == PAGE_STATS) {
            titleId = Rez.Strings.PageStats;
        } else if (_page == PAGE_JOURNEY) {
            titleId = Rez.Strings.PageJourney;
        } else if (_page == PAGE_TAMER) {
            titleId = Rez.Strings.PageTamer;
        } else {
            titleId = Rez.Strings.PageParty;
        }
        var title = WatchUi.loadResource(titleId) as String;

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.12, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The ally itself, front and centre. This is what the app opens on — the creature, not a
    //! readout — so it stays deliberately sparse: sprite, name, standing.
    private function drawPetPage(dc as Dc, centerX as Number, height as Number) as Void {
        var partner = GameState.partner();
        var extra = GameState.partnerExtraLevel();

        // No art for this species yet: its name takes the sprite's place rather than leaving a hole.
        if (!Sprites.drawIdle(dc, centerX, height * 0.42, partner.key)) {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.42, Graphics.FONT_SMALL, partner.name,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Theme.ink(dc);
        dc.drawText(centerX, height * 0.64, Graphics.FONT_TINY, partner.name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Growth is shown as "2/6" so how close the ally is to evolving is readable at a glance.
        var standing = "L" + partner.friendlyLevel(extra).toString();
        var growth = partner.maxExtraLevel();
        if (growth > 0) {
            standing += "   " + extra.toString() + "/" + growth.toString();
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.75, Graphics.FONT_XTINY, standing,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawPendingNotice(dc, centerX, height);
    }

    //! What the road is holding, on the page the app opens to.
    //!
    //! Without this an event announced by the background service is invisible until the player
    //! happens to page across to JOURNEY — the app would open on a creature with no hint that
    //! anything is waiting. Read-only: the trek is created in onShow, never here.
    private function drawPendingNotice(dc as Dc, centerX as Number, height as Number) as Void {
        var trek = JourneyState.peekTrek();
        if (trek == null) {
            return;
        }

        if (!trek.hasPendingEvent()) {
            // Nothing waiting: show how much further, so the page still answers "what now?".
            Theme.muted(dc);
            dc.drawText(centerX, height * 0.89, Graphics.FONT_XTINY,
                        (WatchUi.loadResource(Rez.Strings.LabelNextEvent) as String)
                            + " " + trek.stepsToNextEvent.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var bannerId;
        if (trek.pendingEvent == Journey.EVENT_BOSS) {
            bannerId = Rez.Strings.EventBoss;
        } else if (trek.pendingEvent == Journey.EVENT_REWARD) {
            bannerId = Rez.Strings.EventFound;
        } else {
            bannerId = Rez.Strings.EventEncounter;
        }

        Theme.alertBanner(dc, centerX, height * 0.89,
                          WatchUi.loadResource(bannerId) as String, Graphics.FONT_XTINY);
    }

    //! Steps / distance / calories / heart rate from ActivityMonitor.
    private function drawStatsPage(dc as Dc, centerX as Number, height as Number) as Void {
        var info = ActivityMonitor.getInfo();
        var noValue = WatchUi.loadResource(Rez.Strings.NoValue) as String;

        var rawSteps = info.steps;
        var rawGoal = info.stepGoal;
        var rawDistance = info.distance;
        var rawCalories = info.calories;

        var steps = (rawSteps != null) ? rawSteps.toString() : noValue;
        var goal = (rawGoal != null) ? rawGoal : 0;

        var distance = noValue;
        if (rawDistance != null) {
            // ActivityMonitor reports centimeters.
            distance = (rawDistance / 100000.0).format("%.2f") + " km";
        }

        var calories = (rawCalories != null) ? rawCalories.toString() : noValue;

        drawRow(dc, centerX, height * 0.32, Rez.Strings.LabelSteps, steps);
        drawRow(dc, centerX, height * 0.47, Rez.Strings.LabelDistance, distance);
        drawRow(dc, centerX, height * 0.62, Rez.Strings.LabelCalories, calories);

        drawGoalBar(dc, centerX, height * 0.78, rawSteps, goal);
    }

    //! Where the trek stands: current area, distance left, and what is waiting.
    private function drawJourneyPage(dc as Dc, centerX as Number, height as Number) as Void {
        var trek = Atlas.ensureTrek();

        drawRow(dc, centerX, height * 0.30, Rez.Strings.LabelArea, Atlas.areaName(trek.area));
        drawRow(dc, centerX, height * 0.44, Rez.Strings.LabelRemaining, trek.distance.toString());

        if (trek.hasPendingEvent()) {
            var bannerId;
            if (trek.pendingEvent == Journey.EVENT_BOSS) {
                bannerId = Rez.Strings.EventBoss;
            } else if (trek.pendingEvent == Journey.EVENT_REWARD) {
                bannerId = Rez.Strings.EventFound;
            } else {
                bannerId = Rez.Strings.EventEncounter;
            }
            var banner = WatchUi.loadResource(bannerId) as String;

            Theme.alertBanner(dc, centerX, height * 0.59, banner, Graphics.FONT_TINY);
        } else {
            drawRow(dc, centerX, height * 0.59, Rez.Strings.LabelNextEvent,
                    trek.stepsToNextEvent.toString());
        }

        Theme.centeredBar(dc, centerX, height * 0.73, Atlas.progressOf(trek));

        // Only advertise the battle button when there is actually a battle behind it.
        var pending = trek.hasPendingEvent();
        Theme.inkIf(dc, pending);
        dc.drawText(centerX, height * 0.86, Graphics.FONT_XTINY,
                    WatchUi.loadResource(pending ? Rez.Strings.HintBattle : Rez.Strings.HintWalk) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Player level, experience bar, partner and battle record. START from here starts a battle.
    private function drawTamerPage(dc as Dc, centerX as Number, height as Number) as Void {
        var level = GameState.level();
        var partner = GameState.partner();
        var partnerLevel = partner.friendlyLevel(GameState.partnerExtraLevel());

        // A maxed-out partner shows its growth as "3/3" so the reason MENU lit up is visible.
        var growth = partner.maxExtraLevel();
        var partnerLabel = partner.name + " L" + partnerLevel.toString();
        if (growth > 0) {
            partnerLabel += " " + GameState.partnerExtraLevel().toString() + "/" + growth.toString();
        }

        drawRow(dc, centerX, height * 0.28, Rez.Strings.LabelLevel, level.toString());
        drawRow(dc, centerX, height * 0.41, Rez.Strings.LabelPartner, partnerLabel);
        drawRow(dc, centerX, height * 0.54, Rez.Strings.LabelFocus,
                GameState.focus().toString() + "/" + Evolution.MAX_FOCUS.toString());
        drawRow(dc, centerX, height * 0.67, Rez.Strings.LabelRecord,
                GameState.wins().toString() + "/" + GameState.battles().toString());

        Theme.centeredBar(dc, centerX, height * 0.78, GameState.levelProgress());

        var ready = GameState.partnerCanEvolve();
        var hintId = ready
            ? Rez.Strings.HintEvolveReady
            : (Encounter.canBegin() ? Rez.Strings.HintBattle : Rez.Strings.HintWalk);

        Theme.inkIf(dc, ready);
        dc.drawText(centerX, height * 0.86, Graphics.FONT_XTINY,
                    WatchUi.loadResource(hintId) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The four roster slots at a glance. MENU opens the editor.
    private function drawPartyPage(dc as Dc, centerX as Number, height as Number) as Void {
        for (var i = 0; i < Party.SIZE; i += 1) {
            var species = Party.member(i);
            var label;

            if (species == null) {
                label = "--";
                Theme.muted(dc);
            } else {
                var level = species.friendlyLevel(Party.extraLevel(species.key));
                label = species.name + " L" + level.toString();
                Theme.inkIf(dc, i == Party.LEAD_SLOT);
            }
            dc.drawText(centerX, height * (0.30 + (i * 0.13)), Graphics.FONT_XTINY, label,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.86, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.HintPartyEdit) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Label left of center, value right of center, on one baseline.
    private function drawRow(dc as Dc, centerX as Number, y as Numeric,
                             labelId as ResourceId, value as String) as Void {
        var label = WatchUi.loadResource(labelId) as String;

        Theme.muted(dc);
        dc.drawText(centerX - 6, y, Graphics.FONT_TINY, label,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        Theme.ink(dc);
        dc.drawText(centerX + 6, y, Graphics.FONT_TINY, value,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Horizontal progress bar for steps against the daily goal.
    private function drawGoalBar(dc as Dc, centerX as Number, y as Numeric,
                                 steps as Number?, goal as Number) as Void {
        if (steps == null || goal <= 0) {
            return;
        }

        Theme.centeredBar(dc, centerX, y, steps.toFloat() / goal.toFloat());
    }

}
