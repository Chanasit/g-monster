import Toybox.Lang;
import Toybox.WatchUi;

//! Decides what the player is about to fight and puts the battle on screen.
module Encounter {

    //! Seed for the debug preview battle. Any constant will do; it only has to not change.
    const PREVIEW_SEED = 20260807;

    //! Whether a fight is available at all.
    //!
    //! Battles are earned by walking — they exist only because the trek produced an event. Without
    //! this gate START is an unlimited battle button, and experience, focus, recruits and spirit
    //! power all come free while the step counter goes ignored.
    function canBegin() as Boolean {
        return JourneyState.pendingEvent() != Journey.EVENT_NONE;
    }

    //! Open whatever the trek is waiting on: the area guardian, the creature that ambushed the
    //! player, or whatever the road turned up. Returns false when nothing is pending.
    function begin() as Boolean {
        var pending = JourneyState.pendingEvent();
        if (pending == Journey.EVENT_NONE) {
            return false;
        }

        // Not everything on the road is a fight.
        if (pending == Journey.EVENT_REWARD) {
            var found = new RewardView();
            WatchUi.pushView(found, new RewardDelegate(found), WatchUi.SLIDE_LEFT);
            return true;
        }

        var playerLevel = GameState.level();
        var rng = new Combat.Rng(GameState.nextSeed());

        var enemy;
        var isBoss = false;

        if (pending == Journey.EVENT_BOSS) {
            var trek = Atlas.ensureTrek();
            var boss = Combat.Bestiary.get(Atlas.areaBoss(trek.area));
            enemy = (boss == null) ? Combat.Bestiary.randomEncounter(playerLevel, rng) : boss;
            isBoss = true;
        } else {
            enemy = Combat.Bestiary.randomEncounter(playerLevel, rng);
        }

        var view = new BattleView(enemy, isBoss, rng);
        WatchUi.pushView(view, new BattleDelegate(view), WatchUi.SLIDE_LEFT);
        return true;
    }

    //! Debug: a battle with nothing behind it, for looking at the battle scene without walking to
    //! an encounter first.
    //!
    //! Deliberately bypasses `canBegin` — that gate exists so battles stay earned by walking, and a
    //! preview is not a way around it: the fight is marked as a preview, so it pays out nothing and
    //! never touches the trek. Named species so a specific creature's artwork can be checked;
    //! unknown keys fall back to a level-appropriate roll.
    function preview(species as String, isBoss as Boolean) as [WatchUi.Views, WatchUi.InputDelegates] {
        // A fixed seed rather than GameState.nextSeed(), which persists the advanced seed and would
        // make the preview a write. This also makes the fight replay identically on every launch,
        // so an animation change is the only thing that differs between two runs.
        var rng = new Combat.Rng(PREVIEW_SEED);

        var enemy = Combat.Bestiary.get(species);
        if (enemy == null) {
            enemy = Combat.Bestiary.randomEncounter(GameState.level(), rng);
        }

        var view = new BattleView(enemy, isBoss, rng);
        view.markPreview();
        return [view, new BattleDelegate(view)];
    }
}
