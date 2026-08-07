import Toybox.Lang;

module Combat {

    //! Damage gap below which a mirror-match exchange is a stalemate instead of a hit.
    const TIE_DAMAGE_THRESHOLD = 5;

    //! Call points available per battle. The summon-cost table is scaled against this pool.
    const STARTING_CALL_POINTS = 10;

    //! What happened in a single exchange. Purely descriptive — the engine has already applied it.
    class TurnResult {
        public var playerAttack as Number;   // the attack actually thrown, after disobedience
        public var chosenAttack as Number;   // what the player asked for
        public var enemyAttack as Number;
        public var winner as Number;         // WINNER_PLAYER | WINNER_ENEMY | WINNER_TIE
        public var damage as Number;
        public var disobeyed as Boolean;
        public var battleOver as Boolean;

        function initialize() {
            playerAttack = ATTACK_IDLE;
            chosenAttack = ATTACK_IDLE;
            enemyAttack = ATTACK_IDLE;
            winner = WINNER_TIE;
            damage = 0;
            disobeyed = false;
            battleOver = false;
        }
    }

    //! Picks the enemy's attack. Weighting each option by its own damage stat makes a creature
    //! favour what it is good at without ever becoming fully predictable.
    class AttackChooser {
        private var _rng as Rng;
        private var _stats as CombatStats;

        function initialize(rng as Rng, stats as CombatStats) {
            _rng = rng;
            _stats = stats;
        }

        function next() as Number {
            var weightEnergy = 30 + _stats.energy;
            var weightCrush = 30 + _stats.crush;
            var weightAbility = 30 + _stats.ability;

            var roll = _rng.nextInt(weightEnergy + weightCrush + weightAbility);
            if (roll < weightEnergy) {
                return ATTACK_ENERGY;
            }
            if (roll < weightEnergy + weightCrush) {
                return ATTACK_CRUSH;
            }
            return ATTACK_ABILITY;
        }
    }

    //! One battle. Construct it, call takeTurn() until isOver(), then read the winner.
    //!
    //! Combat is rock-paper-scissors over three attacks: Crush beats Energy, Energy beats Ability,
    //! Ability beats Crush. The winner of an exchange deals its own attack stat as damage; the loser
    //! deals nothing. Same-attack clashes are resolved by stat gap instead of by the wheel.
    class BattleEngine {
        private var _playerSpecies as Creature;
        private var _enemySpecies as Creature;
        private var _playerStats as CombatStats;
        private var _enemyStats as CombatStats;
        private var _playerLevel as Number;
        private var _enemyLevel as Number;
        private var _rng as Rng;
        private var _chooser as AttackChooser;
        private var _turns as Number;
        private var _callPoints as Number;
        private var _called as Array<String>;
        private var _spiritPower as Number;
        private var _hostSpecies as Creature?;      // who to return to when a spirit collapses
        private var _hostExtraLevel as Number;
        private var _spiritCollapsed as Boolean;    // set for the turn a form breaks

        function initialize(
            playerSpecies as Creature,
            playerExtraLevel as Number,
            enemySpecies as Creature,
            playerLevel as Number,
            rng as Rng
        ) {
            _playerSpecies = playerSpecies;
            _enemySpecies = enemySpecies;
            _playerLevel = playerLevel;
            _enemyLevel = enemySpecies.enemyLevel(playerLevel);
            _playerStats = playerSpecies.friendlyStats(playerExtraLevel);
            _enemyStats = enemySpecies.enemyStats(playerLevel);
            _rng = rng;
            _chooser = new AttackChooser(rng, _enemyStats);
            _turns = 0;
            _callPoints = STARTING_CALL_POINTS;

            // The creature already on the field counts as called, so it cannot be re-summoned to
            // refill its own HP.
            _called = [playerSpecies.key] as Array<String>;

            _spiritPower = 0;
            _hostSpecies = null;
            _hostExtraLevel = 0;
            _spiritCollapsed = false;
        }

        function playerStats() as CombatStats { return _playerStats; }
        function enemyStats() as CombatStats { return _enemyStats; }
        function playerSpecies() as Creature { return _playerSpecies; }
        function enemySpecies() as Creature { return _enemySpecies; }
        function playerLevel() as Number { return _playerLevel; }
        function enemyLevel() as Number { return _enemyLevel; }
        function turnCount() as Number { return _turns; }

        function callPoints() as Number { return _callPoints; }

        //! Spirit power is the player's, not the battle's — the caller seeds it before the fight
        //! and writes back whatever is left afterwards.
        function spiritPower() as Number { return _spiritPower; }

