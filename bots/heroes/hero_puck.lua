-- Puck: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local EscapeRules = require(GetScriptDirectory() .. "/lib/systems/escape_rules")
local DodgeRules = require(GetScriptDirectory() .. "/lib/systems/dodge_rules")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 0, 10 }, ["t20"] = { 0, 10 }, ["t15"] = { 10, 0 }, ["t10"] = { 0, 10 } }
local tAllAbilityBuildList = { { 1, 3, 1, 2, 1, 6, 1, 2, 2, 2, 6, 3, 3, 3, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sMagicImmuneItem = RandomInt(1, 2) == 1 and "item_black_king_bar" or "item_sphere"
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 50,775 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_magic_wand",
	"item_null_talisman",
	"item_power_treads",
	"item_witch_blade",
	"item_blink",
	"item_aghanims_shard",
	"item_devastator",
	sMagicImmuneItem,
	"item_ultimate_scepter",
	"item_greater_crit",
	"item_ultimate_scepter_2",
	"item_overwhelming_blink",
	"item_wind_waker",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1 has 251 matches, built from pos 2 (50,775) (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = sRoleItemsBuyList["pos_2"]
-- Stratz 7.41f, week of 9 Nov 2026: pos 3 has 532 matches, built from pos 2 (50,775) (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = sRoleItemsBuyList["pos_2"]
-- Pos 4/5: a support start (Stratz 7.41f pos 4, n=902: Tango 100%, Blood Grenade 47%, Magic Stick 47%,
-- Branches 70%) and the same core items (Blink 105%, Witch Blade 59%, Eul's 59%).
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 1,196 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_null_talisman",
	"item_magic_wand",
	"item_power_treads",
	"item_blink",
	"item_cyclone",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_octarine_core",
	"item_maelstrom",
	"item_mjollnir",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5 has 728 matches, built from pos 4 (1,196) (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = sRoleItemsBuyList["pos_4"]
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_black_king_bar", "item_quelling_blade" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_mid" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDeafaultAbility"] = false
-- Cast when cornered (retreating into 3+ enemies with no way out), before running further.
X["LastStandSpells"] = { { name = "puck_dream_coil", kind = "point" } }
X["bDeafaultItem"] = false
function X.MinionThink(minionUnit)
	Minion.MinionThink(minionUnit)
end
local illusoryOrbAbility = SafeAbility(bot:GetAbilityByName("puck_illusory_orb"), "puck_illusory_orb", "puck")
local waningRiftAbility = SafeAbility(bot:GetAbilityByName("puck_waning_rift"), "puck_waning_rift", "puck")
local phaseShiftAbility = SafeAbility(bot:GetAbilityByName("puck_phase_shift"), "puck_phase_shift", "puck")
local etherealJauntAbility = SafeAbility(bot:GetAbilityByName("puck_ethereal_jaunt"), "puck_ethereal_jaunt", "puck")
local dreamCoilAbility = SafeAbility(bot:GetAbilityByName("puck_dream_coil"), "puck_dream_coil", "puck")
local illusoryOrbDesire, illusoryOrbLocation
local waningRiftDesire, waningRiftLocation
local phaseShiftDesire
local etherealJauntDesire
local dreamCoilDesire, dreamCoilLocation
local phaseOrbDesire, phaseOrbLocation
local isOrbEscaping = false
local botTarget
local isGoingOnSomeone
local isRetreating
local isAttacking
local mpRatio
-- Diagnostic (#15): Phase Shift is channelled (game files: DOTA_ABILITY_BEHAVIOR_CHANNELLED), so any new order ends
-- it. Does Puck stay shifted for the full duration, or does the next mode order cut it short? One line per shift.
function X.TrackPhaseShift()
	if bot._phaseProbeAt ~= nil and DotaTime() >= bot._phaseProbeAt then
		local since = DotaTime() - (bot._phaseOrderAt or DotaTime())
		-- Two probes inside the shift: 0.3s after the order and 0.15s before its end (duration 1 / 1.75 / 2.5 /
		-- 3.25s). Game 051: the one probe at 1.0s came after a rank 1 shift was over, so it said nothing.
		bot._phaseProbeAt = since < 0.5
				and bot._phaseOrderAt + math.max(0.6, phaseShiftAbility:GetSpecialValueFloat("duration") - 0.15)
			or nil
		local mods = {}
		for i = 0, bot:NumModifiers() - 1 do
			mods[#mods + 1] = tostring(bot:GetModifierName(i))
		end
		local activeNow = bot:GetCurrentActiveAbility()
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase-probe after=%.1f moved=%d action=%s cd=%.1f invuln=%s damaged=%s channelling=%s active=%s mods=%s",
				DotaTime(),
				since,
				-- Distance from where she ordered the shift and what she is doing now: a move or another order
				-- inside the shift means something broke the channel.
				bot._phaseOrderLoc ~= nil and GetUnitToLocationDistance(bot, bot._phaseOrderLoc) or -1,
				tostring(bot:GetCurrentActionType()),
				phaseShiftAbility:GetCooldownTimeRemaining(),
				tostring(bot:IsInvulnerable()),
				tostring(X.HurtSincePhaseOrder()),
				tostring(bot:IsChanneling()),
				activeNow ~= nil and not activeNow:IsNull() and activeNow:GetName() or "-",
				table.concat(mods, ",")
			)
		)
	end
	local active = bot:IsChanneling() and bot:GetCurrentActiveAbility() or nil
	local channelling = active ~= nil and not active:IsNull() and active:GetName() == "puck_phase_shift"
	local shifted = bot:HasModifier("modifier_puck_phase_shift") or channelling
	local track = bot._phaseTrack
	if shifted and track == nil then
		bot._phaseTrack = {
			at = DotaTime(),
			full = phaseShiftAbility:GetSpecialValueFloat("duration"),
			mode = bot:GetActiveMode(),
			by = channelling and "channel" or "modifier",
		}
	elseif shifted and track ~= nil and not track.leftLogged and bot:GetActiveMode() ~= (BOT_MODE_OUTPOST or 26) then
		-- Game 057: 4 shifts inside the hold ended at 0.3-0.7s when the mode left the hold (to attack or roam). Which
		-- mode took over, with what desire, and whether the hold was still meant to run.
		track.leftLogged = true
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase hold-left after=%.2f mode=%d desire=%.2f hold-for=%.2f hurt=%s hold-desire=%.2f age=%.2f invuln=%s",
				DotaTime(),
				DotaTime() - track.at,
				bot:GetActiveMode(),
				bot:GetActiveModeDesire(),
				(bot._castHoldUntil or 0) - DotaTime(),
				tostring(X.HurtSincePhaseOrder()),
				bot._outpostLastDesire or -1,
				DotaTime() - (bot._outpostLastDesireAt or -99),
				tostring(bot:IsInvulnerable())
			)
		)
	elseif not shifted and track ~= nil then
		bot._phaseTrack = nil
		-- For the 2s offensive Rift block after a shift (X.OffensiveRiftBlocked).
		bot._phaseEndAt = DotaTime()
		bot._phaseEndEscape = bot._phaseCastEscape == true
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase held=%.2f of=%.2f mode=%d->%d hp=%.2f by=%s exit=%s",
				DotaTime(),
				DotaTime() - track.at,
				track.full or -1,
				track.mode or -1,
				bot:GetActiveMode(),
				Fu.GetHP(bot),
				track.by or "?",
				-- She ended it herself (X.ShiftExit): a short held= then is not a broken hold.
				bot._phaseExitHow or "-"
			)
		)
		bot._phaseExitHow = nil
	end
end
-- Escape order (#15, game 044, 38:47): Puck Eul'd herself against Pudge's hook while her orb flew away unused,
-- landed among 8 enemies, was rooted and died. Her own escapes come first: tell the generic self-Eul rule
-- (bot._puckEscapeReady) and Jaunt to an orb in flight when in danger. Jaunt is ROOT_DISABLES (game files), so it
-- has to come before a root.
function X.OrbInFlight()
	for _, projectile in pairs(GetLinearProjectiles() or {}) do
		if
			projectile ~= nil
			and projectile.ability ~= nil
			and projectile.ability:GetName() == "puck_illusory_orb"
			and not Fu.IsLocationInChrono(projectile.location)
		then
			return projectile.location
		end
	end
	return nil
end
function X.DangerJaunt()
	if
		not etherealJauntAbility:IsFullyCastable()
		or bot:IsRooted()
		or DotaTime() < (bot._dangerJauntAt or -999) + 3
	then
		return false
	end
	local orbAt = X.OrbInFlight()
	if orbAt == nil or GetUnitToLocationDistance(bot, orbAt) < 500 then
		return false
	end
	local enemiesHere = #Fu.GetEnemiesNearLoc(bot:GetLocation(), 900)
	local enemiesThere = #Fu.GetEnemiesNearLoc(orbAt, 700)
	local alliesHere = #Fu.GetAlliesNearLoc(bot:GetLocation(), 900)
	local danger = bot:WasRecentlyDamagedByAnyHero(1.5) and (enemiesHere > alliesHere or Fu.GetHP(bot) < 0.5)
		or Fu.IsStunProjectileIncoming(bot, 800)
	-- Only to an orb on the escape side (away from the nearest enemies, toward our fountain). Game 064, t=2600: a
	-- danger Jaunt took her to an orb flying away from base, and she died at 43:23 farther from the fountain.
	local here = bot:GetLocation()
	local _, dirX, dirY = X.EscapePoint(1)
	local escapeSide = EscapeRules.IsOnEscapeSide(here.x, here.y, orbAt.x, orbAt.y, dirX, dirY)
	if danger and enemiesThere < enemiesHere and not escapeSide then
		if DotaTime() >= (bot._jauntSideLogAt or -999) then
			bot._jauntSideLogAt = DotaTime() + 3
			pcall(
				print,
				string.format(
					"[SHy-PUCK] t=%.0f escape-order skip=jaunt why=wrong-side enemies=%d->%d hp=%.2f",
					DotaTime(),
					enemiesHere,
					enemiesThere,
					Fu.GetHP(bot)
				)
			)
		end
		return false
	end
	if danger and enemiesThere < enemiesHere then
		X.LogEscapeAction("jaunt", "danger", orbAt)
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f escape-order used=jaunt enemies=%d->%d hp=%.2f",
				DotaTime(),
				enemiesHere,
				enemiesThere,
				Fu.GetHP(bot)
			)
		)
		bot._dangerJauntAt = DotaTime()
		bot:Action_UseAbility(etherealJauntAbility)
		return true
	end
	return false
end
-- Diagnostic (#15, game 048 64:10: Puck used Eul, not Phase Shift or Blink). In danger, what escapes she has.
-- Blink: damage puts it on a 3s cooldown (game files: blink_damage_cooldown 3.0). Every 3s at most.
function X.LogEscapeCheck(orbOut, canCast)
	if
		DotaTime() < (bot._escapeCheckLogAt or -999)
		or not bot:WasRecentlyDamagedByAnyHero(1.5)
		or Fu.GetHP(bot) > 0.5
	then
		return
	end
	bot._escapeCheckLogAt = DotaTime() + 3
	local blinkItem = X.BlinkItem()
	local blinkCd = blinkItem ~= nil and blinkItem:GetCooldownTimeRemaining() or -1
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f escape-check hp=%.2f silenced=%s canCast=%s phaseCd=%.1f orbOut=%s jauntOk=%s rooted=%s blinkCd=%.1f blink=%s siphoned=%s ready=%s enemies=%d",
			DotaTime(),
			Fu.GetHP(bot),
			tostring(bot:IsSilenced()),
			tostring(canCast),
			phaseShiftAbility:GetCooldownTimeRemaining(),
			tostring(orbOut),
			tostring(etherealJauntAbility:IsFullyCastable()),
			tostring(bot:IsRooted()),
			blinkCd,
			X.BlinkState(blinkItem),
			tostring(bot:HasModifier("modifier_death_prophet_spirit_siphon_slow")),
			tostring(bot._puckEscapeReady),
			#Fu.GetEnemiesNearLoc(bot:GetLocation(), 1000)
		)
	)
end
-- Her Blink Dagger (or an upgrade) in the main slots, or nil.
function X.BlinkItem()
	for _, name in ipairs({ "item_blink", "item_overwhelming_blink", "item_swift_blink", "item_arcane_blink" }) do
		local slot = bot:FindItemSlot(name)
		if slot >= 0 and slot <= 5 then
			local item = bot:GetItemInSlot(slot)
			if item ~= nil and not item:IsNull() then
				return item
			end
		end
	end
	return nil
end
-- ready | damage-block (hero damage puts Blink on cooldown for blink_damage_cooldown 3.0s, 7.42 items) | cooldown
-- | none. Game 064, 43:18-43:23: blinkCd=3.0 twice, the block renewed by every hit.
function X.BlinkState(blinkItem)
	if blinkItem == nil then
		return "none"
	end
	local cd = blinkItem:GetCooldownTimeRemaining()
	if cd <= 0 then
		return "ready"
	end
	if cd <= 3.0 and bot:WasRecentlyDamagedByAnyHero(3.0) then
		return "damage-block"
	end
	return "cooldown"
