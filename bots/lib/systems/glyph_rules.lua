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

-- Second save Glyph (games 072 46:22/46:30, 081 23:26/23:34, 084 15:42/15:50 and 20:54/21:02, 085 60:26/60:36):
-- the 7s fortification (structures, tooltip DOTA_Tooltip_ability_fountain_glyph_duration_structures) and the 7s
-- cooldown between uses end together, so the next 2s tick saw the same dying building,
-- no modifier_fountain_glyph on it and the Glyph ready, and spent the second charge. With nobody of ours there or on
-- the way, that only delayed the fall by 7s (in games 081-085 each of those towers fell 2-5s after it ended), and the
-- spent charge then blocked the fight Glyph (`glyph-skip why=reserve`) for the next 6 minutes. Game 085 t=2760/2770
-- is the counter case: Shadow Fiend was at the tower and four defenders walked in, and the second Glyph kept the mid
-- T3 standing for 2 more minutes.
GlyphRules.USE_COOLDOWN = 7 -- 7s between uses (7.42 patch notes)
-- A save on the same building this soon after our last Glyph on it is a repeat on the same fight: 7s fortified plus
-- up to 13s of the enemies hitting it again.
GlyphRules.REPEAT_WINDOW = 20
-- An ally this close can reach the building within the 7s fortification: ~330 move speed x 7s = 2300 plus the
-- tower's 700 attack range to fight under it.
GlyphRules.HELP_RADIUS = 2800
-- A teleport of ours landing this close to the building counts as help (it lands under the tower; GetIncomingTeleports).
GlyphRules.TP_RADIUS = 1500

-- When a save needs help on the way: nil (no), "repeat" (our last Glyph on this building was under REPEAT_WINDOW s
-- ago) or "last-charge" (it would spend our last charge). The Ancient never needs it: losing it ends the game, and 7s
-- more can bring a respawn or a buyback. kind = "tower", "barracks" or "ancient"; charges = before this cast;
-- sinceSame = seconds since our last Glyph on this building (nil: none).
function GlyphRules.SaveNeedsHelp(kind, charges, sinceSame)
	if kind == "ancient" then
		return nil
	end
	if sinceSame ~= nil and sinceSame < GlyphRules.REPEAT_WINDOW then
		return "repeat"
	end
	if charges <= 1 then
		return "last-charge"
	end
	return nil
end

-- Spend a save Glyph? s = { kind, charges, sinceSame, allies, coming }: allies = our heroes fighting at the building
-- (GlyphAlliesFighting), coming = our heroes walking in from within HELP_RADIUS or teleporting in (GlyphHelpComing).
-- Returns ok, why ("save" or "no-help"), rule (what asked for help, or nil).
function GlyphRules.ShouldSpendSave(s)
	local rule = GlyphRules.SaveNeedsHelp(s.kind, s.charges, s.sinceSame)
	if rule ~= nil and s.allies < 1 and s.coming < 1 then
		return false, "no-help", rule
	end
	return true, "save", rule
end

-- Correct our charge count from GetGlyphCooldown(): above the 7s between uses it is the time until a charge comes
-- back, so none is left (game 085: Dire's own count gave a charge back at t=1884, the API said t=1980). At 0 at least
-- one is ready. Returns the count before the correction when it changed anything, else nil.
function GlyphRules.Sync(state, now, cd)
	local before = state.charges
	if cd > GlyphRules.USE_COOLDOWN + 0.5 then
		local nextAt = now + cd
		if state.charges ~= 0 or state.nextAt == nil or math.abs(state.nextAt - nextAt) > 3 then
			state.charges = 0
			state.nextAt = nextAt
			return before
		end
	elseif cd <= 0 and state.charges == 0 then
		state.charges = 1
		if state.nextAt == nil then
			state.nextAt = now + GlyphRules.CHARGE_TIME
		end
		return before
	end
	return nil
end

return GlyphRules
