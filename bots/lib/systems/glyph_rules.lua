-- Pure rules for the Glyph of Fortification (UseGlyphIfNeeded in ability_item_usage_generic.lua, #12): plain values
-- in, so tests/test_glyph_rules.lua can check them without the bot API.
--
-- 7.42 Glyph, from the game files and Valve's patch notes:
-- - Tooltip `DOTA_Tooltip_ability_fountain_glyph*` (abilities_english localization in pak01_dir.vpk,
--   7.42): structures and lane creeps become invulnerable ("Impervious to damage", modifier_fountain_glyph),
--   structures for 7s, lane creeps for 3s; towers get multishot with 5 additional targets, tier 1 towers excluded;
--   2 charges. The towers keep attacking while invulnerable (that is what the multishot is for).
-- - Patch notes 7.42 (https://www.dota2.com/datafeed/patchnotes?version=7.42&language=english): "Now has 2 charges
--   with a 6 minute replenish time and a 7s cooldown between uses", and it no longer resets when buildings die.
-- - Tower attack range 700 (scripts/npc/npc_units.txt, npc_dota_goodguys_tower2_mid "AttackRange" "700").
local GlyphRules = {}

GlyphRules.CHARGES = 2
GlyphRules.CHARGE_TIME = 360 -- 6 minute replenish (7.42 patch notes)
GlyphRules.TOWER_RANGE = 700 -- fallback when GetAttackRange() gives nothing
GlyphRules.RANGE_MARGIN = 150 -- enemies just outside the range are about to be in it (centre-to-centre distance)
GlyphRules.ALLY_RADIUS = 1200 -- our heroes this close to the tower count as fighting there
GlyphRules.TOWER_SAVE_HP = 0.36
GlyphRules.BUILDING_SAVE_HP = 0.5 -- melee barracks, the Ancient

-- Save case (unchanged values): a tower under 36% HP, a melee barracks or the Ancient under 50%, that an enemy hero
-- attacks. kind = "tower" or "building". Never while that building is already fortified (the next 2s tick would
-- otherwise spend the second charge: only 7s between uses).
function GlyphRules.ShouldSave(kind, hpRatio, targeted, fortified)
	if fortified or not targeted then
		return false
	end
	local limit = kind == "tower" and GlyphRules.TOWER_SAVE_HP or GlyphRules.BUILDING_SAVE_HP
	return hpRatio > 0 and hpRatio < limit
end

-- Enemy heroes needed inside the tower's range for a fight Glyph: 3, or every alive enemy when only 2 are alive.
-- nil when fewer than 2 enemies are alive (no fight Glyph against one hero).
function GlyphRules.EnemiesNeeded(aliveEnemies)
	if aliveEnemies >= 3 then
		return 3
	end
	if aliveEnemies == 2 then
		return 2
	end
	return nil
end

-- Any HP drop between two samples (2s apart) counts as the tower being hit.
function GlyphRules.HpFalling(prevHp, hp)
	return prevHp ~= nil and hp < prevHp
end

-- Fight case. f = { tier, enemies, aliveEnemies, allies, hit, charges, fortified }:
-- tier 1..4 of the tower; enemies = distinct enemy heroes inside its range (+ margin); allies = our heroes within
-- ALLY_RADIUS that attack those enemies or are hit by them; hit = an enemy hero or creep attacks the tower or its HP
-- fell since the last sample; charges = Glyph charges by our own count (GlyphRules.Charges).
-- Returns ok, reason (the reason says what blocked it).
function GlyphRules.ShouldFight(f)
	if f.fortified then
		return false, "fortified"
	end
	-- Tier 1 towers get no multishot (tooltip); the save case still covers a dying T1.
	if f.tier < 2 then
		return false, "tier1"
	end
	local need = GlyphRules.EnemiesNeeded(f.aliveEnemies)
	if need == nil or f.enemies < need then
		return false, "few-enemies"
	end
	if f.allies < 1 then
		return false, "no-allies"
	end
	if not f.hit then
		return false, "not-hit"
	end
	-- Keep one charge for a save: a fight Glyph only spends the first of the two charges.
	if f.charges < GlyphRules.CHARGES then
		return false, "reserve"
	end
	return true, "fight"
end

-- Own count of the team's Glyph charges (the bot API has GetGlyphCooldown but no charge count; only team slot 1
-- casts, and only when all five are bots, so our own casts are the only ones). Charges come back one at a time.
function GlyphRules.NewCharges()
	return { charges = GlyphRules.CHARGES, nextAt = nil }
end

function GlyphRules.Tick(state, now)
	while state.nextAt ~= nil and now >= state.nextAt do
		state.charges = state.charges + 1
		if state.charges < GlyphRules.CHARGES then
			state.nextAt = state.nextAt + GlyphRules.CHARGE_TIME
		else
			state.nextAt = nil
		end
	end
	return state.charges
end

function GlyphRules.Spend(state, now)
	GlyphRules.Tick(state, now)
	state.charges = math.max(0, state.charges - 1)
	if state.nextAt == nil then
		state.nextAt = now + GlyphRules.CHARGE_TIME
	end
end

return GlyphRules