end
-- Where safety is for an escape: the nearest standing allied tower within SAFE_TOWER_RANGE, else our fountain
-- (#36, game 071). Returns the location and "tower" | "fountain".
local SAFE_TOWER_RANGE = 5000
function X.SafePoint()
	local best, bestDist = nil, SAFE_TOWER_RANGE
	for id = TOWER_TOP_1 or 0, TOWER_BASE_2 or 10 do
		local okTower, tower = pcall(GetTower, GetTeam(), id)
		tower = okTower and tower or nil
		if tower ~= nil and not tower:IsNull() and tower:IsAlive() then
			local dist = GetUnitToUnitDistance(bot, tower)
			if dist < bestDist then
				best, bestDist = tower, dist
			end
		end
	end
	if best ~= nil then
		return best:GetLocation(), "tower"
	end
	return Fu.GetTeamFountain(), "fountain"
end
-- The point for an escape jump of `distance`: toward safety (X.SafePoint), bent away from the visible enemy heroes
-- within 1600 only inside that (EscapeRules.SafeDirection, game 071 34:06: the exit Orb went 547 farther from home).
-- The path check looks at least 600 ahead, so a short jump does not head into a threat behind it. Returns the point,
-- the unit direction and how (safe | bent | away | fallback, kept in bot._escapeHow for the escape-action line).
-- extraThreats: more { x, y } points to keep clear of (the tower in X.TowerEscape).
function X.EscapePoint(distance, extraThreats)
	local here = bot:GetLocation()
	local enemies = {}
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
			local at = enemyHero:GetLocation()
			enemies[#enemies + 1] = { x = at.x, y = at.y }
		end
	end
	-- Other threats to keep clear of, e.g. the enemy tower hitting her (X.TowerEscape): { x, y } points.
	for _, threat in ipairs(extraThreats or {}) do
		enemies[#enemies + 1] = threat
	end
	local safe, safeKind = X.SafePoint()
	local dx, dy, how = EscapeRules.SafeDirection(here.x, here.y, enemies, safe.x, safe.y, math.max(distance or 0, 600))
	bot._escapeHow = tostring(how) .. "/" .. tostring(safeKind)
	return Vector(here.x + dx * distance, here.y + dy * distance, here.z), dx, dy
end
-- One line per escape action (#36, game 064: no line named the escape action or where it went).
-- jump: how far the point is; home: distance to our fountain now -> from the point; nearest: the nearest enemy
-- hero and its distance now -> to the point.
function X.LogEscapeAction(spell, why, point)
	local here = bot:GetLocation()
	local fountain = Fu.GetTeamFountain()
	local nearest, nearestDist = nil, math.huge
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) then
			local dist = GetUnitToUnitDistance(bot, enemyHero)
			if dist < nearestDist then
				nearest, nearestDist = enemyHero, dist
			end
		end
	end
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f escape-action spell=%s why=%s to=%.0f,%.0f jump=%.0f home=%.0f->%.0f nearest=%s:%.0f->%.0f enemies=%d hp=%.2f blink=%s dir=%s",
			DotaTime(),
			spell,
			why,
			point.x,
			point.y,
			(point - here):Length2D(),
			(fountain - here):Length2D(),
			(fountain - point):Length2D(),
			nearest ~= nil and (string.gsub(nearest:GetUnitName(), "npc_dota_hero_", "")) or "-",
			nearest ~= nil and nearestDist or -1,
			nearest ~= nil and GetUnitToLocationDistance(nearest, point) or -1,
			#Fu.GetEnemiesNearLoc(here, 1200),
			Fu.GetHP(bot),
			X.BlinkState(X.BlinkItem()),
			-- How the last escape direction was picked (EscapeRules.SafeDirection) and toward what.
			tostring(bot._escapeHow or "-")
		)
	)
end
-- The enemy Death Prophet whose Spirit Siphon is on her (the slow modifier is on Puck: game 064 phase-probe mods=
-- ...modifier_death_prophet_spirit_siphon_slow), or nil. Within 1200 so a far one doesn't count.
function X.SiphonSource()
	if not bot:HasModifier("modifier_death_prophet_spirit_siphon_slow") then
		return nil
	end
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and enemyHero:GetUnitName() == "npc_dota_hero_death_prophet" then
			return enemyHero
		end
	end
	return nil
end
-- Under Spirit Siphon (game 064, 4:00: siphoned at 42% HP with Phase Shift ready, she used Waning Rift and TP'd home
-- at 29%, drained during the channel). The link breaks past EscapeRules.SIPHON_BREAK (750) from Death Prophet; a Rift
-- (350) doesn't get there. In danger: Orb away first (Orb and Rift can't be cast inside the shift), then Phase Shift
-- (ConsiderPhaseShift why=siphon) blocks the drain, and the Jaunt goes once the orb is past the break distance
-- (X.ShiftExit inside the shift, here otherwise). No TP while she has one of these escapes up (bot._noTpUntil, read
-- by the TP rule in ability_item_usage_generic.lua). Returns true when it gave an order.
function X.ConsiderSiphonEscape()
	local siphoner = X.SiphonSource()
	if siphoner == nil or not (Fu.GetHP(bot) < 0.7 or Fu.IsRetreating(bot)) then
		bot._siphonEscapeFrom = nil
		return false
	end
	local mana = bot:GetMana()
	local jauntReady = etherealJauntAbility:IsFullyCastable() and not bot:IsRooted()
	local orbReady = illusoryOrbAbility:IsFullyCastable() and jauntReady and mana >= illusoryOrbAbility:GetManaCost()
	local phaseReady = phaseShiftAbility:IsFullyCastable()
	if orbReady or phaseReady or bot._siphonEscapeFrom ~= nil then
		bot._noTpUntil = math.max(bot._noTpUntil or -999, DotaTime() + 0.5)
	end
	-- Orb and Phase Shift both down (game 067, 4:04: the Orb went on a lane harass, Phase was used): Waning Rift
	-- (max_distance 350, datafeed hero 13) toward home, then the walk out past the break distance.
	local riftReady = waningRiftAbility:IsFullyCastable()
		and not bot:IsRooted()
		and mana >= waningRiftAbility:GetManaCost()
		and not bot:HasModifier("modifier_puck_phase_shift")
	local skipWhy = "-"
	if not orbReady and not phaseReady then
		if not illusoryOrbAbility:IsFullyCastable() then
			skipWhy = "orb-cd"
		elseif not jauntReady then
			skipWhy = "jaunt-down"
		else
			skipWhy = "no-mana"
		end
	end
	if DotaTime() >= (bot._siphonLogAt or -999) then
		bot._siphonLogAt = DotaTime() + 3
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f siphoned dist=%d hp=%.2f orb=%s phase=%s jaunt=%s rift=%s skip=%s tp-held=%s",
				DotaTime(),
				GetUnitToUnitDistance(bot, siphoner),
				Fu.GetHP(bot),
				tostring(orbReady),
				tostring(phaseReady),
				tostring(jauntReady),
				tostring(riftReady),
				skipWhy,
				tostring(DotaTime() < (bot._noTpUntil or -999))
			)
		)
	end
	-- The orb is past the break distance: Jaunt to it.
	local orbAt = X.OrbInFlight()
	if
		bot._siphonEscapeFrom ~= nil
		and orbAt ~= nil
		and jauntReady
		and DotaTime() - (bot._siphonOrbAt or -999) < 3
		and GetUnitToLocationDistance(siphoner, orbAt) > EscapeRules.SIPHON_BREAK + 50
	then
		bot._siphonEscapeFrom = nil
		X.LogEscapeAction("jaunt", "siphon", orbAt)
		bot:Action_UseAbility(etherealJauntAbility)
		return true
	end
	if orbReady and DotaTime() - (bot._siphonOrbAt or -999) > 3 then
		local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
		local point = X.EscapePoint(castRange)
		bot._siphonOrbAt = DotaTime()
		bot._orbCastAt = DotaTime()
		bot._siphonEscapeFrom = siphoner
		X.LogEscapeAction("orb", "siphon", point)
		bot:Action_UseAbilityOnLocation(illusoryOrbAbility, point)
		return true
	end
	-- Hit by the drain in the last second only: no Rift for a link that is about to end.
	if not orbReady and not phaseReady and riftReady and bot:WasRecentlyDamagedByHero(siphoner, 1.0) then
		local riftDistance = waningRiftAbility:GetSpecialValueInt("max_distance")
		if riftDistance == nil or riftDistance <= 0 then
			riftDistance = 350
		end
		local point = X.EscapePoint(riftDistance - 10)
		X.LogEscapeAction("rift", "siphon", point)
		bot:Action_UseAbilityOnLocation(waningRiftAbility, point)
		return true
	end
	return false
end
-- A Phase Shift's hold ends early (she jumped out of it): free the item think, this script and the outpost hold.
function X.ReleasePhaseHold()
	bot._castHoldUntil = nil
	bot._phaseOrderAt = nil
	bot._phaseWantAt = nil
	bot._phaseProbeAt = nil
end
-- Inside the shift (only CastHoldTick runs then). Two ways out, each once per shift:
-- 1. Spirit Siphon: the orb she threw before the shift is past the break distance from Death Prophet: Jaunt to it.
-- 2. An escape shift with an Orb out: Jaunt to it (X.EscapeShiftJaunt).
-- 3. The shift's last 0.2s with an enemy on her: Blink away first, before a projectile that waited for the shift's
--    end lands and renews Blink's damage block (game 064, 43:16: Death Coil landed as the shift ended, tti=0.04,
--    and Blink read 3.0 for the rest of the fight).
-- An escape shift (bot._phaseCastEscape): Jaunt to the Orb so she is gone when the enemies waiting for the shift to
-- end hit (game 068: 7 of 10 deaths 1-3s after a shift in place). EscapeRules.ShiftJauntNow: early (from 0.15s when
-- no stun or projectile is due at her, from 0.5s anyway) once the Orb's spot passes X.ExitJauntCheck; else in the
-- shift's last 0.2s or before the Orb ends. With no Orb out and the Orb ready again (off cooldown during the shift),
-- she throws it home in the shift's last ORB_EXIT_BEFORE_END seconds; that cast ends the shift (the Orb does not
-- ignore channels, game files), and X.ExitOrbJaunt follows it.
-- [SHy-PUCK] phase-exit jaunt when=early|end|orb-end dist= need= gain= since= hp=, on each Jaunt; phase-exit
-- skip=jaunt why=wrong-side|near|crowded|no-gain|in-range when= dist= need= gain= enemies=here->orb since= hp=, at the
-- end / orb-end checks only, once per 3s. The late Orb prints escape-action spell=orb why=phase-exit.
function X.EscapeShiftJaunt(orderAt, since, duration)
	if bot._phaseCastEscape ~= true or bot._phaseTrack == nil or bot:IsRooted() then
		return false
	end
	if not etherealJauntAbility:IsFullyCastable() then
		return false
	end
	local orbAt = X.OrbInFlight()
	if orbAt == nil then
		if illusoryOrbAbility:IsFullyCastable() and since >= duration - EscapeRules.ORB_EXIT_BEFORE_END then
			local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
			local point = X.EscapePoint(castRange)
			bot._phaseExitFor = orderAt
			bot._phaseExitHow = "orb"
			bot._orbCastAt = DotaTime()
			bot._exitOrbAt = DotaTime()
			-- No TP while it flies (#191): the TP rule runs before this script in the next think.
			bot._noTpUntil = math.max(bot._noTpUntil or -999, DotaTime() + 1.0)
			X.LogEscapeAction("orb", "phase-exit", point)
			X.ReleasePhaseHold()
			bot:Action_UseAbilityOnLocation(illusoryOrbAbility, point)
			return true
		end
		return false
	end
	local sinceOrb = bot._orbCastAt ~= nil and DotaTime() - bot._orbCastAt or nil
	local threatDue = false
	if since < EscapeRules.EARLY_JAUNT_AFTER then
		local okLinear, threat =
			pcall(Fu.FindLinearProjectileIncoming, bot, phaseShiftAbility:GetCastPoint(), "cyclone")
		threatDue = okLinear and threat ~= nil
			or Fu.IsStunProjectileIncoming(bot, 1000)
			or Fu.IsUnitTargetProjectileIncoming(bot, 1000)
	end
	local now, when = EscapeRules.ShiftJauntNow(since, duration, sinceOrb, X.OrbFlightTime(), threatDue)
	if not now then
		return false
	end
	local check = X.ExitJauntCheck(orbAt)
	if check.ok then
		bot._phaseExitFor = orderAt
		bot._phaseExitHow = "jaunt-orb"
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase-exit jaunt when=%s dist=%.0f need=%.0f gain=%.0f since=%.2f hp=%.2f",
				DotaTime(),
				tostring(when),
				check.dist,
				check.need,
				check.gain or -1,
				since,
				Fu.GetHP(bot)
			)
		)
		X.LogEscapeAction("jaunt", "phase-end", orbAt)
		X.ReleasePhaseHold()
		bot:Action_UseAbility(etherealJauntAbility)
		return true
	end
	-- An early check that fails is normal while the Orb flies out; only the late ones are logged.
	if when ~= "early" and DotaTime() >= (bot._phaseExitSkipLogAt or -999) then
		bot._phaseExitSkipLogAt = DotaTime() + 3
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase-exit skip=jaunt why=%s when=%s dist=%.0f need=%.0f gain=%.0f enemies=%d->%d since=%.2f hp=%.2f",
				DotaTime(),
				tostring(check.why),
				tostring(when),
				check.dist,
				check.need,
				check.gain or -1,
				check.enemiesHere,
				check.enemiesThere,
				since,
				Fu.GetHP(bot)
			)
		)
	end
	return false
