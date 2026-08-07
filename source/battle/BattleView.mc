import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! Screen for a single battle. Owns presentation and the encounter's persistence side effects;
//! all rules live in Combat.BattleEngine.
class BattleView extends WatchUi.View {

    // View states.
    private const STATE_INTRO = 0;    // the encounter flash, before control is handed over
    private const STATE_SELECT = 1;   // player is choosing an attack
    private const STATE_RESOLVE = 2;  // showing what happened this turn
    private const STATE_OVER = 3;     // battle finished, showing the payout

    //! Ticks the encounter flash runs for. Long enough to register as an event, short enough that
    //! it never feels like something to sit through.
    private const INTRO_TICKS = 4;

    private const RESOLVE_TICKS = 2;  // ~1s at the 500ms tick rate

    private var _engine as Combat.BattleEngine;
    private var _state as Number;
    private var _selected as Number;
    private var _lastResult as Combat.TurnResult?;
    private var _ticksLeft as Number;
    private var _timer as Timer.Timer?;
    private var _experienceDelta as Number;
    private var _levelChanged as Boolean;
    private var _settled as Boolean;
    private var _isBoss as Boolean;
    private var _areaCleared as Boolean;
    private var _partnerLevelDelta as Number;
    private var _recruited as String?;
    private var _summonedName as String?;
    private var _summonTicks as Number;
    private var _introTicks as Number;

    //! Every battle comes from a trek event — there is no free sparring — so the trek is always
    //! blocked on this fight and always has to be unblocked when it ends.
    //!
    //! @param enemy   what the player is fighting
    //! @param isBoss  true when this is the area guardian, so a win advances the trek
    //! @param rng     seeded generator; shared with the caller so the fight replays
    function initialize(
        enemy as Combat.Creature,
        isBoss as Boolean,
        rng as Combat.Rng
    ) {
        View.initialize();

        _isBoss = isBoss;
        _areaCleared = false;
        _partnerLevelDelta = 0;
        _recruited = null;
        _summonedName = null;
        _summonTicks = 0;

        _engine = new Combat.BattleEngine(
            GameState.partner(),
            GameState.partnerExtraLevel(),
            enemy,
            GameState.level(),
            rng
        );

        // Spirit power is carried into the fight and written back when it ends.
        _engine.setSpiritPower(GameState.spiritPower());

        _state = STATE_INTRO;
        _introTicks = INTRO_TICKS;
        _selected = Combat.ATTACK_ENERGY;
        _lastResult = null;
        _ticksLeft = 0;
        _timer = null;
        _experienceDelta = 0;
        _levelChanged = false;
        _settled = false;
    }

