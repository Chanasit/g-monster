import Toybox.Lang;

module Combat {

    //! Seedable linear congruential generator.
    //!
    //! The engine never touches Toybox.Math.rand() directly: every random decision goes through an
    //! Rng instance, so a battle replays identically from a stored seed and tests can pin outcomes.
    //! Background-scoped: the service rolls event gaps while the app is closed.
    (:background)
    class Rng {
        private const MULTIPLIER = 25214903917l;
        private const INCREMENT = 11l;
        private const MASK = 0xFFFFFFFFFFFFl; // 48 bits

        private var _state as Long;

        function initialize(seed as Number) {
            _state = (seed.toLong() ^ MULTIPLIER) & MASK;
        }

        //! Raw generator step returning the top `bits` bits of the state.
        private function next(bits as Number) as Number {
            _state = ((_state * MULTIPLIER) + INCREMENT) & MASK;
            return (_state >> (48 - bits)).toNumber();
        }

        //! Uniform integer in [0, bound). Returns 0 for a non-positive bound.
        function nextInt(bound as Number) as Number {
            if (bound <= 0) {
                return 0;
            }
            return next(31) % bound;
        }

        //! Uniform float in [0.0, 1.0).
        function nextFloat() as Float {
            return next(24) / 16777216.0;
        }

        //! True with probability `chance`. Chances >= 1 always hit, <= 0 never do.
        function chance(probability as Float) as Boolean {
            if (probability >= 1.0) {
                return true;
            }
            if (probability <= 0.0) {
                return false;
            }
            return nextFloat() < probability;
        }
    }
}