end
-- Is the Orb at orbAt a way out (EscapeRules.ExitJauntOk)? need: EscapeRules.ExitJauntNeed of the path the Orb has
-- flown (orb_speed x time since it left, cast point 0.1, datafeed hero 13); gain: against the nearest enemy hero
-- within 1600 (its distance to the Orb minus its distance to her). Returns { ok, why, dist, need, gain, enemiesHere,
-- enemiesThere }.
function X.ExitJauntCheck(orbAt)
	local here = bot:GetLocation()
	local _, dirX, dirY = X.EscapePoint(1)
	local dist = GetUnitToLocationDistance(bot, orbAt)
	local escapeSide = EscapeRules.IsOnEscapeSide(here.x, here.y, orbAt.x, orbAt.y, dirX, dirY)
	local enemiesHere = #Fu.GetEnemiesNearLoc(here, 700)
	local enemiesThere = #Fu.GetEnemiesNearLoc(orbAt, 700)
	local pathFlown = nil
	local speed = illusoryOrbAbility:GetSpecialValueInt("orb_speed")
	if bot._orbCastAt ~= nil and speed ~= nil and speed > 0 then
		pathFlown = speed * math.max(0, DotaTime() - bot._orbCastAt - illusoryOrbAbility:GetCastPoint())
	end
	local need = EscapeRules.ExitJauntNeed(pathFlown)
	local nearest, nearestDist = nil, nil
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and not Fu.IsSuspiciousIllusion(enemyHero) then
			local enemyDist = GetUnitToUnitDistance(bot, enemyHero)
			if nearestDist == nil or enemyDist < nearestDist then
				nearest, nearestDist = enemyHero, enemyDist
			end
		end
	end
	local orbToEnemy = nearest ~= nil and GetUnitToLocationDistance(nearest, orbAt) or nil
	local enemyRange = nearest ~= nil and nearest:GetAttackRange() or nil
	local ok, why, gain =
		EscapeRules.ExitJauntOk(dist, need, escapeSide, enemiesThere, enemiesHere, nearestDist, orbToEnemy, enemyRange)
	return {
		ok = ok,
		why = why,
		dist = dist,
		need = need,
		gain = gain,
		enemiesHere = enemiesHere,
		enemiesThere = enemiesThere,
	}
end
-- The Orb thrown at a shift's end (X.EscapeShiftJaunt, bot._exitOrbAt): Jaunt to it once it passes X.ExitJauntCheck,
-- within the Orb's flight. Runs before the danger Jaunt. [SHy-PUCK] escape-action spell=jaunt why=exit-orb.
function X.ExitOrbJaunt()
	local thrownAt = bot._exitOrbAt
	if thrownAt == nil then
		return false
	end
	local flight = X.OrbFlightTime() or 2.6
	if DotaTime() - thrownAt > flight + 0.2 then
		bot._exitOrbAt = nil
		return false
	end
	if not etherealJauntAbility:IsFullyCastable() or bot:IsRooted() then
		return false
	end
	local orbAt = X.OrbInFlight()
	if orbAt == nil then
		return false
	end
	local check = X.ExitJauntCheck(orbAt)
	if not check.ok then
		-- Game 071, t=2046-2049: the exit Orb flew out and no Jaunt came, with nothing in the log to say why.
		if DotaTime() - thrownAt > 1.0 and DotaTime() >= (bot._exitOrbSkipLogAt or -999) then
			bot._exitOrbSkipLogAt = DotaTime() + 3
			pcall(
				print,
				string.format(
					"[SHy-PUCK] t=%.0f phase-exit skip=jaunt why=%s when=exit-orb dist=%.0f need=%.0f gain=%.0f enemies=%d->%d since=%.2f hp=%.2f",
					DotaTime(),
					tostring(check.why),
					check.dist,
					check.need,
					check.gain or -1,
					check.enemiesHere,
					check.enemiesThere,
					DotaTime() - thrownAt,
					Fu.GetHP(bot)
				)
			)
		end
		return false
	end
	bot._exitOrbAt = nil
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f phase-exit jaunt when=exit-orb dist=%.0f need=%.0f gain=%.0f since=%.2f hp=%.2f",
			DotaTime(),
			check.dist,
			check.need,
			check.gain or -1,
			DotaTime() - thrownAt,
			Fu.GetHP(bot)
		)
	)
	X.LogEscapeAction("jaunt", "exit-orb", orbAt)
	bot:Action_UseAbility(etherealJauntAbility)
	return true
end
function X.ShiftExit()
	local orderAt = bot._phaseOrderAt
	if orderAt == nil or bot._phaseExitFor == orderAt then
		return
	end
	local since = DotaTime() - orderAt
	if since < 0.15 then
		return
	end
	local siphoner = bot._siphonEscapeFrom
	if
		siphoner ~= nil
		and not siphoner:IsNull()
		and etherealJauntAbility:IsFullyCastable()
		and not bot:IsRooted()
		and DotaTime() - (bot._siphonOrbAt or -999) < 3
	then
		local orbAt = X.OrbInFlight()
		if orbAt ~= nil and GetUnitToLocationDistance(siphoner, orbAt) > EscapeRules.SIPHON_BREAK + 50 then
			bot._phaseExitFor = orderAt
			bot._phaseExitHow = "jaunt"
			bot._siphonEscapeFrom = nil
			X.LogEscapeAction("jaunt", "siphon", orbAt)
			X.ReleasePhaseHold()
			bot:Action_UseAbility(etherealJauntAbility)
			return true
		end
	end
	local duration = phaseShiftAbility:GetSpecialValueFloat("duration")
	local okJaunt, jaunted = pcall(X.EscapeShiftJaunt, orderAt, since, duration)
	if okJaunt and jaunted then
		return true
	end
	-- The shift must still be on (TrackPhaseShift keeps bot._phaseTrack while it is), and it must have been an escape
	-- shift: after a dodge in a fight she is winning, Blink (her initiation item) stays unless she is under 35%.
	local castWhy = tostring(bot._phaseCastWhy)
	if
		since < duration - 0.2
		or since > duration + 0.1
		or bot._phaseTrack == nil
		or string.sub(castWhy, 1, 5) == "dodge" and Fu.GetHP(bot) >= 0.35
	then
		return
	end
	local blinkItem = X.BlinkItem()
	if blinkItem == nil or not blinkItem:IsFullyCastable() then
		return
	end
	local enemies = #Fu.GetEnemiesNearLoc(bot:GetLocation(), 1200)
	local allies = #Fu.GetAlliesNearLoc(bot:GetLocation(), 1200)
	if enemies < 1 or (Fu.GetHP(bot) >= 0.6 and enemies <= allies) then
		return
	end
	bot._phaseExitFor = orderAt
	bot._phaseExitHow = "blink"
	-- 1150: inside blink_range 1200 (7.42 items_all.txt; a point beyond it lands at blink_range_clamp 960).
	local point = X.EscapePoint(1150)
	X.LogEscapeAction("blink", "phase-end", point)
	X.ReleasePhaseHold()
	bot:Action_UseAbilityOnLocation(blinkItem, point)
	return true
end
-- Hit by a hero after the Phase Shift order (0.1s for the cast): the shift is not on, so stop holding
-- (game 048, t=752: Puck died at 31% HP within a second of the order, under the hold).
function X.HurtSincePhaseOrder()
	if bot._phaseOrderAt == nil then
		return false
	end
	local since = DotaTime() - bot._phaseOrderAt - 0.1
	return since > 0.05 and bot:WasRecentlyDamagedByAnyHero(since)
end
-- The cast hold (bot._castHoldUntil) pauses the item think, and with it SkillsComplement. The item think calls
-- this instead, so the Phase Shift probe and the "hit: release the hold" check keep running inside the shift
-- (game 051: every probe printed only after the hold, 1.1s to 3.3s after the order).
function X.CastHoldTick()
	pcall(X.SampleHp)
	local okHold, errHold = pcall(X.HoldTpInDanger)
	if not okHold then
		X.LogStepError("HoldTpInDanger", errHold)
	end
	pcall(X.TrackPhaseShift)
	pcall(X.ShiftExit)
	if bot._castHoldUntil ~= nil and X.HurtSincePhaseOrder() then
		bot._castHoldUntil = nil
	end
end
-- No TP while siphoned or next to a hero that is hitting her (EscapeRules.HoldTp, #36 game 067 4:05), while Roshan,
-- an enemy tower or (under 50% HP) creeps are hitting her, or while her exit Orb is in flight with the Jaunt ready
-- (#191, games 073 t=2379 and 074 t=6323: TPs at 0.09 and 0.14 HP the think after a full shift). Runs first in
-- every think, before the returns for the shift, the cast hold and silence (silence stops spells, not the TP).
-- The item think runs the TP rule before this script, so the window rolls 1s ahead of the last check.
-- [SHy-PUCK] tp-hold why=siphoned|hit-near|exit-orb|roshan|tower|units hitter= dist= hp= unitAge= towerAge=, when
-- the why changes or at most once per 3s.
function X.HoldTpInDanger()
	local now = DotaTime()
	local siphoned = bot:HasModifier("modifier_death_prophet_spirit_siphon_slow")
	local hitter, hitterDist = nil, nil
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, EscapeRules.TP_HOLD_RANGE, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and bot:WasRecentlyDamagedByHero(enemyHero, 2.0) then
			local dist = GetUnitToUnitDistance(bot, enemyHero)
			if hitterDist == nil or dist < hitterDist then
				hitter, hitterDist = enemyHero, dist
			end
		end
	end
	-- The last hits by creeps and by an enemy tower (kept across the shift, EscapeRules.HitAge).
	if bot:WasRecentlyDamagedByCreep(0.5) or X.UnitAttackers() > 0 then
		bot._puckUnitHitAt = now
	end
	if bot:WasRecentlyDamagedByTower(0.5) then
		bot._puckTowerHitAt = now
	end
	-- Roshan within 700 of her attacking her (he is in the neutral creep list; whether his hits count for
	-- WasRecentlyDamagedByCreep is unverified, so his attack target is read too).
	local roshanNear = false
	for _, creep in pairs(bot:GetNearbyNeutralCreeps(700) or {}) do
		if Fu.IsRoshan(creep) then
			roshanNear = true
			if creep:GetAttackTarget() == bot then
				bot._puckUnitHitAt = now
			end
		end
	end
	local shiftAt = bot._phaseOrderAt
	local shiftEnd = shiftAt ~= nil and shiftAt + phaseShiftAbility:GetSpecialValueFloat("duration") or nil
	local unitAge = EscapeRules.HitAge(now, bot._puckUnitHitAt, shiftAt, shiftEnd)
	local towerAge = EscapeRules.HitAge(now, bot._puckTowerHitAt, shiftAt, shiftEnd)
	local hold, why = EscapeRules.HoldTp(siphoned, hitterDist, {
		exitOrb = X.ExitOrbOut(),
		roshan = roshanNear and unitAge ~= nil and unitAge <= EscapeRules.TP_HOLD_HIT_AGE,
		towerAge = towerAge,
		unitAge = unitAge,
		hp = Fu.GetHP(bot),
	})
	if not hold then
		return false
	end
	bot._noTpUntil = math.max(bot._noTpUntil or -999, now + 1.0)
	-- Own log fields: bot._tpHoldLogAt belongs to the generic TP rule's [SHy-TP] tp-hold line.
	if why ~= bot._puckTpHoldWhy or now >= (bot._puckTpHoldLogAt or -999) then
		bot._puckTpHoldWhy = why
		bot._puckTpHoldLogAt = now + 3
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f tp-hold why=%s hitter=%s dist=%d hp=%.2f unitAge=%.1f towerAge=%.1f",
				now,
				tostring(why),
				hitter ~= nil and (string.gsub(hitter:GetUnitName(), "npc_dota_hero_", "")) or "-",
				hitterDist or -1,
				Fu.GetHP(bot),
				unitAge or -1,
				towerAge or -1
			)
		)
	end
	return true
end
-- Her exit Orb (thrown at a shift's end, bot._exitOrbAt) is in flight and the Jaunt to it is ready: no TP, the
-- Jaunt is the way out (X.ExitOrbJaunt).
function X.ExitOrbOut()
	local thrownAt = bot._exitOrbAt
	if thrownAt == nil or DotaTime() - thrownAt > (X.OrbFlightTime() or 2.6) + 0.2 then
		return false
	end
	return etherealJauntAbility:IsFullyCastable() and not bot:IsRooted() and X.OrbInFlight() ~= nil
end
-- HP samples (every 0.2s, the last 1.5s) for the HP drop over the last second (X.HpLoss).
function X.SampleHp()
	local now = DotaTime()
	local samples = bot._puckHpSamples or {}
	bot._puckHpSamples = samples
	local last = samples[#samples]
	if last == nil or now - last.t >= 0.2 then
		samples[#samples + 1] = { t = now, hp = Fu.GetHP(bot) }
	end
	while #samples > 0 and now - samples[1].t > 1.5 do
		table.remove(samples, 1)
	end
end
-- The HP lost over the last second (share of max HP; 0 when it rose).
function X.HpLoss()
	local now = DotaTime()
	local highest = Fu.GetHP(bot)
	for _, sample in ipairs(bot._puckHpSamples or {}) do
		if now - sample.t <= 1.0 and sample.hp > highest then
			highest = sample.hp
		end
	end
	return highest - Fu.GetHP(bot)
end
-- An enemy hero within 600 that hit her in the last 2s.
function X.HeroOnHer()
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and bot:WasRecentlyDamagedByHero(enemyHero, 2.0) then
			return true
		end
	end
	return false
end
-- A Jaunt to an Orb in flight gets her out now (X.ExitJauntCheck).
function X.ExitJauntReady()
	if not etherealJauntAbility:IsFullyCastable() or bot:IsRooted() then
		return false
	end
	local orbAt = X.OrbInFlight()
	return orbAt ~= nil and X.ExitJauntCheck(orbAt).ok == true
end
-- An escape Rift is wanted now (EscapeRules.EscapeRiftNow): low, a hero or 2+ units on her, no Jaunt out.
function X.EscapeRiftWanted()
	return EscapeRules.EscapeRiftNow(Fu.GetHP(bot), X.HeroOnHer(), X.UnitAttackers(), X.ExitJauntReady())
end
-- Enemy non-hero units (creeps, zombies, summons) within 700 attacking her.
function X.UnitAttackers()
	local count = 0
	for _, unit in pairs(bot:GetNearbyCreeps(700, true) or {}) do
		if Fu.IsValid(unit) and unit:GetAttackTarget() == bot then
			count = count + 1
		end
	end
	return count
end
-- The nearest enemy Undying Tombstone (zombies spawn by every enemy within its radius 1200, datafeed hero 85), its
-- distance or -1. Only read when the low-HP Phase rule fires, for the log.
function X.TombstoneDistance()
	local best = -1
	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES) or {}) do
		if
			unit ~= nil
			and not unit:IsNull()
			and unit:IsAlive()
			and string.find(unit:GetUnitName(), "npc_dota_unit_tombstone", 1, true)
		then
			local dist = GetUnitToUnitDistance(bot, unit)
			if best < 0 or dist < best then
				best = dist
			end
		end
	end
	return best
end
-- Time to impact and spell of the skillshot a dodge Phase Shift is for: the linear-projectile finder of the
-- skillshot dodge (#134) when the build has it (pcall: absent on builds without it), else nil, "-" (the tracking
-- projectile rules on main have no speed, so no time to impact).
function X.PhaseDodgeThreat()
	if Fu.FindLinearProjectileIncoming == nil then
		return nil, "-"
	end
	local ok, threat = pcall(Fu.FindLinearProjectileIncoming, bot, phaseShiftAbility:GetCastPoint(), "cyclone")
	if not ok or type(threat) ~= "table" or type(threat.tti) ~= "number" then
		return nil, "-"
	end
	return threat.tti, tostring(threat.name or "-")
end
-- [SHy-PUCK] phase dodge spell= tti= waited= result=cast|late how=now|waited|cant-cast|expired why=, one per dodge.
-- result=late: the cast went out after the hit time, or never (stunned first: cant-cast; threat gone: expired).
function X.LogPhaseDodge(want, result, how)
	bot._phaseDodgeWant = nil
	local waited = DotaTime() - want.at
	result = result or EscapeRules.PhaseDodgeResult(waited, want.tti)
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f phase dodge spell=%s tti=%.2f waited=%.2f result=%s how=%s why=%s",
			DotaTime(),
			tostring(want.spell),
			want.tti or -1,
			waited,
			result,
			tostring(how),
			tostring(want.why)
		)
	)
