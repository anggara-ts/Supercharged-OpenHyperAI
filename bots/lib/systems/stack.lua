-- Shared bot system: supports (pos 4/5) stack a safe camp in our jungle on the minute (#229). The rules are in
-- bots/lib/systems/stack_rules.lua; this file reads the game and acts. It runs inside the ward mode
-- (bots/mode_ward_generic.lua: pos 4/5 only, and a mode the stuck watch lets stand still): Stack.Desire is asked
-- first, and while a stack runs the ward Think hands over to Stack.Think.
--
-- Steps: pick a camp between :15 and :44 (walk ...), stop WAIT_DIST from the camp (wait ...; a camp out of sight
-- there is stepped in on until it is in sight), give the attack order so the hit lands at the camp's pull second
-- (pull ...), walk back out to where the bot was EXIT_DIST from the camp on its way in (leave ...), then after the
-- spawn step back in until the camp is in sight and count it (check ...).
-- [SHy-STACK] start / wait / step-in / in-sight / pull / result lines show each stack; skip says why a support in
-- its pick window did not go.
local Stack = {}
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Rules = require(GetScriptDirectory() .. "/lib/systems/stack_rules")

-- Above the support's laning (0.30) and roam desires, below the ward trips (0.6), retreat and fights.
local STACK_DESIRE = 0.55
-- Camp creeps are counted within this radius of the camp, if this camp is the nearest spawner to them.
local COUNT_RADIUS = 1400
-- A stack that the ward mode has not run for this long (another mode won) is dropped.
local LOST_MODE_SECONDS = 3

-- One stack per camp per minute, for the whole team (bots of a team share this module).
local claims = {}
local spawnerKeysLogged = {}

local function HeroName(bot)
	return (string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""))
end
local function CampKey(loc)
	return string.format("%.0f,%.0f", loc.x, loc.y)
end
local function ClockText(dotaTime)
	local sec, minute = Rules.Clock(dotaTime)
	return string.format("%d:%04.1f", minute, sec)
end
local function Log(fmt, ...)
	pcall(print, string.format(fmt, ...))
end

local function Spawners()
	local list = {}
	for _, spawner in pairs(GetNeutralSpawners() or {}) do
		if spawner ~= nil and spawner.location ~= nil then
			list[#list + 1] = spawner
		end
	end
	return list
end

-- Once per team: the fields a spawner has (whether the API exposes the camp box or a speed).
local function LogSpawnerKeys(bot, spawners)
	local team = GetTeam()
	if spawnerKeysLogged[team] or spawners[1] == nil then
		return
	end
	spawnerKeysLogged[team] = true
	local keys = {}
	for key, value in pairs(spawners[1]) do
		keys[#keys + 1] = tostring(key) .. ":" .. type(value)
	end
	table.sort(keys)
	Log("[SHy-STACK] t=%.0f %s spawner-keys keys=%s", DotaTime(), HeroName(bot), table.concat(keys, ","))
end

local function EnemyHeroNear(loc, radius)
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES) or {}) do
		if
			Fu.IsValidHero(enemy)
			and not Fu.IsSuspiciousIllusion(enemy)
			and GetUnitToLocationDistance(enemy, loc) <= radius
		then
			return true
		end
	end
	return false
end
local function EnemyHeroesNearUnit(unit, radius)
	local n = 0
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES) or {}) do
		if
			Fu.IsValidHero(enemy)
			and not Fu.IsSuspiciousIllusion(enemy)
			and GetUnitToUnitDistance(enemy, unit) <= radius
		then
			n = n + 1
		end
	end
	return n
end

