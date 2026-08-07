import Toybox.Application;
import Toybox.Lang;

module Combat {

    //! The species table and the encounter roll.
    //!
    //! Data lives in `resources/data/creatures.json` and `rarities.json`, not in code — swapping in
    //! a different roster is an edit to those files. Rarity is kept in its own file so a species can
    //! be re-tiered without touching its stat line. Both are parsed once, on first use, and cached
    //! for the life of the process.
    module Bestiary {

        var _species as Array<Creature>?;

        //! All species, ordered by base level.
        function all() as Array<Creature> {
            var cached = _species;
            if (cached != null) {
                return cached;
            }

            var records = Application.loadResource(Rez.JsonData.Creatures) as Array;
            var rarities = Application.loadResource(Rez.JsonData.Rarities) as Dictionary;

            var list = [] as Array<Creature>;
            for (var i = 0; i < records.size(); i += 1) {
                list.add(parseCreature(records[i] as Dictionary, rarities));
            }

            _species = list;
            return list;
        }

        //! One JSON record into a Creature. A species missing from rarities.json falls back to
        //! common rather than failing the whole load.
        function parseCreature(record as Dictionary, rarities as Dictionary) as Creature {
            var key = record["key"] as String;
            var stats = record["stats"] as Dictionary;

            var rarity = rarities[key];
            if (rarity == null) {
                rarity = RARITY_COMMON;
            }

            var species = new Creature(
                key,
                record["name"] as String,
                record["stage"] as Number,
                rarity as Number,
                record["baseLevel"] as Number,
                [
                    stats["HP"] as Number,
                    stats["EN"] as Number,
                    stats["CR"] as Number,
                    stats["AB"] as Number
                ],
                record["evolvesTo"] as String?
            );

            // Absent `spirit` field means an ordinary creature.
            species.spiritType = Spirit.typeFromName(record["spirit"] as String?);
            return species;
        }

        //! The species a new game may start with.
        function starters() as Array<String> {
            var raw = Application.loadResource(Rez.JsonData.Starters) as Array;
            var list = [] as Array<String>;
            for (var i = 0; i < raw.size(); i += 1) {
                list.add(raw[i] as String);
            }
            return list;
        }

        //! The lead a fresh save begins with.
        function defaultStarter() as String {
            var list = starters();
            if (list.size() == 0) {
                return all()[0].key;
            }
            return list[0];
        }

        function get(key as String) as Creature? {
            var list = all();
            for (var i = 0; i < list.size(); i += 1) {
                if (list[i].key.equals(key)) {
                    return list[i];
                }
            }
            return null;
        }

        //! How far from the player's level an encounter may stray. The band widens as the player
        //! climbs so high-level play does not collapse onto a handful of species.
        function encounterBand(playerLevel as Number) as Number {
            if (playerLevel <= 2) { return 3; }
            if (playerLevel <= 4) { return 4; }
            if (playerLevel <= 10) { return 7; }
            if (playerLevel <= 60) { return 10; }
            if (playerLevel <= 80) { return 20; }
            return 40;
        }

        function rarityWeight(rarity as Number) as Float {
            if (rarity == RARITY_COMMON) { return 10.0; }
            if (rarity == RARITY_RARE) { return 6.0; }
            if (rarity == RARITY_EPIC) { return 3.0; }
            return 1.0;
        }

        //! The highest-level creature that may legitimately be met in the wild.
        function toughestEncounterable() as Creature {
            var list = all();
            var best = null as Creature?;

            for (var i = 0; i < list.size(); i += 1) {
                var species = list[i];
                if (species.isSpirit()) {
                    continue;
                }
                if (best == null || species.baseLevel > (best as Creature).baseLevel) {
                    best = species;
                }
            }

            // Only reachable if the data contains nothing but spirits.
            return (best == null) ? list[0] : best;
        }

        //! Weighted encounter roll. Candidates must sit inside the level band; within it, weight
        //! falls off linearly with distance from the player's level and by rarity. Level-matched
        //! commons dominate, and the 1.1 offset keeps band-edge species from hitting zero weight.
        function randomEncounter(playerLevel as Number, rng as Rng) as Creature {
            var list = all();
            var band = encounterBand(playerLevel);

            var candidates = [] as Array<Creature>;
            var weights = [] as Array<Float>;
            var totalWeight = 0.0;

            for (var i = 0; i < list.size(); i += 1) {
                var species = list[i];

                // Spirits are transformations, not inhabitants — they are never found in the wild.
                if (species.isSpirit()) {
                    continue;
                }

                var levelDiff = species.baseLevel - playerLevel;
                var distance = (levelDiff < 0) ? -levelDiff : levelDiff;

                if (distance >= band) {
                    continue;
                }

                var weight = (1.1 - (distance.toFloat() / band.toFloat())) * rarityWeight(species.rarity);
                if (weight <= 0.0) {
                    continue;
                }

                candidates.add(species);
                weights.add(weight);
                totalWeight += weight;
            }

            // Nothing in band (very high player level, sparse table): fall back to the toughest
            // ordinary creature. Found by scanning rather than taking the last entry — the table
            // is not guaranteed sorted, and its tail is spirits, which must never be encountered.
            if (candidates.size() == 0) {
                return toughestEncounterable();
            }

            var roll = rng.nextFloat() * totalWeight;
            var running = 0.0;
            for (var i = 0; i < candidates.size(); i += 1) {
                running += weights[i];
                if (roll < running) {
                    return candidates[i];
                }
            }
            return candidates[candidates.size() - 1];
        }
    }
}