end
-- How long the Orb flies: max_distance / orb_speed (1950 / 750 = 2.6s, datafeed hero 13), read from the handle;
-- nil when the values are missing.
function X.OrbFlightTime()
	local maxDistance = illusoryOrbAbility:GetSpecialValueInt("max_distance")
	local speed = illusoryOrbAbility:GetSpecialValueInt("orb_speed")
	if maxDistance == nil or speed == nil or maxDistance <= 0 or speed <= 0 then
		return nil
	end
	return maxDistance / speed
end
-- The start of a Phase Shift's wait for the outpost hold. Fixes the why, the mode and whether it is an escape shift
-- (EscapeRules.IsEscapeShift); for an escape shift it throws the Orb toward the escape point now, inside the wait
-- (EscapeRules.PhaseOrbFirst), so X.ShiftExit can Jaunt to it as the shift ends (game 068, t=2326-2330: shift in
-- place, Orb after it, dead). bot._phaseOrbFirstWhy: thrown | rooted | orb-out | orb-down | jaunt-down | - (not an
-- escape shift), printed on the phase cast line (thrown as left or cancelled). True: wait this think.
function X.StartPhaseWant(outpostMode)
	local now = DotaTime()
	local mode = bot:GetActiveMode()
	bot._phaseWantAt = now
	bot._phaseWantMode = mode
	bot._phaseWantWhy = X.phaseWhy
	bot._phaseOrbFirstAt = nil
	local retreating = isRetreating or mode == BOT_MODE_RETREAT or now < (bot._hardRetreatUntil or -1)
	local escapeShift = EscapeRules.IsEscapeShift(X.phaseWhy, retreating, Fu.GetHP(bot))
	bot._phaseWantEscape = escapeShift
	local orbReady = illusoryOrbAbility:IsFullyCastable()
	local jauntReady = etherealJauntAbility:IsFullyCastable()
	local rooted = bot:IsRooted()
	local orbOut = X.OrbInFlight() ~= nil
	if EscapeRules.PhaseOrbFirst(escapeShift, orbReady, jauntReady, rooted, orbOut) then
		local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
		local point = X.EscapePoint(castRange)
		bot._phaseOrbFirstAt = now
		bot._phaseOrbFirstWhy = "thrown"
		bot._orbCastAt = now
		X.LogEscapeAction("orb", "phase-first", point)
		bot:Action_UseAbilityOnLocation(illusoryOrbAbility, point)
		return true
	end
	bot._phaseOrbFirstWhy = not escapeShift and "-"
		or rooted and "rooted"
		or orbOut and "orb-out"
		or not orbReady and "orb-down"
		or not jauntReady and "jaunt-down"
		or "-"
	return mode ~= outpostMode
end
-- No offensive Rift (why=group / target) under 50% HP with an enemy hero near, when outnumbered, or for 2s after an
-- escape shift: EscapeRules.OffensiveRiftBlocked (game 068 t=2329, 2456, 2788; game 069 t=909, 2091, 2255: a Rift
-- into the enemies, dead 1-3s later). Heroes counted within 1200. [SHy-PUCK] rift-skip why=hurt|outnumbered|after-shift
-- branch= since= escape= hp= enemies= allies=, at most once per 3s.
function X.OffensiveRiftBlocked(branch)
	local here = bot:GetLocation()
	local enemies = #Fu.GetEnemiesNearLoc(here, 1200)
	local allies = #Fu.GetAlliesNearLoc(here, 1200)
	local since = bot._phaseEndAt ~= nil and DotaTime() - bot._phaseEndAt or nil
	local blocked, why = EscapeRules.OffensiveRiftBlocked(since, bot._phaseEndEscape, Fu.GetHP(bot), enemies, allies)
	if not blocked then
		return false
	end
	if DotaTime() >= (bot._riftSkipLogAt or -999) then
		bot._riftSkipLogAt = DotaTime() + 3
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f rift-skip why=%s branch=%s since=%.2f escape=%s hp=%.2f enemies=%d allies=%d",
				DotaTime(),
				tostring(why),
				tostring(branch),
				since or -1,
				tostring(bot._phaseEndEscape),
				Fu.GetHP(bot),
				enemies,
				allies
			)
		)
	end
	return true
end
-- The enemy tower within 1600 that is hitting her: it targets her, or it hit her in the last second with no allied
-- lane creep or other allied hero inside its range to take the shots. Returns tower, distance, range (its attack
-- range from the handle), or nil and a note for the tower-check line (out | tanked | other | none).
-- Fu.IsValidBuilding, not Fu.IsValid: Fu.IsValid is false for every building, so from the first build of this rule
-- (game 072) to game 079 no tower was ever found, and no tower-escape or tower-hop line printed (078 t=493: the
-- laning log had the mid T1 on her at 0.56 HP, holders=0, and no tower-escape line).
function X.TowerOnHer()
	local note = "none"
	for _, tower in pairs(bot:GetNearbyTowers(1600, true) or {}) do
		if Fu.IsValidBuilding(tower) then
			local range = tower:GetAttackRange()
			local dist = GetUnitToUnitDistance(bot, tower)
			if dist <= range + EscapeRules.TOWER_MARGIN then
				local onHer = tower:GetAttackTarget() == bot
				note = "other"
				if not onHer and bot:WasRecentlyDamagedByTower(1.0) then
					local tanked = #Fu.GetAlliesNearLoc(tower:GetLocation(), range) > 1
					for _, creep in pairs(bot:GetNearbyLaneCreeps(1600, false) or {}) do
						if Fu.IsValid(creep) and GetUnitToUnitDistance(creep, tower) <= range then
							tanked = true
							break
						end
					end
					onHer = not tanked
					note = tanked and "tanked" or note
				end
				if onHer then
					return tower, dist, range
				end
			elseif note == "none" then
				note = "out"
			end
		end
	end
	return nil, note
end
-- Diagnostic (#191, items 16-17 never printed in games 074-079): hit by a tower in the last second and no
-- tower-escape order this think. found=no: X.TowerOnHer found no tower on her (note: out | tanked | other | none);
-- found=yes: why the escape gave no order (hp-ok: over 65% HP and not falling fast; hero-hit: the walk waits for the
-- hero rules). At most once per 3s.
-- [SHy-PUCK] t= tower-check found=yes|no why= tower= dist= range= hp= loss=
function X.LogTowerCheck(found, why, tower, dist, range, loss)
	if DotaTime() < (bot._towerCheckLogAt or -999) then
		return
	end
	bot._towerCheckLogAt = DotaTime() + 3
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f tower-check found=%s why=%s tower=%s dist=%.0f range=%.0f hp=%.2f loss=%.2f",
			DotaTime(),
			found and "yes" or "no",
			tostring(why),
			tower ~= nil and tostring(tower:GetUnitName()) or "-",
			dist or -1,
			range or -1,
			Fu.GetHP(bot),
			loss or 0
		)
	)
end
-- A Lua error in one of the tower steps (they run in pcall, which dropped the error unseen): [SHy-ERROR] once per
-- distinct message, at most 3.
local towerErrors = {}
function X.LogStepError(name, err)
	local key = name .. ": " .. tostring(err)
	if towerErrors[key] or #towerErrors >= 3 then
		return
	end
	towerErrors[key] = true
	towerErrors[#towerErrors + 1] = key
	pcall(print, string.format("[SHy-ERROR] t=%.1f puck %s", DotaTime(), key))
end
-- [SHy-PUCK] tower-escape via=walk|rift|orb-jaunt|orb-hop why=hit|behind-tower dist= out= hp= loss= tower=, when
-- the way changes or once per 3s.
function X.LogTowerEscape(via, why, tower, dist, out, loss)
	local key = via .. why
	if key == bot._towerEscapeLogKey and DotaTime() < (bot._towerEscapeLogAt or -999) then
		return
	end
	bot._towerEscapeLogKey = key
	bot._towerEscapeLogAt = DotaTime() + 3
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f tower-escape via=%s why=%s dist=%.0f out=%.0f hp=%.2f loss=%.2f tower=%s",
			DotaTime(),
			via,
			why,
			dist or -1,
			out or -1,
			Fu.GetHP(bot),
			loss or 0,
			tower ~= nil and tostring(tower:GetUnitName()) or "-"
		)
	)
end
-- Out of an enemy tower's range at once when it hits her and nothing tanks it (EscapeRules.TowerEscape, game 072
-- 19:56-20:05). No TP while it hits her (bot._noTpUntil; the TP channel is 3s, 7.42 items). A walk is held by the
-- outpost mode's hold (bot._phaseHoldAskUntil: its Think gives no order), so the push or retreat Think does not walk
-- her back in. The Orb + Jaunt way ends in X.TowerOrbJaunt. True: an order went out this think.
function X.TowerEscape(canCast)
	local tower, dist, range = X.TowerOnHer()
	if tower == nil then
		-- dist holds the note when no tower was found.
		if bot:WasRecentlyDamagedByTower(1.0) then
			X.LogTowerCheck(false, dist, nil, nil, nil, X.HpLoss())
		end
		return false
	end
	local now = DotaTime()
	bot._noTpUntil = math.max(bot._noTpUntil or -999, now + 1.0)
	local loss = X.HpLoss()
	local out = range + EscapeRules.TOWER_MARGIN - dist
	local orbJauntReady = canCast
		and illusoryOrbAbility:IsFullyCastable()
		and etherealJauntAbility:IsFullyCastable()
		and not bot:IsRooted()
		and X.OrbInFlight() == nil
	local riftReady = canCast and waningRiftAbility:IsFullyCastable()
	local riftDistance = waningRiftAbility:GetSpecialValueInt("max_distance")
	if riftDistance == nil or riftDistance <= 0 then
		riftDistance = 350
	end
	local via = EscapeRules.TowerEscape(true, Fu.GetHP(bot), loss, out, orbJauntReady, riftReady, riftDistance)
	if via == nil then
		X.LogTowerCheck(true, "hp-ok", tower, dist, range, loss)
		return false
	end
	local towerAt = tower:GetLocation()
	local threats = { { x = towerAt.x, y = towerAt.y } }
	if via == "rift" then
		X.LogTowerEscape(via, "hit", tower, dist, out, loss)
		local point = X.EscapePoint(riftDistance - 10, threats)
		X.LogEscapeAction("rift", "tower", point)
		bot:Action_UseAbilityOnLocation(waningRiftAbility, point)
		return true
	end
	if via == "orb-jaunt" then
		X.LogTowerEscape(via, "hit", tower, dist, out, loss)
		local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
		local point = X.EscapePoint(castRange, threats)
		bot._orbCastAt = now
		bot._towerOrb = { at = now, x = towerAt.x, y = towerAt.y, range = range, why = "hit" }
		X.LogEscapeAction("orb", "tower", point)
		bot:Action_UseAbilityOnLocation(illusoryOrbAbility, point)
		return true
	end
	-- walk: past the edge plus 150, held from the modes' Thinks for this think and the next few. Not while a hero is
	-- hitting her too: her shift / Orb / Rift rules answer that, and the TP stays held.
	if bot:WasRecentlyDamagedByAnyHero(1.0) then
		X.LogTowerCheck(true, "hero-hit", tower, dist, range, loss)
		return false
	end
	X.LogTowerEscape(via, "hit", tower, dist, out, loss)
	local point = X.EscapePoint(math.max(out, 0) + 150, threats)
	bot._phaseHoldAskUntil = now + 0.3
	bot:Action_MoveToLocation(point)
	return true
