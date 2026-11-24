-- Shared bot system: wires the difficulty levels (#232, bots/lib/systems/difficulty.lua) into the bot's orders and rules.
-- Each bot reads its own bot:GetDifficulty() once ([SHy-DIFF] ... src=api|default); Unfair (and any value the API does
-- not give) is today's play: every hook below returns before any roll or state write when the profile is neutral.
--   cast orders     every Action / ActionPush / ActionQueue _UseAbility* (installed from global_overrides.lua):
--                   reaction delay and skip chance per ability; Passive: no targeted spells on enemy heroes.
--   attack orders   Action / ActionPush / ActionQueue _AttackUnit: Passive never right-clicks an enemy hero; a timed
--                   last hit (last_hit_timing.lua's armed creep) goes out late by the level's lastHitError.
--   dodges          the Fu projectile checks the hero files use (installed from func_utils.lua) and the dodge items
--                   (ability_item_usage_generic.lua Usage.TimedTrackingProjectile / FindLinearProjectileIncoming).
--   gates           team roam's hero hunts and help fights, Smoke of Deceit, chasing a hero under an enemy tower,
--                   Valve's attack mode for Passive bots.
-- Logs: [SHy-DIFF] held kind=reaction|skip|dodge-off|gate|lasthit, at most once per 10s per bot and kind.
-- Loaded by global_overrides.lua before func_utils.lua exists: Fu is required only at call time.
local D = require(GetScriptDirectory() .. "/lib/systems/difficulty")

local H = {}
H.D = D

local HELD_LOG_EVERY = 10
-- A location cast this close to an enemy hero counts as a cast on that hero (Passive). An estimate: most targeted
-- area nukes have a 200-300 radius.
local HERO_LOCATION_RADIUS = 250

local function shortName(unit)
	local ok, name = pcall(function()
		return unit:GetUnitName()
	end)
	return ok and (string.gsub(tostring(name), "npc_dota_hero_", "")) or "?"
end

local function runningBot()
	local ok, bot = pcall(GetBot)
	if ok then
		return bot
	end
	return nil
end

-- The bot's profile, read and logged once per bot. Returns profile, info { level, name, profile, src }.
function H.Get(bot)
	if bot == nil then
		return D.PROFILES[D.DEFAULT], nil
	end
	local info = bot._ohaDiff
	if info ~= nil then
		return info.profile, info
	end
	local okRaw, raw = pcall(function()
		return bot:GetDifficulty()
	end)
	local level, name, profile, src = D.Resolve(okRaw and raw or nil)
	info = { level = level, name = name, profile = profile, src = src }
	bot._ohaDiff = info
	local okTeam, team = pcall(function()
		return bot:GetTeam()
	end)
	pcall(
		print,
		string.format(
			"[SHy-DIFF] t=%.0f %s team=%s difficulty=%d name=%s src=%s raw=%s",
			DotaTime(),
			shortName(bot),
			okTeam and tostring(team) or "?",
			level,
			name,
			src,
			okRaw and tostring(raw) or "error"
		)
	)
	return profile, info
end

function H.Held(bot, kind, fmt, ...)
	local logAt = bot._ohaDiffLogAt
	if logAt == nil then
		logAt = {}
		bot._ohaDiffLogAt = logAt
	end
	local now = DotaTime()
	-- Per kind and call site (a gate on hero attacks does not hide a gate on hero spells).
	local key = kind .. "|" .. fmt
	if now < (logAt[key] or -999) then
		return
	end
	logAt[key] = now + HELD_LOG_EVERY
	local info = bot._ohaDiff
	local okText, text = pcall(string.format, fmt, ...)
	pcall(
		print,
		string.format(
			"[SHy-DIFF] t=%.0f %s held kind=%s level=%s %s",
			now,
			shortName(bot),
			kind,
			info ~= nil and info.name or "?",
			okText and text or "?"
		)
	)
end

local function isEnemyHero(bot, unit)
	local ok, enemy = pcall(function()
		return unit ~= nil and not unit:IsNull() and unit:IsHero() and unit:GetTeam() ~= bot:GetTeam()
	end)
	return ok and enemy == true
end

-- Passive: a spell aimed at an enemy hero (unit target, or a point next to one).
local function aimsAtEnemyHero(bot, kind, target)
	if kind == "entity" then
		return isEnemyHero(bot, target)
	end
	if kind ~= "location" or target == nil then
		return false
	end
	local ok, near = pcall(function()
		for _, enemy in ipairs(bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) or {}) do
			if GetUnitToLocationDistance(enemy, target) <= HERO_LOCATION_RADIUS then
				return true
			end
		end
		return false
	end)
	return ok and near == true
end

-- One random number per bot per frame for new cast decisions: the spells of one combo (Blink then the spell) are
-- skipped together or not at all.
local function frameRoll(bot, now)
	return function()
		local last = bot._ohaDiffRoll
		if last == nil or last.at ~= now then
			last = { at = now, value = math.random() }
			bot._ohaDiffRoll = last
		end
		return last.value
	end
end

-- kind: "none" | "location" | "entity" | "tree". False: hold this order (the unit keeps its current action).
function H.CastAllowed(unit, kind, ability, target)
	local bot = runningBot()
	if bot == nil then
		return true
	end
	local profile = H.Get(bot)
	if profile.neutral or ability == nil then
		return true
	end
	local okName, name = pcall(function()
		return ability:GetName()
	end)
	if not okName or D.IsExemptAbility(name) then
		return true
	end
	if not profile.fightHeroes and bot:GetActiveMode() ~= BOT_MODE_RETREAT and aimsAtEnemyHero(bot, kind, target) then
		H.Held(bot, "gate", "what=hero-cast ability=%s", name)
		return false
	end
	if profile.reactionDelay <= 0 and profile.castSkipChance <= 0 then
		return true
	end
	-- Items go out at once unless aimed at an enemy hero (maintainer, 2026-11-24). The hold below needs the same
	-- order again after the reaction delay (within D.PENDING_GAP), and many item orders are given only once (an eat right after a backpack swap,
	-- a TP, a ward), so a held one never went out (game 077 20:56: Puck's Vital Toadstool). Items on an enemy hero
	-- (Hex, Orchid, Dagon, Abyssal) keep the hold and the skip, so a lower level still reacts slower in fights.
	if string.sub(name, 1, 5) == "item_" and not aimsAtEnemyHero(bot, kind, target) then
		return true
	end
	-- A dodge item the item think chose this frame (Usage.LogDodge sets bot._dodgeChosen before the order): the
	-- dodge share already decided whether to react, and its timing window ([react, react + 0.35s],
	-- dodge_rules.lua Window) is shorter than a reaction hold, so a held dodge order would always land too late.
	local chosen = bot._dodgeChosen
	if chosen ~= nil and chosen.t == DotaTime() then
		return true
	end
	local states = unit._ohaDiffCast
	if states == nil then
		states = {}
		unit._ohaDiffCast = states
	end
	local state = states[name]
	if state == nil then
		state = {}
		states[name] = state
	end
	local now = DotaTime()
	local allowed, why = D.CastStep(state, now, profile, frameRoll(bot, now))
	if not allowed then
		H.Held(bot, why, "ability=%s unit=%s since=%.2f", name, shortName(unit), now - state.startAt)
	end
	return allowed
end

-- False: hold this attack order.
function H.AttackAllowed(unit, target, isOnce)
	local bot = runningBot()
	if bot == nil then
		return true
	end
	local profile = H.Get(bot)
	if profile.neutral or target == nil then
		return true
	end
	if not profile.fightHeroes and isEnemyHero(bot, target) then
		H.Held(bot, "gate", "what=hero-attack target=%s", shortName(target))
		return false
	end
	if profile.lastHitError <= 0 or unit ~= bot then
		return true
	end
	-- The creep last_hit_timing.lua armed for a last hit (the laning Think's order and the per-frame release).
	local armed = bot._lhTiming
	if armed == nil or armed.creep ~= target then
		return true
	end
	local state = bot._ohaDiffLh
	if state == nil then
		state = {}
		bot._ohaDiffLh = state
	end
	local now = DotaTime()
	if D.LastHitStep(state, now, profile, math.random, target) then
		state.pending = nil
		return true
	end
	-- Sent by H.LastHitRetry on the first frame the wait is over (the laning Think re-orders only ~3 times a second).
	state.pending = { creep = target, isOnce = isOnce }
	H.Held(bot, "lasthit", "late=%.2f", state.readyAt - now)
	return false
end

-- Every frame from ItemUsageThink: sends a held last-hit attack once its wait is over, while the creep is still armed.
function H.LastHitRetry(bot)
	local state = bot._ohaDiffLh
	local pending = state ~= nil and state.pending or nil
	if pending == nil then
		return
	end
	local armed = bot._lhTiming
	if armed == nil or armed.creep ~= pending.creep or state.creep ~= pending.creep then
		state.pending = nil
		return
	end
	if DotaTime() < state.readyAt then
		return
	end
	state.pending = nil
	local creep = pending.creep
	if creep:IsNull() or not creep:IsAlive() then
		return
	end
	bot:Action_AttackUnit(creep, pending.isOnce)
end

-- A dodge (item or hero spell) for `unit` that a projectile check found. False: the bot does not react to it.
function H.DodgeAllowed(unit, what)
	local bot = runningBot()
	if bot == nil then
		return true
	end
	local profile = H.Get(bot)
	if profile.dodgeChance >= 1 then
		return true
	end
	local latches = bot._ohaDiffDodge
	if latches == nil then
		latches = {}
		bot._ohaDiffDodge = latches
	end
	local key = unit or bot
	local latch = latches[key]
	if latch == nil then
		latch = {}
		latches[key] = latch
	end
	local allowed = D.DodgeStep(latch, DotaTime(), profile, math.random)
	if not allowed then
		H.Held(bot, "dodge-off", "what=%s unit=%s", tostring(what), shortName(unit))
	end
	return allowed
end

-- Team roam's desire after the hunt / help-fight gate. Returns desire, why.
function H.GateRoam(bot, desire, why, target, allies, enemies)
	local profile = H.Get(bot)
	if profile.neutral or desire == nil or desire <= 0 then
		return desire, why
	end
	local kind = D.RoamFightKind(why)
	if kind == nil then
		return desire, why
	end
	local okHp, targetHp = pcall(function()
		return target:GetHealth() / math.max(1, target:GetMaxHealth())
	end)
	if D.RoamAllowed(profile, kind, okHp and targetHp or 1, allies or 0, enemies or 0) then
		return desire, why
	end
	H.Held(bot, "gate", "what=%s why=%s target=%s allies=%d enemies=%d", kind, why, shortName(target), allies, enemies)
	return 0, "diff-" .. why
end

-- Smoke of Deceit's desire function behind the smoke gate. A gated Smoke never runs the rule (its team "smoked" mark).
function H.WrapSmoke(bot, considerSmoke)
	return function(item, ...)
		local profile = H.Get(bot)
		if profile.smoke ~= "on" then
			local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
			local allies = #(Fu.GetAllyList(bot, 1200) or {})
			if not D.SmokeAllowed(profile, allies) then
				H.Held(bot, "gate", "what=smoke allies=%d", allies)
				return BOT_ACTION_DESIRE_NONE
			end
		end
		return considerSmoke(item, ...)
	end
end

local CHASE_MODES = { BOT_MODE_ATTACK, BOT_MODE_TEAM_ROAM, BOT_MODE_ROAM }
local PUSH_MODES = { BOT_MODE_PUSH_TOWER_TOP, BOT_MODE_PUSH_TOWER_MID, BOT_MODE_PUSH_TOWER_BOT }
local function inModes(mode, modes)
	for _, m in ipairs(modes) do
		if m ~= nil and mode == m then
			return true
		end
	end
	return false
end
-- A retreat started by the dive gate holds this long, or the bot flips back into the chase the next think.
local DIVE_HOLD = 2.0
-- Retreat desire for a hero chase under an enemy tower (0 = no opinion).
function H.DiveRetreat(bot, target)
	local profile = H.Get(bot)
	if profile.dive == "on" then
		return 0
	end
	local now = DotaTime()
	if now < (bot._ohaDiffDiveUntil or -99) then
		return D.DIVE_RETREAT_DESIRE
	end
	local tower = (bot:GetNearbyTowers(900, true) or {})[1]
	if tower == nil or tower:IsNull() or not tower:IsAlive() then
		return 0
	end
	local mode = bot:GetActiveMode()
	local okHp, targetHp = pcall(function()
		return target:GetHealth() / math.max(1, target:GetMaxHealth())
	end)
	local facts = {
		underTower = GetUnitToUnitDistance(bot, tower) < (tower:GetAttackRange() or 700) + 160,
		chasingHero = isEnemyHero(bot, target) and inModes(mode, CHASE_MODES),
		pushing = inModes(mode, PUSH_MODES),
		towerOnUs = tower:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(1.0),
		targetHp = okHp and targetHp or 1,
	}
	local desire = D.DiveRetreat(profile, facts)
	if desire > 0 then
		bot._ohaDiffDiveUntil = now + DIVE_HOLD
		H.Held(
			bot,
			"gate",
			"what=dive target=%s targetHp=%.2f towerOnUs=%s",
			shortName(target),
			facts.targetHp,
			tostring(facts.towerOnUs)
		)
	end
	return desire
end

-- Passive bots: false (no Valve attack mode, no hero fights).
function H.FightsHeroes(bot)
	local profile = H.Get(bot)
	if not profile.fightHeroes then
		H.Held(bot, "gate", "what=attack-mode")
	end
	return profile.fightHeroes
end

-- The cast and attack order wrappers. Called once from global_overrides.lua, after its own cast guards (so these
-- run first: a held order never reaches them).
local CAST_METHODS = {
	{ "Action_UseAbility", "none" },
	{ "ActionPush_UseAbility", "none" },
	{ "ActionQueue_UseAbility", "none" },
	{ "Action_UseAbilityOnLocation", "location" },
	{ "ActionPush_UseAbilityOnLocation", "location" },
	{ "ActionQueue_UseAbilityOnLocation", "location" },
	{ "Action_UseAbilityOnEntity", "entity" },
	{ "ActionPush_UseAbilityOnEntity", "entity" },
	{ "ActionQueue_UseAbilityOnEntity", "entity" },
	{ "Action_UseAbilityOnTree", "tree" },
	{ "ActionPush_UseAbilityOnTree", "tree" },
	{ "ActionQueue_UseAbilityOnTree", "tree" },
}
local ATTACK_METHODS = { "Action_AttackUnit", "ActionPush_AttackUnit", "ActionQueue_AttackUnit" }
local unitHooked, fuHooked = false, false
function H.InstallUnitHooks(class)
	if class == nil or unitHooked then
		return
	end
	unitHooked = true
	for _, spec in ipairs(CAST_METHODS) do
		local original, kind = class[spec[1]], spec[2]
		if original ~= nil then
			class[spec[1]] = function(self, ...)
				local ok, allowed = pcall(H.CastAllowed, self, kind, ...)
				if ok and allowed == false then
					return nil
				end
				return original(self, ...)
			end
		end
	end
	for _, method in ipairs(ATTACK_METHODS) do
		local original = class[method]
		if original ~= nil then
			class[method] = function(self, ...)
				local ok, allowed = pcall(H.AttackAllowed, self, ...)
				if ok and allowed == false then
					return nil
				end
				return original(self, ...)
			end
		end
	end
end

-- The projectile checks the hero files dodge with (bots/lib/general_utils/projectile.lua). Called from func_utils.lua.
local FU_DODGE_CHECKS = {
	"IsStunProjectileIncoming",
	"IsUnitTargetProjectileIncoming",
	"IsNotAttackProjectileIncoming",
	"IsWillBeCastUnitTargetSpell",
	"FindLinearProjectileIncoming",
}
function H.InstallFu(Fu)
	if fuHooked then
		return
	end
	fuHooked = true
	for _, name in ipairs(FU_DODGE_CHECKS) do
		local original = Fu[name]
		if original ~= nil then
			Fu[name] = function(unit, ...)
				local bot = runningBot()
				if bot == nil or H.Get(bot).dodgeChance >= 1 then
					return original(unit, ...)
				end
				local result = original(unit, ...)
				if result and not H.DodgeAllowed(unit, name) then
					if type(result) == "boolean" then
						return false
					end
					return nil
				end
				return result
			end
		end
	end
end

return H
