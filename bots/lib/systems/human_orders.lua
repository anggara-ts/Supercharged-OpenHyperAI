-- Shared bot system: human orders (#222). The human's pings and chat commands become team orders for the bots.
--   * Ping tiers by count (maintainer, 2026-11-23: "1 ping = ask / 2 ping = force ally nearby ping / 3+ ping = force
--     all ally accross map"): one ping is a request (ASK: the bots check it, bots/lib/systems/human_order_rules.lua,
--     and may refuse; a bot whose mode is above the request's desire, e.g. a Roshan gather, is busy); the same ping
--     again within 3s is FORCE NEAR (every bot within 4000 or at that lane goes); a third is FORCE ALL (every bot).
--     A forced order's desire is above the team's own calls and below retreat (Rules.OrderDesire). Under a force a
--     far bot TPs at once when that is clearly faster (TravelFar). `!push top` is FORCE NEAR, `!push top all` FORCE
--     ALL. A force still queues dead, channelling and very low bots; they join when back.
--   * Replies ("response 'on my way' only when acknowledging. no reply for 'cant do'"): every bot that goes says what
--     it does once, "Pushing bot", "Attacking Medusa", "On my way" (game 077; Rules.AckKey), when it starts doing it
--     (its first obey; game 078); bots that can't go say nothing. Only when nobody goes does one bot say one short
--     reason, at most once per 30s per team, after the 3s a repeated ping has to force the order.
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
-- (danger: affected=) once per order; per bot obey ack=yes|no / queue why= / ignore why= / done why=, and <hero> said id= reply=
-- for every chat reply. A bot whose order gives way to Valve's dodge (#225): <hero> yield id= to=evasive des= evasive=
-- order= tier= (at the start, then every 3s), and <hero> resume id= after=evasive held= des= when the dodge ends. A forced bot that goes by TP prints [SHy-TRAVEL] ... for=order; a far one that walks
-- order-walk why=. A quick ping that did not chain: <human> insist-miss dist= age= kind= lane=. A ping at our
-- fountain: skip why=own-fountain near=spawn|building; the fountain building once found: fountain-building at=.
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Rules = require(GetScriptDirectory() .. "/lib/systems/human_order_rules")
local Lines = require(GetScriptDirectory() .. "/lib/data/human_order_lines")
local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
local HeroDisplayNames = require(GetScriptDirectory() .. "/lib/data/hero_display_names")
local ChatGuard = require(GetScriptDirectory() .. "/lib/systems/chat_guard")
local ObjectiveTravel = require(GetScriptDirectory() .. "/lib/systems/objective_travel")

local Orders = {}
Orders.Rules = Rules

-- A request's desire (Rules.OrderDesire has both tiers and why): fades with HP so a retreat takes over; a bot under
-- 30% HP leaves a request (done why=low-hp); a forced order keeps it down to Rules.FORCE_MIN_HP (then it queues and
-- rejoins when healed).
Orders.DESIRE = Rules.ASK_DESIRE
Orders.LEAVE_HP = Rules.LEAVE_HP
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
	-- GameTime() of the last insist-miss line (at most one per second).
	insistMissLogAt = nil,
	-- Our fountain building's location once found (OwnFountainBuilding), and when it was last looked for.
	fountainBuilding = nil,
	fountainLookAt = nil,
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

-- Short names of the modes that make a bot busy for a request (Rules.IsBusy); push / defend carry the lane. Attack,
-- retreat and evasive maneuvers are left out: the fight and retreat states cover them, and a dodge is a moment.
local BUSY_MODE_NAMES = {}
for _, pair in ipairs({
	{ BOT_MODE_ROSHAN, "roshan" },
	{ BOT_MODE_PUSH_TOWER_TOP, "push-top" },
	{ BOT_MODE_PUSH_TOWER_MID, "push-mid" },
	{ BOT_MODE_PUSH_TOWER_BOT, "push-bot" },
	{ BOT_MODE_DEFEND_TOWER_TOP, "defend-top" },
	{ BOT_MODE_DEFEND_TOWER_MID, "defend-mid" },
	{ BOT_MODE_DEFEND_TOWER_BOT, "defend-bot" },
	{ BOT_MODE_FARM, "farm" },
	{ BOT_MODE_LANING, "laning" },
	{ BOT_MODE_RUNE, "rune" },
	{ BOT_MODE_WARD, "ward" },
	{ BOT_MODE_ITEM, "item" },
	{ BOT_MODE_OUTPOST or 26, "outpost" },
	{ BOT_MODE_TEAM_ROAM, "team-roam" },
	{ BOT_MODE_ROAM, "roam" },
	{ BOT_MODE_DEFEND_ALLY, "ally-defend" },
	{ BOT_MODE_SECRET_SHOP, "shop" },
	{ BOT_MODE_SIDE_SHOP, "shop" },
	{ BOT_MODE_ASSEMBLE, "assemble" },
}) do
	if pair[1] ~= nil then
		BUSY_MODE_NAMES[pair[1]] = pair[2]
	end
end

-- The mode that carries out an order of this kind (lane), or nil.
local function OrderMode(order)
	if order == nil then
		return nil
	elseif order.kind == "push" then
		return PUSH_MODE[LANE_OF[order.lane or ""] or -1]
	elseif order.kind == "defend" then
		return DEFEND_MODE[LANE_OF[order.lane or ""] or -1]
	elseif order.kind == "rosh" then
		return BOT_MODE_ROSHAN
	elseif order.kind == "farm" then
		return BOT_MODE_FARM
	elseif ASSEMBLE_KINDS[order.kind] then
		return BOT_MODE_ASSEMBLE
	end
	return nil
end

-- The mode that keeps `member` from a request (its active mode's desire above the request's, Rules.IsBusy), or nil.
-- A bot is not busy with the mode that carries out the human's current order for it; a bot still listed for that
-- order but held by another mode (game 078: Largo, obeying a camp ping, taken by the Roshan gather) is.
local function BusyMode(member)
	local order = state.order
	local entry = order ~= nil and order.bots[member:GetPlayerID()] or nil
	local orderMode = nil
	if entry ~= nil and entry.state == "obey" then
		orderMode = BUSY_MODE_NAMES[OrderMode(order) or -1]
	end
	local name = BUSY_MODE_NAMES[member:GetActiveMode()]
	if not Rules.IsBusy(name, member:GetActiveModeDesire(), Orders.DESIRE, orderMode) then
		return nil
	end
	return name
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
		busy = alive and BusyMode(member) or nil,
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
-- runs the next tick. The team's repeat filter (bots/lib/systems/chat_guard.lua) is skipped: every bot that goes says
-- the same short line for its order ("Pushing bot"; maintainer, game 077), and the filter would drop all but one.
local function Say(bot, text)
	local chat = ChatGuard.originalChat or bot.ActionImmediate_Chat
	pcall(chat, bot, text, false)
end

-- The enemy hero an order is on, by display name: its unit, or (a chase into the fog has only the player ID) the
-- hero picked by that player; nil when the order is on no hero.
local function TargetName(order)
	if order.target ~= nil and not order.target:IsNull() then
		return DisplayName(order.target)
	end
	if order.targetId == nil then
		return nil
	end
	local ok, unitName = pcall(GetSelectedHeroName, order.targetId)
	if not ok or type(unitName) ~= "string" or unitName == "" then
		return nil
	end
	local names = HeroDisplayNames[Localization.GetLocale()] or HeroDisplayNames.en
	return names[unitName] or HeroDisplayNames.en[unitName] or (string.gsub(unitName, "npc_dota_hero_", ""))
end

-- The reply key and fill-ins for a bot's "what I do" line (Rules.AckKey): the order's lane and the enemy hero.
local function AckLine(order)
	local target = TargetName(order)
	return Rules.AckKey(order.kind, order.lane, target ~= nil), { lane = order.lane, target = target }
end

local function ReplyText(key, human, seconds, extra)
	return Lines.Get(Localization.GetLocale(), key, DisplayName(human), seconds, extra)
end

-- `delay`: seconds to hold the line (a refusal waits for a repeated ping that would force the order). `extra`: the
-- fill-ins of a "what I do" line (AckLine), or nil.
local function QueueReply(orderId, kind, speakerId, key, human, seconds, delay, extra)
	local now = GameTime()
	local at = math.max(now + (delay or 0), state.replyNextAt)
	state.replyNextAt = at + REPLY_GAP_SECONDS
	local reply = {
		speakerId = speakerId,
		key = key,
		orderId = orderId or 0,
		kind = kind or "-",
		text = ReplyText(key, human, seconds, extra),
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
	-- A bot busy with a team call says that call (game 078: "Going Roshan" for a Roshan gather), with its lane for a
	-- push or defend (Rules.BusyKey).
	local key = Rules.BusyKey(nearest.state)
	if
		nearest.state == "dead"
		or nearest.state == "low-hp"
		or nearest.state == "retreat"
		or nearest.state == "base"
	then
		key = nearest.state
	end
	local seconds = nearest.state == "dead" and unitById[nearest.id]:GetRespawnTime() or nil
	local lane = type(nearest.state) == "string" and nearest.state:match("^busy:%a+%-(%a+)$") or nil
	return { id = nearest.id, key = key, seconds = seconds, lane = LANE_OF[lane or ""] ~= nil and lane or nil }
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
-- bots that already said their line for this ping chain (they don't say it again; order.acked starts as a copy and
-- NoteObey adds each bot that says it).
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
		-- Refuse only while Roshan is surely dead: between 8 and 11 minutes he may be up (Rules.RoshanSurelyDead).
		facts.roshanAlive = not Rules.RoshanSurelyDead(Fu.GetRoshanKillTime(), DotaTime(), Fu.IsModeTurbo())
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
		acked = {},
		startedAt = DotaTime(),
		untilAt = DotaTime() + Rules.OrderSeconds(kind, tier, maxEta),
		bots = {},
	}
	if order.camp ~= nil then
		order.campObj = { idx = order.camp.idx, cattr = order.camp }
	end
	for id in pairs(acked or {}) do
		order.acked[id] = true
	end
	for _, id in ipairs(obey) do
		order.bots[id] = { state = "obey", unit = unitById[id] }
	end
	for _, id in ipairs(queue) do
		order.bots[id] = { state = "queue", unit = unitById[id], why = queueWhy[id] }
	end
	-- Replies (Rules.ReplyPlan): one reason only when nobody goes. A bot that goes says what it does ("Pushing bot",
	-- Rules.AckKey) at its first obey (NoteObey), not here.
	local refuser = nil
	if verdict == "refuse" and why == "nobody-free" and kind ~= "danger" then
		refuser = NearestRefuser(decisions, unitById)
	end
	local replyKey, replies = "none", {}
	local tickId = tickBot ~= nil and tickBot:GetPlayerID() or nil
	local _, ackFill = AckLine(order)
	local plan = Rules.ReplyPlan(kind, verdict, why, refuser, {
		now = DotaTime(),
		lastRefusalAt = state.refusalAt,
	})
	for _, line in ipairs(plan) do
		local speakerId = line.id or tickId
		-- A busy bot's "Pushing <lane>" names its own lane, not the order's.
		local fill = line.lane ~= nil and { lane = line.lane } or ackFill
		QueueReply(order.id, kind, speakerId, line.key, human, line.seconds, line.delay, fill)
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
	state.chat = {
		kind = command.kind,
		lane = command.lane,
		all = command.all,
		cmd = command.cmd,
		senderId = senderId,
		at = GameTime(),
	}
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
	if chat.kind == "stop" then
		local hadOrder = state.order ~= nil or state.danger ~= nil
		EndOrder("cancelled")
		Finish("danger", "cancelled")
		Log("%s order kind=stop from=%s via=chat verdict=%s", Short(tickBot), Short(human), hadOrder and "go" or "none")
		if hadOrder then
			QueueReply(nil, "stop", tickBot:GetPlayerID(), "cancelled", human)
		end
		return
	end
	if (chat.kind == "push" or chat.kind == "defend") and chat.lane == nil then
		Log("%s order kind=%s from=%s via=chat verdict=refuse why=no-lane", Short(tickBot), chat.kind, Short(human))
		-- Names the command that was typed (game 080, maintainer: "sending !def asked confirm 'which lane? !push
		-- top/mid/bot'").
		QueueReply(nil, chat.kind, tickBot:GetPlayerID(), "which_lane", human, nil, nil, { cmd = chat.cmd })
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
	local lane = nil
	if kind == "push" then
		lane = found.enemyLane or found.waveLane
	elseif kind == "defend" then
		lane = found.ourLane or found.waveLane
	end
	local current = {
		time = ping.time,
		x = loc.x,
		y = loc.y,
		targetKey = targetKey,
		humanId = human:GetPlayerID(),
		normal = ping.normal_ping,
		kind = kind,
		lane = lane,
	}
	-- Pings in a row on the same spot, target or (push / defend) lane, each within 3s of the one before: 1 ask, 2
	-- force near, 3+ force all (Rules.IsInsist).
	local prev = state.prevPing
	local same = prev ~= nil and prev.humanId == current.humanId
	current.count = same and Rules.PingCount(prev, current) or 1
	if same and current.count == 1 then
		-- A quick ping that did not chain (game 077: pings 590-620 apart around one tower never reached count=3).
		local age = current.time - prev.time
		local now = GameTime()
		if age > 0 and age <= Rules.INSIST_SECONDS + 1 and now >= (state.insistMissLogAt or -999) + 1 then
			state.insistMissLogAt = now
			local dx, dy = current.x - prev.x, current.y - prev.y
			Log(
				"%s insist-miss dist=%.0f age=%.1f kind=%s lane=%s prev=%s/%s normal=%s/%s",
				Short(human),
				math.sqrt(dx * dx + dy * dy),
				age,
				kind,
				tostring(lane or "-"),
				tostring(prev.kind or "-"),
				tostring(prev.lane or "-"),
				tostring(prev.normal),
				tostring(current.normal)
			)
		end
	end
	local tier = kind == "danger" and "ask" or Rules.Tier(current.count)
	local acked = nil
	if current.count >= 2 then
		-- The order is forced now: a reason not said yet is dropped, and the bots that already said their line for
		-- this chain don't say it again.
		DropRefusals()
		acked = prev.acked
	end
	local via = current.count >= 2 and "insist" or "ping"
	local order, verdict = Orders.Start(kind, via, human, loc, found, tickBot, tier, current.count, acked)
	-- The chain's acked bots: the running order's own table when this ping made one (NoteObey adds the bots that say
	-- their line later), else the ones from before.
	if verdict ~= "refuse" and kind ~= "danger" then
		current.acked = order.acked
	else
		current.acked = {}
		for id in pairs(acked or {}) do
			current.acked[id] = true
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
	if order.kind == "rosh" and Rules.RoshanSurelyDead(Fu.GetRoshanKillTime(), DotaTime(), Fu.IsModeTurbo()) then
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
	-- Queued bots join when they can, and say their line at their first obey (NoteObey; maintainer: "on my way" only
	-- when acknowledging).
	-- A request's queued bot (in a fight) leaves when it dies or retreats; a forced order's queued bot (dead,
	-- channelling, very low) waits until it respawns, the channel ends or it is healed (Rules.ForceRejoin).
	for _, entry in pairs(order.bots) do
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
			end
		end
	end
end

-- Our fountain building ("dota_fountain" in the allied building list, as the game 070 unit survey showed), looked up
-- at most every 5s until found, then kept; nil until then (the spawn point alone counts). Not hard-coded: the spawn
-- point Fu.GetTeamFountain() is ~1040 from it.
local function OwnFountainBuilding()
	if state.fountainBuilding ~= nil then
		return state.fountainBuilding
	end
	local now = GameTime()
	if state.fountainLookAt ~= nil and now - state.fountainLookAt < 5 and now >= state.fountainLookAt then
		return nil
	end
	state.fountainLookAt = now
	-- The one nearest our spawn point, within 3000 of it (the survey listed only our own fountain; this keeps an
	-- enemy one out should the list ever hold it).
	local spawn = Fu.GetTeamFountain()
	local best, bestDist = nil, 3000
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIED_BUILDINGS) or {}) do
		if unit ~= nil and not unit:IsNull() and unit:GetUnitName() == "dota_fountain" then
			local loc = unit:GetLocation()
			local dist = spawn ~= nil and Dist(loc, spawn) or 0
			if dist <= bestDist then
				best, bestDist = loc, dist
			end
		end
	end
	if best ~= nil then
		state.fountainBuilding = best
		Log(
			"%s fountain-building at=%.0f,%.0f from-spawn=%.0f",
			GetTeam() == TEAM_RADIANT and "radiant" or "dire",
			best.x,
			best.y,
			bestDist
		)
	end
	return best
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
		-- credit line in ping_streak.lua, #217); without this, 3+ quick pings there forced the team home. Measured
		-- from the spawn point and from the fountain building (game 077: a ping on the building was not skipped).
		local inFountain, near = Rules.InOwnFountainArea(ping.location, Fu.GetTeamFountain(), OwnFountainBuilding())
		if inFountain then
			pcall(
				print,
				string.format(
					"[SHy-PING] t=%.0f %s skip why=own-fountain near=%s at=%.0f,%.0f",
					DotaTime(),
					(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
					tostring(near),
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

-- This bot's part in the current order: the order and its entry, else nil. While the bot backs off from a danger
-- ping (DangerFor) the order waits: a forced order (0.97) would beat the back-off (0.85) otherwise.
function Orders.ForBot(bot)
	local order = state.order
	local entry = EntryOf(order, bot)
	if entry == nil or DangerFor(bot) ~= nil then
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

-- The bot's first obey of an order (it is in the order's mode now): logs it, and the bot says what it does then, once
-- per ping chain (Rules.ShouldAck; game 078: a bot picked for a camp said "Clearing the camp" and never went).
local function NoteObey(bot, order, entry)
	if entry.logged then
		return
	end
	entry.logged = true
	local id = bot:GetPlayerID()
	local ack = order.acked ~= nil and Rules.ShouldAck(order.kind, order.acked, id)
	if ack then
		order.acked[id] = true
		local ackKey, ackFill = AckLine(order)
		QueueReply(order.id, order.kind, id, ackKey, order.from, nil, nil, ackFill)
	end
	Log(
		"%s obey id=%d kind=%s via=%s tier=%s mode=%d dist=%.0f ack=%s%s",
		Short(bot),
		order.id,
		order.kind,
		order.via,
		tostring(order.tier),
		bot:GetActiveMode(),
		GetUnitToLocationDistance(bot, order.loc),
		ack and "yes" or "no",
		entry.after ~= nil and (" after=" .. (entry.after == "in-fight" and "fight" or entry.after)) or ""
	)
end

-- The bot's retreat desire from its last think (mode_retreat_generic.lua publishes it), or nil when older than 1s.
local function RetreatDesireNow(bot)
	local last = bot._retreatFinalDesire
	if last == nil or last.d == nil or DotaTime() - (last.t or -999) > 1 then
		return nil
	end
	return last.d
end

-- Seconds between two yield lines of one bot while the same dodge goes on.
local YIELD_LOG_SECONDS = 3

-- `desire` cut under a running dodge (Rules.YieldToDodge; #225: a forced order at 0.97 could take the bot back from
-- Valve's evasive maneuvers at 0.90-0.96). Logs the yield when it starts and every YIELD_LOG_SECONDS, and the resume.
local function YieldToDodge(bot, order, desire)
	local evasive = nil
	if bot:GetActiveMode() == BOT_MODE_EVASIVE_MANEUVERS then
		evasive = bot:GetActiveModeDesire()
	end
	local cut, yielded = Rules.YieldToDodge(desire, evasive)
	local now = DotaTime()
	local id = order ~= nil and order.id or -1
	if yielded then
		if bot._orderYieldSince == nil or bot._orderYieldId ~= id then
			bot._orderYieldSince, bot._orderYieldId, bot._orderYieldLogAt = now, id, nil
		end
		if now >= (bot._orderYieldLogAt or -999) then
			bot._orderYieldLogAt = now + YIELD_LOG_SECONDS
			Log(
				"%s yield id=%d to=evasive des=%.2f evasive=%.2f order=%.2f tier=%s",
				Short(bot),
				id,
				cut,
				evasive,
				desire,
				order ~= nil and tostring(order.tier) or "danger"
			)
		end
	elseif bot._orderYieldSince ~= nil and evasive == nil then
		-- Only for the order it yielded (a later order's first think does not print the old one's resume).
		if bot._orderYieldId == id then
			Log("%s resume id=%d after=evasive held=%.1f des=%.2f", Short(bot), id, now - bot._orderYieldSince, desire)
		end
		bot._orderYieldSince, bot._orderYieldId, bot._orderYieldLogAt = nil, nil, nil
	end
	return cut
end

-- The order's desire for this bot before a dodge (Rules.OrderDesire): a request 0.75, a forced order 0.97, fading
-- with HP and kept under a strong retreat. A danger back-off (order nil) uses the request's.
local function BaseDesire(bot, order)
	return Rules.OrderDesire(order ~= nil and order.tier or "ask", Fu.GetHP(bot), RetreatDesireNow(bot))
end

-- The order's desire for this bot: BaseDesire, under a running dodge (YieldToDodge).
local function Desire(bot, order)
	return YieldToDodge(bot, order, BaseDesire(bot, order))
end

-- Push.GetPushDesire for a lane the bot is not ordered to: the most that lane may return while the bot carries out a
-- forced order (just under the order's desire, so a kill push at 0.99 does not pull it away; maintainer, game 078:
-- the human insisting outranks the team's calls), else nil.
function Orders.CapForOrder(bot)
	local order = Orders.ForBot(bot)
	if order == nil or order.tier == "ask" or order.kind == "danger" then
		return nil
	end
	return Desire(bot, order) - 0.01
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
-- the pit safety checks still apply) or "order" (a forced call: a repeated ping or `!rosh`: go anyway), and the
-- order's desire (Rules.OrderDesire); else false.
-- Roshan may be up (not killed in the last 8 minutes; turbo 4): a human's Roshan call is followed then, even before
-- Fu.IsRoshanAlive's 11-minute mark (game 082, 24:05).
function Orders.RoshanMaybeUp()
	return not Rules.RoshanSurelyDead(Fu.GetRoshanKillTime(), DotaTime(), Fu.IsModeTurbo())
end
function Orders.RoshCalled(bot)
	local order, entry = Orders.ForBot(bot)
	if order == nil or order.kind ~= "rosh" then
		return false
	end
	if bot:GetActiveMode() == BOT_MODE_ROSHAN then
		NoteObey(bot, order, entry)
	end
	return order.tier == "ask" and "ping" or "order", Desire(bot, order)
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

-- A forced bot this far from the spot that walks logs why it did not TP (order-walk).
local WALK_LOG_DIST = 4000
local NEAR_WALK_DIST = 3000
-- No order TP with a visible enemy hero this close: it can interrupt the 3s channel (game 079, 0:35: Dark Willow's
-- Bramble Maze, cast on Largo's TP, rooted Spirit Breaker and broke his order TP; he never tried again). A map
-- estimate around cast ranges, not game data.
local TP_ENEMY_RADIUS = 1200
-- How far a bot walks per step to get clear of that enemy before it TPs.
local TP_CLEAR_STEP = 700

-- The nearest visible enemy hero within `radius` of the bot (illusions left out), or nil.
local function NearestEnemyHero(bot, radius)
	local best, bestDist = nil, radius
	for _, enemy in ipairs(bot:GetNearbyHeroes(radius, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(enemy) and not Fu.IsSuspiciousIllusion(enemy) then
			local dist = GetUnitToUnitDistance(bot, enemy)
			if dist <= bestDist then
				best, bestDist = enemy, dist
			end
		end
	end
	return best
end

-- A step away from `enemy`, bent toward our fountain (our side), TP_CLEAR_STEP long.
local function StepClearOf(bot, enemy)
	local here, from, home = bot:GetLocation(), enemy:GetLocation(), Fu.GetTeamFountain()
	local ax, ay = here.x - from.x, here.y - from.y
	local hx, hy = home.x - here.x, home.y - here.y
	local al, hl = math.sqrt(ax * ax + ay * ay), math.sqrt(hx * hx + hy * hy)
	local dx, dy =
		(al > 0 and ax / al or 0) + (hl > 0 and hx / hl or 0), (al > 0 and ay / al or 0) + (hl > 0 and hy / hl or 0)
	local dl = math.sqrt(dx * dx + dy * dy)
	if dl <= 0 then
		return home
	end
	return Vector(here.x + dx / dl * TP_CLEAR_STEP, here.y + dy / dl * TP_CLEAR_STEP, here.z or 0)
end

-- "ready" / "cooldown" / "none": the bot's TP scroll or Boots of Travel (the items objective_travel.lua uses).
local function TpState(bot)
	local held = false
	for _, slot in ipairs({ 15, 0, 1, 2, 3, 4, 5 }) do
		local ok, item = pcall(function()
			return bot:GetItemInSlot(slot)
		end)
		if ok and item ~= nil then
			local name = item:GetName()
			if name == "item_tpscroll" or name == "item_travel_boots" or name == "item_travel_boots_2" then
				if item:IsFullyCastable() then
					return "ready"
				end
				held = true
			end
		end
	end
	return held and "cooldown" or "none"
end

-- A forced order (force near or force all, every kind): a TP (or Twin Gate) toward loc at once when it is clearly
-- faster than walking (objective_travel.lua: 8s saved; it prints [SHy-TRAVEL] ... for=order). Game 077: under a
-- force-all push Spirit Breaker (12857 away) walked 15s before the push mode's own TP rule fired, and Largo (10066)
-- walked and was caught, so push and defend call this too (Orders.TravelThink), before their modes walk. No TP under
-- Orders.LEAVE_HP or while hit by a hero (ObjectiveTravel.Go). A far bot that walks logs why, at most every 5s
-- (`order-walk why=enemy-near|low-hp|danger|rooted|no-scroll|cooldown|eta`). With a visible enemy hero within
-- TP_ENEMY_RADIUS it walks clear of it toward our side first; a TP that was broken is tried again once the guards
-- allow (`order-tp-retry try=`). True when it gave the bot an action (also while it channels the TP).
local function TravelFar(bot, order, loc)
	if order.tier == "ask" or loc == nil then
		return false
	end
	-- A TP being channelled: no other order on top of it (game 079: the push Think's moves must not cancel it).
	if bot:IsChanneling() or bot:HasModifier("modifier_teleporting") then
		return true
	end
	-- Within NEAR_WALK_DIST a TP (3s channel + 1s) cannot save the 8s objective_travel.lua asks for; skip the work.
	local dist = GetUnitToLocationDistance(bot, loc)
	if dist <= NEAR_WALK_DIST then
		return false
	end
	local hpOk = Fu.GetHP(bot) >= Orders.LEAVE_HP
	local entry = order.bots[bot:GetPlayerID()]
	local enemyNear = nil
	if hpOk and not bot:IsRooted() then
		local ok, _, how = pcall(ObjectiveTravel.Best, bot, loc)
		if ok and how == "tp" then
			-- A visible enemy hero near could break the channel: walk clear of it toward our side first, then TP.
			enemyNear = NearestEnemyHero(bot, TP_ENEMY_RADIUS)
			if enemyNear == nil and ObjectiveTravel.Go(bot, loc, "order") == true then
				-- Each TP started for this order (orders repeated until the channel starts count once: 4s apart); a
				-- second one is a retry after a broken channel (game 079).
				if entry ~= nil and DotaTime() - (entry.tpAt or -999) > 4 then
					entry.tpAt = DotaTime()
					entry.tpTries = (entry.tpTries or 0) + 1
					if entry.tpTries >= 2 then
						Log(
							"%s order-tp-retry id=%d kind=%s try=%d dist=%.0f",
							Short(bot),
							order.id,
							order.kind,
							entry.tpTries,
							dist
						)
					end
				end
				return true
			end
		elseif ok and ObjectiveTravel.Go(bot, loc, "order") == true then
			-- A Twin Gate.
			return true
		end
	end
	if enemyNear ~= nil then
		bot:Action_MoveToLocation(StepClearOf(bot, enemyNear))
	end
	if dist > WALK_LOG_DIST and DotaTime() >= (bot._orderWalkLogAt or -999) then
		bot._orderWalkLogAt = DotaTime() + 5
		local why = "eta"
		if enemyNear ~= nil then
			why = "enemy-near"
		elseif not hpOk then
			why = "low-hp"
		elseif bot:WasRecentlyDamagedByAnyHero(2) then
			why = "danger"
		elseif bot:IsRooted() then
			why = "rooted"
		else
			local tp = TpState(bot)
			if tp == "none" then
				why = "no-scroll"
			elseif tp == "cooldown" then
				why = "cooldown"
			end
		end
		Log(
			"%s order-walk id=%d kind=%s tier=%s why=%s dist=%.0f eta=%.0f",
			Short(bot),
			order.id,
			order.kind,
			order.tier,
			why,
			dist,
			ObjectiveTravel.Eta(bot, loc)
		)
	end
	return enemyNear ~= nil
end

-- Push.PushThink / Defend.DefendThink: a bot carrying out a forced push / defend order on `lane` TPs toward the
-- order's spot first when that is clearly faster (TravelFar). True when it gave the bot an action (the mode's own
-- Think then waits).
function Orders.TravelThink(bot, kind, lane)
	local order = state.order
	if order == nil or order.kind ~= kind or order.tier == "ask" or LANE_OF[order.lane] ~= lane then
		return false
	end
	local entry = order.bots[bot:GetPlayerID()]
	if entry == nil or entry.state ~= "obey" or entry.unit ~= bot then
		return false
	end
	return TravelFar(bot, order, order.loc)
end

-- mode_farm_generic.lua Think: walk to the ordered camp first (farm's own camp code then clears it, with the
-- hero's spells); without this the bot would stop for nearer lane creeps on the way (game 074 Alchemist).
-- A forced order goes by TP when that is clearly faster (TravelFar, objective_travel.lua, as the Roshan rally does).
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
		return YieldToDodge(bot, nil, math.min(0.85, BaseDesire(bot) + 0.05))
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