end
-- Behind an enemy tower and heading home (EscapeRules.TowerHopWanted, game 072): the Orb along a line home that
-- clears the tower's range (EscapeRules.HopDirection), then a Jaunt once the Orb is past it (X.TowerOrbJaunt), instead
-- of walking through its range. Only with the Orb and Jaunt both ready.
function X.TowerHop(canCast)
	if
		not canCast
		or bot:IsRooted()
		or not illusoryOrbAbility:IsFullyCastable()
		or not etherealJauntAbility:IsFullyCastable()
		or X.OrbInFlight() ~= nil
	then
		return false
	end
	local headingHome = Fu.IsRetreating(bot) or bot:GetActiveMode() == BOT_MODE_RETREAT
	if not headingHome then
		return false
	end
	local here = bot:GetLocation()
	local home = Fu.GetTeamFountain()
	local homeDist = GetUnitToLocationDistance(bot, home)
	local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
	for _, tower in pairs(bot:GetNearbyTowers(1600, true) or {}) do
		if Fu.IsValidBuilding(tower) then
			local towerAt = tower:GetLocation()
			local range = tower:GetAttackRange()
			local towerDist = GetUnitToUnitDistance(bot, tower)
			local towerHome = (home - towerAt):Length2D()
			-- How close the straight line home passes the tower.
			local ux, uy = home.x - here.x, home.y - here.y
			local uLen = math.max(1, math.sqrt(ux * ux + uy * uy))
			local along = math.max(0, ((towerAt.x - here.x) * ux + (towerAt.y - here.y) * uy) / uLen)
			local px, py = here.x + ux / uLen * along, here.y + uy / uLen * along
			local pathToTower = math.sqrt((towerAt.x - px) * (towerAt.x - px) + (towerAt.y - py) * (towerAt.y - py))
			if EscapeRules.TowerHopWanted(homeDist, towerHome, pathToTower, towerDist, range, true) then
				local orbReach = illusoryOrbAbility:GetSpecialValueInt("max_distance")
				if orbReach == nil or orbReach <= 0 then
					orbReach = 1950
				end
				local dx, dy, hopAt =
					EscapeRules.HopDirection(here.x, here.y, towerAt.x, towerAt.y, range, home.x, home.y, orbReach)
				if dx ~= nil then
					local point = Vector(here.x + dx * castRange, here.y + dy * castRange, here.z)
					bot._orbCastAt = DotaTime()
					bot._towerOrb = {
						at = DotaTime(),
						x = towerAt.x,
						y = towerAt.y,
						range = range,
						why = "behind-tower",
						towerHome = towerHome,
					}
					X.LogTowerEscape("orb-hop", "behind-tower", tower, towerDist, hopAt, X.HpLoss())
					X.LogEscapeAction("orb", "tower-hop", point)
					bot:Action_UseAbilityOnLocation(illusoryOrbAbility, point)
					return true
				end
			end
		end
	end
	return false
end
-- The Orb of a tower escape or hop (bot._towerOrb): Jaunt once it is outside the tower's range + margin and closer to
-- home than she is, within its flight. [SHy-PUCK] escape-action spell=jaunt why=tower-hit|tower-behind-tower.
function X.TowerOrbJaunt()
	local hop = bot._towerOrb
	if hop == nil then
		return false
	end
	if DotaTime() - hop.at > (X.OrbFlightTime() or 2.6) + 0.2 then
		bot._towerOrb = nil
		return false
	end
	if not etherealJauntAbility:IsFullyCastable() or bot:IsRooted() then
		return false
	end
	local orbAt = X.OrbInFlight()
	if orbAt == nil then
		return false
	end
	local home = Fu.GetTeamFountain()
	local orbToTower = math.sqrt((orbAt.x - hop.x) * (orbAt.x - hop.x) + (orbAt.y - hop.y) * (orbAt.y - hop.y))
	if
		orbToTower <= hop.range + EscapeRules.TOWER_MARGIN
		or (home - orbAt):Length2D() >= GetUnitToLocationDistance(bot, home)
		-- A hop Jaunts only once the Orb is past the tower (closer to home than it), not just ahead of her.
		or hop.towerHome ~= nil and (home - orbAt):Length2D() >= hop.towerHome
	then
		-- A hop waits outside the tower's range while the Orb flies (about 2.4s for 1800), held from the retreat
		-- Think that would walk her in (the outpost hold, bot._phaseHoldAskUntil), unless an enemy hero is near.
		-- The hold gives no order, so her last move would go on: stop it once the Orb is out.
		if
			hop.towerHome ~= nil
			and #Fu.GetEnemiesNearLoc(bot:GetLocation(), 1000) == 0
			and illusoryOrbAbility:GetCooldownTimeRemaining() > 0
		then
			bot._phaseHoldAskUntil = DotaTime() + 0.3
			bot:Action_ClearActions(true)
		end
		return false
	end
	bot._towerOrb = nil
	X.LogEscapeAction("jaunt", "tower-" .. tostring(hop.why), orbAt)
	bot:Action_UseAbility(etherealJauntAbility)
	return true
end
-- Ask for the outpost hold before a dodge Phase Shift (EscapeRules.AskDodgeHold): an enemy hero within the spell's
-- range + 200 casting a linear stun from DodgeRules.LINEAR while facing her (its cast point: Impale 0.3s, datafeed
-- hero 88), or a linear stun flying at her with tti under 1s. The hold (mode_outpost_generic.lua reads
-- bot._phaseHoldAskUntil) is then the active mode when the dodge casts (game 069, t=761 / 830: the dodge cast at
-- once in attack mode, the shift broke at 0.10s, Impale landed). The ask runs 0.3s past the last sight.
-- [SHy-PUCK] phase hold-ask why=cast|projectile spell= dist= tti= mode=, once per ask.
function X.AskDodgeHold()
	if not phaseShiftAbility:IsFullyCastable() then
		return
	end
	local now = DotaTime()
	local casting, spell, dist = false, "-", -1
	for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemyHero) and (enemyHero:IsCastingAbility() or enemyHero:IsUsingAbility()) then
			local active = enemyHero:GetCurrentActiveAbility()
			local name = active ~= nil and not active:IsNull() and active:GetName() or nil
			local spec = name ~= nil and DodgeRules.LINEAR[name] or nil
			local enemyDist = GetUnitToUnitDistance(bot, enemyHero)
			if
				spec ~= nil
				and spec.why == "stun"
				and DodgeRules.ToolAnswers(spec, "cyclone")
				and enemyDist <= spec.range + 200
				and enemyHero:IsFacingLocation(bot:GetLocation(), 30)
			then
				casting, spell, dist = true, name, enemyDist
				break
			end
		end
	end
	local tti = nil
	if not casting then
		local ok, threat = pcall(Fu.FindLinearProjectileIncoming, bot, phaseShiftAbility:GetCastPoint(), "cyclone")
		if ok and type(threat) == "table" and type(threat.tti) == "number" and threat.spec.why == "stun" then
			tti, spell = threat.tti, tostring(threat.name)
		end
	end
	if not EscapeRules.AskDodgeHold(casting, tti) then
		return
	end
	if bot._phaseHoldAskUntil == nil or now > bot._phaseHoldAskUntil then
		bot._phaseHoldAskAt = now
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase hold-ask why=%s spell=%s dist=%d tti=%.2f mode=%d",
				now,
				casting and "cast" or "projectile",
				spell,
				dist,
				tti or -1,
				bot:GetActiveMode()
			)
		)
	end
	bot._phaseHoldAskUntil = now + 0.3