        function setSpiritPower(value as Number) as Void {
            var capped = value;
            if (capped > Spirit.MAX_POWER) { capped = Spirit.MAX_POWER; }
            if (capped < 0) { capped = 0; }
            _spiritPower = capped;
        }

        //! True while a borrowed form is on the field.
        function isSpiritActive() as Boolean {
            return _hostSpecies != null;
        }

        //! Set for the single turn on which a form ran out of power and broke.
        function spiritCollapsed() as Boolean {
            return _spiritCollapsed;
        }

        function spiritCost(species as Creature) as Number {
            return Spirit.cost(species, _playerLevel);
        }

        //! A form can be entered when it is affordable, the fight is live, and no form is already
        //! held — spirits do not stack.
        function canInvokeSpirit(species as Creature) as Boolean {
            if (isOver() || isSpiritActive() || !species.isSpirit()) {
                return false;
            }
            return spiritCost(species) <= _spiritPower;
        }

        //! Enter a spirit form. The current fighter is set aside, not lost: when the form breaks it
        //! comes back carrying the same share of its health that the spirit had left, so a
        //! transformation can neither be used to heal nor to shrug off a beating for free.
        function invokeSpirit(species as Creature, hostExtraLevel as Number) as Boolean {
            if (!canInvokeSpirit(species)) {
                return false;
            }

            _spiritPower -= spiritCost(species);
            _hostSpecies = _playerSpecies;
            _hostExtraLevel = hostExtraLevel;

            _playerSpecies = species;
            _playerStats = Spirit.stats(species, _playerLevel);
            return true;
        }

        //! Drop the borrowed form and restore the creature underneath it.
        function breakSpirit() as Void {
            var host = _hostSpecies;
            if (host == null) {
                return;
            }

            var retained = _playerStats.hpFraction();
            var restored = host.friendlyStats(_hostExtraLevel);

            var hp = (restored.maxHp * retained).toNumber();
            if (hp < 1) {
                hp = 1;   // surviving the collapse is the point; the fight continues
            }
            restored.hp = hp;

            _playerSpecies = host;
            _playerStats = restored;
            _hostSpecies = null;
            _hostExtraLevel = 0;
        }

        function isOver() as Boolean {
            return _playerStats.isDown() || _enemyStats.isDown();
        }

        //! Call points needed to bring this species in, from how it compares to the player.
        function summonCost(species as Creature) as Number {
            return species.summonCost(_playerLevel);
        }

        //! True once a species has been on the field this battle. Each one gets a single call.
        function hasBeenCalled(key as String) as Boolean {
            for (var i = 0; i < _called.size(); i += 1) {
                if (_called[i].equals(key)) {
                    return true;
                }
            }
            return false;
        }

        function canSummon(species as Creature) as Boolean {
            if (isOver()) {
                return false;
            }
            if (hasBeenCalled(species.key)) {
                return false;
            }
            return summonCost(species) <= _callPoints;
        }

        //! Bring a fresh creature onto the field. It arrives at full health, the enemy keeps the
        //! damage it has taken, and no turn is spent — the cost is the call points and the fact
        //! that each species can only ever be called once per battle.
        //!
        //! Obedience is judged against whoever is currently fighting, so calling something far
        //! above the player's standing buys power at the price of control.
        function summon(species as Creature, extraLevel as Number) as Boolean {
            if (!canSummon(species)) {
                return false;
            }

            _callPoints -= summonCost(species);
            _called.add(species.key);

            _playerSpecies = species;
            _playerStats = species.friendlyStats(extraLevel);
            return true;
        }

        //! WINNER_PLAYER, WINNER_ENEMY, or WINNER_TIE while the battle is still running.
        function outcome() as Number {
            if (_enemyStats.isDown()) {
                return WINNER_PLAYER;
            }
            if (_playerStats.isDown()) {
                return WINNER_ENEMY;
            }
            return WINNER_TIE;
        }

