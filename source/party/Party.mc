import Toybox.Application.Storage;
import Toybox.Lang;

//! The four-slot roster the player fights with, the species they have unlocked, and each species'
//! own growth. Growth is per creature rather than per slot, so moving one around never loses it.
module Party {

    //! Slots available. Four is what the summon-cost table's ten-point pool is balanced against.
    const SIZE = 4;

    //! Slot 0 is the creature that starts every battle.
    const LEAD_SLOT = 0;

    const EMPTY = "";

    const KEY_SLOT_PREFIX = "slot";
    const KEY_UNLOCKED = "unlocked";
    const KEY_LEVEL_PREFIX = "xl_";

    function slotKey(index as Number) as String {
        return KEY_SLOT_PREFIX + index.toString();
    }

    //! The species key in a slot, or EMPTY. Slot 0 defaults to the starter so a new game is playable.
    function slot(index as Number) as String {
        var value = Storage.getValue(slotKey(index));
        if (value == null) {
            return (index == LEAD_SLOT) ? Combat.Bestiary.defaultStarter() : EMPTY;
        }
        return value as String;
    }

    //! Whether a lead has actually been written, as opposed to the default standing in for one.
    //! Lets a save made before character select existed be recognised as already started.
    function hasStoredLead() as Boolean {
        return Storage.getValue(slotKey(LEAD_SLOT)) != null;
    }

    function setSlot(index as Number, key as String) as Void {
        if (index < 0 || index >= SIZE) {
            return;
        }
        Storage.setValue(slotKey(index), key);
    }

    //! The species in a slot, or null when the slot is empty or holds a stale key.
    function member(index as Number) as Combat.Creature? {
        var key = slot(index);
        if (key.equals(EMPTY)) {
            return null;
        }
        return Combat.Bestiary.get(key);
    }

    //! The creature that leads every battle. Falls back to the first species if storage is bad.
    function lead() as Combat.Creature {
        var species = member(LEAD_SLOT);
        if (species == null) {
            species = Combat.Bestiary.all()[0];
            setSlot(LEAD_SLOT, species.key);
        }
        return species;
    }

    function firstEmptySlot() as Number {
        for (var i = 0; i < SIZE; i += 1) {
            if (slot(i).equals(EMPTY)) {
                return i;
            }
        }
        return -1;
    }

    function isInParty(key as String) as Boolean {
        for (var i = 0; i < SIZE; i += 1) {
            if (slot(i).equals(key)) {
                return true;
            }
        }
        return false;
    }

    //! Species the player has beaten and may field.
    function unlocked() as Array<String> {
        var value = Storage.getValue(KEY_UNLOCKED);
        if (value == null) {
            var starter = [lead().key] as Array<String>;
            Storage.setValue(KEY_UNLOCKED, starter as Array<Storage.ValueType>);
            return starter;
        }
        return value as Array<String>;
    }

    function isUnlocked(key as String) as Boolean {
        var list = unlocked();
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i].equals(key)) {
                return true;
            }
        }
        return false;
    }

    //! Record a species as fieldable. Returns true only the first time, so callers can announce it.
    //! A newly unlocked species drops straight into an empty slot — an unreachable recruit is no
    //! reward at all.
    function unlock(key as String) as Boolean {
        if (key.equals(EMPTY) || isUnlocked(key)) {
            return false;
        }

        var list = unlocked();
        list.add(key);
        Storage.setValue(KEY_UNLOCKED, list as Array<Storage.ValueType>);

        var empty = firstEmptySlot();
        if (empty >= 0) {
            setSlot(empty, key);
        }
        return true;
    }

    //! Levels a species has gained above its base, stored per species.
    function extraLevel(key as String) as Number {
        var value = Storage.getValue(KEY_LEVEL_PREFIX + key);
        if (value == null) {
            return 0;
        }
        return value as Number;
    }

    function setExtraLevel(key as String, value as Number) as Void {
        var species = Combat.Bestiary.get(key);
        if (species == null) {
            return;
        }

        var capped = value;
        var ceiling = species.maxExtraLevel();
        if (capped > ceiling) {
            capped = ceiling;
        }
        if (capped < 0) {
            capped = 0;
        }
        Storage.setValue(KEY_LEVEL_PREFIX + key, capped);
    }

    function addExtraLevel(key as String, amount as Number) as Void {
        setExtraLevel(key, extraLevel(key) + amount);
    }

    //! Swap the lead for its evolved form, keeping the rest of the roster intact. The new form
    //! starts its own growth at zero and is unlocked in its own right.
    function replaceLead(key as String) as Void {
        setSlot(LEAD_SLOT, key);
        setExtraLevel(key, 0);

        if (!isUnlocked(key)) {
            var list = unlocked();
            list.add(key);
            Storage.setValue(KEY_UNLOCKED, list as Array<Storage.ValueType>);
        }
    }
}