end
function X.SkillsComplement()
	pcall(X.SampleHp)
	local okHold, errHold = pcall(X.HoldTpInDanger)
	if not okHold then
		X.LogStepError("HoldTpInDanger", errHold)
	end
	pcall(X.TrackPhaseShift)
	local okExit, exited = pcall(X.ShiftExit)
	if okExit and exited then
		return
	end
	-- Hit after the order: the shift is not on, so nothing is held any more.
	if bot._castHoldUntil ~= nil and X.HurtSincePhaseOrder() then
		bot._castHoldUntil = nil
	end
	-- Hold every other cast while Phase Shift starts and lasts (#15, game 046: 15 orders, never channelling 0.3s later;
	-- 5 of 8 probes found Puck already casting Waning Rift or the orb: our own next think broke the channel).
	if bot._phaseOrderAt ~= nil and DotaTime() - bot._phaseOrderAt < 0.4 then
		return
	end
	if
		bot._phaseOrderAt ~= nil
		and DotaTime() - bot._phaseOrderAt < phaseShiftAbility:GetSpecialValueFloat("duration") + 0.05
		and phaseShiftAbility:GetCooldownTimeRemaining() > 0
		and not X.HurtSincePhaseOrder()
	then
		return
	end
	local activeNow = bot:IsChanneling() and bot:GetCurrentActiveAbility() or nil
	if
		bot:HasModifier("modifier_puck_phase_shift")
		or activeNow ~= nil and not activeNow:IsNull() and activeNow:GetName() == "puck_phase_shift"
	then
		return
	end
	local okReady, orbOut = pcall(X.OrbInFlight)
	local canCast = not Fu.CanNotUseAbility(bot)
	bot._puckEscapeReady = canCast
		and (
			phaseShiftAbility:IsFullyCastable()
			or okReady and orbOut ~= nil and etherealJauntAbility:IsFullyCastable() and not bot:IsRooted()
		)
	pcall(X.LogEscapeCheck, okReady and orbOut ~= nil, canCast)
	-- A dodge that waited for the hold and never went out: stunned first, or the threat passed.
	local dodgeWant = bot._phaseDodgeWant
	if dodgeWant ~= nil and (not canCast or DotaTime() - dodgeWant.at > 0.6) then
		pcall(X.LogPhaseDodge, dodgeWant, "late", canCast and "expired" or "cant-cast")
	end
	-- An enemy tower hitting her: out of its range first, even silenced (a walk needs no spell).
	local okT, towerActed = pcall(X.TowerEscape, canCast)
	if not okT then
		X.LogStepError("TowerEscape", towerActed)
	elseif towerActed then
		return
	end
	if not canCast then
		return
	end
	pcall(X.AskDodgeHold)
	local okTj, towerJaunted = pcall(X.TowerOrbJaunt)
	if not okTj then
		X.LogStepError("TowerOrbJaunt", towerJaunted)
	elseif towerJaunted then
		return
	end
	local okHop, hopped = pcall(X.TowerHop, canCast)
	if not okHop then
		X.LogStepError("TowerHop", hopped)
	elseif hopped then
		return
	end
	local okE, exitJaunted = pcall(X.ExitOrbJaunt)
	if okE and exitJaunted then
		return
	end
	local okJ, jaunted = pcall(X.DangerJaunt)
	if okJ and jaunted then
		return
	end
	local okS, siphonOrder = pcall(X.ConsiderSiphonEscape)
	if okS and siphonOrder then
		return
	end
	isGoingOnSomeone = Fu.IsGoingOnSomeone(bot)
	isRetreating = Fu.IsRetreating(bot)
	isAttacking = Fu.IsAttacking(bot)
	mpRatio = Fu.GetMP(bot)
	phaseShiftDesire = X.ConsiderPhaseShift()
	-- Hold first, cast one frame later (game 055: 12 of 33 shifts held the full duration; 20 ended after
	-- 0.03-0.17s, in retreat or attack mode). For Puck both modes are Valve's own: our retreat file has no Think
	-- and our attack mode only replaces Valve's for a few heroes, so neither can be paused by the cast hold, and
	-- their Think replaced the cast order. The outpost mode's hold (desire 1.5, Think gives no order) is asked for
	-- first; the cast goes out once it is the active mode, or when the wait (EscapeRules.PhaseMaxWait) runs out.
	local outpostMode = BOT_MODE_OUTPOST or 26
	-- Game 064: two casts went out after the 0.2s wait in attack mode and broke at 0.1s; the outpost GetDesire had
	-- last run 0.27-0.3s earlier (hold-left age=0.30/0.33, hold-desire=0.00), so the hold had not been asked yet.
	-- The wait is EscapeRules.PhaseMaxWait: a dodge can't wait (the disjoint on cast is the point, 0.2s); a low-HP
	-- shift waits 0.2s only in Valve's retreat mode (game 068, t=3499: the 0.2s cast in defend mode broke at 0.13s);
	-- any other shift waits up to 0.4s for the hold. The why and the mode are fixed when the wait starts
	-- (X.StartPhaseWant), so a mode or why change inside the wait does not shorten it.
	-- A dodge whose hit is closer than the wait: cast in this think (game 067, t=3039: Impale tti=0.20, the 0.2s
	-- wait let the stun land first, canCast=false the next think; she died at 3041). Phase Shift's cast point is
	-- 0.01 (datafeed hero 13). The cast hold below still starts with the order.
	local dodgeTti, dodgeSpell = nil, "-"
	if phaseShiftDesire > 0 and string.sub(tostring(X.phaseWhy), 1, 5) == "dodge" then
		dodgeTti, dodgeSpell = X.PhaseDodgeThreat()
		if bot._phaseDodgeWant == nil then
			bot._phaseDodgeWant = { at = DotaTime(), spell = dodgeSpell, tti = dodgeTti, why = X.phaseWhy }
		end
	end
	-- A close dodge casts in this think only once the hold is up, or when the hit is too close to wait
	-- (EscapeRules.PhaseDodgeNow); the hold was asked for when the stun was first seen (X.AskDodgeHold).
	local castNow = EscapeRules.PhaseDodgeNow(dodgeTti, bot:GetActiveMode() == outpostMode)
	if phaseShiftDesire > 0 and not castNow then
		local now = DotaTime()
		if
			not EscapeRules.PhaseWantFresh(
				bot._phaseWantAt ~= nil and now - bot._phaseWantAt or nil,
				bot._phaseWantMaxWait
			)
		then
			if X.StartPhaseWant(outpostMode) then
				return
			end
		end
		local activeMode = bot:GetActiveMode()
		bot._phaseWantMaxWait = EscapeRules.PhaseMaxWait(
			bot._phaseWantWhy,
			bot._phaseWantMode == BOT_MODE_RETREAT and activeMode == BOT_MODE_RETREAT
		)
		-- The Orb thrown for this shift leaves first: a shift order inside its cast point (0.1s, datafeed hero 13)
		-- would cancel it, and she may have to turn to the point first (0.2s more at most). Its cooldown starts once
		-- it is out.
		if
			bot._phaseOrbFirstAt ~= nil
			and illusoryOrbAbility:GetCooldownTimeRemaining() <= 0
			and now - bot._phaseOrbFirstAt < illusoryOrbAbility:GetCastPoint() + 0.3
		then
			return
		end
		if activeMode ~= outpostMode and now - bot._phaseWantAt < bot._phaseWantMaxWait then
			return
		end
	end
	if phaseShiftDesire > 0 then
		local activeMode = bot:GetActiveMode()
		-- The wait's fields only when the wait is this cast's (a close dodge skips the wait and can find an old one).
		local wantFresh = EscapeRules.PhaseWantFresh(
			bot._phaseWantAt ~= nil and DotaTime() - bot._phaseWantAt or nil,
			bot._phaseWantMaxWait
		)
		-- An escape shift (EscapeRules.IsEscapeShift) ends with a Jaunt to the Orb (X.ShiftExit) and blocks the
		-- offensive Rift for 2s after it (X.OffensiveRiftBlocked).
		local escapeShift = wantFresh and bot._phaseWantEscape == true
			or EscapeRules.IsEscapeShift(
				X.phaseWhy,
				isRetreating or activeMode == BOT_MODE_RETREAT or DotaTime() < (bot._hardRetreatUntil or -1),
				Fu.GetHP(bot)
			)
		-- orb-first=left (the Orb thrown for this shift is out: its cooldown runs) | cancelled (it never left) |
		-- rooted | orb-out | orb-down | jaunt-down | - (not an escape shift, or no wait).
		local orbFirst = wantFresh and bot._phaseOrbFirstWhy or "-"
		if wantFresh and bot._phaseOrbFirstAt ~= nil then
			orbFirst = illusoryOrbAbility:GetCooldownTimeRemaining() > 0 and "left" or "cancelled"
		end
		-- via=now (a close dodge), hold (the outpost hold is the active mode) or timeout (the wait ran out first).
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f phase cast hp=%.2f enemies=%d retreating=%s why=%s from-mode=%s mode=%d waited=%.2f outpost-age=%.2f via=%s max-wait=%.2f escape=%s orb-first=%s asked=%.2f",
				DotaTime(),
				Fu.GetHP(bot),
				#Fu.GetEnemiesNearLoc(bot:GetLocation(), 1000),
				tostring(isRetreating),
				tostring(X.phaseWhy),
				tostring(bot._phaseWantMode),
				activeMode,
				bot._phaseWantAt ~= nil and DotaTime() - bot._phaseWantAt or -1,
				-- How long ago the outpost GetDesire last ran to its end (what the hold had seen).
				DotaTime() - (bot._outpostLastDesireAt or -99),
				castNow and "now" or (activeMode == outpostMode and "hold" or "timeout"),
				bot._phaseWantMaxWait or -1,
				tostring(escapeShift),
				orbFirst,
				-- Seconds since the dodge hold was asked for (X.AskDodgeHold), -1 when it was not.
				DotaTime() < (bot._phaseHoldAskUntil or -1) and DotaTime() - (bot._phaseHoldAskAt or DotaTime()) or -1
			)
		)
		if bot._phaseDodgeWant ~= nil then
			pcall(X.LogPhaseDodge, bot._phaseDodgeWant, nil, castNow and "now" or "waited")
		end
		bot._phaseWantAt = nil
		bot._phaseWantMode = nil
		bot._phaseWantWhy = nil
		bot._phaseWantEscape = nil
		bot._phaseWantMaxWait = nil
		bot._phaseOrbFirstAt = nil
		bot._phaseOrbFirstWhy = nil
		bot._phaseCastEscape = escapeShift
		bot._phaseProbeAt = DotaTime() + 0.3
		bot._phaseOrderAt = DotaTime()
		bot._phaseCastWhy = X.phaseWhy
		bot._phaseOrderLoc = bot:GetLocation()
		-- Item orders and every wrapped mode Think wait too (OhaCastGuard, ItemUsageThink).
		bot._castHoldUntil = DotaTime() + phaseShiftAbility:GetSpecialValueFloat("duration") + 0.05
		bot:Action_UseAbility(phaseShiftAbility)
		return
	end
	local phaseDuration
	phaseOrbDesire, phaseOrbLocation, phaseDuration = X.ConsiderPhaseOrb()
	if phaseOrbDesire > 0 then
		bot._orbCastAt = DotaTime()
		-- An escape combo (ConsiderPhaseOrb): no offensive Rift right after its shift either.
		bot._phaseCastEscape = true
		bot:Action_ClearActions(false)
		bot:ActionQueue_UseAbilityOnLocation(illusoryOrbAbility, phaseOrbLocation)
		bot:ActionQueue_Delay(0.1)
		bot:ActionQueue_UseAbility(phaseShiftAbility)
		-- The Jaunt goes before the Orb ends: it flies 2.6s (X.OrbFlightTime), less than a rank 4 shift (3.25s,
		-- datafeed hero 13), and the old duration - 0.3 delay put the Jaunt 3.15s after the Orb.
		local orbFlight = X.OrbFlightTime()
		local jauntDelay = phaseDuration - 0.3
		if orbFlight ~= nil then
			jauntDelay = math.min(jauntDelay, orbFlight - 0.2 - EscapeRules.JAUNT_ORB_MARGIN)
		end
		bot:ActionQueue_Delay(math.max(0.1, jauntDelay))
		bot:ActionQueue_UseAbility(etherealJauntAbility)
		return
	end
	illusoryOrbDesire, illusoryOrbLocation = X.ConsiderIllusoryOrb()
	if illusoryOrbDesire > 0 then
		-- Bots can't make the orb fly straight: no alt-cast, and neither a full-range aim nor facing the point first
		-- changed the curve (games 044-045, discussion #50). Aim at the target point.
		bot._orbCastAt = DotaTime()
		bot:Action_UseAbilityOnLocation(illusoryOrbAbility, illusoryOrbLocation)
		return
	end
	etherealJauntDesire = X.ConsiderEtherealJaunt()
	if etherealJauntDesire > 0 then
		bot:Action_UseAbility(etherealJauntAbility)
		return
	end
	dreamCoilDesire, dreamCoilLocation = X.ConsiderDreamCoil()
	if dreamCoilDesire > 0 then
		bot:Action_UseAbilityOnLocation(dreamCoilAbility, dreamCoilLocation)
		return
	end
	waningRiftDesire, waningRiftLocation = X.ConsiderWaningRift()
	if waningRiftDesire > 0 then
		pcall(
			print,
			string.format(
				"[SHy-PUCK] t=%.0f rift why=%s heroes=%d dist=%d",
				DotaTime(),
				X.riftWhy or "other",
				#Fu.GetEnemiesNearLoc(waningRiftLocation, waningRiftAbility:GetSpecialValueInt("radius")),
				GetUnitToLocationDistance(bot, waningRiftLocation)
			)
		)
		bot:Action_UseAbilityOnLocation(waningRiftAbility, waningRiftLocation)
		return
	end
end
-- The Orb stays for the escape (Orb + Jaunt) under 50% HP with an enemy hero within 1200
-- (EscapeRules.KeepOrbForEscape, game 069: at 6 of 6 escape shifts the Orb was already out as a fight Orb or on
-- cooldown). Only the escape Orbs (stuck, retreat) go then. [SHy-PUCK] orb-keep hp= enemies=, once per 3s.
function X.ConsiderIllusoryOrb()
	local desire, location = X.ConsiderIllusoryOrbRaw()
	if desire <= 0 or X.orbWhy == "escape" then
		return desire, location
	end
	local enemies = #Fu.GetEnemiesNearLoc(bot:GetLocation(), EscapeRules.KEEP_ORB_RANGE)
	if not EscapeRules.KeepOrbForEscape(Fu.GetHP(bot), enemies) then
		return desire, location
	end
	if DotaTime() >= (bot._orbKeepLogAt or -999) then
		bot._orbKeepLogAt = DotaTime() + 3
		pcall(print, string.format("[SHy-PUCK] t=%.0f orb-keep hp=%.2f enemies=%d", DotaTime(), Fu.GetHP(bot), enemies))
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderIllusoryOrbRaw()
	if not illusoryOrbAbility:IsFullyCastable() or bot:HasModifier("modifier_puck_phase_shift") then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
	local castPoint = illusoryOrbAbility:GetCastPoint()
	local radius = illusoryOrbAbility:GetSpecialValueInt("radius")
	local damage = illusoryOrbAbility:GetSpecialValueInt("damage")
	botTarget = Fu.GetProperTarget(bot)
	X.orbWhy = "other"
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanKillTarget(enemyHero, damage, DAMAGE_TYPE_MAGICAL)
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
			and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
			and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
			and not enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
		then
			return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
		end
	end
	if Fu.IsStuck(bot) then
		local escapeLocation = Fu.GetEscapeLoc()
		X.orbWhy = "escape"
		return BOT_ACTION_DESIRE_HIGH, Fu.Site.GetXUnitsTowardsLocation(bot, escapeLocation, castRange)
	end
	if isGoingOnSomeone then
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE)
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			and not botTarget:HasModifier("modifier_templar_assassin_refraction_absorb")
		then
			local targetAllies = Fu.GetNearbyHeroes(botTarget, 1000, false, BOT_MODE_NONE)
			if nearbyAllies ~= nil and targetAllies ~= nil and #nearbyAllies >= #targetAllies then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetExtrapolatedLocation(castPoint)
			end
		end
	end
	if isRetreating then
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 800, false, BOT_MODE_NONE)
		local nearbyEnemyHeroes = Fu.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
		if
			nearbyAllies ~= nil
			and nearbyEnemyHeroes ~= nil
			and Fu.IsValidHero(nearbyEnemyHeroes[1])
			and not Fu.IsSuspiciousIllusion(nearbyEnemyHeroes[1])
		then
			local enemyAllies = Fu.GetNearbyHeroes(nearbyEnemyHeroes[1], 1000, false, BOT_MODE_NONE)
			if enemyAllies ~= nil and #enemyAllies > #nearbyAllies then
				isOrbEscaping = true
				local escapePoint = X.EscapePoint(castRange)
				X.LogEscapeAction("orb", "retreat", escapePoint)
				X.orbWhy = "escape"
				return BOT_ACTION_DESIRE_HIGH, escapePoint
			else
				isOrbEscaping = false
			end
		end
	end
	if Fu.IsPushing(bot) or Fu.IsDefending(bot) then
		local aoeLocation = bot:FindAoELocation(true, false, bot:GetLocation(), castRange, radius, castPoint, 0)
		local laneCreeps = bot:GetNearbyLaneCreeps(castRange, true)
		if laneCreeps ~= nil and #laneCreeps >= 4 and aoeLocation.count >= 4 then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
		aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, castPoint, 0)
		if aoeLocation.count >= 1 then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	if Fu.IsFarming(bot) then
		local aoeLocation = bot:FindAoELocation(true, false, bot:GetLocation(), castRange, radius, castPoint, 0)
		if isAttacking then
			local neutralCreeps = bot:GetNearbyNeutralCreeps(castRange)
			if
				neutralCreeps ~= nil
				and (
					#neutralCreeps >= 3 and aoeLocation.count >= 3
					or #neutralCreeps >= 2 and neutralCreeps[1]:IsAncientCreep() and aoeLocation.count >= 2
				)
			then
				return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
			end
			local laneCreeps = bot:GetNearbyLaneCreeps(castRange, true)
			if laneCreeps ~= nil and #laneCreeps >= 3 and aoeLocation.count >= 3 then
				return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
			end
		end
	end
	if Fu.IsLaning(bot) then
		local killableCreepCount = 0
		local killableCreeps = {}
		local laneCreeps = bot:GetNearbyLaneCreeps(castRange, true)
		local nearbyEnemyHeroes = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
		for _, creep in pairs(laneCreeps) do
			if Fu.IsValid(creep) and creep:GetHealth() <= damage then
				killableCreepCount = killableCreepCount + 1
				table.insert(killableCreeps, creep)
			end
		end
		if killableCreepCount >= 2 and mpRatio > 0.25 and nearbyEnemyHeroes ~= nil and #nearbyEnemyHeroes >= 1 then
			return BOT_ACTION_DESIRE_HIGH, Fu.GetCenterOfUnits(killableCreeps)
		end
		-- Harass on spare mana (game 064: 3 orbs in 5 minutes of lane; the rule above needs 2 killable creeps): mana
		-- for Rift stays after the orb, and the pool is nearly full or the regen pays the orb back over its cooldown
		-- (datafeed hero 13: Orb 90-120 mana, 12-9s; Phase Shift costs none). Aimed at the nearest enemy hero within
		-- 1100 where it will be when the orb arrives (orb_speed 750); through= counts killable creeps on the way.
		local okSpare, spare = pcall(
			EscapeRules.SpareManaOrb,
			bot:GetMana(),
			bot:GetMaxMana(),
			bot:GetManaRegen(),
			illusoryOrbAbility:GetManaCost(),
			waningRiftAbility:GetManaCost(),
			illusoryOrbAbility:GetCooldown()
		)
		-- Keep the Orb for the Orb + Jaunt escape when an enemy hero is close or she is hurt (EscapeRules.OrbHarassSafe,
		-- game 067 3:55). [SHy-PUCK] orb-harass-skip why=threat|hp near= dist= hp=, at most once per 5s.
		if okSpare and spare and not Fu.IsRetreating(bot) then
			local threat, threatDist = nil, nil
			for _, enemyHero in
				pairs(Fu.GetNearbyHeroes(bot, EscapeRules.HARASS_THREAT_RANGE, true, BOT_MODE_NONE) or {})
			do
				if
					Fu.IsValidHero(enemyHero)
					and not Fu.IsSuspiciousIllusion(enemyHero)
					and not Fu.IsDisabled(enemyHero)
					and (threatDist == nil or GetUnitToUnitDistance(bot, enemyHero) < threatDist)
				then
					threat, threatDist = enemyHero, GetUnitToUnitDistance(bot, enemyHero)
				end
			end
			local safe, why = EscapeRules.OrbHarassSafe(Fu.GetHP(bot), threatDist)
			if not safe then
				spare = false
				if DotaTime() >= (bot._orbHarassSkipAt or -999) then
					bot._orbHarassSkipAt = DotaTime() + 5
					pcall(
						print,
						string.format(
							"[SHy-PUCK] t=%.0f orb-harass-skip why=%s near=%s dist=%d hp=%.2f",
							DotaTime(),
							tostring(why),
							threat ~= nil and (string.gsub(threat:GetUnitName(), "npc_dota_hero_", "")) or "-",
							threatDist or -1,
							Fu.GetHP(bot)
						)
					)
				end
			end
		end
		if okSpare and spare and not Fu.IsRetreating(bot) then
			local target, targetDist = nil, 1100
			for _, enemyHero in pairs(nearbyEnemyHeroes or {}) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.CanCastOnNonMagicImmune(enemyHero)
					and not Fu.IsSuspiciousIllusion(enemyHero)
					and GetUnitToUnitDistance(bot, enemyHero) < targetDist
				then
					target, targetDist = enemyHero, GetUnitToUnitDistance(bot, enemyHero)
				end
			end
			if target ~= nil and #(target:GetNearbyTowers(700, false) or {}) == 0 then
				local orbSpeed = illusoryOrbAbility:GetSpecialValueInt("orb_speed")
				if orbSpeed == nil or orbSpeed <= 0 then
					orbSpeed = 750
				end
				local aim = target:GetExtrapolatedLocation(castPoint + targetDist / orbSpeed)
				local through = 0
				for _, creep in pairs(killableCreeps) do
					local lineInfo = PointToLineDistance(bot:GetLocation(), aim, creep:GetLocation())
					if lineInfo ~= nil and lineInfo.within and lineInfo.distance <= radius then
						through = through + 1
					end
				end
				pcall(
					print,
					string.format(
						"[SHy-PUCK] t=%.0f orb-harass target=%s dist=%d mana=%.2f regen=%.1f through=%d",
						DotaTime(),
						(string.gsub(target:GetUnitName(), "npc_dota_hero_", "")),
						targetDist,
						Fu.GetMP(bot),
						bot:GetManaRegen(),
						through
					)
				)
				return BOT_ACTION_DESIRE_HIGH, aim
			end
		end
	end
	if Fu.IsDoingRoshan(bot) then
		if
			Fu.IsRoshan(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, 500)
			and isAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if Fu.IsTormentor(botTarget) and Fu.IsInRange(bot, botTarget, 400) and isAttacking then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderWaningRift()
	if not waningRiftAbility:IsFullyCastable() or bot:HasModifier("modifier_puck_phase_shift") then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castPoint = waningRiftAbility:GetCastPoint()
	local radius = waningRiftAbility:GetSpecialValueInt("radius")
	-- Game files: Puck moves up to max_distance (350, +350 talent) and hits radius (400) around where she lands.
	local moveDistance = waningRiftAbility:GetSpecialValueInt("max_distance")
	if moveDistance == nil or moveDistance <= 0 then
		moveDistance = 350
	end
	local reach = moveDistance + radius
	local damage = waningRiftAbility:GetSpecialValueInt("damage")
	botTarget = Fu.GetProperTarget(bot)
	X.riftWhy = "kill"
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, reach, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanKillTarget(enemyHero, damage, DAMAGE_TYPE_MAGICAL)
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
			and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
			and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
			and not enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
		then
			return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
		end
	end
	-- Low and being hit, with no Jaunt out right now: Rift toward safety for its move (EscapeRules.EscapeRiftNow, game
	-- 071 34:04-34:15). Its silence still hits heroes near where she lands.
	X.riftWhy = "escape-low"
	local okLow, lowRift = pcall(X.EscapeRiftWanted)
	if okLow and lowRift then
		local escapePoint = X.EscapePoint(moveDistance - 10)
		X.LogEscapeAction("rift", "escape-low", escapePoint)
		return BOT_ACTION_DESIRE_HIGH, escapePoint
	end
	X.riftWhy = "stuck"
	if Fu.IsStuck(bot) then
		local escapeLocation = Fu.GetEscapeLoc()
		return BOT_ACTION_DESIRE_HIGH, Fu.Site.GetXUnitsTowardsLocation(bot, escapeLocation, moveDistance)
	end
	-- Silence a group, or a channelling hero, from where she lands (game files: radius 400 around the landing
	-- point, max_distance 350): the best point for 2+ heroes within max_distance of Puck.
	if (isGoingOnSomeone or Fu.IsInTeamFight(bot, 1200)) and mpRatio > 0.25 then
		local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), moveDistance, radius - 50, castPoint, 0)
		if
			aoe ~= nil
			and aoe.count >= 2
			and #Fu.GetEnemiesNearLoc(aoe.targetloc, radius - 50) >= 2
			and not X.OffensiveRiftBlocked("group")
		then
			X.riftWhy = "group"
			return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
		end
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and enemyHero:IsChanneling()
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and not Fu.IsSuspiciousIllusion(enemyHero)
			then
				X.riftWhy = "channel"
				return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
			end
		end
	end
	X.riftWhy = "target"
	if isGoingOnSomeone then
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, reach)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			and not botTarget:HasModifier("modifier_templar_assassin_refraction_absorb")
		then
			local targetAllies = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			if
				nearbyAllies ~= nil
				and targetAllies ~= nil
				and #nearbyAllies >= #targetAllies
				and not X.OffensiveRiftBlocked("target")
			then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetExtrapolatedLocation(castPoint)
			end
		end
	end
	X.riftWhy = "escape"
	if isRetreating then
		-- An escape jump needs someone to escape from (game 050, 14:06: she jumped 349 with no enemy in sight,
		-- still in retreat mode from a fight 30s before): an enemy hero chasing her within 600, and she was hit in
		-- the last 2s or a stun is flying at her.
		local hitNow = bot:WasRecentlyDamagedByAnyHero(2) or Fu.IsStunProjectileIncoming(bot, 600)
		for _, enemyHero in pairs(Fu.GetNearbyHeroes(bot, 600, true, BOT_MODE_NONE) or {}) do
			if
				hitNow
				and Fu.IsValidHero(enemyHero)
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and Fu.IsChasingTarget(enemyHero, bot)
			then
				local escapePoint = X.EscapePoint(moveDistance)
				X.LogEscapeAction("rift", "escape", escapePoint)
				return BOT_ACTION_DESIRE_HIGH, escapePoint
			end
		end
	end
	-- Rift moves Puck to the point (game 050, 46:19: a creep-clear Rift put her back on a wave she was walking
	-- away from). Creep clears only on a point she is facing.
	X.riftWhy = "push"
	if Fu.IsPushing(bot) or Fu.IsDefending(bot) then
		local aoeLocation =
			bot:FindAoELocation(true, false, bot:GetLocation(), bot:GetAttackRange() + 150, radius, 0, 0)
		local laneCreeps = bot:GetNearbyLaneCreeps(radius, true)
		if
			laneCreeps ~= nil
			and #laneCreeps >= 4
			and aoeLocation.count >= 4
			and bot:IsFacingLocation(aoeLocation.targetloc, 60)
		then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	X.riftWhy = "farm"
	if Fu.IsFarming(bot) then
		local aoeLocation =
			bot:FindAoELocation(true, false, bot:GetLocation(), bot:GetAttackRange() + 150, radius, 0, 0)
		if isAttacking and bot:IsFacingLocation(aoeLocation.targetloc, 60) then
			local neutralCreeps = bot:GetNearbyNeutralCreeps(radius)
			if
				neutralCreeps ~= nil
				and (
					#neutralCreeps >= 3 and aoeLocation.count >= 3
					or #neutralCreeps >= 2 and neutralCreeps[1]:IsAncientCreep() and aoeLocation.count >= 2
				)
			then
				return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
			end
			local laneCreeps = bot:GetNearbyLaneCreeps(radius, true)
			if laneCreeps ~= nil and #laneCreeps >= 3 and aoeLocation.count >= 3 then
				return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
			end
		end
	end
	X.riftWhy = "lane"
	if Fu.IsLaning(bot) then
		local killableCreepCount = 0
		local killableCreeps = {}
		local laneCreeps = bot:GetNearbyLaneCreeps(radius, true)
		local nearbyEnemyHeroes = Fu.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
		for _, creep in pairs(laneCreeps) do
			if Fu.IsValid(creep) and creep:GetHealth() <= damage then
				killableCreepCount = killableCreepCount + 1
				table.insert(killableCreeps, creep)
			end
		end
		if killableCreepCount >= 2 and mpRatio > 0.25 and nearbyEnemyHeroes ~= nil and #nearbyEnemyHeroes >= 1 then
			return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
		end
	end
	X.riftWhy = "roshan"
	if Fu.IsDoingRoshan(bot) then
		if Fu.IsRoshan(botTarget) and Fu.IsInRange(bot, botTarget, 500) and isAttacking then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if Fu.IsTormentor(botTarget) and Fu.IsInRange(bot, botTarget, 400) and isAttacking then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderPhaseShift()
	X.phaseWhy = "hero"
	if not phaseShiftAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end
	-- datafeed: Phase Shift duration is fractional (1/1.75/2.5/3.25s).
	local duration = phaseShiftAbility:GetSpecialValueFloat("duration")
	if Fu.IsStunProjectileIncoming(bot, 600) then
		X.phaseWhy = "dodge-stun"
		return BOT_ACTION_DESIRE_HIGH
	end
	-- Spirit Siphon draining her (X.ConsiderSiphonEscape threw the orb first when it could): the shift blocks the
	-- drain, then the Jaunt or a walk breaks the link.
	if
		X.SiphonSource() ~= nil
		and bot:WasRecentlyDamagedByAnyHero(1.0)
		and (Fu.GetHP(bot) < 0.7 or Fu.IsRetreating(bot))
	then
		X.phaseWhy = "siphon"
		return BOT_ACTION_DESIRE_HIGH
	end
	if Fu.IsUnitTargetProjectileIncoming(bot, 400) then
		X.phaseWhy = "dodge-projectile"
		return BOT_ACTION_DESIRE_HIGH
	end
	-- (#134) A dangerous skillshot (bots/lib/systems/dodge_rules.lua) about to hit: Phase Shift is "immune from
	-- harm" (datafeed), like a self-cyclone. Cast point 0.01 (datafeed), read from the handle.
	local okLinear, threat = pcall(Fu.FindLinearProjectileIncoming, bot, phaseShiftAbility:GetCastPoint(), "cyclone")
	if okLinear and threat ~= nil and threat.window == "now" then
		X.phaseWhy = "dodge-linear"
		if DotaTime() >= (X.phaseLinearLogAt or -99) then
			X.phaseLinearLogAt = DotaTime() + 2
			print(
				string.format(
					"[SHy-DODGE] t=%.0f puck item=phase_shift target=self spell=%s dist=%.0f why=%s kind=linear tti=%.2f src=%s",
					DotaTime(),
					threat.name,
					GetUnitToLocationDistance(bot, threat.projectile.location),
					threat.spec.why,
					threat.tti,
					tostring(threat.src)
				)
			)
		end
		return BOT_ACTION_DESIRE_HIGH
	end
	if not bot:HasModifier("modifier_sniper_assassinate") and not bot:IsMagicImmune() then
		if Fu.IsWillBeCastUnitTargetSpell(bot, 400) then
			X.phaseWhy = "dodge-will-cast"
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	-- Roshan on her under 40% HP (game 050, 29:49-29:53: she died to Roshan from 58% with Phase Shift unused; every
	-- rule above reacts to heroes). The shift drops his attack; she walks out after it.
	local roshanHandle = Fu.Utils.GameStates and Fu.Utils.GameStates.roshHandle
	if
		Fu.GetHP(bot) < 0.4
		and roshanHandle ~= nil
		and not roshanHandle:IsNull()
		and roshanHandle:IsAlive()
		and roshanHandle:GetAttackTarget() == bot
	then
		X.phaseWhy = "roshan"
		return BOT_ACTION_DESIRE_HIGH
	end
	-- Under 20% HP and being hit: EscapeRules.LowHpPhase (game 067, 42:07-42:16), why=low-hp-units (a creep hit or a
	-- unit attacking her) or low-hp-hit (only her HP falling, a hero too: game 068, t=2656/2666). The rules above
	-- react to heroes and projectiles only. After the shift the retreat walks her home, out of a Tombstone's 1200
	-- radius. [SHy-PUCK] phase why=low-hp-units|low-hp-hit hp= loss= creep-hit= attackers= tombstone=, once per 3s.
	local lowHp = Fu.GetHP(bot) < EscapeRules.LOW_HP_PHASE
	local attackers = lowHp and X.UnitAttackers() or 0
	local hpLoss = lowHp and X.HpLoss() or 0
	local creepHit = lowHp and bot:WasRecentlyDamagedByCreep(1.0)
	local lowHpWhy = lowHp and EscapeRules.LowHpPhase(Fu.GetHP(bot), hpLoss, creepHit, attackers) or nil
	if lowHpWhy ~= nil then
		-- Units only, nothing due from a hero, and a Rift out is ready: move out, no shift in place
		-- (EscapeRules.MoveOutInsteadOfShift, game 071 t=2051). The Rift goes in ConsiderWaningRift (why=escape-low).
		local heroHit = bot:WasRecentlyDamagedByAnyHero(1.5)
		local okLinear, linearThreat =
			pcall(Fu.FindLinearProjectileIncoming, bot, phaseShiftAbility:GetCastPoint(), "cyclone")
		local threatDue = okLinear and linearThreat ~= nil
			or Fu.IsStunProjectileIncoming(bot, 1000)
			or Fu.IsUnitTargetProjectileIncoming(bot, 1000)
		local okRift, riftWanted = pcall(X.EscapeRiftWanted)
		local canMoveOut = waningRiftAbility:IsFullyCastable() and okRift and riftWanted == true
		if EscapeRules.MoveOutInsteadOfShift(lowHpWhy, heroHit, threatDue, canMoveOut) then
			if DotaTime() >= (bot._moveOutLogAt or -999) then
				bot._moveOutLogAt = DotaTime() + 3
				pcall(
					print,
					string.format(
						"[SHy-PUCK] t=%.0f phase skip=move-out why=%s hp=%.2f attackers=%d creeps=%d",
						DotaTime(),
						lowHpWhy,
						Fu.GetHP(bot),
						attackers,
						#(bot:GetNearbyCreeps(700, true) or {})
					)
				)
			end
			return BOT_ACTION_DESIRE_NONE
		end
		X.phaseWhy = lowHpWhy
		if DotaTime() >= (bot._lowHpPhaseLogAt or -999) then
			bot._lowHpPhaseLogAt = DotaTime() + 3
			pcall(
				print,
				string.format(
					"[SHy-PUCK] t=%.0f phase why=%s hp=%.2f loss=%.2f creep-hit=%s attackers=%d hero-hit=%s tombstone=%d",
					DotaTime(),
					lowHpWhy,
					Fu.GetHP(bot),
					hpLoss,
					tostring(creepHit),
					attackers,
					tostring(bot:WasRecentlyDamagedByAnyHero(1.0)),
					X.TombstoneDistance()
				)
			)
		end
		return BOT_ACTION_DESIRE_HIGH
	end
	if isRetreating then
		-- Phase only to wait out a short blink lockout (damage puts Blink on a 3s cooldown) with an enemy
		-- near: a READY blink (cooldown 0) also passed "< duration", so Puck stood in Phase Shift
		-- instead of blinking away. The build buys Overwhelming Blink, so look for it too.
		local blinkSlot = bot:FindItemSlot("item_blink")
		if blinkSlot < 0 then
			blinkSlot = bot:FindItemSlot("item_overwhelming_blink")
		end
		local blinkItem = blinkSlot >= 0 and blinkSlot <= 5 and bot:GetItemInSlot(blinkSlot) or nil
		if
			blinkItem ~= nil
			and blinkItem:GetCooldownTimeRemaining() > 0
			and blinkItem:GetCooldownTimeRemaining() < duration
			and bot:WasRecentlyDamagedByAnyHero(1.0)
		then
			return BOT_ACTION_DESIRE_HIGH
		end
		local linearProjectiles = GetLinearProjectiles()
		for _, projectile in pairs(linearProjectiles) do
			-- ability can be nil on a linear projectile (hero_ancient_apparition guards it too)
			if
				projectile ~= nil
				and projectile.ability ~= nil
				and projectile.ability:GetName() == "puck_illusory_orb"
			then
				if GetUnitToLocationDistance(bot, projectile.location) < 300 then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	end
	local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 800)
	local nearbyAllies = Fu.GetNearbyHeroes(bot, 800, false, BOT_MODE_NONE)
	if
		nearbyEnemies ~= nil
		and #nearbyEnemies >= 2
		and nearbyAllies ~= nil
		and #nearbyEnemies > #nearbyAllies
		and bot:WasRecentlyDamagedByAnyHero(1.5)
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderEtherealJaunt()
	if not etherealJauntAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end
	local attackRange = bot:GetAttackRange()
	botTarget = Fu.GetProperTarget(bot)
	if isGoingOnSomeone then
		if Fu.IsValidTarget(botTarget) and not Fu.IsInRange(bot, botTarget, attackRange) then
			local linearProjectiles = GetLinearProjectiles()
			local targetAllies = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			local targetEnemies = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			if targetEnemies ~= nil and targetAllies ~= nil and #targetEnemies >= #targetAllies then
				local targetTowers = botTarget:GetNearbyTowers(700, false)
				for _, projectile in pairs(linearProjectiles) do
					if
						projectile ~= nil
						and projectile.ability ~= nil
						and projectile.ability:GetName() == "puck_illusory_orb"
						and not Fu.IsLocationInChrono(projectile.location)
					then
						if Fu.IsInLaningPhase() then
							if targetTowers ~= nil and #targetTowers == 0 then
								if GetUnitToLocationDistance(botTarget, projectile.location) < attackRange * 1.15 then
									return BOT_ACTION_DESIRE_HIGH
								end
							end
						else
							if GetUnitToLocationDistance(botTarget, projectile.location) < attackRange * 1.15 then
								local alliesNearOrb = Fu.GetAlliesNearLoc(projectile.location, 700)
								local enemiesNearOrb = Fu.GetEnemiesNearLoc(projectile.location, 700)
								if #alliesNearOrb >= #enemiesNearOrb then
									if
										#alliesNearOrb <= 1
										and #enemiesNearOrb == 1
										and targetTowers ~= nil
										and #targetTowers == 0
									then
										-- was "#targetAllies == 0", never true (the target counts itself);
										-- the laning branch above checks the towers the same way.
										X.LogJaunt("solo-no-tower", botTarget)
										return BOT_ACTION_DESIRE_HIGH
									end
									if #alliesNearOrb >= 2 then
										return BOT_ACTION_DESIRE_HIGH
									end
								end
							end
						end
					end
				end
			end
		end
	end
	if isRetreating and isOrbEscaping then
		local linearProjectiles = GetLinearProjectiles()
		for _, projectile in pairs(linearProjectiles) do
			if
				projectile ~= nil
				and projectile.ability ~= nil
				and projectile.ability:GetName() == "puck_illusory_orb"
				and not Fu.IsLocationInChrono(projectile.location)
			then
				if GetUnitToLocationDistance(bot, projectile.location) > 600 then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
