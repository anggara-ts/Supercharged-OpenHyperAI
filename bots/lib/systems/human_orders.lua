-- Shared bot system: human orders (#222). The human's pings and chat commands become team orders for the bots.
--   * Ping tiers by count (maintainer, 2026-11-23: "1 ping = ask / 2 ping = force ally nearby ping / 3+ ping = force
--     all ally accross map"): one ping is a request (ASK: the bots check it, bots/lib/systems/human_order_rules.lua,
--     and may refuse); the same ping again within 2s is FORCE NEAR (every bot within 4000 or at that lane goes); a
--     third is FORCE ALL (every bot, by TP when the walk is long). `!push top` is FORCE NEAR, `!push top all` FORCE
--     ALL. A force still queues dead, channelling and very low bots; they join when back.
--   * Replies ("response 'on my way' only when acknowledging. no reply for 'cant do'"): every bot that goes says
--     "On my way!" (a queued bot when it joins); bots that can't go say nothing. Only when nobody goes does one bot
--     say one short reason, at most once per 30s per team, after the 2s a repeated ping has to force the order.
--   * What a ping means comes from what it is on, whatever the ping type: an enemy hero (focus in a fight, gank
--     elsewhere), an enemy building or wave near their tower (push), our building or a wave coming to ours
--     (defend), a neutral camp (one bot, a core first, clears it), Roshan, or fog (chase a hero seen there a moment
--     ago, or scout). Only a non-normal ping on empty ground or fog is "danger": the bots near it back off for a
--     few seconds, on top of the running order (it does not replace it).
--   * The modes read the order through the hooks below: Push.GetPushDesire (push), Defend.GetDefendDesire
--     (defend), mode_farm_generic.lua (camp), mode_roshan_generic.lua (rosh), the attack override (focus target)
--     and mode_assemble_generic.lua (gank, chase, fog, group, danger, move; it also runs Tick).
-- The module is shared by the team's bots (as bots/lib/systems/role.lua is), so one order serves all of them.
--
-- Logs: [SHy-PING] t= <hero> order kind= from= via=ping|insist|chat tier=ask|force-near|force-all count= lane=
-- target= verdict=go|refuse|queue why= responders= queued= reply= replies= cands=<hero>:<answer>[/<state>]:<dist>,...
-- (danger: affected=) once per order; per bot obey / queue why= / ignore why= / done why=, and <hero> said id= reply=
-- for every chat reply. A forced bot that goes by TP prints [SHy-TRAVEL] ... for=order.
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Rules = require(GetScriptDirectory() .. "/lib/systems/human_order_rules")
local Lines = require(GetScriptDirectory() .. "/lib/data/human_order_lines")
local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
local HeroDisplayNames = require(GetScriptDirectory() .. "/lib/data/hero_display_names")
local ChatGuard = require(GetScriptDirectory() .. "/lib/systems/chat_guard")
local ObjectiveTravel = require(GetScriptDirectory() .. "/lib/systems/objective_travel")

local Orders = {}
Orders.Rules = Rules

-- An order's desire: above farm (up to ~0.6) and laning (0.565 for a safe core), below a base last stand (0.9) and
-- a hurt bot's retreat. Fades with HP so a retreat takes over; a bot under 30% HP leaves a request (done
-- why=low-hp); a forced order keeps it down to Rules.FORCE_MIN_HP (then it queues and rejoins when healed).
Orders.DESIRE = 0.75
Orders.LEAVE_HP = 0.3
-- A bot's think-to-think checks run at most this often for the whole team (seconds of game time).
local TICK_SECONDS = 0.2
-- A ping older than this when first read is old news (e.g. from before a reload).
local PING_FRESH_SECONDS = 2
-- A reply the chosen bot hasn't said by then is said by whichever bot runs the next tick.
local REPLY_FALLBACK_SECONDS = 1.5
-- Seconds between two replies (maintainer, game 075: "~0.5s apart").
local REPLY_GAP_SECONDS = Rules.REPLY_GAP_SECONDS

local state = {
	order = nil,
	nextId = 0,
	lastPingTime = nil,
	prevPing = nil,
	chat = nil,
	tickAt = -999,
	-- Chat replies waiting to be said, in order: { speakerId =, text =, key =, orderId =, kind =, at = }.
	replies = {},
	replyNextAt = -999,
	replySaidAt = -999,
	-- DotaTime() of the team's last "why nobody goes" line (Rules.RefusalAllowed), nil: none yet.
	refusalAt = nil,
	-- A danger ping's back-off runs beside the order (it does not replace it).
	danger = nil,
}
Orders.state = state

local LANE_OF = { top = LANE_TOP, mid = LANE_MID, bot = LANE_BOT }
local LANE_NAME = { [LANE_TOP] = "top", [LANE_MID] = "mid", [LANE_BOT] = "bot" }
local TOWERS = {
	top = { TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3 },
	mid = { TOWER_MID_1, TOWER_MID_2, TOWER_MID_3 },
	bot = { TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3 },
}
-- Kinds the assemble mode carries out (push, defend, farm and rosh go through their own modes; danger runs beside
-- the order, see Orders.AssembleDesire).
local ASSEMBLE_KINDS = { focus = true, gank = true, chase = true, fog = true, move = true, group = true }
local TARGET_KINDS = { focus = true, gank = true, chase = true, fog = true }
local PUSH_MODE = {
	[LANE_TOP] = BOT_MODE_PUSH_TOWER_TOP,
	[LANE_MID] = BOT_MODE_PUSH_TOWER_MID,
	[LANE_BOT] = BOT_MODE_PUSH_TOWER_BOT,
}
local DEFEND_MODE = {
	[LANE_TOP] = BOT_MODE_DEFEND_TOWER_TOP,
	[LANE_MID] = BOT_MODE_DEFEND_TOWER_MID,
	[LANE_BOT] = BOT_MODE_DEFEND_TOWER_BOT,
}

local function Short(unit)
	if unit == nil or unit:IsNull() then
		return "-"
	end
	return (string.gsub(unit:GetUnitName(), "npc_dota_hero_", ""))
end

local function DisplayName(unit)
	if unit == nil or unit:IsNull() then
		return ""
	end
	local unitName = unit:GetUnitName()
	local names = HeroDisplayNames[Localization.GetLocale()] or HeroDisplayNames.en
	return names[unitName] or HeroDisplayNames.en[unitName] or Short(unit)
end

local function Log(fmt, ...)
	pcall(print, string.format("[SHy-PING] t=%.0f " .. fmt, DotaTime(), ...))
end

