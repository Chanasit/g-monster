import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Creature artwork: four two-frame action states per species, looked up by species key.
//!
//! Not every species has art, and that is expected — `draw` reports whether it managed to, so a
//! caller can fall back to text rather than leaving a hole in the layout.
module Sprites {

    //! Rendered size on screen. The source grids are 24x24 at 3x, so edges stay hard.
    const SIZE = 72;

    //! Milliseconds each frame is held, and the rate views run their redraw timer at.
    const FRAME_MS = 500;

    //! Sleep breathes slower than everything else. Kept a multiple of FRAME_MS so the existing
    //! redraw timer still lands on every frame change — a faster action would mean a faster timer,
    //! which is battery the animation is not worth. That is also why there is no separate running
    //! cadence: a 250 ms frame sampled by a 500 ms timer lands on the same frame every tick.
    const SLEEP_FRAME_MS = 1500;

    //! Action states. These are slot numbers in the generated table, so their values have to keep
    //! matching the variant order in tools/sprites/generate_sprites.py.
    //!
    //! One movement state, not two. Walking and running both draw ACTION_MOVE: they animated at
    //! the same rate from the same base grid, and a forward shear at 72px read as a second waddle
    //! rather than as a run. Giving the run a real cadence would mean retiming the views' redraw
    //! timer, which is battery this animation does not justify.
    const ACTION_IDLE = 0;
    const ACTION_SLEEP = 1;
    const ACTION_MOVE = 2;
    const ACTION_FIGHT = 3;
    const ACTION_COUNT = 4;

    //! Which way the creature is pointed. Only the lunge has a direction in it, so it is the only
    //! action carrying a mirrored slot; every other action ignores facing entirely.
    const FACE_RIGHT = 0;
    const FACE_LEFT = 1;

    const SLOT_FIGHT_LEFT = 4;

    //! One-entry cache. Only ever one creature is on screen at a time, and holding every bitmap
    //! resident would be a poor trade against the app's memory budget.
    var _cachedKey as String?;
    var _cachedSlot as Number = -1;
    var _cached as WatchUi.BitmapResource?;

    //! Species key -> one drawable id per slot.
    //!
    //! Built on first lookup rather than at module load: a player who never opens a screen with
    //! artwork on it never pays for the table. What it holds is only resource ids -- numbers, not
    //! bitmaps -- so the whole roster costs far less than the single bitmap cached below.
    var _index as Dictionary<String, Array<ResourceId> >?;

    function index() as Dictionary<String, Array<ResourceId> > {
        var built = _index;
        if (built != null) {
            return built;
        }
        built = SpriteIndex.build();
        _index = built;
        return built;
    }

    //! How long one frame of an action is held.
    function periodFor(action as Number) as Number {
        return (action == ACTION_SLEEP) ? SLEEP_FRAME_MS : FRAME_MS;
    }

    //! How many frames a species' variant has. Two unless hand-drawn art supplied more.
    function frameCount(key as String, action as Number, facing as Number) as Number {
        return SpriteIndex.frameCount(key, slotFor(action, facing));
    }

    //! Which frame of an action is showing right now. Driven by the clock rather than a counter so
    //! callers do not have to own animation state — any redraw lands on the correct frame.
    //!
    //! Takes the species because the cycle length is per variant: emberling's walk is a four-frame
    //! hand-drawn cycle where every other creature's is a two-frame derived waddle.
    function currentFrame(key as String, action as Number, facing as Number) as Number {
        return (System.getTimer() / periodFor(action)) % frameCount(key, action, facing);
    }

    //! Which of a species' bitmaps an action and facing want. Anything out of range falls back to
    //! idle rather than running off the end of the array.
    function slotFor(action as Number, facing as Number) as Number {
        var slot = (action >= 0 && action < ACTION_COUNT) ? action : ACTION_IDLE;
        if (facing == FACE_LEFT && slot == ACTION_FIGHT) {
            slot = SLOT_FIGHT_LEFT;
        }
        return slot;
    }

    //! The drawable id for a species, action and facing, or null when that species has no art.
    function resourceIdFor(key as String, action as Number, facing as Number) as ResourceId? {
        var ids = index()[key];
        if (ids == null) {
            return null;
        }
        return ids[slotFor(action, facing)];
    }

    function hasArt(key as String) as Boolean {
        return index().hasKey(key);
    }

    //! Load a slot's bitmap, reusing the cached one when it is already what is wanted. Both frames
    //! ride in it, so alternating frames never costs a load.
    function bitmapFor(key as String, action as Number, facing as Number) as WatchUi.BitmapResource? {
        var slot = slotFor(action, facing);
        var cachedKey = _cachedKey;
        if (cachedKey != null && cachedKey.equals(key) && _cachedSlot == slot) {
            return _cached;
        }

        var id = resourceIdFor(key, action, facing);
        if (id == null) {
            return null;
        }

        _cached = WatchUi.loadResource(id) as WatchUi.BitmapResource;
        _cachedKey = key;
        _cachedSlot = slot;
        return _cached;
    }

    //! Draw a species centred on a point. Returns false when there is no art for it, so the caller
    //! can put something else in that space.
    function draw(dc as Dc, centerX as Number, centerY as Numeric, key as String,
                  action as Number, facing as Number, frame as Number) as Boolean {
        var bitmap = bitmapFor(key, action, facing);
        if (bitmap == null) {
            return false;
        }

        // The bitmap is every frame stacked, so the wanted one is selected by clipping to a single
        // frame's worth of screen and sliding the sheet up behind it.
        var left = centerX - (SIZE / 2);
        var top = (centerY - (SIZE / 2)).toNumber();

        var index = frame;
        if (index < 0 || index >= frameCount(key, action, facing)) {
            index = 0;   // never slide a frame that is not in the sheet into view
        }

        dc.setClip(left, top, SIZE, SIZE);
        dc.drawBitmap(left, top - (index * SIZE), bitmap);
        dc.clearClip();
        return true;
    }

    //! Draw an action at whatever frame its own clock is on.
    function drawAction(dc as Dc, centerX as Number, centerY as Numeric, key as String,
                        action as Number, facing as Number) as Boolean {
        return draw(dc, centerX, centerY, key, action, facing,
                    currentFrame(key, action, facing));
    }

    //! Draw the idle breath. Kept for the screens where the creature is a portrait rather than a
    //! participant: nothing to react to, and nothing to face.
    function drawIdle(dc as Dc, centerX as Number, centerY as Numeric, key as String) as Boolean {
        return drawAction(dc, centerX, centerY, key, ACTION_IDLE, FACE_RIGHT);
    }
}
