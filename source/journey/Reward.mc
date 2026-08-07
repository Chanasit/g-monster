import Toybox.Lang;

//! Things found on the road: the non-combat outcome of a step event.
//!
//! Rewards are what stop a long walk from being an unbroken run of fights. Most are small nudges to
//! the resources the player already cares about; a couple are setbacks, so an event is not a
//! guaranteed gift and the banner is worth reading.
//!
//! Deliberately foreground-only — applying a reward touches saved state and the map.
module Reward {

    enum {
        KIND_NOTHING = 0,
        KIND_SHORTCUT = 1,       // ground covered for free
        KIND_SETBACK = 2,        // ground lost
        KIND_SPIRIT_GAIN = 3,
        KIND_SPIRIT_LOSS = 4,
        KIND_FOCUS = 5,
        KIND_EXPERIENCE = 6,
        KIND_DATA_STORM = 7      // swept to another area entirely
    }

    //! Steps of ground a shortcut or setback moves the player.
    const GROUND_STEP = 250;

    //! How often each outcome comes up. Good outcomes outweigh bad ones — walking should feel
    //! rewarded on balance — but the setbacks keep an event from being free.
    function weightOf(kind as Number) as Number {
        if (kind == KIND_NOTHING) { return 10; }
        if (kind == KIND_SHORTCUT) { return 20; }
        if (kind == KIND_SETBACK) { return 12; }
        if (kind == KIND_SPIRIT_GAIN) { return 16; }
        if (kind == KIND_SPIRIT_LOSS) { return 8; }
        if (kind == KIND_FOCUS) { return 16; }
        if (kind == KIND_EXPERIENCE) { return 13; }
        if (kind == KIND_DATA_STORM) { return 5; }
        return 0;
    }

    function kinds() as Array<Number> {
        return [
            KIND_NOTHING, KIND_SHORTCUT, KIND_SETBACK, KIND_SPIRIT_GAIN,
            KIND_SPIRIT_LOSS, KIND_FOCUS, KIND_EXPERIENCE, KIND_DATA_STORM
        ] as Array<Number>;
    }

    function totalWeight() as Number {
        var all = kinds();
        var total = 0;
        for (var i = 0; i < all.size(); i += 1) {
            total += weightOf(all[i]);
        }
        return total;
    }

    //! Pick an outcome. Pure — nothing is applied until apply() is called.
    function roll(rng as Combat.Rng) as Number {
        var all = kinds();
        var target = rng.nextInt(totalWeight());
        var running = 0;

        for (var i = 0; i < all.size(); i += 1) {
            running += weightOf(all[i]);
            if (target < running) {
                return all[i];
            }
        }
        return KIND_NOTHING;
    }

    //! Carry out the outcome and return a one-line account of it for the screen.
    //!
    //! Every branch is written so it cannot corrupt the trek: ground gained never walks past the
    //! guardian's doorstep, and ground lost never exceeds the area it is in.
    function apply(kind as Number, rng as Combat.Rng) as String {
        if (kind == KIND_SHORTCUT) {
            return moveGround(-(GROUND_STEP + rng.nextInt(3) * 100));
        }
        if (kind == KIND_SETBACK) {
            return moveGround(GROUND_STEP + rng.nextInt(2) * 100);
        }
        if (kind == KIND_SPIRIT_GAIN) {
            var gain = 10 + rng.nextInt(3) * 5;
            GameState.addSpiritPower(gain);
            return "+" + gain.toString() + " SPIRIT";
        }
        if (kind == KIND_SPIRIT_LOSS) {
            var loss = 5 + rng.nextInt(3) * 5;
            GameState.addSpiritPower(-loss);
            return "-" + loss.toString() + " SPIRIT";
        }
        if (kind == KIND_FOCUS) {
            GameState.addFocus(1);
            return "+1 FOCUS";
        }
        if (kind == KIND_EXPERIENCE) {
            var xp = Combat.Progression.experienceForWin(GameState.level(), GameState.level());
            GameState.addExperience(xp);
            return "+" + xp.toString() + " XP";
        }
        if (kind == KIND_DATA_STORM) {
            return dataStorm(rng);
        }
        return "NOTHING HERE";
    }

    //! Shift the trek forward or back within its current area. Negative moves closer to the
    //! guardian; the floor of 1 is the doorstep, which is exactly where a boss triggers.
    function moveGround(delta as Number) as String {
        var trek = Atlas.ensureTrek();
        var before = trek.distance;

        var moved = trek.distance + delta;
        var areaLength = Atlas.areaDistance(trek.area);
        if (moved < 1) {
            moved = 1;
        }
        if (moved > areaLength) {
            moved = areaLength;
        }
        trek.distance = moved;
        JourneyState.saveTrek(trek);

        var difference = before - moved;
        if (difference > 0) {
            return "-" + difference.toString() + " TO GO";
        }
        if (difference < 0) {
            return "+" + (-difference).toString() + " TO GO";
        }
        return "NOTHING HERE";
    }

    //! Swept to a different area at full distance. The one outcome that moves the player off the
    //! map square they were on, so it never lands them back where they started.
    function dataStorm(rng as Combat.Rng) as String {
        var trek = Atlas.ensureTrek();
        var count = Atlas.areaCount();

        if (count <= 1) {
            return "THE STORM PASSES";
        }

        // Offset by 1..count-1 so the destination is always somewhere else.
        var destination = (trek.area + 1 + rng.nextInt(count - 1)) % count;
        trek.moveTo(destination, Atlas.areaDistance(destination), Journey.rollEventGap(rng));
        JourneyState.saveTrek(trek);

        return "SWEPT TO " + Atlas.areaName(destination).toUpper();
    }
}