local function Dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Our team's heroes: bots and humans, main heroes only (GetTeamMember takes a slot 1-5).
local function Members(wantBots)
	local list = {}
	for slot = 1, #GetTeamPlayers(GetTeam()) do
		local member = GetTeamMember(slot)
		if member ~= nil and not member:IsNull() and not member:IsIllusion() and member:IsBot() == wantBots then
			list[#list + 1] = member
		end
	end
	return list
end

local function MemberById(playerId)
	for slot = 1, #GetTeamPlayers(GetTeam()) do
		local member = GetTeamMember(slot)
		if member ~= nil and not member:IsNull() and member:GetPlayerID() == playerId then
			return member
		end
	end
	return nil
end

-- The newest ping among the team's humans (not only the first human's).
function Orders.NewestHumanPing()
	local bestHuman, bestPing = nil, nil
	for _, human in ipairs(Members(false)) do
		local ping = human:GetMostRecentPing()
		if ping ~= nil and ping.time ~= nil and ping.time ~= 0 and (bestPing == nil or ping.time > bestPing.time) then
			bestHuman, bestPing = human, ping
		end
	end
	return bestHuman, bestPing
end

-- Our base is under siege (defend.lua Defend.GetBaseSiege, kept in Fu.Utils.GameStates.baseSiege) away from `loc`.
local function BaseSiegeAwayFrom(loc)
	local states = Fu.Utils.GameStates
	local siege = states ~= nil and states.baseSiege or nil
	if siege == nil or DotaTime() - siege.at > 10 or siege.loc == nil then
		return false
	end
	return loc == nil or Dist(siege.loc, loc) > 3000
end

local function InFight(member)
	local enemies = member:GetNearbyHeroes(1200, true, BOT_MODE_NONE) or {}
	local count = 0
	for _, enemy in ipairs(enemies) do
		if Fu.IsValidHero(enemy) and not Fu.IsSuspiciousIllusion(enemy) then
			count = count + 1
		end
	end
	if count == 0 or not (member:WasRecentlyDamagedByAnyHero(2.5) or Fu.IsGoingOnSomeone(member)) then
		return false, false
	end
	local allies = member:GetNearbyHeroes(1200, false, BOT_MODE_NONE) or {}
	return true, #allies < count or Fu.GetHP(member) < 0.45
end

local function BotState(member)
	local alive = member:IsAlive()
	local inFight, losing = false, false
	if alive then
		inFight, losing = InFight(member)
	end
	local states = Fu.Utils.GameStates
	local siege = states ~= nil and states.baseSiege or nil
	local holdingBase = alive
		and Fu.IsDefending(member)
		and siege ~= nil
		and DotaTime() - siege.at <= 10
		and siege.loc ~= nil
		and GetUnitToLocationDistance(member, siege.loc) < 3000
	return Rules.BotState({
		alive = alive,
		hp = alive and Fu.GetHP(member) or 0,
		retreating = alive and Fu.IsRetreating(member),
		inFight = inFight,
		losing = losing,
		holdingBase = holdingBase,
	})
end

-- A bot within this distance of the ordered lane's path stands "on" it (force near takes it), outside both bases
-- (every lane's path starts at the Ancients, so a bot in a base is near all three). Map estimates.
local ON_LANE_DISTANCE = 1200
local ON_LANE_MIN_AMOUNT, ON_LANE_MAX_AMOUNT = 0.15, 0.85

local function Candidates(loc, laneName)
	local list = {}
	for _, member in ipairs(Members(true)) do
		local alive = member:IsAlive()
		local onLane = false
		if alive and laneName ~= nil and LANE_OF[laneName] ~= nil then
			local along = GetAmountAlongLane(LANE_OF[laneName], member:GetLocation())
			onLane = along ~= nil
				and along.distance ~= nil
				and along.distance <= ON_LANE_DISTANCE
				and (along.amount or 0) >= ON_LANE_MIN_AMOUNT
				and (along.amount or 1) <= ON_LANE_MAX_AMOUNT
		end
		list[#list + 1] = {
			id = member:GetPlayerID(),
			unit = member,
			dist = alive and GetUnitToLocationDistance(member, loc) or math.huge,
			state = BotState(member),
			core = Fu.IsCore(member),
			lane = LANE_NAME[member:GetAssignedLane()],
			hp = alive and Fu.GetHP(member) or 0,
			channeling = alive and member:IsChanneling(),
			onLane = onLane,
		}
	end
	return list
end

-- A queued bot's state for Rules.ForceRejoin.
local function ForceFacts(member)
	local alive = member:IsAlive()
	return {
		state = alive and "ok" or "dead",
		hp = alive and Fu.GetHP(member) or 0,
		channeling = alive and member:IsChanneling(),
	}
end

-- The nearest lane building of `team` within `radius` of `loc`: building, distance, lane, tier.
local function NearestBuilding(listType, loc, radius)
	local best, bestDist, bestLane, bestTier = nil, radius, nil, nil
	for _, building in pairs(GetUnitList(listType) or {}) do
		if building ~= nil and not building:IsNull() and building:IsAlive() then
			local lane, tier = Rules.BuildingInfo(building:GetUnitName())
			if lane ~= nil then
				local dist = GetUnitToLocationDistance(building, loc)
				if dist <= bestDist then
					best, bestDist, bestLane, bestTier = building, dist, lane, tier
				end
			end
		end
	end
	if best == nil then
		return nil
	end
	return best, bestDist, bestLane, bestTier
end

local function NearestLane(loc)
	local bestLane, bestDist = "mid", math.huge
	for laneName, lane in pairs(LANE_OF) do
		local along = GetAmountAlongLane(lane, loc)
		if along ~= nil and along.distance ~= nil and along.distance < bestDist then
			bestLane, bestDist = laneName, along.distance
		end
	end
	return bestLane
end

local function IsLaneCreep(unit)
	local unitName = unit:GetUnitName()
	return string.find(unitName, "creep_goodguys") ~= nil
		or string.find(unitName, "creep_badguys") ~= nil
		or string.find(unitName, "siege") ~= nil
end

local function AllyFightingNear(enemy)
	local enemyLoc = enemy:GetLocation()
	local allies = Fu.GetAlliesNearLoc(enemyLoc, 1200) or {}
	if #allies == 0 then
		return false
	end
	if enemy:WasRecentlyDamagedByAnyHero(3) then
		return true
	end
	for _, ally in ipairs(allies) do
		if Fu.IsValidHero(ally) and ally:WasRecentlyDamagedByAnyHero(3) then
			return true
		end
	end
	return false
end

local function VisibleEnemyHero(loc, radius, playerId)
	local best, bestDist = nil, radius
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES) or {}) do
		if
			Fu.IsValidHero(enemy)
			and enemy:CanBeSeen()
			and not Fu.IsSuspiciousIllusion(enemy)
			and (playerId == nil or enemy:GetPlayerID() == playerId)
		then
			local dist = GetUnitToLocationDistance(enemy, loc)
			if dist <= bestDist then
				best, bestDist = enemy, dist
			end
		end
	end
	return best
