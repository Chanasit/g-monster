import Toybox.Lang;

//! Partner growth: when a partner has nothing left to learn at its current form, focus can be spent
//! to push it into the next one. Pure logic — the caller owns storage and presentation.
module Evolution {

    //! Ceiling on banked focus. Ten matches the per-battle pool the summon-cost table is scaled to.
    const MAX_FOCUS = 10;

    //! The species this partner grows into, or null if it is already final.
    function target(partner as Combat.Creature) as Combat.Creature? {
        var key = partner.evolvesTo;
        if (key == null) {
            return null;
        }
        return Combat.Bestiary.get(key);
    }

    //! A partner may evolve once it has maxed out its current form and has focus to spend.
    //! Final forms never qualify, however much focus is banked.
    function isReady(partner as Combat.Creature, extraLevel as Number, focus as Number) as Boolean {
        if (target(partner) == null) {
            return false;
        }
        if (focus < 1) {
            return false;
        }
        return extraLevel >= partner.maxExtraLevel();
    }

    //! Odds of the attempt landing, 0.0 .. 1.0. More focus fakes a higher player level for the roll,
    //! so committing the whole pool is what makes a big jump plausible.
    function chance(into as Combat.Creature, playerLevel as Number, focus as Number) as Float {
        return into.evolveChance(playerLevel, focus);
    }

    //! Roll the attempt. The focus is spent either way — that is the cost of trying early.
    function attempt(
        into as Combat.Creature,
        playerLevel as Number,
        focus as Number,
        rng as Combat.Rng
    ) as Boolean {
        return rng.chance(chance(into, playerLevel, focus));
    }
}