-- Visible neutral creeps of this camp: within COUNT_RADIUS of it and nearer to it than to any other spawner.
-- Returns the count and the creep nearest to `from`.
local function CampCreeps(campLoc, spawners, from)
	local n, nearest, nearestDist = 0, nil, math.huge
	for _, creep in pairs(GetUnitList(UNIT_LIST_NEUTRAL_CREEPS) or {}) do
		if
			creep ~= nil
			and not creep:IsNull()
			and creep:IsAlive()
			and not Fu.IsRoshan(creep)
			and not Fu.IsTormentor(creep)
		then
			local dist = GetUnitToLocationDistance(creep, campLoc)
			if dist <= COUNT_RADIUS then
				local ours = true
				for _, spawner in ipairs(spawners) do
					if GetUnitToLocationDistance(creep, spawner.location) < dist - 1 then
						ours = false
						break
					end
				end
				if ours then
					n = n + 1
					local d = from ~= nil and GetUnitToUnitDistance(from, creep) or dist
					if d < nearestDist then
						nearest, nearestDist = creep, d
					end
				end
			end
		end
	end
	return n, nearest, nearestDist
end

-- The lane the laning mode gives this position (mode_laning_generic.lua, outside LAN mode).
local function PositionLane(pos)
	if pos == 2 then
		return LANE_MID
	end
	local safe = pos == 1 or pos == 5
	if GetTeam() == TEAM_RADIANT then
		return safe and LANE_BOT or LANE_TOP
	end
	return safe and LANE_TOP or LANE_BOT
end

local function PartnerThreat(pos)
	local partnerPos = Rules.PartnerPosition(pos)
	if partnerPos == nil then
		return false
	end
	for i = 1, #GetTeamPlayers(GetTeam()) do
		local member = GetTeamMember(i)
		if member ~= nil and member:IsHero() and Fu.GetPosition(member) == partnerPos then
			local alive = member:IsAlive()
			return Rules.PartnerThreat(
				alive,
				alive and Fu.GetHP(member) or 0,
				alive and member:WasRecentlyDamagedByAnyHero(3.0),
				alive and EnemyHeroesNearUnit(member, 1600) or 0
			)
		end
	end
	return false
end

local function LaneBehind(pos)
	local states = Fu.Utils.GameStates
	local lane = PositionLane(pos)
	local untilAt = states ~= nil and states.enemyHalfOff ~= nil and states.enemyHalfOff[lane] or nil
	return untilAt ~= nil and untilAt > DotaTime()
end

local function GroupUp(bot)
	local push = math.max(GetPushLaneDesire(LANE_TOP), GetPushLaneDesire(LANE_MID), GetPushLaneDesire(LANE_BOT))
	local defend = math.max(GetDefendLaneDesire(LANE_TOP), GetDefendLaneDesire(LANE_MID), GetDefendLaneDesire(LANE_BOT))
	return push > 0.5 or defend > 0.5 or Fu.IsInTeamFight(bot, 1500)
end

local function OtherMode(bot)
	local mode = bot:GetActiveMode()
	return Fu.IsRetreating(bot)
		or Fu.IsGoingOnSomeone(bot)
		or Fu.IsDefending(bot)
		or mode == BOT_MODE_RUNE
		or mode == BOT_MODE_ROSHAN
		or mode == BOT_MODE_DEFEND_ALLY
		or bot:WasRecentlyDamagedByAnyHero(4.0)
end

-- One skip line per bot per minute, only for reasons that say something (not the clock or the position).
local function LogSkip(bot, minute, why, extra)
	if bot._stackSkipMinute == minute then
		return
	end
	bot._stackSkipMinute = minute
	Log("[SHy-STACK] t=%.0f %s skip why=%s%s", DotaTime(), HeroName(bot), why, extra or "")
end

