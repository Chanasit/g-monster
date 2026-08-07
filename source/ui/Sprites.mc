import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Creature artwork: two-frame idle sprites, looked up by species key.
//!
//! Not every species has art, and that is expected — `draw` reports whether it managed to, so a
//! caller can fall back to text rather than leaving a hole in the layout.
module Sprites {

    //! Rendered size on screen. The source grids are 24x24 at 3x, so edges stay hard.
    const SIZE = 72;

    //! Milliseconds each idle frame is held.
    const FRAME_MS = 500;

    //! One-entry cache. Only ever one creature is on screen at a time, and holding every bitmap
    //! resident would be a poor trade against the app's memory budget.
    var _cachedKey as String?;
    var _cachedFrame as Number = -1;
    var _cached as WatchUi.BitmapResource?;

    //! Which idle frame is showing right now. Driven by the clock rather than a counter so callers
    //! do not have to own animation state — any redraw lands on the correct frame.
    function currentFrame() as Number {
        return (System.getTimer() / FRAME_MS) % 2;
    }

    //! The drawable id for a species and frame, or null when that species has no art.
    function resourceIdFor(key as String, frame as Number) as ResourceId? {
        var second = (frame != 0);

        if (key.equals("emberling")) {
            return second ? Rez.Drawables.EmberlingB : Rez.Drawables.EmberlingA;
        }
        if (key.equals("drizzlet")) {
            return second ? Rez.Drawables.DrizzletB : Rez.Drawables.DrizzletA;
        }
        if (key.equals("sparkmite")) {
            return second ? Rez.Drawables.SparkmiteB : Rez.Drawables.SparkmiteA;
        }
        if (key.equals("mosscub")) {
            return second ? Rez.Drawables.MosscubB : Rez.Drawables.MosscubA;
        }
        return null;
    }

    function hasArt(key as String) as Boolean {
        return resourceIdFor(key, 0) != null;
    }

    //! Load a frame, reusing the cached bitmap when it is the one already wanted.
    function bitmapFor(key as String, frame as Number) as WatchUi.BitmapResource? {
        var cachedKey = _cachedKey;
        if (cachedKey != null && cachedKey.equals(key) && _cachedFrame == frame) {
            return _cached;
        }

        var id = resourceIdFor(key, frame);
        if (id == null) {
            return null;
        }

        _cached = WatchUi.loadResource(id) as WatchUi.BitmapResource;
        _cachedKey = key;
        _cachedFrame = frame;
        return _cached;
    }

    //! Draw a species centred on a point. Returns false when there is no art for it, so the caller
    //! can put something else in that space.
    function draw(dc as Dc, centerX as Number, centerY as Numeric, key as String, frame as Number) as Boolean {
        var bitmap = bitmapFor(key, frame);
        if (bitmap == null) {
            return false;
        }

        dc.drawBitmap(centerX - (SIZE / 2), (centerY - (SIZE / 2)).toNumber(), bitmap);
        return true;
    }

    //! Draw at whatever idle frame the clock is on.
    function drawIdle(dc as Dc, centerX as Number, centerY as Numeric, key as String) as Boolean {
        return draw(dc, centerX, centerY, key, currentFrame());
    }
}
