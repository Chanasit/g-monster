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

    //! Species key -> [frame A, frame B] drawable ids.
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

        built = {
            "emberling" => [Rez.Drawables.EmberlingA, Rez.Drawables.EmberlingB],
            "drizzlet" => [Rez.Drawables.DrizzletA, Rez.Drawables.DrizzletB],
            "sparkmite" => [Rez.Drawables.SparkmiteA, Rez.Drawables.SparkmiteB],
            "mosscub" => [Rez.Drawables.MosscubA, Rez.Drawables.MosscubB],
            "gustling" => [Rez.Drawables.GustlingA, Rez.Drawables.GustlingB],
            "shardpup" => [Rez.Drawables.ShardpupA, Rez.Drawables.ShardpupB],
            "cinderpip" => [Rez.Drawables.CinderpipA, Rez.Drawables.CinderpipB],
            "silthatch" => [Rez.Drawables.SilthatchA, Rez.Drawables.SilthatchB],
            "cinderfang" => [Rez.Drawables.CinderfangA, Rez.Drawables.CinderfangB],
            "tidecaller" => [Rez.Drawables.TidecallerA, Rez.Drawables.TidecallerB],
            "voltcrest" => [Rez.Drawables.VoltcrestA, Rez.Drawables.VoltcrestB],
            "thornmane" => [Rez.Drawables.ThornmaneA, Rez.Drawables.ThornmaneB],
            "galewing" => [Rez.Drawables.GalewingA, Rez.Drawables.GalewingB],
            "glacierjaw" => [Rez.Drawables.GlacierjawA, Rez.Drawables.GlacierjawB],
            "duneshell" => [Rez.Drawables.DuneshellA, Rez.Drawables.DuneshellB],
            "ashlynx" => [Rez.Drawables.AshlynxA, Rez.Drawables.AshlynxB],
            "pyrewarden" => [Rez.Drawables.PyrewardenA, Rez.Drawables.PyrewardenB],
            "abyssward" => [Rez.Drawables.AbysswardA, Rez.Drawables.AbysswardB],
            "stormcrown" => [Rez.Drawables.StormcrownA, Rez.Drawables.StormcrownB],
            "grovekeeper" => [Rez.Drawables.GrovekeeperA, Rez.Drawables.GrovekeeperB],
            "sandmonarch" => [Rez.Drawables.SandmonarchA, Rez.Drawables.SandmonarchB],
            "emberdrake" => [Rez.Drawables.EmberdrakeA, Rez.Drawables.EmberdrakeB],
            "solmonarch" => [Rez.Drawables.SolmonarchA, Rez.Drawables.SolmonarchB],
            "voidsentinel" => [Rez.Drawables.VoidsentinelA, Rez.Drawables.VoidsentinelB],
            "flarewisp" => [Rez.Drawables.FlarewispA, Rez.Drawables.FlarewispB],
            "stonefang" => [Rez.Drawables.StonefangA, Rez.Drawables.StonefangB],
            "twinflare" => [Rez.Drawables.TwinflareA, Rez.Drawables.TwinflareB],
            "elderflame" => [Rez.Drawables.ElderflameA, Rez.Drawables.ElderflameB],
            "gleammote" => [Rez.Drawables.GleammoteA, Rez.Drawables.GleammoteB]
        };
        _index = built;
        return built;
    }

    //! The drawable id for a species and frame, or null when that species has no art.
    function resourceIdFor(key as String, frame as Number) as ResourceId? {
        var pair = index()[key];
        if (pair == null) {
            return null;
        }
        return pair[(frame != 0) ? 1 : 0];
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