-- [SHy-PUCK] Jaunt to the orb onto a lone target with no tower near it, at most once per 10s.
function X.LogJaunt(reason, target)
	if DotaTime() < (bot._jauntLogAt or -999) then
		return
	end
	bot._jauntLogAt = DotaTime() + 10
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f jaunt why=%s target=%s hp=%.2f",
			DotaTime(),
			reason,
			(string.gsub(target:GetUnitName(), "npc_dota_hero_", "")),
			Fu.GetHP(target)
		)
	)
end
-- [SHy-PUCK] pick-off Dream Coil on a lone target, at most once per 10s.
function X.LogCoil(reason, target)
	if DotaTime() < (bot._coilLogAt or -999) then
		return
	end
	bot._coilLogAt = DotaTime() + 10
	pcall(
		print,
		string.format(
			"[SHy-PUCK] t=%.0f coil why=%s target=%s hp=%.2f",
			DotaTime(),
			reason,
			(string.gsub(target:GetUnitName(), "npc_dota_hero_", "")),
			Fu.GetHP(target)
		)
	)
end
function X.ConsiderDreamCoil()
	if not dreamCoilAbility:IsFullyCastable() or bot:HasModifier("modifier_puck_phase_shift") then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, dreamCoilAbility:GetCastRange())
	local radius = dreamCoilAbility:GetSpecialValueInt("coil_radius")
	local duration = dreamCoilAbility:GetSpecialValueInt("coil_duration")
	if Fu.IsInTeamFight(bot, 1200) then
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
		local enemiesInRadius = Fu.GetEnemiesNearLoc(aoeLocation.targetloc, radius)
		if
			enemiesInRadius ~= nil
			and #enemiesInRadius >= 2
			and not Fu.IsLocationInChrono(aoeLocation.targetloc)
			and not Fu.IsLocationInBlackHole(aoeLocation.targetloc)
		then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	if isGoingOnSomeone then
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE)
		local strongestTarget = Fu.GetStrongestUnit(castRange, bot, true, false, duration)
		if
			Fu.IsValidTarget(strongestTarget)
			and Fu.CanCastOnNonMagicImmune(strongestTarget)
			and not Fu.IsSuspiciousIllusion(strongestTarget)
			and not Fu.IsDisabled(strongestTarget)
			and not Fu.IsLocationInChrono(strongestTarget:GetLocation())
			and not Fu.IsLocationInBlackHole(strongestTarget:GetLocation())
			and not strongestTarget:HasModifier("modifier_abaddon_borrowed_time")
			and not strongestTarget:HasModifier("modifier_dazzle_shallow_grave")
			and not strongestTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			and not strongestTarget:HasModifier("modifier_oracle_false_promise_timer")
		then
			-- enemiesNearTarget was Puck's own allies again (same list as nearbyAllies), so "#enemiesNearTarget == 0" could never hold and this
			-- pick-off coil never fired. Now it is the enemy heroes near the target (the target included):
			-- coil a lone target.
			local enemiesNearTarget = Fu.GetEnemiesNearLoc(strongestTarget:GetLocation(), 1000)
			if nearbyAllies ~= nil and enemiesNearTarget and #nearbyAllies >= #enemiesNearTarget then
				if
					#nearbyAllies == 1
					and #enemiesNearTarget <= 1
					and Fu.GetHP(strongestTarget) > 0.55
					and isAttacking
				then
					X.LogCoil("solo", strongestTarget)
					return BOT_ACTION_DESIRE_HIGH, strongestTarget:GetLocation()
				end
				if
					#nearbyAllies >= 2
					and #enemiesNearTarget <= 1
					and Fu.GetHP(strongestTarget) > 0.2
					and Fu.IsRunning(strongestTarget)
					and not strongestTarget:IsFacingLocation(bot:GetLocation(), 90)
				then
					X.LogCoil("runner", strongestTarget)
					return BOT_ACTION_DESIRE_HIGH, strongestTarget:GetLocation()
				end
			end
		end
	end
	if isRetreating then
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE)
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
		local enemiesInRadius = Fu.GetEnemiesNearLoc(aoeLocation.targetloc, radius)
		local allyTowers = bot:GetNearbyTowers(700, false)
		if nearbyAllies ~= nil and enemiesInRadius ~= nil then
			if
				allyTowers ~= nil
				and #allyTowers == 0
				and #enemiesInRadius > #nearbyAllies
				and #enemiesInRadius >= 3
				and #nearbyAllies <= 1
				and GetUnitToLocationDistance(bot, aoeLocation.targetloc) < 700
				and GetUnitToLocationDistance(bot, GetAncient(GetTeam()):GetLocation()) > 3200
			then
				return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
