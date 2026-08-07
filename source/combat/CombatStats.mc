import Toybox.Lang;

module Combat {

    // Attack indices. IDLE is not selectable — it is what a disobeying creature does instead.
    enum {
        ATTACK_ENERGY = 0,
        ATTACK_CRUSH = 1,
        ATTACK_ABILITY = 2,
        ATTACK_IDLE = 3
    }

    // Turn outcomes.
    enum {
        WINNER_PLAYER = 0,
        WINNER_ENEMY = 1,
        WINNER_TIE = 2
    }

    //! A creature's live combat stats. HP is mutable; EN/CR/AB double as attack-selection weights
    //! and as the raw damage each attack deals.
    class CombatStats {
        public var hp as Number;
        public var maxHp as Number;
        public var energy as Number;
        public var crush as Number;
        public var ability as Number;

        function initialize(hp as Number, energy as Number, crush as Number, ability as Number) {
            self.hp = hp;
            self.maxHp = hp;
            self.energy = energy;
            self.crush = crush;
            self.ability = ability;
        }

        //! Damage this creature deals with the given attack index. IDLE deals nothing.
        function attackDamage(attackIndex as Number) as Number {
            if (attackIndex == ATTACK_ENERGY) {
                return energy;
            }
            if (attackIndex == ATTACK_CRUSH) {
                return crush;
            }
            if (attackIndex == ATTACK_ABILITY) {
                return ability;
            }
            return 0;
        }

        //! Energy is bucketed into ranks. In a mirror energy clash the higher rank wins outright,
        //! regardless of how small the raw stat gap is.
        function energyRank() as Number {
            var cutoffs = [20, 30, 45, 60, 75, 90, 105, 120, 135, 150, 175, 200, 225, 250, 275];
            for (var i = 0; i < cutoffs.size(); i += 1) {
                if (energy < cutoffs[i]) {
                    return i;
                }
            }
            return cutoffs.size();
        }

        function applyDamage(amount as Number) as Void {
            hp -= amount;
            if (hp < 0) {
                hp = 0;
            }
        }

        function isDown() as Boolean {
            return hp <= 0;
        }

        //! HP as a 0.0 .. 1.0 fraction, for bar rendering.
        function hpFraction() as Float {
            if (maxHp <= 0) {
                return 0.0;
            }
            var fraction = hp.toFloat() / maxHp.toFloat();
            return (fraction < 0.0) ? 0.0 : fraction;
        }
    }
}
