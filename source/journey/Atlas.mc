import Toybox.Application;
import Toybox.Lang;

//! The overworld map, loaded from `resources/data/worlds.json`.
//!
//! Worlds hold areas; this flattens them into one ordered list, so a trek is positioned by a single
//! index and adding a world is a data edit rather than a code change.
//!
//! Deliberately NOT background-scoped: parsing a resource is too heavy for the background process's
//! memory budget. Journey.Trek is the part the background service touches, and it holds no map data.
module Atlas {

    //! One area: a stretch of walking ending at a guardian.
    class Area {
        public var world as Number;
        public var name as String;
        public var distance as Number;
        public var boss as String;

        function initialize(world as Number, name as String, distance as Number, boss as String) {
            self.world = world;
            self.name = name;
            self.distance = distance;
            self.boss = boss;
        }
    }

    var _areas as Array<Area>?;

    //! Every area across every world, in traversal order. Parsed once and cached.
    function areas() as Array<Area> {
        var cached = _areas;
        if (cached != null) {
            return cached;
        }

        var worlds = Application.loadResource(Rez.JsonData.Worlds) as Array;
        var list = [] as Array<Area>;

        for (var w = 0; w < worlds.size(); w += 1) {
            var world = worlds[w] as Dictionary;
            var worldAreas = world["areas"] as Array;

            for (var a = 0; a < worldAreas.size(); a += 1) {
                var record = worldAreas[a] as Dictionary;
                list.add(new Area(
                    world["number"] as Number,
                    record["name"] as String,
                    record["distance"] as Number,
                    record["boss"] as String
                ));
            }
        }

        _areas = list;
        return list;
    }

    function areaCount() as Number {
        return areas().size();
    }

    function clampArea(index as Number) as Number {
        var count = areaCount();
        if (index < 0) {
            return 0;
        }
        if (index >= count) {
            return count - 1;
        }
        return index;
    }

    function area(index as Number) as Area {
        return areas()[clampArea(index)];
    }

    function areaName(index as Number) as String {
        return area(index).name;
    }

    function areaDistance(index as Number) as Number {
        return area(index).distance;
    }

    function areaBoss(index as Number) as String {
        return area(index).boss;
    }

    //! A fresh trek at the first area.
    function newTrek(rng as Combat.Rng) as Journey.Trek {
        return new Journey.Trek(0, areaDistance(0), Journey.rollEventGap(rng), 0, Journey.EVENT_NONE);
    }

    //! The stored trek, starting one if the game has not begun. Foreground only — the background
    //! service must never be the thing that creates it.
    function ensureTrek() as Journey.Trek {
        var trek = JourneyState.peekTrek();
        if (trek != null) {
            return trek;
        }

        var fresh = newTrek(new Combat.Rng(JourneyState.nextSeed()));
        JourneyState.saveTrek(fresh);
        return fresh;
    }

    //! Guardian beaten: persist the move to the next area.
    function completeArea() as Void {
        var trek = ensureTrek();
        advanceToNextArea(trek, new Combat.Rng(JourneyState.nextSeed()));
        JourneyState.saveTrek(trek);
    }

    //! Guardian beaten: move the trek on to the next area, wrapping at the end of the chain.
    function advanceToNextArea(trek as Journey.Trek, rng as Combat.Rng) as Void {
        var next = (trek.area + 1) % areaCount();
        trek.moveTo(next, areaDistance(next), Journey.rollEventGap(rng));
    }

    //! How far through its current area a trek is, 0.0 .. 1.0.
    function progressOf(trek as Journey.Trek) as Float {
        return trek.areaProgress(areaDistance(trek.area));
    }
}
