import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;

//! Persistence for the trek.
//!
//! Background-scoped, so it deals only in stored primitives — it never creates a trek, because
//! doing so would need Atlas and its resource parsing. The foreground creates the trek on first
//! run (Atlas.ensureTrek); the background service only ever advances one that already exists.
(:background)
module JourneyState {

    const KEY_AREA = "jArea";
    const KEY_DISTANCE = "jDistance";
    const KEY_NEXT_EVENT = "jNextEvent";
    const KEY_TOTAL_STEPS = "jTotalSteps";
    const KEY_PENDING = "jPending";
    const KEY_BASELINE = "jBaseline";
    const KEY_SEED = "jSeed";

    function readNumber(key as String, fallback as Number) as Number {
        var value = Storage.getValue(key);
        if (value == null) {
            return fallback;
        }
        return value as Number;
    }

    //! Rolling seed for event-gap rolls. Seeded off the system timer the first time only.
    function nextSeed() as Number {
        var seed = readNumber(KEY_SEED, 0);
        if (seed == 0) {
            var now = System.getTimer();
            seed = (now == 0) ? 7919 : now;
        }
        seed = (seed * 1103515 + 12345) & 0x7FFFFFFF;
        if (seed == 0) {
            seed = 1;
        }
        Storage.setValue(KEY_SEED, seed);
        return seed;
    }

    function exists() as Boolean {
        return readNumber(KEY_DISTANCE, 0) > 0;
    }

    //! The stored trek, or null if the game has not started one yet.
    function peekTrek() as Journey.Trek? {
        var distance = readNumber(KEY_DISTANCE, 0);
        if (distance <= 0) {
            return null;
        }

        return new Journey.Trek(
            readNumber(KEY_AREA, 0),
            distance,
            readNumber(KEY_NEXT_EVENT, 300),
            readNumber(KEY_TOTAL_STEPS, 0),
            readNumber(KEY_PENDING, Journey.EVENT_NONE)
        );
    }

    function saveTrek(trek as Journey.Trek) as Void {
        Storage.setValue(KEY_AREA, trek.area);
        Storage.setValue(KEY_DISTANCE, trek.distance);
        Storage.setValue(KEY_NEXT_EVENT, trek.stepsToNextEvent);
        Storage.setValue(KEY_TOTAL_STEPS, trek.totalSteps);
        Storage.setValue(KEY_PENDING, trek.pendingEvent);
    }

    function pendingEvent() as Number {
        return readNumber(KEY_PENDING, Journey.EVENT_NONE);
    }

    //! Clear the pending event after the player has dealt with it.
    function resolveEvent() as Void {
        var trek = peekTrek();
        if (trek == null) {
            return;
        }
        trek.resolveEvent();
        saveTrek(trek);
    }

    //! Pedometer reading already folded into the trek.
    function stepBaseline() as Number {
        return readNumber(KEY_BASELINE, 0);
    }

    function setStepBaseline(value as Number) as Void {
        Storage.setValue(KEY_BASELINE, value);
    }
}
