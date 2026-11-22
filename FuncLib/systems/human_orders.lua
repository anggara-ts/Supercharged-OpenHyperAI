-- Shared bot system: human orders (#222). The human's pings and chat commands become team orders for the bots.
--   * A ping is a REQUEST: the bots check it (FuncLib/systems/human_order_rules.lua) and one bot says why when they
--     don't go. The same ping again within ~5s is an INSIST: they go anyway. A chat command (`!push top`) is an
--     ORDER. One bot answers ("On my way!", or the reason).
--   * What a ping means comes from what it is on: an enemy hero (focus in a fight, gank elsewhere), an enemy
--     building or wave near their tower (push), our building or a wave coming to ours (defend), a neutral camp
--     (one bot, a core first, clears it), Roshan, or fog (chase a hero seen there a moment ago, or scout).
--   * The modes read the order through the hooks below: Push.GetPushDesire (push), Defend.GetDefendDesire
--     (defend), mode_farm_generic.lua (camp), mode_roshan_generic.lua (rosh), the attack override (focus target)
--     and mode_assemble_generic.lua (gank, chase, fog, group, danger, move; it also runs Tick).
-- The module is shared by the team's bots (as FuncLib/systems/role.lua is), so one order serves all of them.
--
-- Logs: [OHA-PING] t= <hero> order kind= from= via=ping|insist|chat lane= target= verdict=go|refuse|queue why=
-- responders= reply= once per order; per bot obey / queue / ignore why= / done why=.
local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
local Rules = require(GetScriptDirectory() .. "/FuncLib/systems/human_order_rules")
local Lines = require(GetScriptDirectory() .. "/FuncLib/data/human_order_lines")
local Localization = require(GetScriptDirectory() .. "/FuncLib/systems/localization")
local HeroDisplayNames = require(GetScriptDirectory() .. "/FuncLib/data/hero_display_names")
local ChatGuard = require(GetScriptDirectory() .. "/FuncLib/systems/chat_guard")

local Orders = {}
Orders.Rules = Rules

-- An order's desire: above farm (up to ~0.6) and laning (0.565 for a safe core), below a base last stand (0.9) and
-- a hurt bot's retreat. Fades with HP so a retreat takes over; a bot under 30% HP leaves the order (done why=low-hp).
Orders.DESIRE = 0.75
Orders.LEAVE_HP = 0.3
-- A bot's think-to-think checks run at most this often for the whole team (seconds of game time).
local TICK_SECONDS = 0.2
-- A ping older than this when first read is old news (e.g. from before a reload).
local PING_FRESH_SECONDS = 2
-- A reply the chosen bot hasn't said by then is said by whichever bot runs the next tick.
local REPLY_FALLBACK_SECONDS = 1.5

local state = {
	order = nil,
	nextId = 0,
	lastPingTime = nil,
	prevPing = nil,
	chat = nil,
	tickAt = -999,
	reply = nil,
}
Orders.state = state

local LANE_OF = { top = LANE_TOP, mid = LANE_MID, bot = LANE_BOT }
local TOWERS = {
	top = { TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3 },
	mid = { TOWER_MID_1, TOWER_MID_2, TOWER_MID_3 },
	bot = { TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3 },
}
-- Kinds the assemble mode carries out (push, defend, farm and rosh go through their own modes).
local ASSEMBLE_KINDS = { focus = true, gank = true, chase = true, fog = true, move = true, group = true, danger = true }
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
	pcall(print, string.format("[OHA-PING] t=%.0f " .. fmt, DotaTime(), ...))
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

local function Candidates(loc)
	local list = {}
	for _, member in ipairs(Members(true)) do
		local alive = member:IsAlive()
		list[#list + 1] = {
			id = member:GetPlayerID(),
			unit = member,
			dist = alive and GetUnitToLocationDistance(member, loc) or math.huge,
			state = BotState(member),
			core = Fu.IsCore(member),
		}
	end
	return list
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

-- Chat: one line per order, said by the chosen bot (any bot after REPLY_FALLBACK_SECONDS). The team's repeat
-- filter (FuncLib/systems/chat_guard.lua) is skipped: "On my way!" answers a new ping each time.
local function Say(bot, text)
	local chat = ChatGuard.originalChat or bot.ActionImmediate_Chat
	pcall(chat, bot, text, false)
end

local function QueueReply(speakerId, key, human, seconds)
	local text = nil
	if key == "on-my-way" then
		-- The assemble mode's line (localization.lua say_assemble, first entry: "On my way!").
		local lines = Localization.Get("say_assemble")
		text = type(lines) == "table" and lines[1] or "On my way!"
	else
		text = Lines.Get(Localization.GetLocale(), key, DisplayName(human), seconds)
	end
	state.reply = { speakerId = speakerId, text = text, at = GameTime() }
end

local function SayPendingReply(bot)
	local reply = state.reply
	if reply == nil then
		return
	end
	if bot:GetPlayerID() == reply.speakerId or GameTime() - reply.at > REPLY_FALLBACK_SECONDS then
		state.reply = nil
		Say(bot, reply.text)
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

local function EndOrder(why)
	local order = state.order
	if order == nil then
		return
	end
	state.order = nil
	for _, entry in pairs(order.bots) do
		if entry.state == "obey" or entry.state == "queue" then
			entry.state = "done"
			LogDone(order, entry, why)
		end
	end
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
	end
end

-- Starts an order. `found`: what Orders.ReadSpot found (target, buildings, camp), or the chat command's target.
function Orders.Start(kind, via, human, loc, found, tickBot)
	state.nextId = state.nextId + 1
	local lane = found.lane
	local building, tier = found.building, found.tier
	if kind == "push" then
		lane = lane or found.enemyLane or found.waveLane
		building, tier = building or found.enemyBuilding, tier or found.enemyTier
	elseif kind == "defend" then
		lane = lane or found.ourLane or found.waveLane
		building, tier = building or found.ourBuilding, tier or found.ourTier
	end
	local cands = Candidates(loc)
	local available = 0
	for _, cand in ipairs(cands) do
		if Rules.Answer(kind, cand.state) ~= "ignore" and cand.dist <= Rules.MaxDistance(kind) then
			available = available + 1
		end
	end
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
		available = available,
		enemiesNear = #(Fu.GetLastSeenEnemiesNearLoc(loc, 1600) or {}),
		humanNear = human ~= nil and human:IsAlive() and GetUnitToLocationDistance(human, loc) <= 2500,
		baseUnderAttack = kind ~= "defend" and BaseSiegeAwayFrom(loc),
		tier = tier,
		ourCreepsNear = ourCreepsNear,
	}
	if kind == "rosh" then
		facts.roshanAlive = Fu.IsRoshanAlive()
	end
	local checkVerdict, why = Rules.Check(kind, via, facts)
	local obey, queue, ignore = {}, {}, {}
	if checkVerdict == "go" then
		obey, queue, ignore = Rules.PickResponders(kind, cands, Rules.Need(kind, facts))
	end
	local verdict = Rules.Verdict(checkVerdict, #obey, #queue)
	if verdict == "refuse" and checkVerdict == "go" then
		why = "nobody-free"
	end
	local order = {
		id = state.nextId,
		kind = kind,
		via = via,
		from = human,
		loc = loc,
		lane = lane,
		building = building,
		tier = tier,
		camp = found.camp,
		target = found.target,
		targetId = found.targetId,
		startedAt = DotaTime(),
		untilAt = DotaTime() + (kind == "danger" and Rules.DANGER_SECONDS or Rules.ORDER_SECONDS),
		bots = {},
	}
	if order.camp ~= nil then
		order.campObj = { idx = order.camp.idx, cattr = order.camp }
	end
	local unitById = {}
	for _, cand in ipairs(cands) do
		unitById[cand.id] = cand.unit
	end
	for _, id in ipairs(obey) do
		order.bots[id] = { state = "obey", unit = unitById[id] }
	end
	for _, id in ipairs(queue) do
		order.bots[id] = { state = "queue", unit = unitById[id] }
	end
	-- One reply per order, from the bot it is about.
	local replyKey, speakerId, seconds = "none", nil, nil
	if kind ~= "danger" then
		if verdict == "go" then
			replyKey, speakerId = "on-my-way", obey[1]
		elseif verdict == "queue" then
			replyKey, speakerId = "queue", queue[1]
		elseif why ~= "nobody-free" then
			replyKey = why
		else
			-- Nobody can go: the nearest bot says why it can't (all dead: the first one back says when).
			local nearest = nil
			for _, cand in ipairs(cands) do
				if nearest == nil or cand.dist < nearest.dist then
					nearest = cand
				elseif
					cand.dist == math.huge
					and nearest.dist == math.huge
					and cand.unit:GetRespawnTime() < nearest.unit:GetRespawnTime()
				then
					nearest = cand
				end
			end
			replyKey = "busy"
			if nearest ~= nil then
				speakerId = nearest.id
				if nearest.state == "dead" or nearest.state == "low-hp" or nearest.state == "retreat" then
					replyKey = nearest.state
				elseif nearest.state == "base" then
					replyKey = "base"
				end
				if nearest.state == "dead" then
					seconds = nearest.unit:GetRespawnTime()
				end
			end
		end
		if speakerId == nil and tickBot ~= nil then
			speakerId = tickBot:GetPlayerID()
		end
		QueueReply(speakerId, replyKey, human, seconds)
	end
	local targetName = "-"
	if order.target ~= nil then
		targetName = Short(order.target)
	elseif building ~= nil then
		targetName = (string.gsub(building:GetUnitName(), "npc_dota_", ""))
	elseif order.camp ~= nil then
		targetName = "camp-" .. tostring(order.camp.type or "?")
	end
	Log(
		"%s order kind=%s from=%s via=%s lane=%s target=%s verdict=%s why=%s responders=%s queued=%s reply=%s need=%d at=%.0f,%.0f id=%d%s",
		Short(tickBot),
		kind,
		Short(human),
		via,
		tostring(lane or "-"),
		targetName,
		verdict,
		tostring(why),
		NamesOf(obey),
		NamesOf(queue),
		replyKey,
		Rules.Need(kind, facts),
		loc.x,
		loc.y,
		order.id,
		kind == "fog" and string.format(" missing=%d", MissingEnemies())
			or (kind == "chase" and string.format(" seen=%.1f", found.seenAgo or -1) or "")
	)
	for _, entry in ipairs(ignore) do
		local unit = unitById[entry.id]
		if unit ~= nil and verdict ~= "refuse" then
			Log("%s ignore id=%d kind=%s why=%s", Short(unit), order.id, kind, entry.why)
		end
	end
	for _, id in ipairs(queue) do
		Log("%s queue id=%d kind=%s why=in-fight", Short(unitById[id]), order.id, kind)
	end
	-- A refused request leaves the current order running; an accepted one replaces it.
	if verdict ~= "refuse" then
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
	state.chat = { kind = command.kind, lane = command.lane, senderId = senderId, at = GameTime() }
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
		local hadOrder = state.order ~= nil
		EndOrder("cancelled")
		Log("%s order kind=no from=%s via=chat verdict=%s", Short(tickBot), Short(human), hadOrder and "go" or "none")
		if hadOrder then
			QueueReply(tickBot:GetPlayerID(), "cancelled", human)
		end
		return
	end
	if (chat.kind == "push" or chat.kind == "defend") and chat.lane == nil then
		Log("%s order kind=%s from=%s via=chat verdict=refuse why=no-lane", Short(tickBot), chat.kind, Short(human))
		QueueReply(tickBot:GetPlayerID(), "which_lane", human)
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
	Orders.Start(chat.kind, "chat", human, loc, found, tickBot)
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
	local prev = state.prevPing
	local insist = prev ~= nil
		and prev.humanId == current.humanId
		and prev.normal == current.normal
		and Rules.IsInsist(prev, current)
	state.prevPing = current
	Orders.Start(kind, insist and "insist" or "ping", human, loc, found, tickBot)
end

-- Keeps the current order up to date: ends it when it is done, lets queued bots go after their fight.
local function KeepOrder()
	local order = state.order
	if order == nil then
		return
	end
	local now = DotaTime()
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
	for _, entry in pairs(order.bots) do
		if entry.state == "queue" then
			local botState = BotState(entry.unit)
			if botState == "ok" then
				entry.state, entry.logged, entry.afterFight = "obey", false, true
			elseif botState == "dead" or botState == "retreat" or botState == "low-hp" then
				LeaveOrder(order, entry, botState)
				if state.order ~= order then
					return
				end
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
	if now - state.tickAt < TICK_SECONDS and now >= state.tickAt then
		return
	end
	state.tickAt = now
	if state.chat ~= nil then
		local chat = state.chat
		state.chat = nil
		StartChatOrder(chat, bot)
	end
	local human, ping = Orders.NewestHumanPing()
	if
		human ~= nil
		and ping ~= nil
		and ping.location ~= nil
		and ping.time ~= state.lastPingTime
		and now - ping.time <= PING_FRESH_SECONDS
	then
		state.lastPingTime = ping.time
		StartPingOrder(human, ping, bot)
	end
	KeepOrder()
end

-- This bot's part in the current order: the order and its entry while the bot obeys it, else nil. A bot leaves the
-- order when it dies, retreats or drops under LEAVE_HP. The first call under an order prints its obey line.
function Orders.ForBot(bot)
	local order = state.order
	if order == nil or bot == nil then
		return nil
	end
	local entry = order.bots[bot:GetPlayerID()]
	if entry == nil or entry.state ~= "obey" or entry.unit ~= bot then
		return nil
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

local function NoteObey(bot, order, entry)
	if entry.logged then
		return
	end
	entry.logged = true
	Log(
		"%s obey id=%d kind=%s via=%s mode=%d dist=%.0f%s",
		Short(bot),
		order.id,
		order.kind,
		order.via,
		bot:GetActiveMode(),
		GetUnitToLocationDistance(bot, order.loc),
		entry.afterFight and " after=fight" or ""
	)
end

local function Desire(bot)
	return Orders.DESIRE * RemapValClamped(Fu.GetHP(bot), Orders.LEAVE_HP, 0.6, 0.6, 1)
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
	return Desire(bot)
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
	return Desire(bot)
end

-- mode_roshan_generic.lua: while this bot is called to Roshan, "ping" (a Roshan ping the team agreed with: the pit
-- safety checks still apply) or "order" (an insisted ping or `!rosh`: go anyway); else false.
function Orders.RoshCalled(bot)
	local order, entry = Orders.ForBot(bot)
	if order == nil or order.kind ~= "rosh" then
		return false
	end
	if bot:GetActiveMode() == BOT_MODE_ROSHAN then
		NoteObey(bot, order, entry)
	end
	return order.via == "ping" and "ping" or "order"
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
	return order.campObj, Desire(bot)
end

-- mode_farm_generic.lua Think: walk to the ordered camp first (farm's own camp code then clears it, with the
-- hero's spells); without this the bot would stop for nearer lane creeps on the way (game 074 Alchemist).
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

-- Normal chase limits for a gank or chase: no tower dive alone, not into more enemies than we have there.
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
	if #(Fu.GetLastSeenEnemiesNearLoc(targetLoc, 1200) or {}) > allies + 1 then
		return "outnumbered"
	end
	return nil
end

-- mode_assemble_generic.lua GetDesire: the desire for the kinds the assemble mode carries out, else nil.
function Orders.AssembleDesire(bot)
	local order, entry = Orders.ForBot(bot)
	if order == nil or not ASSEMBLE_KINDS[order.kind] then
		return nil
	end
	local kind = order.kind
	if kind == "danger" then
		if GetUnitToLocationDistance(bot, order.loc) >= Rules.MaxDistance("danger") then
			LeaveOrder(order, entry, "safe")
			return nil
		end
		return math.min(0.85, Desire(bot) + 0.05)
	end
	if kind == "group" then
		if order.from == nil or not order.from:IsAlive() then
			LeaveOrder(order, entry, "human-dead")
			return nil
		end
		if GetUnitToUnitDistance(bot, order.from) <= 500 then
			return nil
		end
		return Desire(bot)
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
	return Desire(bot)
end

-- mode_assemble_generic.lua Think: carries out the order. Returns true when it gave the bot an action.
function Orders.AssembleThink(bot)
	local order, entry = Orders.ForBot(bot)
	if order == nil or not ASSEMBLE_KINDS[order.kind] then
		return false
	end
	NoteObey(bot, order, entry)
	local kind = order.kind
	if kind == "danger" then
		bot:Action_MoveToLocation(Fu.VectorAway(bot:GetLocation(), order.loc, 800))
		return true
	end
	if kind == "group" then
		if order.from ~= nil and order.from:IsAlive() then
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
		else
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
		if order.via == "ping" and dist <= vision * 1.1 and MissingEnemies() >= 2 then
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
	bot:Action_MoveToLocation(order.loc)
	return true
end

return Orders
