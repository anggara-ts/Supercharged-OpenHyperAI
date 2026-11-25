-- Shared bot system: Roshan in the respawn window (#12). Game 084: Dire killed Roshan at 35:04 and nobody looked
-- at the pit afterwards; Fu.IsRoshanAlive counts him up only 11 minutes after the kill (or once one of our units
-- sees him), and the take then ramps slowly from Valve's GetRoshanDesire (the first Dire call came at 49:12 at 0.30,
-- under farming). Maintainer: "when it's even, don't they try to rosh instead of farming? or push any of the lane?".
--
-- Two parts, both wrapped around the Roshan mode (bots/mode_roshan_generic.lua), the rules in
-- bots/lib/systems/tempo_rules.lua:
--   Peek: from 8:00 after the kill until Roshan is seen or 11:00, the nearest healthy support (else the nearest
--     healthy bot) walks to see the pit, at most one trip per 60s, and plants an observer there on the way if it
--     carries one. Its Roshan desire is PEEK_DESIRE while the trip runs; the trip ends once the pit has been visible
--     for 1.5s, Roshan is seen, the bot is hit / outnumbered / under 45% HP, or the time runs out.
--   Call: when Roshan is up, after 30:00, with all five of ours alive, nothing to defend and no lead push running
--     (an even game), the team's Roshan call goes at CALL_DESIRE once the mode's own checks passed (contested pit,
--     damage, base threat, early game): the even-numbers refusal (`even(5v5)`) is lifted while the call is armed
--     (RoshanWindow.EvenTakeOk), and the slow timer ramp is raised. The strength push treats the reason
--     ("rosh-window") as a Roshan first, so a late-even group push waits for it.
-- Logs: [SHy-ROSH] rosh-peek who= since-kill= seen= (start, plant, end), rosh-window arm / disarm / call / give-up.
-- Cost: one team tick per second (a few handles and IsLocationVisible), nothing per frame.
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Rules = require(GetScriptDirectory() .. "/lib/systems/tempo_rules")
local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
local StrengthRules = require(GetScriptDirectory() .. "/lib/systems/strength_rules")

