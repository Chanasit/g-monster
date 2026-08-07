import Toybox.Lang;
import Toybox.WatchUi;

//! Decides what the player is about to fight and puts the battle on screen.
module Encounter {

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
}
