import Toybox.Lang;

//! The trek state machine: how walking turns into events. Pure mechanics — it holds no area data
//! and never reads a resource, which is what lets the background service advance it while the app
//! is closed. Where the areas are and what guards them belongs to Atlas.
(:background)
module Journey {

    // What the trek is waiting on. A pending event freezes progress until it is resolved.
    enum {
        EVENT_NONE = 0,
        EVENT_ENCOUNTER = 1,
        EVENT_BOSS = 2,
        EVENT_REWARD = 3
    }

    //! Share of step-triggered events that are a fight. The rest are something found on the road —
    //! without this every event is combat and a long walk is monotonous.
    const ENCOUNTER_PERCENT = 85;

    //! Upper bound on steps applied in one advance() call. Stops a long gap between syncs (or a
    //! pedometer oddity) from burning through several areas at once; the surplus stays banked.
    const MAX_CATCHUP_STEPS = 20000;

    // Steps between events: 300, 400 or 500. Short enough that an ordinary walk produces events,
    // long enough that each one still reads as an occasion.
    const EVENT_GAP_MIN = 300;
    const EVENT_GAP_STEP = 100;
    const EVENT_GAP_CHOICES = 3;

    //! Debug override. While non-zero every event gap collapses to this many steps, so the
    //! encounter loop can be exercised in the simulator without walking several hundred steps per
    //! event. Set back to 0 to restore the real 300..500 pacing — this is a tuning cheat, not a
    //! feature, and shipping it would trivialise the game.
    const DEBUG_EVENT_GAP = 0;

    //! Bounds `rollEventGap` can actually return, override included. Tests assert against these
    //! rather than against 300/500 literals, so flipping the override does not fake a passing suite.
    function eventGapMin() as Number {
        return (DEBUG_EVENT_GAP > 0) ? DEBUG_EVENT_GAP : EVENT_GAP_MIN;
    }

    function eventGapMax() as Number {
        return (DEBUG_EVENT_GAP > 0)
            ? DEBUG_EVENT_GAP
            : EVENT_GAP_MIN + ((EVENT_GAP_CHOICES - 1) * EVENT_GAP_STEP);
    }

    //! Steps until the next event. The roll happens either way so that the generator is consumed
    //! identically with the override on or off — a seeded trek still replays step-for-step.
    function rollEventGap(rng as Combat.Rng) as Number {
        var rolled = EVENT_GAP_MIN + (rng.nextInt(EVENT_GAP_CHOICES) * EVENT_GAP_STEP);
        return (DEBUG_EVENT_GAP > 0) ? DEBUG_EVENT_GAP : rolled;
    }

    //! Cap a gap that was persisted before the override was switched on. Without this a save
    //! sitting on 380 steps would still have to walk all 380 before the override bit.
    function clampEventGap(steps as Number) as Number {
        if (DEBUG_EVENT_GAP > 0 && steps > DEBUG_EVENT_GAP) {
            return DEBUG_EVENT_GAP;
        }
        return steps;
    }

    //! Which kind of event a step counter rollover produces. Mostly a fight, occasionally
    //! something else entirely. Guardians are not rolled — those are triggered by distance.
    function rollEventKind(rng as Combat.Rng) as Number {
        return (rng.nextInt(100) < ENCOUNTER_PERCENT) ? EVENT_ENCOUNTER : EVENT_REWARD;
    }

    //! A trek in progress. Construct it from persisted values, advance it, then persist it back.
    class Trek {
        public var area as Number;              // index into Atlas's flattened area list
        public var distance as Number;          // steps left before the area guardian
        public var stepsToNextEvent as Number;  // steps left before a random encounter
        public var totalSteps as Number;        // lifetime steps walked in the journey
        public var pendingEvent as Number;

        function initialize(
            area as Number,
            distance as Number,
            stepsToNextEvent as Number,
            totalSteps as Number,
            pendingEvent as Number
        ) {
            self.area = area;
            self.distance = distance;
            self.stepsToNextEvent = stepsToNextEvent;
            self.totalSteps = totalSteps;
            self.pendingEvent = pendingEvent;
        }

        //! Walk up to `steps` steps, stopping the moment an event triggers.
        //!
        //! Returns the number of steps actually consumed — which is less than `steps` when an event
        //! interrupts, or zero when one is already pending. The caller must only advance its
        //! pedometer baseline by the consumed count, so unwalked steps stay banked for after the
        //! player resolves the event.
        function advance(steps as Number, rng as Combat.Rng) as Number {
            if (steps <= 0 || pendingEvent != EVENT_NONE) {
                return 0;
            }

            var remaining = steps;
            if (remaining > MAX_CATCHUP_STEPS) {
                remaining = MAX_CATCHUP_STEPS;
            }
            var consumed = 0;

            while (remaining > 0) {
                // Standing on the guardian's doorstep: the fight triggers before any further walking.
                if (distance <= 1) {
                    distance = 1;
                    pendingEvent = EVENT_BOSS;
                    break;
                }

                // Walk to whichever comes first: the end of the batch, the next encounter, or the boss.
                var chunk = remaining;
                if (stepsToNextEvent < chunk) {
                    chunk = stepsToNextEvent;
                }
                if (distance - 1 < chunk) {
                    chunk = distance - 1;
                }
                if (chunk < 1) {
                    chunk = 1;
                }

                distance -= chunk;
                stepsToNextEvent -= chunk;
                totalSteps += chunk;
                remaining -= chunk;
                consumed += chunk;

                if (distance <= 1) {
                    distance = 1;
                    pendingEvent = EVENT_BOSS;
                    break;
                }
                if (stepsToNextEvent <= 0) {
                    stepsToNextEvent = rollEventGap(rng);
                    pendingEvent = rollEventKind(rng);
                    break;
                }
            }

            return consumed;
        }

        //! Clear a pending event without changing position. Walking resumes on the next sync.
        //! A guardian left unbeaten re-triggers immediately, since the distance is still 1.
        function resolveEvent() as Void {
            pendingEvent = EVENT_NONE;
        }

        //! Jump to a new area. The caller supplies the destination because area data lives in
        //! Atlas, which this module deliberately cannot see.
        function moveTo(nextArea as Number, nextDistance as Number, nextGap as Number) as Void {
            area = nextArea;
            distance = nextDistance;
            stepsToNextEvent = nextGap;
            pendingEvent = EVENT_NONE;
        }

        //! How far through the current area, 0.0 .. 1.0, given that area's full length.
        function areaProgress(areaLength as Number) as Float {
            if (areaLength <= 0) {
                return 0.0;
            }
            var walked = areaLength - distance;
            if (walked < 0) {
                walked = 0;
            }
            var progress = walked.toFloat() / areaLength.toFloat();
            return (progress > 1.0) ? 1.0 : progress;
        }

        function hasPendingEvent() as Boolean {
            return pendingEvent != EVENT_NONE;
        }
    }
}