local RoshanWindow = {}
RoshanWindow.Rules = Rules
RoshanWindow.CALL_DESIRE = 0.9
RoshanWindow.PEEK_DESIRE = 0.8
local TICK_SECONDS = 1
local PEEK_MIN_HP = 0.6
local PEEK_ABORT_HP = 0.45
local PEEK_SEE_HOLD = 1.5
local PEEK_TRIP_BASE = 20
local PEEK_TRIP_MAX = 75
local PEEK_WALK_SPEED = 300
local PEEK_STAND_OFFSET = 250
local WARD_OFFSET = 300
-- item_ward_observer "AbilityCastRange" "500" (7.42 items, scripts/npc/items.txt in pak01_dir.vpk).
local OBSERVER_CAST_RANGE = 500
local BASE_HERO_RADIUS = 2200
local CALL_MIN_HP = 0.5
-- The Roshan mode's reasons a call may raise: its checks passed and only the slow timer ramp (or the kill-window
-- floor at VERYHIGH) holds the desire down. Not the human-team invite: with a human on the team the human decides.
-- Matched without a "+..." suffix (#87 prints "timer+pressure").
local RAISABLE = { ["timer"] = true, ["kill-window"] = true }

local states = {}
local function TeamState(team)
	local state = states[team]
	if state == nil then
		state = {
			lastTick = -999,
			killTime = nil,
			phase = "never",
			lastTripEnd = -math.huge,
			armed = false,
			blockedUntil = -math.huge,
		}
		states[team] = state
	end
	return state
end
local function TeamName(team)
	return team == TEAM_DIRE and "dire" or "radiant"
end
local function ShortName(unit)
	return (string.gsub(unit:GetUnitName(), "npc_dota_hero_", ""))
end
local function RoshLog(fmt, ...)
	pcall(print, string.format("[SHy-ROSH] t=%.0f " .. fmt, DotaTime(), ...))
end
local function MemberById(team, playerId)
	for slot = 1, #(GetTeamPlayers(team) or {}) do
		local member = GetTeamMember(slot)
		if member ~= nil and not member:IsNull() and member:GetPlayerID() == playerId then
			return member
		end
	end
	return nil
end
local function AliveCount(team)
	local count = 0
	for _, pid in ipairs(GetTeamPlayers(team) or {}) do
		if IsHeroAlive(pid) then
			count = count + 1
		end
	end
	return count
end
-- In a fight or a job the peek must not pull it out of.
local function Busy(member)
	local mode = member:GetActiveMode()
	return mode == BOT_MODE_ROSHAN
		or mode == BOT_MODE_RETREAT
		or mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_DEFEND_ALLY
		or mode == BOT_MODE_EVASIVE_MANEUVERS
		or mode == BOT_MODE_DEFEND_TOWER_TOP
		or mode == BOT_MODE_DEFEND_TOWER_MID
		or mode == BOT_MODE_DEFEND_TOWER_BOT
end
local function Danger(member)
	return Fu.GetHP(member) < PEEK_ABORT_HP
		or member:WasRecentlyDamagedByAnyHero(2.0)
		or #(Fu.GetEnemiesNearLoc(member:GetLocation(), 1600) or {}) >= 2
end
local function SinceKillText(state)
	return state.sinceKill ~= nil and string.format("%.0f", state.sinceKill) or "-"
end
-- A bot's desire kept under its own retreat desire (mode_retreat_generic.lua bot._retreatFinalDesire).
local function UnderRetreat(bot, value)
	local retreat = bot._retreatFinalDesire
	if retreat ~= nil and DotaTime() - (retreat.t or -999) <= 1 and (retreat.d or 0) >= 0.2 then
		return math.min(value, retreat.d - 0.02)
	end
	return value
end

-- The peeker itself: its player ID and hero (a Spirit Bear shares Lone Druid's player ID; Meepo's clones his name).
local function IsPeeker(state, bot)
	return state.peekerId ~= nil
		and state.peekerId == bot:GetPlayerID()
		and bot:GetUnitName() == state.peekerUnit
		and not Fu.IsMeepoClone(bot)
end
local function EndTrip(state, team, now, why, seen)
	local peeker = MemberById(team, state.peekerId)
	local pit = Fu.GetCurrentRoshanLocation()
	RoshLog(
		"%s rosh-peek who=%s since-kill=%s seen=%s step=end why=%s dist=%d took=%.0f ward=%s",
		TeamName(team),
		peeker ~= nil and ShortName(peeker) or "-",
		SinceKillText(state),
		seen and "yes" or "no",
		why,
		peeker ~= nil and pit ~= nil and math.floor(GetUnitToLocationDistance(peeker, pit)) or -1,
		now - (state.tripStart or now),
		state.wardPlanted and "planted" or "no"
	)
	state.peekerId = nil
	state.lastTripEnd = now
	state.visibleSince = nil
end

local function UpdatePeek(state, team, now, seen, pit)
	local pitVisible = pit ~= nil and IsLocationVisible(pit) == true
	if state.peekerId ~= nil then
		local peeker = MemberById(team, state.peekerId)
		local why = nil
		if seen then
			why = "seen"
		elseif state.phase ~= "window" then
			why = "phase-" .. tostring(state.phase)
		elseif peeker == nil or not peeker:IsAlive() then
			why = "dead"
		elseif now > (state.tripDeadline or now) then
			why = "timeout"
		elseif Danger(peeker) then
			why = "danger"
		elseif pitVisible then
			state.visibleSince = state.visibleSince or now
			if now - state.visibleSince >= PEEK_SEE_HOLD then
				why = "looked"
			end
		end
		if not pitVisible then
			state.visibleSince = nil
		end
		if why ~= nil then
			EndTrip(state, team, now, why, seen)
		end
		return
	end
	local due = Rules.PeekDue({
		phase = state.phase,
		seen = seen,
		pitVisible = pitVisible,
		tripActive = false,
		lastTripEnd = state.lastTripEnd,
		now = now,
	})
	if not due or pit == nil then
		return
	end
	local candidates = {}
	for slot = 1, #(GetTeamPlayers(team) or {}) do
		local member = GetTeamMember(slot)
		if member ~= nil and not member:IsNull() and member:IsAlive() and not member:IsIllusion() then
			local pid = member:GetPlayerID()
			local free = IsPlayerBot(pid)
				and Fu.GetHP(member) >= PEEK_MIN_HP
				and not member:WasRecentlyDamagedByAnyHero(3.0)
				and not Busy(member)
			candidates[#candidates + 1] = {
				id = pid,
				support = not Fu.IsCore(member),
				dist = GetUnitToLocationDistance(member, pit),
				ok = free,
				name = ShortName(member),
				unitName = member:GetUnitName(),
			}
		end
	end
	local pick = Rules.PickPeeker(candidates)
	if pick == nil then
		-- Nobody free now: look again in 10s, not a full interval.
		state.lastTripEnd = now - Rules.PEEK_INTERVAL + 10
		return
	end
	state.peekerId = pick.id
	state.peekerUnit = pick.unitName
	state.tripStart = now
	state.tripDeadline = now + math.min(PEEK_TRIP_MAX, PEEK_TRIP_BASE + pick.dist / PEEK_WALK_SPEED)
	state.visibleSince = nil
	state.wardPlanted = false
	state.wardTried = false
	RoshLog(
		"%s rosh-peek who=%s since-kill=%s seen=no step=start dist=%d support=%s",
		TeamName(team),
		pick.name,
		SinceKillText(state),
		math.floor(pick.dist),
		tostring(pick.support)
	)
end

local function DefendNeeded()
	local desire = 0
	for _, lane in ipairs({ LANE_TOP or 1, LANE_MID or 2, LANE_BOT or 3 }) do
		desire = math.max(desire, GetDefendLaneDesire(lane) or 0)
	end
	local gameStates = Fu.Utils.GameStates
	local pinged = gameStates ~= nil
		and gameStates.defendPings ~= nil
		and GameTime() - (gameStates.defendPings.pingedTime or -999) <= 5
	return desire, pinged
end
local function LeadPushActive(team)
	local StrengthPush = require(GetScriptDirectory() .. "/lib/systems/strength_push")
	local strength = StrengthPush.State(team)
	return strength.active == true and strength.kind ~= "late-even"
end

local function UpdateCall(state, team, now, roshAlive)
	local defendDesire, defendPing = DefendNeeded()
	local ourAncient = GetAncient(team)
	local c = {
		roshAlive = roshAlive,
		now = now,
		aliveUs = AliveCount(team),
		aliveThem = AliveCount(GetOpposingTeam()),
		teamSize = #(GetTeamPlayers(team) or {}),
		defendDesire = defendDesire,
		defendPing = defendPing,
		baseThreat = ourAncient ~= nil and Utils.CountEnemyHeroesNear(ourAncient:GetLocation(), BASE_HERO_RADIUS) >= 1,
		leadPush = LeadPushActive(team),
		active = state.armed,
	}
	local ok, why = Rules.RoshanCallOk(c)
	if ok and now < state.blockedUntil then
		ok, why = false, "gave-up"
	end
	if ok and state.armed and now - (state.callSince or now) >= Rules.CALL_MAX then
		RoshLog(
			"%s rosh-window give-up held=%.0f since-kill=%s",
			TeamName(team),
			now - state.callSince,
			SinceKillText(state)
		)
		state.blockedUntil = now + Rules.CALL_BLOCK
		ok, why = false, "gave-up"
	end
	if ok ~= state.armed then
		RoshLog(
			"%s rosh-window %s why=%s alive=%d/%d defend=%.2f leadPush=%s since-kill=%s",
			TeamName(team),
			ok and "arm" or "disarm",
			why,
			c.aliveUs,
			c.aliveThem,
			defendDesire,
			tostring(c.leadPush),
			SinceKillText(state)
		)
		state.callSince = ok and now or nil
	end
	state.armed = ok
	state.armedWhy = why
end

local function Tick()
	local team = GetTeam()
	local state = TeamState(team)
	local now = DotaTime()
	if now - state.lastTick < TICK_SECONDS and now >= state.lastTick then
		return state
	end
	state.lastTick = now
	local killTime = Fu.GetRoshanKillTime()
	if killTime ~= state.killTime then
		-- A new kill: a new respawn window.
		if state.peekerId ~= nil then
			EndTrip(state, team, now, "new-kill", false)
		end
		state.killTime = killTime
		state.lastTripEnd = -math.huge
	end
	state.sinceKill = killTime > 0 and now - killTime or nil
	state.phase = Rules.RoshanPhase(state.sinceKill, Fu.IsModeTurbo())
	local roshAlive = Fu.IsRoshanAlive()
	local pit = Fu.GetCurrentRoshanLocation()
	UpdatePeek(state, team, now, state.phase == "window" and roshAlive, pit)
	UpdateCall(state, team, now, roshAlive)
	return state
end

-- The Roshan desire of a bot (wrapped at the end of mode_roshan_generic.lua): the peeker's trip desire, or the team
-- call raised to CALL_DESIRE.
function RoshanWindow.Desire(bot, desire)
	if type(desire) ~= "number" or ShouldSkipBotThink ~= nil and ShouldSkipBotThink(bot) then
		return desire
	end
	local okTick, state = pcall(Tick)
	if not okTick then
		if not RoshanWindow._errorLogged then
			RoshanWindow._errorLogged = true
			print(string.format("[SHy-ERROR] t=%.0f roshan-window tick: %s", DotaTime(), tostring(state)))
		end
		return desire
	end
	if not bot:IsAlive() or bot:IsIllusion() then
		return desire
	end
	local now = DotaTime()
	if IsPeeker(state, bot) then
		-- Hurt or hit: let go at once, not at the next team tick (the retreat mode exempts a bot in Roshan mode).
		if Fu.GetHP(bot) < PEEK_ABORT_HP or bot:WasRecentlyDamagedByAnyHero(1.0) then
			return desire
		end
		return math.max(desire, UnderRetreat(bot, RoshanWindow.PEEK_DESIRE))
	end
	if
		state.armed
		and desire < RoshanWindow.CALL_DESIRE
		and RAISABLE[StrengthRules.RoshBase(bot._roshWhy)]
		and Fu.GetHP(bot) >= CALL_MIN_HP
		and not Fu.ShouldLeaveRoshanFight(bot)
	then
		local call = UnderRetreat(bot, RoshanWindow.CALL_DESIRE)
		if call > desire then
			local was = bot._roshWhy
			bot._roshWhy = "rosh-window"
			if now >= (bot._roshWindowLogAt or -999) then
				bot._roshWindowLogAt = now + 10
				RoshLog(
					"%s %s rosh-window call desire=%.2f was=%.2f why=%s since-kill=%s",
					TeamName(GetTeam()),
					ShortName(bot),
					call,
					desire,
					tostring(was),
					SinceKillText(state)
				)
			end
			return call
		end
	end
	return desire
end

-- Whether the Roshan mode may take Roshan with even numbers (mode_roshan_generic.lua FreshTakeNumbers): the team's
-- call is armed (fresh) and we have at least their number alive.
function RoshanWindow.EvenTakeOk(alliesAlive, enemiesAlive)
	local state = states[GetTeam()]
	return state ~= nil
		and state.armed
		and DotaTime() - state.lastTick <= 3
		and (alliesAlive or 0) >= (enemiesAlive or 0)
end

local function ObserverWard(bot)
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and item:GetName() == "item_ward_observer" and Fu.CanCastAbility(item) then
			return item
		end
	end
	return nil
end
-- The peeker's walk (wrapped Think of the Roshan mode). Returns true when it gave the order.
local function PeekThink(bot)
	local state = states[GetTeam()]
	if state == nil or not IsPeeker(state, bot) then
		return false
	end
	local pit = Fu.GetCurrentRoshanLocation()
	if pit == nil then
		return false
	end
	local ward = not state.wardTried and ObserverWard(bot) or nil
	if ward ~= nil then
		local spot = Fu.AdjustLocationWithOffsetTowardsFountain(pit, WARD_OFFSET)
		if GetUnitToLocationDistance(bot, spot) <= OBSERVER_CAST_RANGE - 30 then
			state.wardTried = true
			state.wardPlanted = true
			RoshLog(
				"%s rosh-peek who=%s since-kill=%s seen=no step=ward at=%.0f,%.0f",
				TeamName(GetTeam()),
				ShortName(bot),
				SinceKillText(state),
				spot.x,
				spot.y
			)
			bot:Action_UseAbilityOnLocation(ward, spot)
			return true
		end
		bot:Action_MoveToLocation(spot)
		return true
	end
	bot:Action_MoveToLocation(Fu.AdjustLocationWithOffsetTowardsFountain(pit, PEEK_STAND_OFFSET))
	return true
end
function RoshanWindow.Think(bot)
	local ok, handled = pcall(PeekThink, bot)
	return ok and handled == true
end

-- For tests and other systems: the team's state (armed, phase, peekerId, ...).
function RoshanWindow.State(team)
	return TeamState(team or GetTeam())
end
RoshanWindow._Tick = Tick

return RoshanWindow
