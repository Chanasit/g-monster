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

    //! The view ticks at 100ms rather than the 500ms the rest of the app uses. A lunge that only
    //! gets two frames does not read as movement, and 500ms is already past the point where a hit
    //! feels connected to the button that caused it. Battles are short and the player is watching
    //! the whole time, so the extra redraws are worth it here and nowhere else.
    private const TICK_MS = 100;

    //! The encounter flash. Long enough to register as an event, short enough that it never feels
    //! like something to sit through.
    private const INTRO_MS = 2000;

    //! How long a resolved turn stays on screen. Longer than the old 1s because the animation now
    //! has to play inside it.
    private const RESOLVE_MS = 1200;

    private const SUMMON_MS = 1000;

    //! The attacker travels out and back within this window, then the defender takes the blow.
    private const LUNGE_MS = 400;

    //! How far the attacker travels, as a share of the clear space between the two sprites. Derived
    //! rather than a fixed fraction of the screen: at 208px the two 72px sprites leave only 23px
    //! between them, and any fixed reach large enough to read on a 280px panel makes them collide
    //! on the small one.
    private const LUNGE_SHARE = 3;

    //! The struck creature blinks for this long once the lunge lands. Blinking the sprite is the
    //! only damage cue a two-tone panel has — there is no red to flash.
    private const FLASH_MS = 600;
    private const FLASH_BLINK_MS = 100;

    //! A creature that ignored its tamer jitters in place instead of attacking.
    private const SHAKE_PX = 3;

    private var _engine as Combat.BattleEngine;
    private var _state as Number;
    private var _selected as Number;
    private var _lastResult as Combat.TurnResult?;
    private var _resolveMs as Number;
    private var _timer as Timer.Timer?;
    private var _experienceDelta as Number;
    private var _levelChanged as Boolean;
    private var _settled as Boolean;
    private var _isBoss as Boolean;
    private var _areaCleared as Boolean;
    private var _partnerLevelDelta as Number;
    private var _recruited as String?;
    private var _summonedName as String?;
    private var _summonMs as Number;
    private var _introMs as Number;

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
        _summonMs = 0;

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
        _introMs = INTRO_MS;
        _selected = Combat.ATTACK_ENERGY;
        _lastResult = null;
        _resolveMs = 0;
        _timer = null;
        _experienceDelta = 0;
        _levelChanged = false;
        _settled = false;
    }

    function onShow() as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), TICK_MS, true);
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
            _introMs -= TICK_MS;
            if (_introMs <= 0) {
                _state = STATE_SELECT;
            }
            WatchUi.requestUpdate();
            return;
        }

        if (_summonMs > 0) {
            _summonMs -= TICK_MS;
            if (_summonMs <= 0) {
                _summonedName = null;
            }
        }

        if (_state == STATE_RESOLVE) {
            _resolveMs -= TICK_MS;
            if (_resolveMs <= 0) {
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
            _introMs = 0;
            _state = STATE_SELECT;
            WatchUi.requestUpdate();
            return;
        }

        if (_state == STATE_SELECT) {
            _lastResult = _engine.takeTurn(_selected);
            _state = STATE_RESOLVE;
            _resolveMs = RESOLVE_MS;
        } else if (_state == STATE_RESOLVE) {
            // Skip the result animation.
            _resolveMs = 0;
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
        // Two flashes per second, independent of the 100ms tick so the rate does not change if the
        // tick is ever retuned.
        var flash = ((_introMs / 250) % 2) == 0;

        if (flash) {
            Theme.invertScreen(dc);
            Theme.inverted(dc);
        } else {
            Theme.ink(dc);
        }

        // The enemy slides in from off the right edge and settles at its battle position, so the
        // creature the player is about to fight is on screen before the fight starts.
        var elapsed = INTRO_MS - _introMs;
        var travel = (elapsed < LUNGE_MS) ? (LUNGE_MS - elapsed) : 0;
        var slide = ((dc.getWidth() * travel) / LUNGE_MS).toNumber();

        // On the flash beat the panel is solid ink, and a black sprite on black is invisible. Skip
        // it rather than draw nothing-shaped holes.
        if (!flash) {
            Sprites.drawIdle(dc, enemyX(dc) + slide, height * 0.40, _engine.enemySpecies().key);
        }

        dc.drawText(centerX, height * 0.68, Graphics.FONT_SMALL,
                    WatchUi.loadResource(_isBoss ? Rez.Strings.IntroBoss : Rez.Strings.IntroEncounter) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(centerX, height * 0.83, Graphics.FONT_TINY, _engine.enemySpecies().name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Bring a party member onto the field. Announced for a beat so the swap is visible.
    function summon(species as Combat.Creature) as Void {
        if (!_engine.summon(species, Party.extraLevel(species.key))) {
            return;
        }
        _summonedName = species.name;
        _summonMs = SUMMON_MS;
        WatchUi.requestUpdate();
    }

    //! Enter a spirit form, keeping the current fighter's growth so it comes back intact.
    function invokeSpirit(species as Combat.Creature) as Void {
        var host = _engine.playerSpecies();
        if (!_engine.invokeSpirit(species, Party.extraLevel(host.key))) {
            return;
        }
        _summonedName = species.name;
        _summonMs = SUMMON_MS;
        WatchUi.requestUpdate();
    }

    function popView() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    //! Debug: run this battle as a preview, so nothing it does reaches the save.
    //!
    //! settleBattle is already idempotent on `_settled` — it is the guard that stops a battle from
    //! paying out twice. Marking the fight settled before it starts reuses that guard to neutralise
    //! every write it would otherwise make: experience, focus, recruits, spirit power, party levels
    //! and the trek's pending event. The payout screen consequently reports +0 XP, which is correct:
    //! a preview earns nothing.
    function markPreview() as Void {
        _settled = true;
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

        drawScene(dc, height);

        // A just-called creature is announced over whatever the screen would otherwise show.
        var summoned = _summonedName;
        if (summoned != null) {
            battleBanner(dc, centerX, height * 0.80, summoned + " IN!", Graphics.FONT_TINY);
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

    //! The two combatants stand side by side rather than stacked: two 72px sprites plus a gap is
    //! 160px, which fits the narrowest supported panel (fr55, 208px) across the middle of the
    //! screen where a round display is at its widest. Stacking them would not fit vertically once
    //! the name, bar and attack picker are accounted for.
    private function playerX(dc as Dc) as Number {
        return (dc.getWidth() * 0.30).toNumber();
    }

    private function enemyX(dc as Dc) as Number {
        return (dc.getWidth() * 0.70).toNumber();
    }

    //! An emphasis band sized for this screen rather than Theme.banner's app-wide 0.86 width.
    //!
    //! At the depth these bands sit, a round panel's chord is far narrower than 0.86 of its
    //! diameter, so the full-width version has its ends cut off by the bezel. 0.62 clears the
    //! curve on every supported size.
    private function battleBanner(dc as Dc, centerX as Number, y as Numeric, text as String,
                                  font as Graphics.FontType) as Void {
        Theme.selectionBand(dc, centerX, y, 0.62, 26);
        Theme.inverted(dc);
        dc.drawText(centerX, y, font, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Milliseconds since the current turn started resolving. Zero outside STATE_RESOLVE.
    private function resolveElapsed() as Number {
        return (_state == STATE_RESOLVE) ? (RESOLVE_MS - _resolveMs) : RESOLVE_MS;
    }

    //! Who threw the blow this turn: +1 player, -1 enemy, 0 nobody (a clash or a refusal).
    private function striker() as Number {
        var result = _lastResult;
        if (result == null || _state != STATE_RESOLVE) {
            return 0;
        }
        if (result.disobeyed && result.playerAttack == Combat.ATTACK_IDLE) {
            return 0;   // it never swung; the jitter below carries that instead
        }
        if (result.winner == Combat.WINNER_PLAYER) {
            return 1;
        }
        if (result.winner == Combat.WINNER_ENEMY) {
            return -1;
        }
        return 0;
    }

    //! Horizontal offset for one combatant this frame.
    //!
    //! The attacker ramps toward its target and back over LUNGE_MS — a triangle rather than a
    //! smooth curve, because at 100ms there are only four frames in the move and easing would be
    //! invisible. A creature that ignored its tamer jitters on the spot instead, which reads as
    //! "did something, but not what you asked".
    private function lungeOffset(dc as Dc, mine as Number) as Number {
        var result = _lastResult;
        if (result == null || _state != STATE_RESOLVE) {
            return 0;
        }

        var elapsed = resolveElapsed();

        // Only a creature that refused outright jitters. One that went rogue did swing, just not
        // where it was told, so it still lunges — otherwise the enemy would flinch from a blow the
        // player never sees thrown.
        if (result.disobeyed && result.playerAttack == Combat.ATTACK_IDLE && mine > 0) {
            if (elapsed >= LUNGE_MS) {
                return 0;
            }
            return ((elapsed / FLASH_BLINK_MS) % 2 == 0) ? SHAKE_PX : -SHAKE_PX;
        }

        var swing = striker();
        var reach = lungeReach(dc);

        // A clash: both sides commit, meet in the middle, and neither lands.
        if (swing == 0) {
            if (result.winner != Combat.WINNER_TIE || elapsed >= LUNGE_MS) {
                return 0;
            }
            return travel(elapsed, reach / 2) * ((mine > 0) ? 1 : -1);
        }

        if (swing != mine || elapsed >= LUNGE_MS) {
            return 0;
        }
        return travel(elapsed, reach) * ((mine > 0) ? 1 : -1);
    }

    //! Travel distance that keeps the sprites clear of each other at full extension.
    private function lungeReach(dc as Dc) as Number {
        var clear = (enemyX(dc) - playerX(dc)) - Sprites.SIZE;
        return (clear > 0) ? (clear / LUNGE_SHARE) : 0;
    }

    //! Out and back: 0 at the ends of the window, full reach in the middle.
    private function travel(elapsed as Number, reach as Number) as Number {
        var half = LUNGE_MS / 2;
        var distance = (elapsed < half) ? elapsed : (LUNGE_MS - elapsed);
        return ((distance * reach) / half).toNumber();
    }

    //! Whether a combatant's sprite is drawn this frame. The one that just took a hit blinks for
    //! FLASH_MS after the lunge lands.
    private function visible(mine as Number) as Boolean {
        var result = _lastResult;
        if (result == null || _state != STATE_RESOLVE) {
            return true;
        }

        var swing = striker();
        if (swing == 0 || swing == mine) {
            return true;   // the attacker never blinks; nor does anyone on a clash
        }

        var elapsed = resolveElapsed();
        if (elapsed < LUNGE_MS || elapsed >= LUNGE_MS + FLASH_MS) {
            return true;
        }
        return (((elapsed - LUNGE_MS) / FLASH_BLINK_MS) % 2) == 0;
    }

    //! Both combatants: name, bar, level/HP, and the sprite itself.
    private function drawScene(dc as Dc, height as Numeric) as Void {
        var fighter = _engine.playerSpecies();
        var enemy = _engine.enemySpecies();

        // Once the fight is over the name and bar rows give way to the payout, which needs the
        // depth. The sprites stay so the screen still shows who won.
        var status = (_state != STATE_OVER);

        drawFighter(dc, playerX(dc), height, fighter.name, fighter.key,
                    fighter.friendlyLevel(Party.extraLevel(fighter.key)),
                    _engine.playerStats(), 1, status);

        drawFighter(dc, enemyX(dc), height,
                    _isBoss ? enemy.name + "*" : enemy.name,   // guardians are marked
                    enemy.key, _engine.enemyLevel(), _engine.enemyStats(), -1, status);
    }

    private function drawFighter(
        dc as Dc,
        x as Number,
        height as Numeric,
        name as String,
        key as String,
        level as Number,
        stats as Combat.CombatStats,
        mine as Number,
        status as Boolean
    ) as Void {
        // Name, level and bar sit *below* the sprite. Above it the panel is at its narrowest — a
        // round screen's chord that near the top cannot hold two columns of text, which is what
        // clipped both names and both bars when this block was at the top of the screen.
        if (status) {
            Theme.ink(dc);
            dc.drawText(x, height * 0.60, Graphics.FONT_XTINY,
                        name + " L" + level.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var barWidth = (dc.getWidth() * 0.38).toNumber();
            Theme.bar(dc, x - barWidth / 2, (height * 0.68).toNumber(), barWidth, 7,
                      stats.hpFraction());
        }

        if (!visible(mine)) {
            return;
        }

        // A creature at zero has left the field — but not until the blow that felled it has landed.
        // The engine applies damage the instant the turn resolves, so without the timing check the
        // loser would wink out before the lunge plays and the attacker would swing at empty space.
        if (stats.hp <= 0 && resolveElapsed() >= LUNGE_MS) {
            return;
        }

        var spriteY = height * 0.36;
        if (!Sprites.drawIdle(dc, x + lungeOffset(dc, mine), spriteY, key)) {
            // No art for this species: name the slot so the layout keeps its shape.
            Theme.ink(dc);
            dc.drawText(x, spriteY, Graphics.FONT_TINY, "?",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! The three attacks in a row, highlighted one boxed, with its damage value below.
    private function drawAttackPicker(dc as Dc, centerX as Number, height as Numeric) as Void {
        var labels = ["EN", "CR", "AB"];
        var y = (height * 0.80).toNumber();
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
        dc.drawText(centerX, height * 0.91, Graphics.FONT_XTINY,
                    "PWR " + _engine.playerStats().attackDamage(_selected).toString()
                        + "   " + _engine.callPoints().toString() + "P",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The damage floats up off whoever was hit, starting when the lunge lands.
    //!
    //! It is drawn only on the frames where the struck sprite is blinked out, and in the space that
    //! sprite occupies. That keeps the number tied to the creature that took the blow without
    //! fighting it for pixels — above the sprite there is only 13px between the HP line and the
    //! sprite's top edge on a 208px panel, which will not hold a line of text. Swapping the number
    //! in for the sprite on the off beat is also the more period-correct read: the thing flickers,
    //! and what shows through the gap is the damage.
    private function drawDamageNumber(dc as Dc, height as Numeric, result as Combat.TurnResult) as Void {
        var swing = striker();
        if (swing == 0 || result.damage <= 0) {
            return;
        }

        var elapsed = resolveElapsed();
        if (elapsed < LUNGE_MS || visible(-swing)) {
            return;
        }

        var rise = elapsed - LUNGE_MS;
        if (rise > FLASH_MS) {
            rise = FLASH_MS;
        }

        // Rises within the sprite's own band, so it never reaches the HP line or the result text.
        var lift = ((rise * (height * 0.08)) / FLASH_MS).toNumber();
        var x = (swing > 0) ? enemyX(dc) : playerX(dc);

        Theme.ink(dc);
        dc.drawText(x, height * 0.38 - lift, Graphics.FONT_TINY, "-" + result.damage.toString(),
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
        dc.drawText(centerX, height * 0.91, Graphics.FONT_XTINY, clash,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawDamageNumber(dc, height, result);

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
            battleBanner(dc, centerX, height * 0.80, message, Graphics.FONT_TINY);
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
            battleBanner(dc, centerX, height * 0.62, "VICTORY", Graphics.FONT_SMALL);
        } else {
            Theme.ink(dc);
            dc.drawText(centerX, height * 0.62, Graphics.FONT_SMALL, "DEFEAT",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var sign = (_experienceDelta >= 0) ? "+" : "";
        var line = sign + _experienceDelta.toString() + " XP";
        if (_levelChanged) {
            line += won ? "  LV UP" : "  LV DN";
        }

        Theme.muted(dc);
        dc.drawText(centerX, height * 0.75, Graphics.FONT_XTINY, line,
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
            dc.drawText(centerX, height * 0.87, Graphics.FONT_XTINY, footer,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
