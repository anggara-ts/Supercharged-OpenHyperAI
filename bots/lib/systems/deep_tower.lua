-- Shared bot system: the enemy tier-2-or-deeper tower a spot is in reach of, in the early game (#12, game 087
-- 0:26-0:31; the rule is TempoRules.DeepTowerBlocks). A T2 is invulnerable while its T1 stands, so the tower lists
-- the other checks read (bot:GetNearbyTowers filtered by Fu.IsValidBuilding, which skips invulnerable units) never
-- see it: this reads the tower handles by id. Callers: the laning harass and last hits (mode_laning_generic.lua), the
-- last-hit overlay (last_hit_overlay.lua) and the early-game anti-dive (mode_retreat_generic.lua).
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local TempoRules = require(GetScriptDirectory() .. "/lib/systems/tempo_rules")

local DeepTower = {}

local DEEP_IDS = nil
local function deepIds()
	if DEEP_IDS == nil then
		DEEP_IDS = {
			TOWER_TOP_2,
			TOWER_MID_2,
			TOWER_BOT_2,
			TOWER_TOP_3,
			TOWER_MID_3,
			TOWER_BOT_3,
			TOWER_BASE_1,
			TOWER_BASE_2,
		}
	end
	return DEEP_IDS
end

-- The first alive enemy tower of tier 2+ (invulnerable or not) that has one of the given locations in reach, in the
-- early game. Returns tower, dist (tower to that location); nil when none or after the early game.
function DeepTower.InReach(...)
	if not Fu.IsEarlyGame() then
		return nil
	end
	local count = select("#", ...)
	local enemyTeam = GetOpposingTeam()
	local ids = deepIds()
	for k = 1, #ids do
		local tower = GetTower(enemyTeam, ids[k])
		if tower ~= nil and not tower:IsNull() and tower:IsAlive() then
			-- The ids are tier 2+: a name the pattern does not read still counts as tier 2.
			local tier = TempoRules.TowerTier(tower:GetUnitName()) or 2
			local range = tower:GetAttackRange()
			for i = 1, count do
				local location = select(i, ...)
				if location ~= nil then
					local dist = GetUnitToLocationDistance(tower, location)
					if TempoRules.DeepTowerBlocks(tier, dist, range, true) then
						return tower, dist
					end
				end
			end
		end
	end
	return nil
end

-- [SHy-HARASS] t= <hero> skip why=deep-tower tower= invuln= dist= src=harass|reset|lasthit|overlay target=, at most
-- every 5s per bot (invuln=: whether the tower is invulnerable, which a T2 should be while its T1 stands).
function DeepTower.LogSkip(bot, src, tower, dist, target)
	if DotaTime() < (bot._deepTowerLogAt or -999) then
		return
	end
	bot._deepTowerLogAt = DotaTime() + 5
	pcall(
		print,
		string.format(
			"[SHy-HARASS] t=%.0f %s skip why=deep-tower tower=%s invuln=%s dist=%d src=%s target=%s",
			DotaTime(),
			(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
			(string.gsub(tower:GetUnitName(), "npc_dota_", "")),
			tostring(tower:IsInvulnerable()),
			math.floor(dist or -1),
			src,
			target ~= nil and not target:IsNull() and (string.gsub(target:GetUnitName(), "npc_dota_", "")) or "-"
		)
	)
end

return DeepTower
