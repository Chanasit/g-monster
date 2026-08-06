import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

//! Two-page data view. Page 0 shows activity stats, page 1 shows device state.
//! A 1 Hz timer drives redraws while the view is on screen.
class GarminSampleView extends WatchUi.View {

    private const PAGE_STATS = 0;
    private const PAGE_SYSTEM = 1;
    private const PAGE_COUNT = 2;

    private var _page as Number;
    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
        _page = PAGE_STATS;
        _timer = null;
    }

    function onLayout(dc as Dc) as Void {
    }

    //! Start the refresh timer only while the view is visible, to save battery.
    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        drawHeader(dc, centerX, height);

        if (_page == PAGE_STATS) {
            drawStatsPage(dc, centerX, height);
        } else {
            drawSystemPage(dc, centerX, height);
        }

        drawPageDots(dc, centerX, height);
    }

    //! Title plus current clock time.
    private function drawHeader(dc as Dc, centerX as Number, height as Number) as Void {
        var title = (_page == PAGE_STATS)
            ? WatchUi.loadResource(Rez.Strings.PageStats) as String
            : WatchUi.loadResource(Rez.Strings.PageSystem) as String;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, height * 0.16, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var clock = Lang.format("$1$:$2$", [now.hour.format("%02d"), now.min.format("%02d")]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, height * 0.30, Graphics.FONT_NUMBER_MEDIUM, clock,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

        drawRow(dc, centerX, height * 0.48, Rez.Strings.LabelSteps, steps);
        drawRow(dc, centerX, height * 0.60, Rez.Strings.LabelDistance, distance);
        drawRow(dc, centerX, height * 0.72, Rez.Strings.LabelCalories, calories);

        drawGoalBar(dc, centerX, height * 0.83, rawSteps, goal);
    }

    //! Heart rate, battery and memory — the "is the watch OK" page.
    private function drawSystemPage(dc as Dc, centerX as Number, height as Number) as Void {
        var noValue = WatchUi.loadResource(Rez.Strings.NoValue) as String;
        var stats = System.getSystemStats();

        var heartRate = noValue;
        var iterator = ActivityMonitor.getHeartRateHistory(1, true);
        if (iterator != null) {
            var sample = iterator.next();
            if (sample != null) {
                var bpm = sample.heartRate;
                if (bpm != null && bpm != ActivityMonitor.INVALID_HR_SAMPLE) {
                    heartRate = bpm.toString() + " bpm";
                }
            }
        }

        var battery = stats.battery.format("%.0f") + "%";
        var memory = ((stats.usedMemory * 100) / stats.totalMemory).toString() + "%";

        drawRow(dc, centerX, height * 0.48, Rez.Strings.LabelHeartRate, heartRate);
        drawRow(dc, centerX, height * 0.60, Rez.Strings.LabelBattery, battery);
        drawRow(dc, centerX, height * 0.72, Rez.Strings.LabelMemory, memory);
    }

    //! Label left of center, value right of center, on one baseline.
    private function drawRow(dc as Dc, centerX as Number, y as Numeric,
                             labelId as ResourceId, value as String) as Void {
        var label = WatchUi.loadResource(labelId) as String;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX - 6, y, Graphics.FONT_TINY, label,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX + 6, y, Graphics.FONT_TINY, value,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Horizontal progress bar for steps against the daily goal.
    private function drawGoalBar(dc as Dc, centerX as Number, y as Numeric,
                                 steps as Number?, goal as Number) as Void {
        if (steps == null || goal <= 0) {
            return;
        }

        var barWidth = dc.getWidth() / 2;
        var barHeight = 6;
        var x = centerX - barWidth / 2;

        var ratio = steps.toFloat() / goal.toFloat();
        if (ratio > 1.0) {
            ratio = 1.0;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, barWidth, barHeight);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, (barWidth * ratio).toNumber(), barHeight);
    }

    //! Page indicator dots at the bottom of the screen.
    private function drawPageDots(dc as Dc, centerX as Number, height as Number) as Void {
        var y = height * 0.92;
        var spacing = 12;
        var startX = centerX - ((PAGE_COUNT - 1) * spacing) / 2;

        for (var i = 0; i < PAGE_COUNT; i += 1) {
            var color = (i == _page) ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(startX + i * spacing, y, 3);
        }
    }
}
