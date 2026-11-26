-- Pure rules for the neutral-item use rules in ability_item_usage_generic.lua (#116): plain numbers in, so
-- tests/test_neutral_items.lua can check them without the bot API.
local NeutralRules = {}

-- Mana Draught (tier 2). 7.42 scripts/npc/items.txt: AbilityBehavior "... NO_TARGET | OPTIONAL_UNIT_TARGET ...",
-- AbilityUnitTargetTeam FRIENDLY, AbilityUnitTargetType HERO, AbilityCastRange 650, AbilityCooldown 60,
-- mana_restore 90, mana_restore_pct 3; tooltip (abilities_english.txt): "Restores 90 + 3% of the caster's maximum
-- mana over 6 seconds. If the hero is attacked by an enemy hero or Roshan, the effect is lost. Hold Control to use
-- on an allied hero." Passive (same file): its cooldown runs 30% faster in water (water_acceleration 30).
-- It is given away only when the holder is at or above MANA_DRAUGHT_SELF_BELOW, the ally below
-- MANA_DRAUGHT_ALLY_BELOW and at least MANA_DRAUGHT_GAP lower, and the ally missing at least the whole restore.
-- Otherwise the holder drinks it itself whenever it misses at least one whole restore (ManaDraughtSelfWorth): it is
-- free and comes back in 60s, and a draught kept for "MP below half" sat unused for 10 minutes (#116, game 087:
-- Largo's MP never went below 0.65 in the 9.8 min he held it).
NeutralRules.MANA_DRAUGHT_SELF_BELOW = 0.5
NeutralRules.MANA_DRAUGHT_ALLY_BELOW = 0.3
NeutralRules.MANA_DRAUGHT_GAP = 0.3

-- The mana one draught restores: mana_restore + mana_restore_pct % of the caster's maximum mana.
function NeutralRules.ManaDraughtRestore(restoreFlat, restorePct, casterMaxMana)
	return (restoreFlat or 0) + (restorePct or 0) / 100 * (casterMaxMana or 0)
end

-- Whether the holder (mana ratio myMp) should give the draught to an ally (mana ratio allyMp, allyMissing mana
-- below his maximum), for a draught that restores `restore` mana.
function NeutralRules.ManaDraughtGiveWorth(myMp, allyMp, allyMissing, restore)
	return myMp >= NeutralRules.MANA_DRAUGHT_SELF_BELOW
		and allyMp < NeutralRules.MANA_DRAUGHT_ALLY_BELOW
		and myMp - allyMp >= NeutralRules.MANA_DRAUGHT_GAP
		and allyMissing >= restore
end

-- Whether the holder should drink it itself: it misses at least one whole restore (none of it is wasted), and it is
-- `calm`: no enemy hero close enough to hit it, not hit by a hero lately, not at Roshan. A hit from either ends the
-- effect, so a draught drunk in a fight is thrown away.
function NeutralRules.ManaDraughtSelfWorth(missing, restore, calm)
	return calm == true and (restore or 0) > 0 and (missing or 0) >= restore
end

return NeutralRules