local function CanDoPhaseOrb()
	if phaseShiftAbility:IsFullyCastable() and illusoryOrbAbility:IsFullyCastable() then
		local comboManaCost = phaseShiftAbility:GetManaCost() + illusoryOrbAbility:GetManaCost()
		if bot:GetMana() >= comboManaCost then
			return true
		end
	end
	return false
end
function X.ConsiderPhaseOrb()
	if CanDoPhaseOrb() then
		local castRange = Fu.GetProperCastRange(false, bot, illusoryOrbAbility:GetCastRange())
		-- datafeed: Phase Shift duration is 1/1.75/2.5/3.25s; read as a float so the Jaunt delay is not cut short.
		local phaseDuration = phaseShiftAbility:GetSpecialValueFloat("duration")
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), 800)
		local nearbyAllies = Fu.GetNearbyHeroes(bot, 800, false, BOT_MODE_NONE)
		-- Escape combo only when fleeing or hurt: without this Puck orbed away from every even 2v2+
		-- fight (it runs first, before Dream Coil) even while it was the one attacking.
		if
			nearbyEnemies ~= nil
			and #nearbyEnemies >= 2
			and nearbyAllies ~= nil
			and #nearbyEnemies >= #nearbyAllies
			and (isRetreating or Fu.GetHP(bot) < 0.4 and bot:WasRecentlyDamagedByAnyHero(2))
		then
			local escapePoint = X.EscapePoint(castRange)
			X.LogEscapeAction("phase-orb", "outnumbered", escapePoint)
			return BOT_ACTION_DESIRE_HIGH, escapePoint, phaseDuration
		end
		if isRetreating then
			local nearbyEnemyHeroes = Fu.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
			if
				nearbyAllies ~= nil
				and nearbyEnemyHeroes ~= nil
				and Fu.IsValidHero(nearbyEnemyHeroes[1])
				and not Fu.IsSuspiciousIllusion(nearbyEnemyHeroes[1])
			then
				local enemyAllies = Fu.GetNearbyHeroes(nearbyEnemyHeroes[1], 1000, false, BOT_MODE_NONE)
				if enemyAllies ~= nil and #enemyAllies > #nearbyAllies then
					local escapePoint = X.EscapePoint(castRange)
					X.LogEscapeAction("phase-orb", "retreat", escapePoint)
					return BOT_ACTION_DESIRE_HIGH, escapePoint, phaseDuration
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
return X