end

-- Facts about a ping spot for Rules.Classify, and what was found there.
function Orders.ReadSpot(loc, normal)
	local facts = { normal = normal, visible = IsLocationVisible(loc) }
	local found = {}
	local enemy = VisibleEnemyHero(loc, Rules.HERO_RADIUS)
	if enemy ~= nil then
		facts.enemyHero = true
		facts.enemyHeroInFight = AllyFightingNear(enemy)
		found.target, found.targetId = enemy, enemy:GetPlayerID()
	end
	local roshLoc = Fu.GetCurrentRoshanLocation()
	if roshLoc ~= nil and Dist(roshLoc, loc) <= Rules.ROSHAN_RADIUS then
		facts.roshan = true
	end
	local enemyBuilding, enemyDist, enemyLane, enemyTier =
		NearestBuilding(UNIT_LIST_ENEMY_BUILDINGS, loc, Rules.ENEMY_BUILDING_RADIUS)
	local ourBuilding, ourDist, ourLane, ourTier =
		NearestBuilding(UNIT_LIST_ALLIED_BUILDINGS, loc, Rules.OUR_BUILDING_RADIUS)
	facts.enemyBuildingDist, facts.ourBuildingDist = enemyDist, ourDist
	found.enemyBuilding, found.enemyLane, found.enemyTier = enemyBuilding, enemyLane, enemyTier
	found.ourBuilding, found.ourLane, found.ourTier = ourBuilding, ourLane, ourTier
	for _, creep in pairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS) or {}) do
		if Fu.IsValid(creep) and IsLaneCreep(creep) and GetUnitToLocationDistance(creep, loc) <= Rules.WAVE_RADIUS then
			local ourAncient, theirAncient = GetAncient(GetTeam()), GetAncient(GetOpposingTeam())
			if ourAncient ~= nil and theirAncient ~= nil then
				local toOurs = GetUnitToUnitDistance(creep, ourAncient)
				local toTheirs = GetUnitToUnitDistance(creep, theirAncient)
				facts.waveSide = toTheirs < toOurs and "theirs" or "ours"
				found.waveLane = NearestLane(loc)
			end
			break
		end
	end
	local camps = {}
	local spawners = {}
	for _, spawner in pairs(GetNeutralSpawners() or {}) do
		if spawner ~= nil and spawner.location ~= nil then
			camps[#camps + 1] = { x = spawner.location.x, y = spawner.location.y }
			spawners[#spawners + 1] = spawner
		end
	end
	local campIndex, campDist = Rules.NearestCamp(camps, loc.x, loc.y)
	if campIndex ~= nil then
		facts.campDist = campDist
		found.camp = spawners[campIndex]
	end
	if not facts.visible then
		for _, playerId in ipairs(GetTeamPlayers(GetOpposingTeam())) do
			if IsHeroAlive(playerId) then
				local info = GetHeroLastSeenInfo(playerId)
				local seen = info ~= nil and info[1] or nil
				if
					seen ~= nil
					and seen.location ~= nil
					and seen.time_since_seen <= Rules.CHASE_SEEN_SECONDS
					and Dist(seen.location, loc) <= Rules.CHASE_RADIUS
				then
					facts.recentEnemySeen = true
					found.targetId = found.targetId or playerId
					found.seenAgo = seen.time_since_seen
					break
				end
			end
		end
	end
	return facts, found
end

-- Enemy heroes not seen for 10s+ (for the scout's wait rule).
local function MissingEnemies()
	local missing = 0
	for _, playerId in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(playerId) then
			local info = GetHeroLastSeenInfo(playerId)
			local seen = info ~= nil and info[1] or nil
			if seen == nil or seen.time_since_seen >= 10 then
				missing = missing + 1
			end
		end
	end
	return missing
end

-- Chat: every bot that answers an order says its own line, REPLY_GAP_SECONDS apart (maintainer, game 075); a line
-- its bot hasn't said REPLY_FALLBACK_SECONDS after it is due (a dead bot does not think) is said by whichever bot
-- runs the next tick. The team's repeat filter (bots/lib/systems/chat_guard.lua) is skipped: "On my way!" answers a
-- new ping each time; the "On my way!" lines still vary per bot.
local function Say(bot, text)
	local chat = ChatGuard.originalChat or bot.ActionImmediate_Chat
	pcall(chat, bot, text, false)
end

local function ReplyText(key, human, seconds, index)
	if key == "on-my-way" then
		-- The assemble mode's lines (localization.lua say_assemble: "On my way!", "Coming!", ...), one per bot.
		local lines = Localization.Get("say_assemble")
		if type(lines) == "table" and #lines > 0 then
			return lines[((index or 1) - 1) % #lines + 1]
		end
		return "On my way!"
	end
	return Lines.Get(Localization.GetLocale(), key, DisplayName(human), seconds)
end

-- `delay`: seconds to hold the line (a refusal waits for a repeated ping that would force the order).
local function QueueReply(orderId, kind, speakerId, key, human, seconds, index, delay)
	local now = GameTime()
	local at = math.max(now + (delay or 0), state.replyNextAt)
	state.replyNextAt = at + REPLY_GAP_SECONDS
	local reply = {
		speakerId = speakerId,
		key = key,
		orderId = orderId or 0,
		kind = kind or "-",
		text = ReplyText(key, human, seconds, index),
		at = at,
	}
	if Rules.IsRefusalKey(key) then
		-- Counts for the team's limit now; restored if the line is dropped unsaid (DropRefusals).
		reply.prevRefusalAt = state.refusalAt
		state.refusalAt = DotaTime()
	end
	state.replies[#state.replies + 1] = reply
end

-- A repeated ping forced the order: the reasons not said yet are dropped (the bots go after all).
local function DropRefusals()
	local kept, nextAt = {}, -999
	for _, reply in ipairs(state.replies) do
		if Rules.IsRefusalKey(reply.key) then
			state.refusalAt = reply.prevRefusalAt
			Log("- drop id=%d kind=%s reply=%s why=forced", reply.orderId, reply.kind, reply.key)
		else
			kept[#kept + 1] = reply
			nextAt = math.max(nextAt, reply.at + REPLY_GAP_SECONDS)
		end
	end
	state.replies = kept
	state.replyNextAt = nextAt
end

local function SayPendingReply(bot)
	local now = GameTime()
	if #state.replies == 0 or (now < state.replySaidAt + REPLY_GAP_SECONDS and now >= state.replySaidAt) then
		return
	end
	local botId = bot:GetPlayerID()
	for i, reply in ipairs(state.replies) do
		if now >= reply.at and (botId == reply.speakerId or now - reply.at > REPLY_FALLBACK_SECONDS) then
			table.remove(state.replies, i)
			state.replySaidAt = now
			Say(bot, reply.text)
			Log(
				"%s said id=%d kind=%s reply=%s%s",
				Short(bot),
				reply.orderId,
				reply.kind,
				reply.key,
				botId ~= reply.speakerId and (" for=" .. Short(MemberById(reply.speakerId))) or ""
			)
			return
		end
	end
end

local function NamesOf(ids)
	local names = {}
	for _, id in ipairs(ids) do
		names[#names + 1] = Short(MemberById(id))
	end
	return #names > 0 and table.concat(names, ",") or "-"
end

local function LogDone(order, entry, why)
	Log("%s done id=%d kind=%s why=%s", Short(entry.unit), order.id, order.kind, why)
end

local function Finish(slot, why)
	local order = state[slot]
	if order == nil then
		return
	end
	state[slot] = nil
	for _, entry in pairs(order.bots) do
		if entry.state == "obey" or entry.state == "queue" then
			entry.state = "done"
			LogDone(order, entry, why)
		end
	end
end

local function EndOrder(why)
	Finish("order", why)
end
Orders.EndOrder = EndOrder

local function LeaveOrder(order, entry, why)
	entry.state = "done"
	LogDone(order, entry, why)
	for _, other in pairs(order.bots) do
		if other.state == "obey" or other.state == "queue" then
			return
		end
	end
	if state.order == order then
		state.order = nil
	elseif state.danger == order then
		state.danger = nil
	end
end

-- Nobody can go: the nearest bot and why it can't (dead bots: the first one back), from Rules.PickResponders'
-- decisions.
local function NearestRefuser(decisions, unitById)
	local nearest = nil
	for _, d in ipairs(decisions) do
		local unit = unitById[d.id]
		if unit ~= nil then
			if nearest == nil or d.dist < nearest.dist then
				nearest = d
			elseif
				d.dist == math.huge
				and nearest.dist == math.huge
				and unit:GetRespawnTime() < unitById[nearest.id]:GetRespawnTime()
			then
				nearest = d
			end
		end
	end
	if nearest == nil then
		return nil
	end
	local key = "busy"
	if
		nearest.state == "dead"
		or nearest.state == "low-hp"
		or nearest.state == "retreat"
		or nearest.state == "base"
	then
		key = nearest.state
	end
	local seconds = nearest.state == "dead" and unitById[nearest.id]:GetRespawnTime() or nil
	return { id = nearest.id, key = key, seconds = seconds }
end

-- How long until `unit` can be at `loc` (a dead bot: its respawn, then the walk from the fountain, roughly).
local function EtaOf(unit, loc)
	if unit == nil or unit:IsNull() then
		return 0
	end
	if not unit:IsAlive() then
		return (unit:GetRespawnTime() or 0) + 20
	end
	return ObjectiveTravel.Eta(unit, loc)
end

-- Starts an order. `found`: what Orders.ReadSpot found (target, buildings, camp), or the chat command's target.
-- `tier`: "ask" (default) / "force-near" / "force-all"; `count`: pings in a row (1 for a chat command); `acked`:
-- bots that already said "On my way!" for this ping chain (they don't say it again).
function Orders.Start(kind, via, human, loc, found, tickBot, tier, count, acked)
	tier = kind == "danger" and "ask" or (tier or "ask")
	state.nextId = state.nextId + 1
	local lane = found.lane
	local building, buildingTier = found.building, found.tier
	if kind == "push" then
		lane = lane or found.enemyLane or found.waveLane
		building, buildingTier = building or found.enemyBuilding, buildingTier or found.enemyTier
	elseif kind == "defend" then
		lane = lane or found.ourLane or found.waveLane
		building, buildingTier = building or found.ourBuilding, buildingTier or found.ourTier
	end
	local cands = Candidates(loc, lane)
	local aliveAllies = 0
	for slot = 1, #GetTeamPlayers(GetTeam()) do
		local member = GetTeamMember(slot)
		if member ~= nil and member:IsAlive() then
			aliveAllies = aliveAllies + 1
		end
	end
	local ourCreepsNear = false
	if kind == "push" and lane ~= nil and building ~= nil then
		local front = GetLaneFrontLocation(GetTeam(), LANE_OF[lane], 0)
		ourCreepsNear = front ~= nil and GetUnitToLocationDistance(building, front) <= 1600
	end
	local facts = {
		now = DotaTime(),
		aliveAllies = aliveAllies,
		enemiesNear = #(Fu.GetLastSeenEnemiesNearLoc(loc, 1600) or {}),
		humanNear = human ~= nil and human:IsAlive() and GetUnitToLocationDistance(human, loc) <= 2500,
		baseUnderAttack = kind ~= "defend" and BaseSiegeAwayFrom(loc),
		tier = buildingTier,
		ourCreepsNear = ourCreepsNear,
	}
	if kind == "rosh" then
		facts.roshanAlive = Fu.IsRoshanAlive()
	end
	local need = Rules.Need(kind, facts)
	local obey, queue, ignore, decisions =
		Rules.PickResponders(kind, cands, need, { lane = lane, now = DotaTime(), tier = tier })
	facts.available = Rules.Available(decisions)
	local checkVerdict, why = Rules.Check(kind, tier, facts)
	if checkVerdict ~= "go" then
		obey, queue = {}, {}
	end
	local verdict = Rules.Verdict(checkVerdict, #obey, #queue, kind)
	if verdict == "refuse" and checkVerdict == "go" then
		why = "nobody-free"
	end
	local unitById = {}
	for _, cand in ipairs(cands) do
		unitById[cand.id] = cand.unit
	end
	local queueWhy = {}
	for _, d in ipairs(decisions) do
		if d.answer == "queue" then
			queueWhy[d.id] = d.why or "in-fight"
		end
	end
	local maxEta = 0
	if tier ~= "ask" then
		for _, id in ipairs(obey) do
			maxEta = math.max(maxEta, EtaOf(unitById[id], loc))
		end
		for _, id in ipairs(queue) do
			maxEta = math.max(maxEta, EtaOf(unitById[id], loc))
		end
	end
	local order = {
		id = state.nextId,
		kind = kind,
		via = via,
		tier = tier,
		count = count or 1,
		from = human,
		loc = loc,
		lane = lane,
		building = building,
		buildingTier = buildingTier,
		camp = found.camp,
		target = found.target,
		targetId = found.targetId,
		startedAt = DotaTime(),
		untilAt = DotaTime() + Rules.OrderSeconds(kind, tier, maxEta),
		bots = {},
	}
	if order.camp ~= nil then
		order.campObj = { idx = order.camp.idx, cattr = order.camp }
	end
	for _, id in ipairs(obey) do
		order.bots[id] = { state = "obey", unit = unitById[id] }
	end
	for _, id in ipairs(queue) do
		order.bots[id] = { state = "queue", unit = unitById[id], why = queueWhy[id] }
	end
	-- Replies (Rules.ReplyPlan): "On my way!" from every bot that goes (not again for the same ping chain); one
	-- reason only when nobody goes.
	local refuser = nil
	if verdict == "refuse" and why == "nobody-free" and kind ~= "danger" then
		refuser = NearestRefuser(decisions, unitById)
	end
	local replyKey, replies = "none", {}
	local tickId = tickBot ~= nil and tickBot:GetPlayerID() or nil
	local plan = Rules.ReplyPlan(
		kind,
		verdict,
		why,
		obey,
		refuser,
		{ acked = acked, now = DotaTime(), lastRefusalAt = state.refusalAt }
	)
	for _, line in ipairs(plan) do
		local speakerId = line.id or tickId
		QueueReply(order.id, kind, speakerId, line.key, human, line.seconds, line.index, line.delay)
		if replyKey == "none" then
			replyKey = line.key
		end
		replies[#replies + 1] = Short(unitById[speakerId] or MemberById(speakerId)) .. ":" .. line.key
	end
	local targetName = "-"
	if order.target ~= nil then
		targetName = Short(order.target)
	elseif building ~= nil then
		targetName = (string.gsub(building:GetUnitName(), "npc_dota_", ""))
	elseif order.camp ~= nil then
		targetName = "camp-" .. tostring(order.camp.type or "?")
	end
	local extra = ""
	if kind == "fog" then
		extra = string.format(" missing=%d", MissingEnemies())
	elseif kind == "chase" then
		extra = string.format(" seen=%.1f", found.seenAgo or -1)
	elseif kind == "danger" then
		extra = " affected=" .. NamesOf(obey)
	end
	Log(
		"%s order kind=%s from=%s via=%s tier=%s count=%d lane=%s target=%s verdict=%s why=%s responders=%s queued=%s reply=%s need=%s until=%.0f at=%.0f,%.0f id=%d%s replies=%s cands=%s",
		Short(tickBot),
		kind,
		Short(human),
		via,
		tier,
		order.count,
		tostring(lane or "-"),
		targetName,
		verdict,
		tostring(why),
		NamesOf(obey),
		NamesOf(queue),
		replyKey,
		tier ~= "ask" and kind ~= "farm" and "all" or tostring(need),
		order.untilAt - order.startedAt,
		loc.x,
		loc.y,
		order.id,
		extra,
		#replies > 0 and table.concat(replies, ",") or "-",
		Rules.CandsText(decisions, function(id)
			return Short(unitById[id])
		end)
	)
	-- Every bot that does not go is logged with why (the chat stays quiet: maintainer, "no reply for 'cant do'").
	for _, entry in ipairs(ignore) do
		local unit = unitById[entry.id]
		if unit ~= nil then
			Log("%s ignore id=%d kind=%s tier=%s why=%s", Short(unit), order.id, kind, tier, entry.why)
		end
	end
	for _, id in ipairs(queue) do
		Log("%s queue id=%d kind=%s tier=%s why=%s", Short(unitById[id]), order.id, kind, tier, queueWhy[id])
	end
	-- A danger ping runs beside the current order (only for the bots near it); a refused request leaves the current
	-- order running; an accepted one replaces it.
	if kind == "danger" then
		if #obey > 0 then
			Finish("danger", "replaced")
			state.danger = order
		end
	elseif verdict ~= "refuse" then
		EndOrder("replaced")
		state.order = order
	end
	return order, verdict, why
end

-- Chat commands, from the reply member's chat callback (ability_item_usage_generic.lua Usage.SetReplyHumanTime).
-- Returns true when the text was an order command (no other chat reply then).
function Orders.OnChat(chatEvent)
	if chatEvent == nil then
		return false
	end
	local command = Rules.ParseChat(chatEvent.string)
	if command == nil then
		return false
	end
	local senderId = chatEvent.player_id
	if senderId == nil or IsPlayerBot(senderId) or not Fu.Role.IsAllyMemberID(senderId) then
		return true
	end
	state.chat = { kind = command.kind, lane = command.lane, all = command.all, senderId = senderId, at = GameTime() }
	return true
end

-- The furthest-forward building of `team` on `lane` (tier 1 first): building, tier.
local function FrontTower(team, laneName)
	for tier, towerId in ipairs(TOWERS[laneName]) do
		local tower = GetTower(team, towerId)
		if tower ~= nil and not tower:IsNull() and tower:IsAlive() then
			return tower, tier
		end
	end
	return nil, 4
end

local function StartChatOrder(chat, tickBot)
	local human = MemberById(chat.senderId)
	if chat.kind == "no" then
		local hadOrder = state.order ~= nil or state.danger ~= nil
		EndOrder("cancelled")
		Finish("danger", "cancelled")
		Log("%s order kind=no from=%s via=chat verdict=%s", Short(tickBot), Short(human), hadOrder and "go" or "none")
		if hadOrder then
			QueueReply(nil, "no", tickBot:GetPlayerID(), "cancelled", human)
		end
		return
	end
	if (chat.kind == "push" or chat.kind == "defend") and chat.lane == nil then
		Log("%s order kind=%s from=%s via=chat verdict=refuse why=no-lane", Short(tickBot), chat.kind, Short(human))
		QueueReply(nil, chat.kind, tickBot:GetPlayerID(), "which_lane", human)
		return
	end
	local found = {}
	local loc = nil
	if chat.kind == "push" then
		local tower, tier = FrontTower(GetOpposingTeam(), chat.lane)
		found.lane, found.building, found.tier = chat.lane, tower, tier
		loc = tower ~= nil and tower:GetLocation() or GetLaneFrontLocation(GetTeam(), LANE_OF[chat.lane], 0)
	elseif chat.kind == "defend" then
		local tower, tier = FrontTower(GetTeam(), chat.lane)
		found.lane, found.building, found.tier = chat.lane, tower, tier
		loc = tower ~= nil and tower:GetLocation() or GetLaneFrontLocation(GetTeam(), LANE_OF[chat.lane], 0)
	elseif chat.kind == "rosh" then
		loc = Fu.GetCurrentRoshanLocation()
	elseif chat.kind == "group" and human ~= nil then
		loc = human:GetLocation()
	end
	if loc == nil then
		return
	end
	-- A chat command is FORCE NEAR; with "all" (`!push top all`) FORCE ALL (maintainer, 2026-11-23).
	Orders.Start(chat.kind, "chat", human, loc, found, tickBot, chat.all and "force-all" or "force-near", 1)
end

local function StartPingOrder(human, ping, tickBot)
	local loc = ping.location
	local facts, found = Orders.ReadSpot(loc, ping.normal_ping)
	local kind = Rules.Classify(facts)
	local targetKey = nil
	if found.target ~= nil then
		targetKey = "hero" .. tostring(found.targetId)
	elseif found.enemyBuilding ~= nil or found.ourBuilding ~= nil then
		targetKey = (found.enemyBuilding or found.ourBuilding):GetUnitName()
	end
	local current = {
		time = ping.time,
		x = loc.x,
		y = loc.y,
		targetKey = targetKey,
		humanId = human:GetPlayerID(),
		normal = ping.normal_ping,
	}
	-- Pings in a row on the same spot or target, each within 2s of the one before: 1 ask, 2 force near, 3+ force all.
	local prev = state.prevPing
	local same = prev ~= nil and prev.humanId == current.humanId and prev.normal == current.normal
	current.count = same and Rules.PingCount(prev, current) or 1
	local tier = kind == "danger" and "ask" or Rules.Tier(current.count)
	local acked = nil
	if current.count >= 2 then
		-- The order is forced now: a reason not said yet is dropped, and the bots that already said "On my way!" for
		-- this chain don't say it again.
		DropRefusals()
		acked = prev.acked
	end
	local via = current.count >= 2 and "insist" or "ping"
	local order, verdict = Orders.Start(kind, via, human, loc, found, tickBot, tier, current.count, acked)
	current.acked = {}
	for id in pairs(acked or {}) do
		current.acked[id] = true
	end
	if verdict ~= "refuse" and kind ~= "danger" then
		for id, entry in pairs(order.bots) do
			if entry.state == "obey" then
				current.acked[id] = true
			end
		end
	end
	state.prevPing = current
end

-- Keeps the current order up to date: ends it when it is done, lets queued bots go after their fight.
local function KeepOrder()
	local now = DotaTime()
	if state.danger ~= nil and now > state.danger.untilAt then
		Finish("danger", "timeout")
	end
	local order = state.order
	if order == nil then
		return
	end
	if now > order.untilAt then
		return EndOrder("timeout")
	end
	if TARGET_KINDS[order.kind] and order.targetId ~= nil and not IsHeroAlive(order.targetId) then
		return EndOrder("target-dead")
	end
	if order.kind == "push" and order.building ~= nil and (order.building:IsNull() or not order.building:IsAlive()) then
		return EndOrder("building-dead")
	end
	if order.kind == "rosh" and not Fu.IsRoshanAlive() then
		return EndOrder("roshan-dead")
	end
	if order.kind == "defend" and now - order.startedAt > 8 then
		local enemies = #(Fu.GetLastSeenEnemiesNearLoc(order.loc, 1600) or {})
		local creeps = 0
		for _, creep in pairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS) or {}) do
			if Fu.IsValid(creep) and IsLaneCreep(creep) and GetUnitToLocationDistance(creep, order.loc) <= 1200 then
				creeps = creeps + 1
			end
		end
		if enemies == 0 and creeps == 0 then
			return EndOrder("defence-over")
		end
	end
	if order.kind == "farm" and order.camp ~= nil and IsLocationVisible(order.camp.location) then
		local near = false
		for _, entry in pairs(order.bots) do
			if
				entry.state == "obey"
				and entry.unit:IsAlive()
				and GetUnitToLocationDistance(entry.unit, order.camp.location) <= 800
			then
				near = true
			end
		end
		if near then
			local creepsLeft = 0
			for _, creep in pairs(GetUnitList(UNIT_LIST_NEUTRAL_CREEPS) or {}) do
				if Fu.IsValid(creep) and GetUnitToLocationDistance(creep, order.camp.location) <= 700 then
					creepsLeft = creepsLeft + 1
				end
			end
			if creepsLeft == 0 then
				return EndOrder("cleared")
			end
		end
	end
	if order.kind == "fog" or order.kind == "chase" then
		local enemy = VisibleEnemyHero(order.loc, 900, order.kind == "chase" and order.targetId or nil)
		if enemy ~= nil and enemy ~= order.target then
			order.target, order.targetId = enemy, enemy:GetPlayerID()
			Log("%s retarget id=%d kind=%s target=%s", Short(enemy), order.id, order.kind, Short(enemy))
		end
	end
	-- Queued bots join when they can, and say "On my way!" then (maintainer: "on my way" only when acknowledging).
	-- A request's queued bot (in a fight) leaves when it dies or retreats; a forced order's queued bot (dead,
	-- channelling, very low) waits until it respawns, the channel ends or it is healed (Rules.ForceRejoin).
	for id, entry in pairs(order.bots) do
		if entry.state == "queue" then
			local join = false
			if order.tier ~= "ask" and entry.why ~= "in-fight" then
				join = Rules.ForceRejoin(entry.why, ForceFacts(entry.unit))
			else
				local botState = BotState(entry.unit)
				if botState == "ok" then
					join = true
				elseif botState == "dead" or botState == "retreat" or botState == "low-hp" then
					LeaveOrder(order, entry, botState)
					if state.order ~= order then
						return
					end
				end
			end
			if join then
				entry.state, entry.logged, entry.after = "obey", false, entry.why or "in-fight"
				QueueReply(order.id, order.kind, id, "on-my-way", order.from, nil, (id % 5) + 1)
			end
		end
	end
end

-- Run by every bot from mode_assemble_generic.lua's GetDesire; the team's work happens at most every TICK_SECONDS.
function Orders.Tick(bot)
	if bot == nil or not bot:IsBot() or GetGameState() ~= GAME_STATE_GAME_IN_PROGRESS then
		return
	end
	SayPendingReply(bot)
	local now = GameTime()
	-- The ping is read on every bot's think, before the tick gate: only the newest ping is visible, so a fast burst
	-- (3 clicks within 0.4s) read every TICK_SECONDS would count as 2. It only does work when a new ping arrives.
	local human, ping = Orders.NewestHumanPing()
	if
		human ~= nil
		and ping ~= nil
		and ping.location ~= nil
		and ping.time ~= state.lastPingTime
		and now - ping.time <= PING_FRESH_SECONDS
	then
		state.lastPingTime = ping.time
		-- A ping in our own fountain area is never an order (maintainer 2026-11-23: five pings there are the
		-- credit line in ping_streak.lua, #217); without this, 3+ quick pings there forced the team home.
		local fountain = Fu.GetTeamFountain()
		if fountain ~= nil and Rules.InOwnFountainArea(ping.location, fountain) then
			pcall(
				print,
				string.format(
					"[SHy-PING] t=%.0f %s skip why=own-fountain at=%.0f,%.0f",
					DotaTime(),
					(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
					ping.location.x,
					ping.location.y
				)
			)
		else
			StartPingOrder(human, ping, bot)
		end
	end
	if now - state.tickAt < TICK_SECONDS and now >= state.tickAt then
		return
	end
	state.tickAt = now
	if state.chat ~= nil then
		local chat = state.chat
		state.chat = nil
		StartChatOrder(chat, bot)
	end
	KeepOrder()
end

-- This bot's part in the current order: the order and its entry while the bot obeys it, else nil. A bot leaves the
-- order when it dies, retreats or drops under LEAVE_HP. The first call under an order prints its obey line.
local function EntryOf(order, bot)
	if order == nil or bot == nil then
		return nil
	end
	local entry = order.bots[bot:GetPlayerID()]
	if entry == nil or entry.state ~= "obey" or entry.unit ~= bot then
		return nil
	end
	return entry
end

function Orders.ForBot(bot)
	local order = state.order
	local entry = EntryOf(order, bot)
	if entry == nil then
		return nil
	end
	-- A forced bot that dies or drops under FORCE_MIN_HP queues again and rejoins when it is back (KeepOrder); a
	-- retreat does not end its part (its own desire decides which mode runs meanwhile).
	if order.tier ~= "ask" then
		local why = nil
		if not bot:IsAlive() then
			why = "dead"
		elseif Fu.GetHP(bot) < Rules.FORCE_MIN_HP then
			why = "low-hp"
		end
		if why ~= nil then
			entry.state, entry.why = "queue", why
			Log("%s queue id=%d kind=%s tier=%s why=%s", Short(bot), order.id, order.kind, order.tier, why)
			return nil
		end
		return order, entry
	end
	if not bot:IsAlive() then
		LeaveOrder(order, entry, "dead")
		return nil
	end
	if Fu.GetHP(bot) < Orders.LEAVE_HP then
		LeaveOrder(order, entry, "low-hp")
		return nil
	end
	if Fu.IsRetreating(bot) then
		LeaveOrder(order, entry, "retreat")
		return nil
	end
	return order, entry
end

-- This bot's part in a danger ping's back-off (Rules.DANGER_RADIUS around it when pinged), else nil. It ends when
-- the bot is DANGER_SAFE away, dies or retreats (the retreat mode moves it away anyway).
local function DangerFor(bot)
	local order = state.danger
	local entry = EntryOf(order, bot)
	if entry == nil then
		return nil
	end
	if not bot:IsAlive() then
		LeaveOrder(order, entry, "dead")
		return nil
	end
	if Fu.IsRetreating(bot) then
		LeaveOrder(order, entry, "retreat")
		return nil
	end
	if GetUnitToLocationDistance(bot, order.loc) >= Rules.DANGER_SAFE then
		LeaveOrder(order, entry, "safe")
		return nil
	end
	return order, entry
end

local function NoteObey(bot, order, entry)
	if entry.logged then
		return
	end
	entry.logged = true
	Log(
		"%s obey id=%d kind=%s via=%s tier=%s mode=%d dist=%.0f%s",
		Short(bot),
		order.id,
		order.kind,
		order.via,
		tostring(order.tier),
		bot:GetActiveMode(),
		GetUnitToLocationDistance(bot, order.loc),
		entry.after ~= nil and (" after=" .. (entry.after == "in-fight" and "fight" or entry.after)) or ""
	)
end

-- A forced order keeps its desire down to FORCE_MIN_HP; a request fades out from 60% to LEAVE_HP.
local function Desire(bot, order)
	local low = (order ~= nil and order.tier ~= "ask") and Rules.FORCE_MIN_HP or Orders.LEAVE_HP
	return Orders.DESIRE * RemapValClamped(Fu.GetHP(bot), low, 0.6, 0.6, 1)
end

-- Push.GetPushDesire: the order's desire for the ordered lane, else nil.
function Orders.PushDesire(bot, lane)
	local order, entry = Orders.ForBot(bot)
	if order == nil or order.kind ~= "push" or LANE_OF[order.lane] ~= lane then
		return nil
	end
	if bot:GetActiveMode() == PUSH_MODE[lane] then
		NoteObey(bot, order, entry)
	end
	return Desire(bot, order)
end

-- Defend.GetDefendDesire: the order's desire for the ordered lane, else nil.
function Orders.DefendDesire(bot, lane)
	local order, entry = Orders.ForBot(bot)
	if order == nil or order.kind ~= "defend" or LANE_OF[order.lane] ~= lane then
		return nil
	end
	if bot:GetActiveMode() == DEFEND_MODE[lane] then
		NoteObey(bot, order, entry)
	end
	return Desire(bot, order)
end

-- mode_roshan_generic.lua: while this bot is called to Roshan, "ping" (a single Roshan ping the team agreed with:
-- the pit safety checks still apply) or "order" (a forced call: a repeated ping or `!rosh`: go anyway); else false.
function Orders.RoshCalled(bot)
	local order, entry = Orders.ForBot(bot)
	if order == nil or order.kind ~= "rosh" then
		return false
	end
	if bot:GetActiveMode() == BOT_MODE_ROSHAN then
		NoteObey(bot, order, entry)
	end
	return order.tier == "ask" and "ping" or "order"
end

-- mode_farm_generic.lua GetDesire: the camp this bot was sent to (a farm camp object { idx =, cattr = <spawner> })
-- and the desire, else nil.
function Orders.FarmCamp(bot)
	local order, entry = Orders.ForBot(bot)
	if order == nil or order.kind ~= "farm" or order.campObj == nil then
		return nil
	end
	if bot:GetActiveMode() == BOT_MODE_FARM then
		NoteObey(bot, order, entry)
	end
	return order.campObj, Desire(bot, order)
end

-- A FORCE ALL order: a TP (or Twin Gate) toward loc when it is clearly faster than walking (objective_travel.lua; it
-- prints [SHy-TRAVEL] ... for=order). Push and defend orders TP through the TP rule of their modes
-- (ability_item_usage_generic.lua), Roshan through the Roshan rally. True when it gave the bot an action.
local function TravelFar(bot, order, loc)
	if order.tier ~= "force-all" or loc == nil then
		return false
	end
	return ObjectiveTravel.Go(bot, loc, "order") == true
end

-- mode_farm_generic.lua Think: walk to the ordered camp first (farm's own camp code then clears it, with the
-- hero's spells); without this the bot would stop for nearer lane creeps on the way (game 074 Alchemist).
-- A FORCE ALL order goes by TP when that is clearly faster (objective_travel.lua, as the Roshan rally does).
function Orders.FarmThink(bot)
	local order = state.order
	if order == nil or order.kind ~= "farm" or order.camp == nil then
		return false
	end
	local entry = order.bots[bot:GetPlayerID()]
	if entry == nil or entry.state ~= "obey" or entry.unit ~= bot then
		return false
	end
	if GetUnitToLocationDistance(bot, order.camp.location) > 900 then
		if TravelFar(bot, order, order.camp.location) then
			return true
		end
		bot:Action_MoveToLocation(order.camp.location)
		return true
	end
	return false
end

-- The attack override: the ordered focus target when this bot can reach it within ~2s, else nil.
function Orders.FocusTarget(bot, attackRange)
	local order, entry = Orders.ForBot(bot)
	if order == nil or not TARGET_KINDS[order.kind] then
		return nil
	end
	local target = order.target
	if not Fu.IsValidHero(target) or not target:CanBeSeen() or not Fu.CanBeAttacked(target) then
		return nil
	end
	local gap = GetUnitToUnitDistance(bot, target) - (attackRange or bot:GetAttackRange())
	if gap > bot:GetCurrentMovementSpeed() * 2 then
		return nil
	end
	NoteObey(bot, order, entry)
	return target
end

local function TargetOf(order)
	local target = order.target
	if Fu.IsValidHero(target) and target:CanBeSeen() then
		return target
	end
	if order.targetId ~= nil then
		return VisibleEnemyHero(order.loc, 1500, order.targetId)
	end
	return nil
end

-- Normal chase limits for a gank or chase: no tower dive alone, not into more enemies than we have there. A forced
-- order skips the outnumbered limit (the human insisted, and a force brings more bots), not the tower dive.
local function ChaseStopWhy(bot, order, target)
	if order.kind ~= "gank" and order.kind ~= "chase" then
		return nil
	end
	local targetLoc = target ~= nil and target:GetLocation() or order.loc
	local allies = #(Fu.GetAlliesNearLoc(bot:GetLocation(), 1600) or {})
	for _, building in pairs(GetUnitList(UNIT_LIST_ENEMY_BUILDINGS) or {}) do
		if
			building ~= nil
			and not building:IsNull()
			and building:IsAlive()
			and string.find(building:GetUnitName(), "tower") ~= nil
			and GetUnitToLocationDistance(building, targetLoc) <= 800
			and allies < 3
		then
			return "tower-dive"
		end
	end
	if order.tier == "ask" and #(Fu.GetLastSeenEnemiesNearLoc(targetLoc, 1200) or {}) > allies + 1 then
		return "outnumbered"
	end
	return nil
end

-- mode_assemble_generic.lua GetDesire: the desire for the kinds the assemble mode carries out, else nil.
-- A danger ping's back-off comes first: just above an order's desire, so it also beats an ordered push or defend.
function Orders.AssembleDesire(bot)
	if DangerFor(bot) ~= nil then
		return math.min(0.85, Desire(bot) + 0.05)
	end
	local order, entry = Orders.ForBot(bot)
	if order == nil or not ASSEMBLE_KINDS[order.kind] then
		return nil
	end
	local kind = order.kind
	if kind == "group" then
		if order.from == nil or not order.from:IsAlive() then
			LeaveOrder(order, entry, "human-dead")
			return nil
		end
		if GetUnitToUnitDistance(bot, order.from) <= 500 then
			return nil
		end
		return Desire(bot, order)
	end
	-- A bot fighting there switches through the attack mode (FocusTarget, with its spells) and is not pulled out of
	-- its fight; this mode only brings the bots that are not fighting.
	if (kind == "focus" or kind == "chase") and InFight(bot) then
		return nil
	end
	if TARGET_KINDS[kind] then
		local target = TargetOf(order)
		local stopWhy = ChaseStopWhy(bot, order, target)
		if stopWhy ~= nil then
			LeaveOrder(order, entry, stopWhy)
			return nil
		end
		-- Already fighting it in the attack mode (with this target, FocusTarget): a lower desire keeps the attack mode,
		-- which casts the hero's spells; the assemble mode walks to the target and hits it otherwise.
		if
			target ~= nil
			and bot:GetActiveMode() == BOT_MODE_ATTACK
			and GetUnitToUnitDistance(bot, target) <= bot:GetAttackRange() + bot:GetCurrentMovementSpeed() * 2
		then
			return 0.4
		end
	end
	return Desire(bot, order)
end

-- mode_assemble_generic.lua Think: carries out the order. Returns true when it gave the bot an action.
function Orders.AssembleThink(bot)
	local danger, dangerEntry = DangerFor(bot)
	if danger ~= nil then
		NoteObey(bot, danger, dangerEntry)
		bot:Action_MoveToLocation(Fu.VectorAway(bot:GetLocation(), danger.loc, 800))
		return true
	end
	local order, entry = Orders.ForBot(bot)
	if order == nil or not ASSEMBLE_KINDS[order.kind] then
		return false
	end
	NoteObey(bot, order, entry)
	local kind = order.kind
	if kind == "group" then
		if order.from ~= nil and order.from:IsAlive() then
			if TravelFar(bot, order, order.from:GetLocation()) then
				return true
			end
			bot:Action_MoveToLocation(order.from:GetLocation() + RandomVector(150))
			return true
		end
		return false
	end
	local target = TARGET_KINDS[kind] and TargetOf(order) or nil
	if target ~= nil then
		order.loc = target:GetLocation()
		if GetUnitToUnitDistance(bot, target) <= bot:GetAttackRange() + 200 then
			bot:Action_AttackUnit(target, true)
		elseif not TravelFar(bot, order, target:GetLocation()) then
			bot:Action_MoveToLocation(target:GetLocation())
		end
		return true
	end
	local dist = GetUnitToLocationDistance(bot, order.loc)
	if kind == "chase" and order.targetId ~= nil then
		local info = GetHeroLastSeenInfo(order.targetId)
		local seen = info ~= nil and info[1] or nil
		if seen ~= nil and seen.location ~= nil and seen.time_since_seen <= 3 then
			order.loc = seen.location
		end
	end
	if kind == "fog" then
		-- Scout: from the edge of vision the spot is seen; nothing there ends the order. Alone, on a request, with 2+
		-- enemy heroes missing: wait at the edge for one more ally (maintainer, 2026-11-23).
		local vision = math.max(600, bot:GetCurrentVisionRange() or 1200)
		if IsLocationVisible(order.loc) and dist <= vision then
			LeaveOrder(order, entry, "nothing-there")
			return false
		end
		if order.tier == "ask" and dist <= vision * 1.1 and MissingEnemies() >= 2 then
			local allies = #(Fu.GetAlliesNearLoc(bot:GetLocation(), 1200) or {})
			if allies <= 1 then
				if not entry.waitLogged then
					entry.waitLogged = true
					Log("%s fog-wait id=%d why=alone-missing missing=%d", Short(bot), order.id, MissingEnemies())
				end
				bot:Action_MoveToLocation(bot:GetLocation())
				return true
			end
		end
	end
	if dist <= 250 then
		LeaveOrder(order, entry, kind == "move" and "arrived" or "nothing-there")
		return false
	end
	if TravelFar(bot, order, order.loc) then
		return true
	end
	bot:Action_MoveToLocation(order.loc)
	return true
end

return Orders