        //! Resolve one exchange with the attack the player selected.
        function takeTurn(chosenAttack as Number) as TurnResult {
            var result = new TurnResult();
            result.chosenAttack = chosenAttack;

            if (isOver()) {
                result.battleOver = true;
                result.winner = outcome();
                return result;
            }

            _turns += 1;

            var playerAttack = chosenAttack;
            var disobeyed = false;

            // A creature far above the player's standing may refuse to act, or act on its own idea.
            if (!_rng.chance(_playerSpecies.actChance(_playerLevel))) {
                playerAttack = ATTACK_IDLE;
                disobeyed = true;
            } else if (!_rng.chance(_playerSpecies.obeyChance(_playerLevel))) {
                playerAttack = _rng.nextInt(3);
                disobeyed = true;
            }

            var enemyAttack = _chooser.next();

            result.playerAttack = playerAttack;
            result.enemyAttack = enemyAttack;
            result.disobeyed = disobeyed;

            var damage = 0;
            var winner = resolveExchange(playerAttack, enemyAttack);
            if (winner == WINNER_PLAYER) {
                damage = exchangeDamage(playerAttack, enemyAttack, true);
                _enemyStats.applyDamage(damage);
            } else if (winner == WINNER_ENEMY) {
                damage = exchangeDamage(playerAttack, enemyAttack, false);
                _playerStats.applyDamage(damage);
            }

            result.winner = winner;
            result.damage = damage;

            // Holding a form costs power every turn. When it runs dry the form breaks — but only
            // after the turn resolves, so the spirit still lands the blow it was paying for.
            applySpiritDrain();

            result.battleOver = isOver();
            return result;
        }

        //! Bill the turn's upkeep against a held form, breaking it if the power is gone.
        //! The ancient form is exempt: it costs everything up front and nothing thereafter.
        private function applySpiritDrain() as Void {
            _spiritCollapsed = false;

            if (!isSpiritActive() || !Spirit.drains(_playerSpecies)) {
                return;
            }

            _spiritPower -= Spirit.DRAIN_PER_TURN;
            if (_spiritPower <= 0) {
                _spiritPower = 0;
                breakSpirit();
                _spiritCollapsed = true;
            }
        }

        //! Who wins the exchange, ignoring how much it hurts.
        private function resolveExchange(playerAttack as Number, enemyAttack as Number) as Number {
            // An idle creature simply eats the hit.
            if (playerAttack == ATTACK_IDLE) {
                return WINNER_ENEMY;
            }
            if (enemyAttack == ATTACK_IDLE) {
                return WINNER_PLAYER;
            }

            if (playerAttack == enemyAttack) {
                return resolveMirror(playerAttack);
            }

            return beats(playerAttack, enemyAttack) ? WINNER_PLAYER : WINNER_ENEMY;
        }

        //! Same attack on both sides: raw stats decide it, not the wheel.
        private function resolveMirror(attack as Number) as Number {
            var playerDamage = _playerStats.attackDamage(attack);
            var enemyDamage = _enemyStats.attackDamage(attack);

            // Energy clashes compare rank first, so a rank advantage beats a narrow stat deficit.
            if (attack == ATTACK_ENERGY) {
                var playerRank = _playerStats.energyRank();
                var enemyRank = _enemyStats.energyRank();
                if (playerRank != enemyRank) {
                    return (playerRank > enemyRank) ? WINNER_PLAYER : WINNER_ENEMY;
                }
            }

            var difference = playerDamage - enemyDamage;
            if (difference >= TIE_DAMAGE_THRESHOLD) {
                return WINNER_PLAYER;
            }
            if (difference <= -TIE_DAMAGE_THRESHOLD) {
                return WINNER_ENEMY;
            }
            return WINNER_TIE;
        }

        //! Damage for a decided exchange. A mirror clash deals only the stat gap; anything else
        //! deals the winner's full attack stat.
        private function exchangeDamage(
            playerAttack as Number,
            enemyAttack as Number,
            playerWon as Boolean
        ) as Number {
            if (playerAttack == enemyAttack && playerAttack != ATTACK_IDLE) {
                var gap = _playerStats.attackDamage(playerAttack) - _enemyStats.attackDamage(enemyAttack);
                return (gap < 0) ? -gap : gap;
            }
            var damage = playerWon
                ? _playerStats.attackDamage(playerAttack)
                : _enemyStats.attackDamage(enemyAttack);
            return (damage < 0) ? 0 : damage;
        }

        //! The type wheel: Crush beats Energy, Energy beats Ability, Ability beats Crush.
        static function beats(attack as Number, other as Number) as Boolean {
            if (attack == ATTACK_CRUSH && other == ATTACK_ENERGY) { return true; }
            if (attack == ATTACK_ENERGY && other == ATTACK_ABILITY) { return true; }
            if (attack == ATTACK_ABILITY && other == ATTACK_CRUSH) { return true; }
            return false;
        }

        static function attackName(attack as Number) as String {
            if (attack == ATTACK_ENERGY) { return "ENERGY"; }
            if (attack == ATTACK_CRUSH) { return "CRUSH"; }
            if (attack == ATTACK_ABILITY) { return "ABILITY"; }
            return "IDLE";
        }
    }
}