-- visible: whether the camp centre was in sight when it was counted (nil: not counted, printed "-"). sightDist:
-- how far from the camp centre the bot was when it came in sight (tunes WAIT_DIST and EXIT_DIST).
local function Finish(bot, stacked, why, before, after, visible, sightDist)
	local s = bot._stack
	if s == nil then
		return
	end
	bot._stack = nil
	Log(
		"[SHy-STACK] t=%.0f %s result camp=%s type=%s stacked=%s creeps=%d before=%d visible=%s why=%s sight=%s",
		DotaTime(),
		HeroName(bot),
		s.key,
		s.type,
		stacked,
		after or -1,
		before or s.before or -1,
		visible == nil and "-" or (visible and "1" or "0"),
		why,
		sightDist ~= nil and tostring(math.floor(sightDist)) or "-"
	)
	-- A stacked camp gets one normal (not danger) ping on the camp centre, as a human does after a stack, so the
	-- team sees where it is (maintainer, 2026-11-28). A human's ping on a camp makes the game tell how many stacks
	-- it has; whether a bot's location ping does the same is UNVERIFIED (the [SHy-STACK] ping line gives the time
	-- to check in game).
	if stacked == "yes" and s.loc ~= nil then
		bot:ActionImmediate_Ping(s.loc.x, s.loc.y, true)
		Log(
			"[SHy-STACK] t=%.0f %s ping camp=%s type=%s creeps=%d before=%d",
			DotaTime(),
			HeroName(bot),
			s.key,
			s.type,
			after or -1,
			before or s.before or -1
		)
	end
end

-- One line per phase change, so a stack that stands still (waiting at the camp, out at the exit point) is
-- explained next to a [SHy-STUCK] line (which also prints stack=<phase>).
local function LogPhase(bot, s, what, dist, extra)
	local loc = bot:GetLocation()
	Log(
		"[SHy-STACK] t=%.0f %s %s camp=%s dist=%d at=%.0f,%.0f%s",
		DotaTime(),
		HeroName(bot),
		what,
		s.key,
		math.floor(dist or -1),
		loc.x,
		loc.y,
		extra or ""
	)
end

