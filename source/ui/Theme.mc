import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! The monochrome LCD look: black ink on a white ground, the way a segment display reads.
//!
//! Every view goes through here rather than naming colours directly, so the whole app can be
//! re-toned in one place. There is no accent colour by design — a two-tone panel has no way to
//! shout, so emphasis is carried by inverting a block instead of by tinting it.
module Theme {

    //! The lit panel.
    const BACKGROUND = Graphics.COLOR_WHITE;

    //! Ink. Everything readable is drawn in this.
    const FOREGROUND = Graphics.COLOR_BLACK;

    //! Secondary ink for labels and unavailable options. A real LCD would dither these; on a
    //! colour panel a mid grey reads the same way without hurting legibility.
    const MUTED = Graphics.COLOR_DK_GRAY;

    //! Ink used on top of an inverted block.
    const INVERTED = Graphics.COLOR_WHITE;

    //! Wipe the screen to the panel colour. Call first in every onUpdate.
    function clear(dc as Dc) as Void {
        dc.setColor(FOREGROUND, BACKGROUND);
        dc.clear();
    }

    //! Draw in ink.
    function ink(dc as Dc) as Void {
        dc.setColor(FOREGROUND, Graphics.COLOR_TRANSPARENT);
    }

    //! Draw in secondary ink.
    function muted(dc as Dc) as Void {
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
    }

    //! Draw in ink, or secondary ink when the thing is unavailable.
    function inkIf(dc as Dc, available as Boolean) as Void {
        dc.setColor(available ? FOREGROUND : MUTED, Graphics.COLOR_TRANSPARENT);
    }

    //! Draw on top of an inverted block.
    function inverted(dc as Dc) as Void {
        dc.setColor(INVERTED, Graphics.COLOR_TRANSPARENT);
    }

    //! A filled black band, the panel's way of highlighting a row. Text drawn over it must switch
    //! to `inverted` to stay readable.
    function selectionBand(dc as Dc, centerX as Number, y as Numeric,
                           widthFraction as Float, height as Number) as Void {
        var bandWidth = (dc.getWidth() * widthFraction).toNumber();
        dc.setColor(FOREGROUND, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(centerX - bandWidth / 2, (y - height / 2).toNumber(), bandWidth, height);
    }

    //! A meter: hollow outline, filled from the left. Reads as a bar without needing a hue, which
    //! is how a segment display shows a gauge.
    function bar(dc as Dc, x as Number, y as Number, width as Number, height as Number,
                 fraction as Float) as Void {
        var filled = fraction;
        if (filled < 0.0) { filled = 0.0; }
        if (filled > 1.0) { filled = 1.0; }

        dc.setColor(FOREGROUND, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, width, height);

        var inner = ((width - 2) * filled).toNumber();
        if (inner > 0) {
            dc.fillRectangle(x + 1, y + 1, inner, height - 2);
        }
    }

    //! A centered meter, half the screen wide — the common case.
    function centeredBar(dc as Dc, centerX as Number, y as Numeric, fraction as Float) as Void {
        var width = dc.getWidth() / 2;
        bar(dc, centerX - width / 2, y.toNumber(), width, 8, fraction);
    }

    //! An emphasised line: inverted band with the text knocked out of it. Used where a colour
    //! theme would have reached for yellow or red.
    function banner(dc as Dc, centerX as Number, y as Numeric, text as String,
                    font as Graphics.FontType) as Void {
        selectionBand(dc, centerX, y, 0.86, 26);
        inverted(dc);
        dc.drawText(centerX, y, font, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Blink period, matched to the view tick so the phase does not drift against redraws.
    const BLINK_MS = 500;

    //! Which half of the blink cycle the clock is on. Driven by the clock rather than a counter so
    //! any view can blink without owning animation state.
    function blinkOn() as Boolean {
        return ((System.getTimer() / BLINK_MS) % 2) == 0;
    }

    //! A banner that pulses between filled and outlined. It never disappears on the off beat —
    //! a notice that vanishes half the time is easy to miss entirely.
    function alertBanner(dc as Dc, centerX as Number, y as Numeric, text as String,
                         font as Graphics.FontType) as Void {
        if (blinkOn()) {
            banner(dc, centerX, y, text, font);
            return;
        }

        var bandWidth = (dc.getWidth() * 0.86).toNumber();
        ink(dc);
        dc.drawRectangle(centerX - bandWidth / 2, (y - 13).toNumber(), bandWidth, 26);
        dc.drawText(centerX, y, font, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Fill the whole panel with ink. The flash half of an encounter transition.
    function invertScreen(dc as Dc) as Void {
        dc.setColor(FOREGROUND, FOREGROUND);
        dc.clear();
    }
}
