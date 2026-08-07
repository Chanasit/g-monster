import Toybox.Lang;
import Toybox.Math;

module Combat {

    //! Spirit forms: temporary transformations bought with spirit power.
    //!
    //! A spirit is not a party member. It cannot be recruited, never appears as a wild encounter,
    //! and is not something the player owns — it is a state the current fighter enters mid-battle.
    //! The trade is deliberate: a spirit hits far above the player's own creatures, but every form
    //! except the ancient one burns power each turn and collapses when that runs dry.
    module Spirit {

        // Form classes, ordered by what they cost to hold.
        enum {
            TYPE_NONE = 0,
            TYPE_MINOR = 1,
            TYPE_WARRIOR = 2,
            TYPE_BEAST = 3,
            TYPE_FUSED = 4,
            TYPE_ANCIENT = 5
        }

        //! Spirit power ceiling.
        const MAX_POWER = 99;

        //! Power burned per turn while holding a draining form.
        const DRAIN_PER_TURN = 1;

        //! Map the JSON `spirit` field onto a form class.
        function typeFromName(name as String?) as Number {
            if (name == null) {
                return TYPE_NONE;
            }
            if (name.equals("minor")) { return TYPE_MINOR; }
            if (name.equals("warrior")) { return TYPE_WARRIOR; }
            if (name.equals("beast")) { return TYPE_BEAST; }
            if (name.equals("fused")) { return TYPE_FUSED; }
            if (name.equals("ancient")) { return TYPE_ANCIENT; }
            return TYPE_NONE;
        }

        function typeName(spiritType as Number) as String {
            if (spiritType == TYPE_MINOR) { return "MINOR"; }
            if (spiritType == TYPE_WARRIOR) { return "WARRIOR"; }
            if (spiritType == TYPE_BEAST) { return "BEAST"; }
            if (spiritType == TYPE_FUSED) { return "FUSED"; }
            if (spiritType == TYPE_ANCIENT) { return "ANCIENT"; }
            return "NONE";
        }

        //! Cost at level zero, before the player's own standing discounts it.
        function baseCost(spiritType as Number) as Number {
            if (spiritType == TYPE_MINOR) { return 10; }
            if (spiritType == TYPE_WARRIOR) { return 20; }
            if (spiritType == TYPE_BEAST) { return 30; }
            if (spiritType == TYPE_FUSED) { return 35; }
            if (spiritType == TYPE_ANCIENT) { return 40; }
            return 0;
        }

        //! Levels over which a form's cost halves. Bigger forms discount more slowly, so the
        //! ancient one stays a genuine investment long after the lesser forms are routine.
        function decay(spiritType as Number) as Number {
            if (spiritType == TYPE_MINOR) { return 20; }
            if (spiritType == TYPE_WARRIOR) { return 30; }
            if (spiritType == TYPE_BEAST) { return 30; }
            if (spiritType == TYPE_FUSED) { return 40; }
            if (spiritType == TYPE_ANCIENT) { return 50; }
            return 0;
        }

        //! What holding this form costs the player right now: the base cost halved once per
        //! `decay` levels. Growing into a form is what makes it affordable, never free — the floor
        //! is one, so a spirit always costs something.
        function cost(species as Creature, playerLevel as Number) as Number {
            if (!isSpirit(species)) {
                return 0;
            }

            var spiritType = species.spiritType;
            var halvings = playerLevel.toFloat() / decay(spiritType).toFloat();
            var scaled = baseCost(spiritType) * Math.pow(0.5, halvings);

            var result = Math.floor(scaled).toNumber();
            return (result < 1) ? 1 : result;
        }

        function isSpirit(species as Creature) as Boolean {
            return species.spiritType != TYPE_NONE;
        }

        //! Whether holding this form burns power each turn. The ancient form does not — that is
        //! what its far higher entry cost buys.
        function drains(species as Creature) as Boolean {
            return isSpirit(species) && species.spiritType != TYPE_ANCIENT;
        }

        //! A spirit's stats scale off the player's level rather than its own growth, since a spirit
        //! is borrowed rather than raised. This reuses the same curve enemies are built on.
        function stats(species as Creature, playerLevel as Number) as CombatStats {
            return species.enemyStats(playerLevel);
        }

        //! Every form defined in the data, cheapest first.
        function forms() as Array<Creature> {
            var all = Bestiary.all();
            var list = [] as Array<Creature>;
            for (var i = 0; i < all.size(); i += 1) {
                if (isSpirit(all[i])) {
                    list.add(all[i]);
                }
            }
            return list;
        }
    }
}