-- Try to start a stack (the ward mode has nothing to plant). Returns the desire (0: no stack).
local function TryStart(bot, wardWanted)
	local now = DotaTime()
	local pos = Fu.GetPosition(bot)
	-- Cheap outs first: position, clock, the pick window, at most one try per second.
	if pos ~= 4 and pos ~= 5 or now < Rules.START_TIME or now >= Rules.END_TIME then
		return 0
	end
	local sec, minute = Rules.Clock(now)
	if sec < Rules.PICK_FROM or sec >= Rules.PICK_UNTIL or now < (bot._stackTryAt or -1) then
		return 0
	end
	bot._stackTryAt = now + 1
	local ok, why = Rules.CanStart({
		pos = pos,
		time = now,
		lastStackAt = bot._stackLastAt,
		hp = Fu.GetHP(bot),
		partnerThreat = now < Rules.LANE_PHASE_END and PartnerThreat(pos),
		laneBehind = LaneBehind(pos),
		groupUp = GroupUp(bot),
		enemyNear = EnemyHeroNear(bot:GetLocation(), Rules.ENEMY_RADIUS),
		otherMode = OtherMode(bot),
		wardWanted = wardWanted,
	})
	if not ok then
		if why ~= "laning-gap" then
			LogSkip(bot, minute, why)
		end
		return 0
	end
	local spawners = Spawners()
	LogSpawnerKeys(bot, spawners)
	local ourSide = GetTeam() == TEAM_RADIANT and "radiant" or "dire"
	local speed = bot:GetCurrentMovementSpeed()
	local camps = {}
	for _, spawner in ipairs(spawners) do
		local side, _, by = Fu.Site.CampSide(spawner)
		local key = CampKey(spawner.location)
		local claim = claims[key]
		camps[#camps + 1] = {
			spawner = spawner,
			key = key,
			ourSide = side == ourSide and by == "position",
			type = spawner.type,
			time = now,
			dist = GetUnitToLocationDistance(bot, spawner.location),
			speed = speed,
			claimed = claim ~= nil and claim.minute == minute and claim.bot ~= bot,
		}
	end
	-- The enemy checks only for the camps that pass the rest, nearest first.
	local camp = Rules.PickCamp(camps, function(c)
		return EnemyHeroNear(c.spawner.location, Rules.ENEMY_RADIUS)
			or Fu.Site.IsCampDangerous(bot, { cattr = c.spawner })
	end)
	if camp == nil then
		-- A camp that only waits for its departure second is taken a second later: no skip line for it.
		if Rules.AnyEarly(camps) then
			return 0
		end
		-- Why the camps on our side were left out (the other side's camps are not counted).
		local counts, order = {}, {}
		for _, c in ipairs(camps) do
			if c.ourSide then
				if counts[c.why] == nil then
					counts[c.why] = 0
					order[#order + 1] = c.why
				end
				counts[c.why] = counts[c.why] + 1
			end
		end
		local parts = {}
		for _, w in ipairs(order) do
			parts[#parts + 1] = w .. ":" .. counts[w]
		end
		LogSkip(bot, minute, "no-camp", " camps=" .. table.concat(parts, ","))
		return 0
	end
	claims[camp.key] = { minute = minute, bot = bot }
	local loc = camp.spawner.location
	bot._stackLastAt = now
	bot._stack = {
		phase = "walk",
		key = camp.key,
		type = tostring(camp.type),
		loc = loc,
		minute = minute,
		spawnAt = (minute + 1) * 60,
		startAt = now,
		startLoc = bot:GetLocation(),
		modeSeenAt = now,
	}
	Log(
		"[SHy-STACK] t=%.0f %s start camp=%s type=%s at=%s dist=%d pos=%d minute=%d",
		now,
		HeroName(bot),
		camp.key,
		tostring(camp.type),
		ClockText(minute * 60 + (Rules.PULL_SECOND[camp.type] or Rules.PULL_SECOND_DEFAULT)),
		math.floor(camp.dist),
		pos,
		minute
	)
	return STACK_DESIRE
end

-- A running stack: drop it when it is no longer safe or another mode took the bot. Returns the desire.
local function ActiveDesire(bot)
	local s = bot._stack
	if s == nil then
		return 0
	end
	local now = DotaTime()
	if not bot:IsAlive() then
		Finish(bot, "no", "dead")
		return 0
	end
	if bot:GetActiveMode() == BOT_MODE_WARD then
		s.modeSeenAt = now
	elseif now - s.modeSeenAt > LOST_MODE_SECONDS then
		local dropped = (s.phase == "leave" or s.phase == "check") and "unknown" or "no"
		Finish(bot, dropped, "mode-" .. tostring(bot:GetActiveMode()))
		return 0
	end
	if now - s.startAt > 75 then
		Finish(bot, "no", "timeout")
		return 0
	end
	-- Dropped after the hit landed: the camp may well be stacked, but nobody counts it.
	local dropped = (s.phase == "leave" or s.phase == "check") and "unknown" or "no"
	if Fu.GetHP(bot) < 0.5 or bot:WasRecentlyDamagedByAnyHero(2.0) then
		Finish(bot, dropped, "hit")
		return 0
	end
	if EnemyHeroNear(bot:GetLocation(), 1200) or s.phase == "walk" and EnemyHeroNear(s.loc, Rules.ENEMY_RADIUS) then
		Finish(bot, dropped, "enemy")
		return 0
	end
	return STACK_DESIRE
end

-- Called first by the ward mode's GetDesire. wardWanted: the ward mode itself has a ward to plant (asked only
-- when no stack runs). Returns the stack desire, 0 when there is no stack.
function Stack.Desire(bot, wardWanted)
	if bot._stack ~= nil then
		return ActiveDesire(bot)
	end
	if wardWanted then
		return 0
	end
	return TryStart(bot, false)
end

function Stack.IsActive(bot)
	return bot._stack ~= nil
end

-- The ward mode's Think while a stack runs.
function Stack.Think(bot)
	local s = bot._stack
	if s == nil then
		return
	end
	local now = DotaTime()
	local sec, minute = Rules.Clock(now)
	local dist = GetUnitToLocationDistance(bot, s.loc)
	if s.phase == "walk" then
		if now >= s.spawnAt - 60 + Rules.LATEST_HIT then
			Finish(bot, "no", "late")
			return
		end
		-- The exit point is a point the bot walked: where it was EXIT_DIST from the camp on its way in.
		if s.exitLoc == nil and dist <= Rules.EXIT_DIST then
			if GetUnitToLocationDistance(bot, s.startLoc) > 300 then
				s.exitLoc = bot:GetLocation()
			else
				-- Started inside EXIT_DIST: straight out from the camp past the bot, or the start point.
				local here = bot:GetLocation()
				local x, y = Rules.PointFromCamp(s.loc.x, s.loc.y, here.x, here.y, Rules.EXIT_DIST)
				local point = Vector(x, y, here.z)
				s.exitLoc = IsLocationPassable(point) and point or s.startLoc
			end
		end
		if dist <= Rules.WAIT_DIST then
			s.phase = "wait"
			s.waitLoc = bot:GetLocation()
			s.exitLoc = s.exitLoc or s.startLoc
			LogPhase(bot, s, "wait", dist, " visible=" .. (IsLocationVisible(s.loc) and "1" or "0"))
		else
			bot:Action_MoveToLocation(s.loc)
			return
		end
	end
	if s.phase == "wait" then
		-- The camp is counted every 0.4s, not every think (28 spawner distances per creep). The highest count seen
		-- while waiting is the `before` of the result (a creep standing at the far edge may be out of sight once).
		local cache = s.waitCount
		if
			cache == nil
			or now - cache.at >= 0.4
			or cache.creep ~= nil and (cache.creep:IsNull() or not cache.creep:IsAlive())
		then
			local n, nearest, nearestDist = CampCreeps(s.loc, Spawners(), bot)
			cache = { at = now, count = n, creep = nearest, dist = nearestDist, visible = IsLocationVisible(s.loc) }
			s.waitCount = cache
			s.maxCount = math.max(s.maxCount or 0, n)
		end
		local count, creep, creepDist = s.maxCount or cache.count, cache.creep, cache.dist
		-- Stepped in because the camp was out of sight: it (or a creep) is in sight now, so wait here.
		if s.stepping and (creep ~= nil or cache.visible) then
			s.stepping = nil
			s.waitLoc = bot:GetLocation()
			LogPhase(bot, s, "in-sight", dist, " phase=wait creeps=" .. cache.count)
		end
		if creep == nil then
			-- No creep seen: an empty camp only when the camp is in sight; out of sight, step in (#229, game 087).
			local action = Rules.NoCreepAction(cache.visible, dist, sec, minute > s.minute)
			if action == "empty" then
				Finish(bot, "no", "empty", 0, 0, true, dist)
			elseif action == "unseen" then
				Finish(bot, "unknown", "unseen", count, nil, false)
			elseif action == "step" then
				if not s.stepping then
					s.stepping = true
					LogPhase(bot, s, "step-in", dist, " phase=wait why=unseen")
				end
				bot:Action_MoveToLocation(s.loc)
			else
				if s.stepping then
					-- Stepped in as far as STEP_MIN and still out of sight: stay here, not back out at WAIT_DIST.
					s.waitLoc = bot:GetLocation()
				end
				bot:Action_MoveToLocation(s.waitLoc)
			end
			return
		end
		local orderSec = Rules.OrderSecond(s.type, creepDist, bot:GetAttackRange(), bot:GetCurrentMovementSpeed())
		if minute > s.minute or sec >= Rules.LATEST_HIT then
			Finish(bot, "no", "late", count)
			return
		end
		if sec < orderSec then
			bot:Action_MoveToLocation(s.waitLoc)
			return
		end
		s.phase = "pull"
		s.before = count
		s.creep = creep
		s.creepDist = creepDist
		s.orderAt = now
		s.orderedAt = now
		s.lastAttack = bot:GetLastAttackTime()
		bot:Action_AttackUnit(creep, true)
		return
	end
	if s.phase == "pull" then
		local landed = bot:GetLastAttackTime() > s.lastAttack
		local deadline = minute > s.minute or sec >= Rules.LATEST_HIT
		if landed or deadline then
			s.phase = "leave"
			Log(
				"[SHy-STACK] t=%.0f %s pull camp=%s type=%s order=%s hit=%s landed=%s dist=%d range=%d creeps=%d",
				now,
				HeroName(bot),
				s.key,
				s.type,
				ClockText(s.orderAt),
				landed and ClockText(now) or "-",
				landed and "yes" or "no",
				math.floor(s.creepDist or -1),
				math.floor(bot:GetAttackRange()),
				s.before or -1
			)
			bot:Action_MoveToLocation(s.exitLoc)
			return
		end
		-- The creep died or went out of sight: the next one. Otherwise repeat the order only when the bot is not
		-- attacking (an order lost to something else), at most every 0.7s: a repeated attack order restarts the
		-- attack animation.
		if s.creep == nil or s.creep:IsNull() or not s.creep:IsAlive() or not s.creep:CanBeSeen() then
			local _, creep = CampCreeps(s.loc, Spawners(), bot)
			if creep == nil then
				Finish(bot, "no", "creep-gone", s.before)
				return
			end
			s.creep = creep
			s.orderedAt = -math.huge
		end
		local newCreep = s.orderedAt == -math.huge
		if newCreep or now - s.orderedAt >= 0.7 and bot:GetCurrentActionType() ~= BOT_ACTION_TYPE_ATTACK then
			s.orderedAt = now
			bot:Action_AttackUnit(s.creep, true)
		end
		return
	end
	if s.phase == "leave" then
		-- Out of the box until the spawn has happened, then the count.
		if now < s.spawnAt + 0.5 then
			bot:Action_MoveToLocation(s.exitLoc)
			return
		end
		s.phase = "check"
	end
	if s.phase == "check" then
		-- Until CHECK_SECOND at the exit point (the pulled creeps are still chasing), then step back in until the
		-- camp centre is in sight and stop there. Game 087: counted from the exit point, every check had visible=0
		-- (trees and high ground, by day too) and gave stacked=unknown.
		local elapsed = now - s.spawnAt
		if elapsed >= Rules.CHECK_SECOND then
			local cache = s.checkCount
			if cache == nil or now - cache.at >= 0.4 then
				cache = { at = now, count = CampCreeps(s.loc, Spawners(), nil), visible = IsLocationVisible(s.loc) }
				s.checkCount = cache
				s.best = math.max(s.best or 0, cache.count)
				if cache.visible and s.sightSince == nil then
					s.sightSince = elapsed
					s.sightDist = dist
					if s.checkStepping then
						LogPhase(bot, s, "in-sight", dist, " phase=check creeps=" .. cache.count)
					end
				end
			end
		end
		local visibleNow = s.checkCount ~= nil and s.checkCount.visible
		local action = Rules.CheckAction(elapsed, visibleNow, s.sightSince, s.best, s.before, dist)
		if action == "exit" then
			bot:Action_MoveToLocation(s.exitLoc)
		elseif action == "step" then
			if not s.checkStepping then
				s.checkStepping = true
				LogPhase(bot, s, "step-in", dist, " phase=check why=unseen")
			end
			bot:Action_MoveToLocation(s.loc)
		elseif action == "hold" then
			s.holdLoc = s.holdLoc or bot:GetLocation()
			bot:Action_MoveToLocation(s.holdLoc)
		else
			local seen = s.sightSince ~= nil
			local stacked = Rules.Result(s.before, s.best, seen)
			Finish(bot, stacked, stacked == "unknown" and "unseen" or "checked", s.before, s.best, seen, s.sightDist)
		end
	end
end

return Stack
