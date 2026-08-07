import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Persistent player state. Thin wrapper over Storage so the combat engine itself stays pure.
module GameState {

    const KEY_EXPERIENCE = "xp";
    const KEY_BATTLES = "battles";
    const KEY_WINS = "wins";
    const KEY_SEED = "seed";
    const KEY_INSURED = "insured";
    const KEY_PARTNER = "partner";
    const KEY_PARTNER_EXTRA = "partnerExtra";
    const KEY_FOCUS = "focus";
    const KEY_CHARACTER = "charCreated";
    const KEY_SPIRIT_POWER = "spiritPower";

    function readNumber(key as String, fallback as Number) as Number {
        var value = Storage.getValue(key);
        if (value == null) {
            return fallback;
        }
        return value as Number;
    }

    function readBoolean(key as String, fallback as Boolean) as Boolean {
        var value = Storage.getValue(key);
        if (value == null) {
            return fallback;
        }
        return value as Boolean;
    }

    function readString(key as String, fallback as String) as String {
        var value = Storage.getValue(key);
        if (value == null) {
            return fallback;
        }
        return value as String;
    }

    function experience() as Number {
        return readNumber(KEY_EXPERIENCE, 0);
    }

    function level() as Number {
        return Combat.Progression.levelFromExperience(experience());
    }

    function levelProgress() as Float {
        return Combat.Progression.levelProgress(experience());
    }

    function addExperience(amount as Number) as Void {
        var total = experience() + amount;
        if (total > Combat.Progression.MAX_EXPERIENCE) {
            total = Combat.Progression.MAX_EXPERIENCE;
        }
        Storage.setValue(KEY_EXPERIENCE, total);
        // Any gain clears the safety net earned by a previous demotion.
        Storage.setValue(KEY_INSURED, false);
    }

    //! Subtract experience, honouring the one-shot insurance that a level loss grants. Returns true
    //! if the player's level actually changed.
    function removeExperience(amount as Number) as Boolean {
        var levelBefore = level();

        if (readBoolean(KEY_INSURED, false)) {
            // Insurance absorbs this loss entirely, then burns out.
            Storage.setValue(KEY_INSURED, false);
            return false;
        }

        var total = experience() - amount;
        if (total < 0) {
            total = 0;
        }
        Storage.setValue(KEY_EXPERIENCE, total);

        var levelNow = Combat.Progression.levelFromExperience(total);
        if (levelNow < levelBefore) {
            // Dropping a level insures the next loss, so two demotions can never stack.
            Storage.setValue(KEY_INSURED, true);
            return true;
        }
        return levelBefore != levelNow;
    }

    function battles() as Number {
        return readNumber(KEY_BATTLES, 0);
    }

    function wins() as Number {
        return readNumber(KEY_WINS, 0);
    }

    function winRate() as Float {
        var total = battles();
        if (total <= 0) {
            return 0.0;
        }
        return wins().toFloat() / total.toFloat();
    }

    function recordBattle(won as Boolean) as Void {
        Storage.setValue(KEY_BATTLES, battles() + 1);
        if (won) {
            Storage.setValue(KEY_WINS, wins() + 1);
        }
    }

    //! Whether the player has picked a starter. False only on a genuinely fresh save, which is what
    //! sends the app to the character-select screen instead of the main view.
    function hasCharacter() as Boolean {
        if (readBoolean(KEY_CHARACTER, false)) {
            return true;
        }
        // A save from before this screen existed has no flag but does have a lead. Treat it as
        // started rather than sending it back through select and overwriting its party.
        return Party.hasStoredLead();
    }

    //! Commit the starter choice: it leads the party, counts as unlocked, and the save is started.
    function createCharacter(key as String) as Void {
        Party.setSlot(Party.LEAD_SLOT, key);
        Party.unlock(key);
        Storage.setValue(KEY_CHARACTER, true);
    }

    //! The lead creature — slot 0 of the party, and the one every battle opens with.
    //! Roster storage lives in Party; these stay as the names the rest of the app already calls.
    function partnerKey() as String {
        return Party.lead().key;
    }

    function partner() as Combat.Creature {
        return Party.lead();
    }

    function setPartner(key as String) as Void {
        Party.setSlot(Party.LEAD_SLOT, key);
    }

    function partnerExtraLevel() as Number {
        return Party.extraLevel(partnerKey());
    }

    function addPartnerExtraLevel(amount as Number) as Void {
        Party.addExtraLevel(partnerKey(), amount);
    }

    //! Banked focus, spent on evolution attempts.
    function focus() as Number {
        return readNumber(KEY_FOCUS, 0);
    }

    function addFocus(amount as Number) as Void {
        var total = focus() + amount;
        if (total > Evolution.MAX_FOCUS) {
            total = Evolution.MAX_FOCUS;
        }
        if (total < 0) {
            total = 0;
        }
        Storage.setValue(KEY_FOCUS, total);
    }

    //! Spirit power, spent to enter spirit forms mid-battle and drained by holding them.
    function spiritPower() as Number {
        return readNumber(KEY_SPIRIT_POWER, 0);
    }

    function setSpiritPower(value as Number) as Void {
        var capped = value;
        if (capped > Combat.Spirit.MAX_POWER) {
            capped = Combat.Spirit.MAX_POWER;
        }
        if (capped < 0) {
            capped = 0;
        }
        Storage.setValue(KEY_SPIRIT_POWER, capped);
    }

    function addSpiritPower(amount as Number) as Void {
        setSpiritPower(spiritPower() + amount);
    }

    //! True when the partner has maxed its current form and can attempt to grow.
    function partnerCanEvolve() as Boolean {
        return Evolution.isReady(partner(), partnerExtraLevel(), focus());
    }

    //! Replace the lead with its next form and reset that form's growth. Focus is spent by the
    //! caller, win or lose, so it is untouched here.
    function evolvePartner() as Void {
        var into = Evolution.target(partner());
        if (into == null) {
            return;
        }
        Party.replaceLead(into.key);
    }

    //! Advance and return the stored battle seed. Persisting it means a battle in progress replays
    //! identically if the app is killed and reopened.
    function nextSeed() as Number {
        var seed = readNumber(KEY_SEED, 0);
        if (seed == 0) {
            var now = System.getTimer();
            seed = (now == 0) ? 1 : now;
        }
        seed = (seed * 1103515 + 12345) & 0x7FFFFFFF;
        if (seed == 0) {
            seed = 1;
        }
        Storage.setValue(KEY_SEED, seed);
        return seed;
    }
}