    function onShow() as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 500, true);
        _timer = timer;
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        if (_state == STATE_INTRO) {
            _introTicks -= 1;
            if (_introTicks <= 0) {
                _state = STATE_SELECT;
            }
            WatchUi.requestUpdate();
            return;
        }

        if (_summonTicks > 0) {
            _summonTicks -= 1;
            if (_summonTicks <= 0) {
                _summonedName = null;
            }
        }

        if (_state == STATE_RESOLVE) {
            _ticksLeft -= 1;
            if (_ticksLeft <= 0) {
                _state = _engine.isOver() ? STATE_OVER : STATE_SELECT;
                if (_state == STATE_OVER) {
                    settleBattle();
                }
            }
        }
        WatchUi.requestUpdate();
    }

    //! Cycle the highlighted attack. No-op outside the selection state.
    function cycleAttack(step as Number) as Void {
        if (_state != STATE_SELECT) {
            return;
        }
        _selected = (_selected + step + 3) % 3;
        WatchUi.requestUpdate();
    }

    //! Commit the highlighted attack, or dismiss the result of the previous one.
    function confirm() as Void {
        if (_state == STATE_INTRO) {
            _introTicks = 0;
            _state = STATE_SELECT;
            WatchUi.requestUpdate();
            return;
        }

        if (_state == STATE_SELECT) {
            _lastResult = _engine.takeTurn(_selected);
            _state = STATE_RESOLVE;
            _ticksLeft = RESOLVE_TICKS;
        } else if (_state == STATE_RESOLVE) {
            // Skip the result animation.
            _ticksLeft = 0;
            _state = _engine.isOver() ? STATE_OVER : STATE_SELECT;
            if (_state == STATE_OVER) {
                settleBattle();
            }
        } else {
            popView();
        }
        WatchUi.requestUpdate();
    }

    function isOver() as Boolean {
        return _state == STATE_OVER;
    }

    function battleEngine() as Combat.BattleEngine {
        return _engine;
    }

    //! True only while the player is free to act — no calling mid-animation or after the last blow.
    function canOpenDDock() as Boolean {
        return _state == STATE_SELECT && !_engine.isOver();
    }

    //! The encounter flash: the panel slams to full ink and back, with the enemy named across it.
    //! This is the moment the fight announces itself — on a two-tone screen, inverting everything
    //! is the loudest thing available.
    private function drawIntro(dc as Dc, centerX as Number, height as Numeric) as Void {
        var flash = (_introTicks % 2) == 0;

        if (flash) {
            Theme.invertScreen(dc);
            Theme.inverted(dc);
        } else {
            Theme.ink(dc);
        }

        dc.drawText(centerX, height * 0.40, Graphics.FONT_SMALL,
                    WatchUi.loadResource(_isBoss ? Rez.Strings.IntroBoss : Rez.Strings.IntroEncounter) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(centerX, height * 0.58, Graphics.FONT_TINY, _engine.enemySpecies().name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Bring a party member onto the field. Announced for a beat so the swap is visible.
    function summon(species as Combat.Creature) as Void {
        if (!_engine.summon(species, Party.extraLevel(species.key))) {
            return;
        }
        _summonedName = species.name;
        _summonTicks = RESOLVE_TICKS;
        WatchUi.requestUpdate();
    }

    //! Enter a spirit form, keeping the current fighter's growth so it comes back intact.
    function invokeSpirit(species as Combat.Creature) as Void {
        var host = _engine.playerSpecies();
        if (!_engine.invokeSpirit(species, Party.extraLevel(host.key))) {
            return;
        }
        _summonedName = species.name;
        _summonTicks = RESOLVE_TICKS;
        WatchUi.requestUpdate();
    }

    function popView() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    //! Award or deduct experience exactly once, when the battle ends.
    private function settleBattle() as Void {
        if (_settled) {
            return;
        }
        _settled = true;

        var won = (_engine.outcome() == Combat.WINNER_PLAYER);
        var partnerLevel = _engine.playerSpecies().friendlyLevel(GameState.partnerExtraLevel());
        var enemyLevel = _engine.enemyLevel();

        GameState.recordBattle(won);

        // Whatever power the fight left unspent goes back to the player, and a win replenishes
        // some — guardians more, since they are what a spirit is worth saving for.
        GameState.setSpiritPower(_engine.spiritPower());
        if (won) {
            GameState.addSpiritPower(_isBoss ? 15 : 5);
        }

        if (won) {
            _experienceDelta = Combat.Progression.experienceForWin(partnerLevel, enemyLevel);
            var levelBefore = GameState.level();
            GameState.addExperience(_experienceDelta);
            _levelChanged = (GameState.level() != levelBefore);
        } else {
            _experienceDelta = -Combat.Progression.experienceForLoss(partnerLevel, enemyLevel);
            _levelChanged = GameState.removeExperience(-_experienceDelta);
        }

        // Every win banks a point of focus toward the lead's next form, and beating a species is
        // what makes it fieldable. A fresh recruit drops into an empty slot on its own.
        if (won) {
            GameState.addFocus(1);
            if (Party.unlock(_engine.enemySpecies().key)) {
                _recruited = _engine.enemySpecies().name;
            }
        }

        // Guardians are what actually grow a creature: beating one hardens it, losing to one sets
        // it back. Ordinary encounters only move the player's own level. Growth lands on whoever
        // was actually fighting at the end, which may be a creature called in mid-battle.
        if (_isBoss) {
            var fighter = _engine.playerSpecies().key;
            var before = Party.extraLevel(fighter);
            Party.addExtraLevel(fighter, won ? 1 : -1);
            _partnerLevelDelta = Party.extraLevel(fighter) - before;
        }

        // Unblock the trek. Beating the guardian moves on to the next area; losing to it leaves the
        // player at distance 1, so the fight re-triggers on the next sync.
        if (won && _isBoss) {
            Atlas.completeArea();
            _areaCleared = true;
        } else {
            JourneyState.resolveEvent();
        }
    }

    function onUpdate(dc as Dc) as Void {
        Theme.clear(dc);

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        if (_state == STATE_INTRO) {
            drawIntro(dc, centerX, height);
            return;
        }

        var enemyLabel = _isBoss
            ? _engine.enemySpecies().name + "*"   // guardians are marked
            : _engine.enemySpecies().name;
        drawCombatant(dc, centerX, height * 0.16, enemyLabel,
                      _engine.enemyLevel(), _engine.enemyStats());
        var fighter = _engine.playerSpecies();
        drawCombatant(dc, centerX, height * 0.34, fighter.name,
                      fighter.friendlyLevel(Party.extraLevel(fighter.key)),
                      _engine.playerStats());

        // A just-called creature is announced over whatever the screen would otherwise show.
        var summoned = _summonedName;
        if (summoned != null) {
            Theme.banner(dc, centerX, height * 0.72, summoned + " IN!", Graphics.FONT_TINY);
            return;
        }

        if (_state == STATE_SELECT) {
            drawAttackPicker(dc, centerX, height);
        } else if (_state == STATE_RESOLVE) {
            drawTurnResult(dc, centerX, height);
        } else {
            drawOutcome(dc, centerX, height);
        }
    }

    //! Name + level on one line, HP bar underneath.
    private function drawCombatant(
        dc as Dc,
        centerX as Number,
        y as Numeric,
        name as String,
        level as Number,
        stats as Combat.CombatStats
    ) as Void {
        Theme.ink(dc);
        dc.drawText(centerX, y, Graphics.FONT_XTINY,
                    name + " L" + level.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var barWidth = (dc.getWidth() * 0.55).toNumber();
        var barHeight = 7;
        var x = centerX - barWidth / 2;
        var barY = (y + 14).toNumber();

        Theme.bar(dc, x, barY, barWidth, barHeight, stats.hpFraction());

        Theme.muted(dc);
        dc.drawText(centerX, barY + barHeight + 8, Graphics.FONT_XTINY,
                    stats.hp.toString() + "/" + stats.maxHp.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The three attacks in a row, highlighted one boxed, with its damage value below.
    private function drawAttackPicker(dc as Dc, centerX as Number, height as Numeric) as Void {
        var labels = ["EN", "CR", "AB"];
        var y = (height * 0.68).toNumber();
        var spacing = 44;
        var startX = centerX - spacing;

        for (var i = 0; i < labels.size(); i += 1) {
            var x = startX + (i * spacing);
            var chosen = (i == _selected);

            if (chosen) {
                Theme.ink(dc);
                dc.fillRectangle(x - 18, y - 12, 36, 24);
                Theme.inverted(dc);
            } else {
                Theme.muted(dc);
            }
            dc.drawText(x, y, Graphics.FONT_XTINY, labels[i],
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.83, Graphics.FONT_XTINY,
                    "PWR " + _engine.playerStats().attackDamage(_selected).toString()
                        + "   " + _engine.callPoints().toString() + "P",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! What both sides threw and who took the hit.
    private function drawTurnResult(dc as Dc, centerX as Number, height as Numeric) as Void {
        var result = _lastResult;
        if (result == null) {
            return;
        }

        var clash = Combat.BattleEngine.attackName(result.playerAttack)
                  + " v "
                  + Combat.BattleEngine.attackName(result.enemyAttack);

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.66, Graphics.FONT_XTINY, clash,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var message;
        var banded = false;   // the player landing a blow is the one thing worth inverting
        if (result.disobeyed && result.playerAttack == Combat.ATTACK_IDLE) {
            message = "IGNORED YOU";
        } else if (result.disobeyed) {
            message = "WENT ROGUE";
        } else if (result.winner == Combat.WINNER_TIE) {
            message = "CLASH";
        } else if (result.winner == Combat.WINNER_PLAYER) {
            message = "HIT -" + result.damage.toString();
            banded = true;
        } else {
            message = "TOOK -" + result.damage.toString();
        }

        if (banded) {
            Theme.banner(dc, centerX, height * 0.80, message, Graphics.FONT_TINY);
        } else {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.80, Graphics.FONT_TINY, message,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Final banner plus the experience swing.
    private function drawOutcome(dc as Dc, centerX as Number, height as Numeric) as Void {
        var won = (_engine.outcome() == Combat.WINNER_PLAYER);

        if (won) {
            Theme.banner(dc, centerX, height * 0.68, "VICTORY", Graphics.FONT_SMALL);
        } else {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.68, Graphics.FONT_SMALL, "DEFEAT",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var sign = (_experienceDelta >= 0) ? "+" : "";
        var line = sign + _experienceDelta.toString() + " XP";
        if (_levelChanged) {
            line += won ? "  LV UP" : "  LV DN";
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.82, Graphics.FONT_XTINY, line,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var footer = null as String?;
        var recruited = _recruited;
        if (recruited != null) {
            footer = recruited.toUpper() + " JOINS";
        } else if (_areaCleared) {
            var trek = Atlas.ensureTrek();
            footer = "ON TO " + Atlas.areaName(trek.area).toUpper();
        } else if (_partnerLevelDelta != 0) {
            var deltaSign = (_partnerLevelDelta > 0) ? "+" : "";
            footer = "ALLY " + deltaSign + _partnerLevelDelta.toString();
        }

        if (footer != null) {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.91, Graphics.FONT_XTINY, footer,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
