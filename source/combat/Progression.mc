import Toybox.Lang;
import Toybox.Math;

module Combat {

    //! Pure experience math. No storage, no side effects — callers own the persistence.
    module Progression {

        const MAX_EXPERIENCE = 1000000;

        //! Level is the cube root of experience, so each level costs progressively more.
        function levelFromExperience(experience as Number) as Number {
            if (experience <= 0) {
                return 1;
            }
            var level = Math.floor(Math.pow(experience.toDouble(), 1.0 / 3.0)).toNumber();
            return (level < 1) ? 1 : level;
        }

        //! Experience at which the given level begins.
        function experienceForLevel(level as Number) as Number {
            return level * level * level;
        }

        //! Progress through the current level, 0.0 .. 1.0.
        function levelProgress(experience as Number) as Float {
            var level = levelFromExperience(experience);
            var floorXp = experienceForLevel(level);
            var topXp = experienceForLevel(level + 1);
            var span = topXp - floorXp;
            if (span <= 0) {
                return 0.0;
            }
            var progress = (experience - floorXp).toFloat() / span.toFloat();
            if (progress < 0.0) { return 0.0; }
            if (progress > 1.0) { return 1.0; }
            return progress;
        }

        //! Experience awarded for a win. The (enemy/combined) ratio term decays sharply once the
        //! player's creature outlevels the enemy, while the trailing factor scales the whole award
        //! with the winner's own level so late-game fights still move the bar.
        function experienceForWin(friendlyLevel as Number, enemyLevel as Number) as Number {
            var a = 30.0 * enemyLevel;
            var b = Math.pow((2 * enemyLevel) + 10, 2.5);
            var c = Math.pow(enemyLevel + friendlyLevel + 10, 2.5);
            var d = 0.025 + (0.025 * friendlyLevel);
            if (d > 0.5) {
                d = 0.5;
            }
            if (c <= 0) {
                return 1;
            }
            var gained = Math.ceil(((a * (b / c)) + 1) * d).toNumber();
            return (gained < 1) ? 1 : gained;
        }

        //! Experience lost on a defeat: a fraction of the enemy's worth, never more than the
        //! current level's whole span.
        function experienceForLoss(friendlyLevel as Number, enemyLevel as Number) as Number {
            var full = experienceForWin(friendlyLevel, enemyLevel);
            var penalty = Math.ceil(full * 0.6).toNumber();
            return (penalty < 1) ? 1 : penalty;
        }
    }
}
