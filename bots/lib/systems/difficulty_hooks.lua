-- Shared bot system: wires the difficulty levels (#232, bots/lib/systems/difficulty.lua) into the bot's orders and rules.
-- Each bot reads its own bot:GetDifficulty() once ([SHy-DIFF] ... src=api|default); Unfair (and any value the API does
-- not give) is today's play: every hook below returns before any roll or state write when the profile is neutral.
--   cast orders     every Action / ActionPush / ActionQueue _UseAbility* (installed from global_overrides.lua): no
--                   delay; a reactive cast (H.IsReactive) goes out when the bot's danger-episode roll passed, any
--                   other cast when its per-decision roll passed; Passive: no targeted spells on enemy heroes.
--   attack orders   Action / ActionPush / ActionQueue _AttackUnit: Passive never right-clicks an enemy hero; a timed
--                   last hit (last_hit_timing.lua's armed creep) goes out late by the level's lastHitError.
--   dodges          the Fu projectile checks the hero files use (installed from func_utils.lua) and the dodge items
--                   (ability_item_usage_generic.lua Usage.TimedTrackingProjectile / FindLinearProjectileIncoming):
--                   the episode's reactive roll.
--   gates           team roam's hero hunts and help fights, Smoke of Deceit, chasing a hero under an enemy tower,
--                   Valve's attack mode for Passive bots.
-- Logs: [SHy-DIFF] roll kind=reactive|cast (one per roll; cast lines at most one per CAST_ROLL_LOG_EVERY s per bot
-- and result, n= counts the rolls since the last one), episode-end (one per episode), held kind=skip|dodge-off|gate|
-- lasthit (at most once per 10s per bot and kind).
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

-- One random number per bot per frame for new "other" cast decisions: the spells of one combo (Blink then the spell)
-- fail together or not at all.
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

-- Cast roll lines: at most one per this many seconds per bot and result (a bot decides many casts in a fight);
-- n= counts the rolls of that result since its last line, so the ok / fail share stays readable.
local CAST_ROLL_LOG_EVERY = 5
local function logRoll(bot, kind, allowed, p, what, episodeId)
	local now = DotaTime()
	local result = allowed and "ok" or "fail"
	local n = 1
	if kind == "cast" then
		local counts = bot._ohaDiffRollLog
		if counts == nil then
			counts = {}
			bot._ohaDiffRollLog = counts
		end
		local entry = counts[result]
		if entry == nil then
			entry = { n = 0, at = -999 }
			counts[result] = entry
		end
		entry.n = entry.n + 1
		if now < entry.at + CAST_ROLL_LOG_EVERY then
			return
		end
		n = entry.n
		entry.n = 0
		entry.at = now
	end
	local info = bot._ohaDiff
	pcall(
		print,
		string.format(
			"[SHy-DIFF] t=%.0f %s roll kind=%s result=%s p=%.2f ability=%s episode=%s level=%s n=%d",
			now,
			shortName(bot),
			kind,
			result,
			p,
			tostring(what),
			episodeId ~= nil and tostring(episodeId) or "-",
			info ~= nil and info.name or "?",
			n
		)
	)
end

local function inRiskyMode(bot)
	local ok, mode = pcall(function()
		return bot:GetActiveMode()
	end)
	return ok and (mode == BOT_MODE_RETREAT or mode == BOT_MODE_EVASIVE_MANEUVERS)
end

-- Ends the bot's danger episode when it is over ([SHy-DIFF] episode-end). Called every frame by H.Tick and before
-- every reactive decision, so an episode also ends when the tick did not run.
local function updateEpisode(bot, rs, now)
	if rs.episode == nil then
		return
	end
	local okAlive, alive = pcall(function()
		return bot:IsAlive()
	end)
	local okHit, hit = pcall(function()
		return bot:WasRecentlyDamagedByAnyHero(D.EPISODE_SAFE)
	end)
	local facts = {
		alive = not okAlive or alive ~= false,
		danger = inRiskyMode(bot),
		hit = okHit and hit == true,
	}
	local why, episode = D.EpisodeTick(rs, now, facts)
	if why == nil then
		return
	end
	local info = bot._ohaDiff
	pcall(
		print,
		string.format(
			"[SHy-DIFF] t=%.0f %s episode-end why=%s fails=%d episode=%d result=%s dur=%.1f level=%s",
			now,
			shortName(bot),
			why,
			episode.fails,
			episode.id,
			episode.allowed and "ok" or "fail",
			now - episode.startAt,
			info ~= nil and info.name or "?"
		)
	)
end

-- A reactive cast or dodge of `bot` (what: the ability or dodge check). Returns allowed.
function H.ReactiveAllowed(bot, profile, what)
	local rs = bot._ohaDiffReact
	if rs == nil then
		rs = {}
		bot._ohaDiffReact = rs
	end
	local now = DotaTime()
	updateEpisode(bot, rs, now)
	local allowed, episode, rolled = D.ReactiveStep(rs, now, profile, math.random, what)
	if rolled then
		logRoll(bot, "reactive", allowed, profile.reactiveChance, what, episode.id)
	end
	return allowed
end

-- Every frame (ItemUsageThink and BuybackUsageThink; unverified that the buyback think runs while the bot is dead:
-- if not, an episode open at a death ends why=cap after the respawn): remembers when the bot was last in retreat or
-- evasive mode (a cast up to D.REACTIVE_RECENT later is still reactive) and ends the danger episode on time. Unfair
-- returns first: no state.
function H.Tick(bot)
	if bot == nil then
		return
	end
	local profile = H.Get(bot)
	if profile.neutral then
		return
	end
	local now = DotaTime()
	if inRiskyMode(bot) then
		bot._ohaDiffRiskyAt = now
	end
	local rs = bot._ohaDiffReact
	if rs ~= nil and rs.episode ~= nil then
		updateEpisode(bot, rs, now)
	end
end

local function isChannellingEnemyHero(bot, unit)
	local ok, channelling = pcall(function()
		return unit:IsChanneling()
	end)
	return ok and channelling == true and isEnemyHero(bot, unit)
end

-- A reactive cast: an escape, dodge, save or interrupt. Rules (the PR's change log has the same list):
--   the bot is in retreat or evasive maneuvers mode, or was within D.REACTIVE_RECENT s (Puck's cast hold);
--   a dodge check (H.DodgeAllowed) found a threat this frame, or the item think chose a dodge item this frame;
--   the target is an allied hero (a save; the bot itself included: Cold Embrace, Shallow Grave on self);
--   the target is an enemy hero that is channelling, or the point is next to one (an interrupt).
function H.IsReactive(bot, kind, target, now)
	if inRiskyMode(bot) or now - (bot._ohaDiffRiskyAt or -99) <= D.REACTIVE_RECENT then
		return true
	end
	if bot._ohaDiffDodgeAt == now then
		return true
	end
	local chosen = bot._dodgeChosen
	if chosen ~= nil and chosen.t == now then
		return true
	end
	if kind == "entity" then
		if target == nil then
			return false
		end
		local okAlly, ally = pcall(function()
			return not target:IsNull() and target:IsHero() and target:GetTeam() == bot:GetTeam()
		end)
		if okAlly and ally == true then
			return true
		end
		return isChannellingEnemyHero(bot, target)
	end
	if kind ~= "location" or target == nil then
		return false
	end
	local ok, near = pcall(function()
		for _, enemy in ipairs(bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) or {}) do
			if
				GetUnitToLocationDistance(enemy, target) <= HERO_LOCATION_RADIUS and isChannellingEnemyHero(bot, enemy)
			then
				return true
			end
		end
		return false
	end)
	return ok and near == true
end

-- kind: "none" | "location" | "entity" | "tree". False: drop this order (the unit keeps its current action).
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
	if profile.reactiveChance >= 1 and profile.castChance >= 1 then
		return true
	end
	-- Items go out at once unless aimed at an enemy hero (maintainer, 2026-11-24): many item orders are given only
	-- once (an eat right after a backpack swap, a TP, a ward; game 077 20:56: Puck's Vital Toadstool). Saves with an
	-- item on an ally (Glimmer, Lotus) and the dodge items on the bot go out at once with them. Items on an enemy hero
	-- (Hex, Orchid, Dagon, Abyssal) are rolled like spells below.
	if string.sub(name, 1, 5) == "item_" and not aimsAtEnemyHero(bot, kind, target) then
		return true
	end
	local now = DotaTime()
	if H.IsReactive(bot, kind, target, now) then
		return H.ReactiveAllowed(bot, profile, name)
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
	local allowed, rolled = D.CastStep(state, now, profile, frameRoll(bot, now))
	if rolled then
		logRoll(bot, "cast", allowed, profile.castChance, name, nil)
	end
	if not allowed then
		H.Held(bot, "skip", "ability=%s unit=%s since=%.2f", name, shortName(unit), now - state.startAt)
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

-- A dodge (item or hero spell) for `unit` that a projectile check found: the bot's reactive episode roll. False: the bot
-- does not react to it.
function H.DodgeAllowed(unit, what)
	local bot = runningBot()
	if bot == nil then
		return true
	end
	local profile = H.Get(bot)
	if profile.reactiveChance >= 1 then
		return true
	end
	local now = DotaTime()
	-- A cast this frame (Phase Shift after the check) is a dodge: reactive, the same episode roll, no second roll.
	bot._ohaDiffDodgeAt = now
	local allowed = H.ReactiveAllowed(bot, profile, "dodge:" .. tostring(what))
	-- A threat seen keeps the bot in danger: the episode does not end "safe" while projectiles keep coming.
	local episode = bot._ohaDiffReact.episode
	if episode ~= nil then
		episode.dangerAt = now
	end
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
				if bot == nil or H.Get(bot).reactiveChance >= 1 then
					return original(unit, ...)
				end
				local result = original(unit, ...)
				if not result then
					return result
				end
				-- In a pcall: a broken dodge rule must not stop the hero's think (a threat then counts as allowed).
				local ok, allowed = pcall(H.DodgeAllowed, unit, name)
				if ok and allowed == false then
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
