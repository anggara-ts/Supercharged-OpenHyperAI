-- Shared bot system: pure rules for human orders (#222): what a human's ping or chat command means, whether the
-- bots agree with a ping, and which bots answer it. No bot API calls here, so tests/test_human_order_rules.lua can
-- run them with plain numbers; bots/lib/systems/human_orders.lua reads the world and acts on the results.
--
-- The maintainer's design (2026-11-23, issue #222), ping tiers by count: "refine ping response: 1 ping = ask / 2 ping
-- = force ally nearby ping / 3+ ping = force all ally accross map / response 'on my way' only when acknowledging. no
-- reply for 'cant do'". One ping is a request (ASK: the bots check it and may refuse); the same ping again within 3s
-- is FORCE NEAR (every bot within FORCE_NEAR_RADIUS or at that lane goes, whatever the checks say); a third is FORCE
-- ALL (every bot on the team goes, by TP when the walk is long). A chat command (`!push top`) is FORCE NEAR,
-- `!push top all` FORCE ALL. A ping is read by what is under it, whatever its type (game 075: a ping clicked on a
-- tower or a hero arrives as a non-normal ping); only a non-normal ping on empty ground or fog is the X-ping
-- "danger, back off" (never forced).
local Rules = {}

-- The same spot (or the same target) pinged again within this many seconds, this close, is an insist: the next tier.
-- A push or defend ping chains with the one before when it reads as the same kind on the same lane, wherever it lands
-- (game 077: quick pings around our bottom tower landed 590-620 apart and never chained with a 300 radius).
-- Was 2 (maintainer 2026-11-23: "narrow it to 2 pings in 2 seconds"). Game 078, maintainer: "how does ping count
-- works? i think i need to ping 5+ to make it work for 2 pings". The pings reach the scripts spaced out even when
-- clicked fast (GetMostRecentPing times, gaps under 6s: game 077 51 gaps, min 1.0s, median 1.5s; game 078 median 1.5s,
-- 90th percentile 3.8s), so one gap over 2s restarted the chain and 5 clicks made two pairs. 3s lets each ping chain
-- to the one before; `insist-miss age=` logs the near misses.
Rules.INSIST_SECONDS = 3
Rules.INSIST_RADIUS = 600
-- A FORCE NEAR order takes every bot within this distance of the spot, or at the ordered lane (maintainer's "~4000").
Rules.FORCE_NEAR_RADIUS = 4000
-- A forced order still skips a bot under this HP (it joins once back at FORCE_REJOIN_HP), a dead bot (it joins when
-- it respawns) and a channelling one (a TP in progress: it joins when the channel ends).
Rules.FORCE_MIN_HP = 0.2
Rules.FORCE_REJOIN_HP = 0.5
-- An order's mode desire. A request (ASK_DESIRE): above farm (up to ~0.6) and laning (0.565 for a safe core), below a
-- base last stand (0.9) and a hurt bot's retreat; it fades from 60% HP to LEAVE_HP (the bot leaves it under that).
-- A forced order (FORCED_DESIRE; maintainer, game 078: the human insisting outranks the team's own calls, not
-- survival) is above the team's calls as the modes return them: the Roshan gather (mode_roshan_generic.lua, 0.96),
-- a defend last stand (defend.lua, 0.9), attack mode (up to 0.95), the strength push (0.78) and farm; and below the
-- hard retreat (mode_retreat_generic.lua, 0.98) and Valve's evasive maneuvers (1.00 in most game 06x-07x lines). It
-- fades from 60% HP to FORCE_MIN_HP, and stays under the bot's own retreat desire when that is RETREAT_YIELD or more
-- (its 0.9 tower rules, or a pit walk-out at 0.96 from an open retreat PR). The kill push (push.lua, 0.99 after two kills) is capped under it
-- on the other lanes (Orders.CapForOrder).
Rules.ASK_DESIRE = 0.75
Rules.FORCED_DESIRE = 0.97
Rules.LEAVE_HP = 0.3
Rules.RETREAT_YIELD = 0.9

local function Remap(value, fromLow, fromHigh, toLow, toHigh)
	local t = (value - fromLow) / (fromHigh - fromLow)
	t = math.max(0, math.min(1, t))
	return toLow + (toHigh - toLow) * t
end

-- The mode desire of an order of `tier` for a bot at `hp` (0-1); `retreatDesire`: the bot's own retreat desire from
-- its last think, or nil.
function Rules.OrderDesire(tier, hp, retreatDesire)
	local forced = tier ~= nil and tier ~= "ask"
	local base = forced and Rules.FORCED_DESIRE or Rules.ASK_DESIRE
	local low = forced and Rules.FORCE_MIN_HP or Rules.LEAVE_HP
	local desire = base * Remap(hp or 1, low, 0.6, 0.6, 1)
	if forced and retreatDesire ~= nil and retreatDesire >= Rules.RETREAT_YIELD then
		desire = math.min(desire, retreatDesire - 0.02)
	end
	return desire
end

-- Is a bot whose active mode runs at `modeDesire` too busy for a request (ask tier, desire `orderDesire`)? Game 078,
-- 24:11: Largo was picked for a camp ping while the team's Roshan gather (0.96) held him; he said "Clearing the camp"
-- and walked to Roshan. `mode`: the mode's short name, or nil for the modes that never count (attack and fights,
-- retreat, evasive maneuvers: their own states cover them). `orderMode`: the short name of the mode that carries out
-- the human's current order for this bot (nil: none); that mode is not busy, any other is (Largo had obeyed the camp
-- ping before the gather took him, so being on the order alone must not exempt a bot).
function Rules.IsBusy(mode, modeDesire, orderDesire, orderMode)
	return mode ~= nil and mode ~= orderMode and (modeDesire or 0) > (orderDesire or Rules.ASK_DESIRE)
end
-- A forced order lasts long enough for the farthest bot to get there (ETA + FORCE_SLACK_SECONDS), within
-- ORDER_SECONDS..FORCE_MAX_SECONDS.
Rules.FORCE_SLACK_SECONDS = 15
Rules.FORCE_MAX_SECONDS = 60
-- When nobody goes, one bot says why, at most this often per team (maintainer: "no reply for 'cant do'").
Rules.REFUSAL_CHAT_SECONDS = 30
-- How long an order lasts when nothing ends it earlier (design: "~20-30s or until done").
Rules.ORDER_SECONDS = 25
Rules.DANGER_SECONDS = 6
-- A danger ping moves the bots within DANGER_RADIUS away until they are DANGER_SAFE from it (maintainer, game 075:
-- "bots within ~1200 back off"); it needs no responders.
Rules.DANGER_RADIUS = 1200
Rules.DANGER_SAFE = 1500
-- Lane orders (push / defend) during the laning stage (maintainer, game 075: "before ~10:00 don't pull a support
-- across the map for a lane push"): the ordered lane's own bots and bots within LANE_NEAR of the target come first;
-- a support off that lane farther than FAR_SUPPORT is not asked for a push. Estimates from the map, not game data
-- (a lane's T1 to the next lane's T1 is ~7000-9000; game 075 Largo was 14016 away, Puck in mid 6689).
Rules.LANING_SECONDS = 600
Rules.LANE_NEAR = 2000
Rules.FAR_SUPPORT = 5000
-- A push request before this game time is refused ("still laning", design: <5:00).
Rules.EARLY_SECONDS = 300
-- What a ping is "on": the nearest thing within these radii of the ping spot. Estimates from the map, not game data:
-- a camp ping lands on the creeps (game 074: 177 from the camp spot), a building ping on the model.
Rules.HERO_RADIUS = 500
Rules.ROSHAN_RADIUS = 600
Rules.ENEMY_BUILDING_RADIUS = 700
Rules.OUR_BUILDING_RADIUS = 800
Rules.WAVE_RADIUS = 600
Rules.CAMP_RADIUS = 600
-- A fog ping is a "chase here" when an enemy hero was seen this recently this close to it.
Rules.CHASE_SEEN_SECONDS = 5
Rules.CHASE_RADIUS = 1000

-- Chat commands. Names checked against the other commands (`!pos`, `!Npos`, `!about`, `!pick`, `!ban`, `!sp`,
-- `!speak`, `!debug`, `!verbose`, `!chatty`): none starts with these words. `!stop` cancels the order (maintainer,
-- 2026-11-24: "replace !no with !stop"; `!no` is gone, not an alias). The match is on the whole first word, so
-- `!sp` / `!speak` (matched by find in ability_item_usage_generic.lua) never see `!stop`: "!stop" holds no "!sp".
local COMMANDS = {
	["!push"] = "push",
	["!def"] = "defend",
	["!defend"] = "defend",
	["!rosh"] = "rosh",
	["!roshan"] = "rosh",
	["!group"] = "group",
	["!stop"] = "stop",
}
local LANE_WORDS = {
	top = "top",
	t = "top",
	mid = "mid",
	m = "mid",
	middle = "mid",
	bot = "bot",
	b = "bot",
	bottom = "bot",
}

-- "!push top" -> { kind = "push", lane = "top", all = false }; "!push top all" -> the same with all = true (FORCE
-- ALL; without it FORCE NEAR); "!push" -> { kind = "push" } (no lane: the bots ask which); "!rosh all",
-- "!group all", "!def mid all" likewise; "!stop" takes no words. Any other text -> nil.
function Rules.ParseChat(text)
	if type(text) ~= "string" then
		return nil
	end
	local command = text:lower():match("^%s*(.-)%s*$")
	local word, rest = command:match("^(!%a+)%s*(.*)$")
	local kind = word ~= nil and COMMANDS[word] or nil
	if kind == nil then
		return nil
	end
	local all, words = false, {}
	for token in rest:gmatch("%S+") do
		if token == "all" and kind ~= "stop" then
			all = true
		else
			words[#words + 1] = token
		end
	end
	if kind == "push" or kind == "defend" then
		local lane = #words == 1 and LANE_WORDS[words[1]] or nil
		return { kind = kind, lane = lane, all = all }
	end
	if #words > 0 then
		return nil
	end
	return { kind = kind, all = all }
end

-- Kinds whose repeated pings chain by lane (the order goes to that lane's front building wherever the ping lands).
Rules.LANE_INSIST_KINDS = { push = true, defend = true }

-- Is `ping` the same ping as `prev` again (an insist)? Both: { time =, x =, y =, targetKey =, kind =, lane =,
-- normal = }. A push / defend ping on the same lane as the one before always is (any spot, any ping type); otherwise
-- the ping type must match and the target or the spot (within INSIST_RADIUS) must be the same.
function Rules.IsInsist(prev, ping)
	if prev == nil or ping == nil or prev.time == nil or ping.time == nil or prev.time == ping.time then
		return false
	end
	local age = ping.time - prev.time
	if age <= 0 or age > Rules.INSIST_SECONDS then
		return false
	end
	if
		Rules.LANE_INSIST_KINDS[ping.kind]
		and ping.lane ~= nil
		and prev.kind == ping.kind
		and prev.lane == ping.lane
	then
		return true
	end
	if prev.normal ~= ping.normal then
		return false
	end
	if prev.targetKey ~= nil and prev.targetKey == ping.targetKey then
		return true
	end
	local dx, dy = (ping.x or 0) - (prev.x or 0), (ping.y or 0) - (prev.y or 0)
	return dx * dx + dy * dy <= Rules.INSIST_RADIUS * Rules.INSIST_RADIUS
end

-- How many pings in a row `ping` is: the previous ping's count + 1 when it is the same ping again (Rules.IsInsist:
-- each within INSIST_SECONDS of the one before), else 1. `prev.count` nil counts as 1.
function Rules.PingCount(prev, ping)
	if Rules.IsInsist(prev, ping) then
		return (prev.count or 1) + 1
	end
	return 1
end

-- The tier for a ping count: 1 "ask", 2 "force-near", 3+ "force-all".
function Rules.Tier(count)
	if (count or 1) >= 3 then
		return "force-all"
	elseif (count or 1) == 2 then
		return "force-near"
	end
	return "ask"
end

-- A building's lane and tier from its unit name ("npc_dota_badguys_tower2_top", "..._melee_rax_bot",
-- "..._fort"). Returns lane ("top" / "mid" / "bot"), tier (1-4 towers, 3 barracks, 5 the Ancient), or nil for
-- fillers and anything that is not a lane building.
function Rules.BuildingInfo(name)
	if type(name) ~= "string" or name:find("fillers") then
		return nil
	end
	if not (name:find("goodguys") or name:find("badguys")) then
		return nil
	end
	local tier = nil
	local towerTier = name:match("tower(%d)")
	if towerTier ~= nil then
		tier = tonumber(towerTier)
	elseif name:find("_rax") then
		tier = 3
	elseif name:find("_fort") then
		tier = 5
	else
		return nil
	end
	local lane = "mid"
	if name:find("_top") then
		lane = "top"
	elseif name:find("_bot") then
		lane = "bot"
	end
	return lane, tier
end

-- The camp nearest to (x, y) within CAMP_RADIUS: `camps` is a list of { x =, y = } (GetNeutralSpawners()
-- locations). Returns the index and the distance, or nil.
function Rules.NearestCamp(camps, x, y)
	local bestIndex, bestDist = nil, Rules.CAMP_RADIUS
	for i, camp in ipairs(camps or {}) do
		local dx, dy = camp.x - x, camp.y - y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist <= bestDist then
			bestIndex, bestDist = i, dist
		end
	end
	if bestIndex == nil then
		return nil
	end
	return bestIndex, bestDist
end

-- What a ping means: what is under it first, whatever the ping type. `f` (facts about the ping spot):
--   normal          a normal ping (false: a ping on a unit, or the X / danger ping on empty ground)
--   enemyHero       a visible enemy hero within HERO_RADIUS; enemyHeroInFight: an ally hero is fighting near it
--   roshan          the spot is at the Roshan pit
--   enemyBuildingDist / ourBuildingDist  distance to the nearest enemy / our lane building in range (nil: none)
--   waveSide        "theirs" (an enemy wave nearer their Ancient) / "ours" (nearer ours) / nil (no enemy wave)
--   campDist        distance to the nearest camp in range (nil: none)
--   visible         the spot is in our vision
--   recentEnemySeen an enemy hero was seen within CHASE_SEEN_SECONDS within CHASE_RADIUS of a fogged spot
-- Returns one of: focus, gank, rosh, push, defend, farm, chase, fog, move, danger.
function Rules.Classify(f)
	if f.enemyHero then
		return f.enemyHeroInFight and "focus" or "gank"
	end
	if f.roshan then
		return "rosh"
	end
	local buildingDist = math.min(f.enemyBuildingDist or math.huge, f.ourBuildingDist or math.huge)
	if f.campDist ~= nil and f.campDist < buildingDist then
		return "farm"
	end
	if f.enemyBuildingDist ~= nil and f.enemyBuildingDist <= (f.ourBuildingDist or math.huge) then
		return "push"
	end
	if f.ourBuildingDist ~= nil then
		return "defend"
	end
	if f.waveSide == "theirs" then
		return "push"
	elseif f.waveSide == "ours" then
		return "defend"
	end
	if not f.normal then
		return "danger"
	end
	if not f.visible then
		return f.recentEnemySeen and "chase" or "fog"
	end
	return "move"
end

-- Does the team agree with a request? `tier`: "ask" (a single ping: checked) or "force-near" / "force-all" (a ping
-- repeated, or a chat command: the checks below are skipped). `f`:
--   now             DotaTime()
--   aliveAllies     our heroes alive (the human too)
--   available       our bots that could go (alive, not retreating / low / holding the base)
--   enemiesNear     enemy heroes seen near the target
--   baseUnderAttack our base is under siege (defend.lua Defend.GetBaseSiege) and the order is elsewhere
--   tier            the target building's tier (push)
--   ourCreepsNear   our wave is near the target building (push)
--   roshanAlive     (rosh)
-- Returns "go" or "refuse", and the reason.
function Rules.Check(kind, tier, f)
	if kind == "rosh" and f.roshanAlive == false then
		return "refuse", "roshan-dead"
	end
	if (f.available or 0) == 0 and kind ~= "danger" then
		return "refuse", "nobody-free"
	end
	if tier ~= "ask" then
		return "go", "forced"
	end
	if kind == "push" or kind == "gank" or kind == "rosh" or kind == "farm" then
		if f.baseUnderAttack then
			return "refuse", "base-under-attack"
		end
	end
	if kind == "push" or kind == "rosh" then
		if (f.now or 0) < Rules.EARLY_SECONDS then
			return "refuse", "too-early"
		end
		if (f.aliveAllies or 0) < 3 then
			return "refuse", "too-few-alive"
		end
	end
	if kind == "push" or kind == "gank" or kind == "rosh" then
		if (f.enemiesNear or 0) > (f.available or 0) + (f.humanNear and 1 or 0) then
			return "refuse", "outnumbered"
		end
	end
	if kind == "push" and (f.tier or 1) >= 2 and not f.ourCreepsNear then
		return "refuse", "no-creeps"
	end
	return "go", "agree"
end

-- How many bots an order needs (design: as many as the target needs, more near the enemy base).
function Rules.Need(kind, f)
	local enemies = f.enemiesNear or 0
	if kind == "farm" or kind == "fog" or kind == "move" then
		return 1
	elseif kind == "gank" or kind == "chase" then
		return math.max(2, math.min(4, enemies + 1))
	elseif kind == "push" then
		local need = (f.tier or 1) <= 1 and 2 or ((f.tier or 1) == 2 and 3 or 5)
		return math.min(5, math.max(need, enemies + 1))
	elseif kind == "defend" then
		return math.max(2, math.min(5, enemies + 1))
	end
	-- focus, rosh, group, danger: everyone in range.
	return 5
end

-- How far a bot may be from the target to answer (beyond: not asked). Focus and danger are about the fight there.
local MAX_DISTANCE = { focus = 2000, chase = 1500, danger = Rules.DANGER_RADIUS, gank = 6000, move = 4000 }
function Rules.MaxDistance(kind)
	return MAX_DISTANCE[kind] or math.huge
end

-- A bot's state for an order. `b`: alive, hp (0-1), retreating, inFight, losing, holdingBase, busy (the short name
-- of an active mode above a request's desire, Rules.IsBusy, else nil).
-- Returns ok, fight, losing, retreat, low-hp, dead, base or busy:<mode> (a request skips it; a forced order takes it).
Rules.LOW_HP = 0.35
function Rules.BotState(b)
	if not b.alive then
		return "dead"
	end
	if b.retreating then
		return "retreat"
	end
	if (b.hp or 1) < Rules.LOW_HP then
		return "low-hp"
	end
	if b.holdingBase then
		return "base"
	end
	if b.inFight then
		return b.losing and "losing" or "fight"
	end
	if b.busy ~= nil then
		return "busy:" .. tostring(b.busy)
	end
	return "ok"
end

-- What a bot in `state` does with an order of `kind`: "obey", "queue" (after its fight) or "ignore".
-- A fighting bot finishes its fight first (a focus or chase call is about that fight, so it obeys); a bot losing
-- its fight may leave it for an order. A bot already at the ordered lane (`atLane`: its own lane in the laning
-- stage, or within LANE_NEAR of the target) obeys a push or defend there even while it trades: it is already
-- there (game 075: Alchemist, harassed by Undying in the bottom lane, was left out of `!push bot`). Retreating,
-- low, dead and base-holding bots don't go.
function Rules.Answer(kind, state, atLane)
	if state == "ok" then
		return "obey"
	end
	if state == "fight" or state == "losing" then
		if kind == "focus" or kind == "chase" or kind == "danger" then
			return kind == "danger" and "ignore" or "obey"
		end
		if atLane and (kind == "push" or kind == "defend") then
			return "obey"
		end
		return state == "losing" and "obey" or "queue"
	end
	return "ignore"
end

-- What a bot does with a forced order: "obey", or "queue" and why (it joins later): dead (on respawn), channel (a
-- TP in progress: when it ends) or low-hp (under FORCE_MIN_HP: once back at FORCE_REJOIN_HP). A fight, a retreat or
-- holding the base does not stop a forced bot. `c`: { state =, hp =, channeling = }.
function Rules.ForceAnswer(c)
	if c.state == "dead" then
		return "queue", "dead"
	end
	if c.channeling then
		return "queue", "channel"
	end
	if (c.hp or 1) < Rules.FORCE_MIN_HP then
		return "queue", "low-hp"
	end
	return "obey"
end

-- May a bot queued for a forced order (`why`: dead / channel / low-hp) join it now? `c`: { state =, hp =,
-- channeling = } now.
function Rules.ForceRejoin(why, c)
	if Rules.ForceAnswer(c) ~= "obey" then
		return false
	end
	return why ~= "low-hp" or (c.hp or 1) >= Rules.FORCE_REJOIN_HP
end

-- Picks the responders. `cands`: list of { id =, dist =, state =, core =, lane =, hp =, channeling =, onLane = }
-- (lane: the bot's own lane, "top" / "mid" / "bot"; onLane: the bot stands on the ordered lane). `ctx` (optional):
-- { lane = the ordered lane, now = DotaTime(), tier = "ask" (default) / "force-near" / "force-all" }.
-- Ask: for a lane order (push / defend with a lane), bots at that lane first (its own laners in the laning stage, or
-- within LANE_NEAR of the target); then nearest first (a core first for a camp: a core within CORE_FIRST_SLACK
-- farther than the nearest support still gets it), up to `need`. Bots beyond MaxDistance, and in the laning stage a
-- support off the lane farther than FAR_SUPPORT from a push, are not asked ("far").
-- Force near: every bot within FORCE_NEAR_RADIUS or at / on the ordered lane; force all: every bot. Both ignore
-- `need` (a camp still takes one bot), MaxDistance and the far-support rule, and the bot's state (Rules.ForceAnswer:
-- only dead, channelling and very low bots queue). A dead bot is not near anything: force near leaves it out.
-- Returns obey (list of ids), queue (ids), ignore (list of { id =, why = }) and every candidate's answer in the
-- order of preference: { id =, state =, dist =, answer = obey | queue | ignore | far | spare (free, not needed) |
-- wait (fighting, not needed), why = (queue: why it waits) }.
Rules.CORE_FIRST_SLACK = 2500
function Rules.PickResponders(kind, cands, need, ctx)
	ctx = ctx or {}
	local tier = ctx.tier or "ask"
	local forced = tier ~= "ask" and kind ~= "danger"
	local maxDist = Rules.MaxDistance(kind)
	local laneOrder = (kind == "push" or kind == "defend") and ctx.lane ~= nil
	local laning = ctx.now ~= nil and ctx.now < Rules.LANING_SECONDS
	if forced and kind ~= "farm" then
		need = math.huge
	end
	local function atLane(c)
		return laneOrder and ((laning and c.lane == ctx.lane) or c.dist <= Rules.LANE_NEAR)
	end
	local function forcedIn(c)
		if tier == "force-all" then
			return true
		end
		return c.dist <= Rules.FORCE_NEAR_RADIUS or atLane(c) or (laneOrder and c.onLane == true)
	end
	local sorted = {}
	for _, c in ipairs(cands or {}) do
		sorted[#sorted + 1] = c
	end
	local function key(c)
		if kind == "farm" and c.core then
			return c.dist - Rules.CORE_FIRST_SLACK
		end
		return c.dist
	end
	table.sort(sorted, function(a, b)
		local la, lb = atLane(a), atLane(b)
		if la ~= lb then
			return la
		end
		local ka, kb = key(a), key(b)
		if ka == kb then
			return a.id < b.id
		end
		return ka < kb
	end)
	-- Free bots first; bots still fighting fill the places left (they go after the fight).
	local obey, queue, ignore, waiting, decisions = {}, {}, {}, {}, {}
	for _, c in ipairs(sorted) do
		local here = atLane(c)
		local answer, why = nil, nil
		if forced then
			if c.state == "dead" and tier ~= "force-all" then
				answer = "far"
			elseif forcedIn(c) then
				answer, why = Rules.ForceAnswer(c)
			else
				answer = "far"
			end
		else
			answer = Rules.Answer(kind, c.state, here)
			if c.dist > maxDist then
				answer = "far"
			elseif
				kind == "push"
				and laneOrder
				and laning
				and not here
				and not c.core
				and c.dist > Rules.FAR_SUPPORT
			then
				answer = "far"
			elseif answer == "queue" then
				why = "in-fight"
			end
		end
		local decision = { id = c.id, state = c.state, dist = c.dist, answer = answer, why = why }
		decisions[#decisions + 1] = decision
		if answer == "obey" then
			if #obey < need then
				obey[#obey + 1] = c.id
			else
				decision.answer = "spare"
			end
		elseif answer == "queue" then
			waiting[#waiting + 1] = decision
		elseif answer == "ignore" then
			ignore[#ignore + 1] = { id = c.id, why = c.state }
		end
	end
	for _, decision in ipairs(waiting) do
		if #obey + #queue < need then
			queue[#queue + 1] = decision.id
		else
			decision.answer = "wait"
		end
	end
	return obey, queue, ignore, decisions
end

-- How many bots could answer: every candidate whose answer is not ignore or far.
function Rules.Available(decisions)
	local count = 0
	for _, d in ipairs(decisions or {}) do
		if d.answer ~= "ignore" and d.answer ~= "far" then
			count = count + 1
		end
	end
	return count
end

-- The candidates for the order line: "alchemist:obey/fight:900,largo:far/ok:14016,zeus:queue/channel:3000" (a dead
-- bot's distance is "-"; a queued bot shows why it waits). `nameOf(id)` gives the hero's short name.
function Rules.CandsText(decisions, nameOf)
	local parts = {}
	for _, d in ipairs(decisions or {}) do
		local answer = d.answer
		local note = d.state
		if d.answer == "queue" and d.why ~= nil then
			note = d.why
		end
		if note ~= "ok" then
			answer = answer .. "/" .. tostring(note)
		end
		local dist = (d.dist == nil or d.dist == math.huge) and "-" or string.format("%.0f", d.dist)
		parts[#parts + 1] = string.format("%s:%s:%s", tostring(nameOf(d.id)), answer, dist)
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

-- The order's verdict from the check and the pick: refuse (the check said no), queue (everyone who would go is
-- still fighting, dead or channelling), or go. A danger ping is a warning: it goes even with nobody near it (game
-- 075 printed `refuse why=nobody-free` for X-pings).
function Rules.Verdict(checkVerdict, obeyCount, queueCount, kind)
	if checkVerdict ~= "go" then
		return "refuse"
	end
	if kind == "danger" then
		return "go"
	end
	if obeyCount == 0 and queueCount > 0 then
		return "queue"
	end
	if obeyCount == 0 then
		return "refuse"
	end
	return "go"
end

-- How long an order lasts: ORDER_SECONDS for a request; a forced order until its farthest bot can be there
-- (`maxEta`: seconds, the slowest responder's travel or respawn + travel) plus FORCE_SLACK_SECONDS, within
-- ORDER_SECONDS..FORCE_MAX_SECONDS. A danger ping: DANGER_SECONDS.
function Rules.OrderSeconds(kind, tier, maxEta)
	if kind == "danger" then
		return Rules.DANGER_SECONDS
	end
	if tier == nil or tier == "ask" then
		return Rules.ORDER_SECONDS
	end
	local seconds = (maxEta or 0) + Rules.FORCE_SLACK_SECONDS
	return math.max(Rules.ORDER_SECONDS, math.min(Rules.FORCE_MAX_SECONDS, seconds))
end

-- May a bot say why nobody goes? At most once per REFUSAL_CHAT_SECONDS per team (`lastAt`: the last such line, nil:
-- none yet).
function Rules.RefusalAllowed(now, lastAt)
	return lastAt == nil or (now or 0) - lastAt >= Rules.REFUSAL_CHAT_SECONDS
end

-- Who says what in team chat when an order is made (maintainer, 2026-11-23: "response 'on my way' only when
-- acknowledging. no reply for 'cant do'"). A bot that goes says what it does only when it starts doing it
-- (Rules.ShouldAck, at its first obey; game 078, 24:11: Largo said "Clearing the camp" when picked, a Roshan gather
-- took him and he never went), so an order that goes plans no line here. Only when nobody goes at all (verdict refuse)
-- one bot says one short reason, if Rules.RefusalAllowed: the check's reason, or with nobody free the nearest bot's own
-- (`refuser`: { id =, key =, seconds =, lane = } or nil: "busy"). The reason waits INSIST_SECONDS (`delay`) so a
-- repeated ping that forces the order drops it. A danger ping, or an order everyone joins later (verdict queue): no
-- reply. `opts`: { now =, lastRefusalAt = }. Returns a list of { id =, key =, seconds =, lane =, delay = } (said
-- REPLY_GAP_SECONDS apart); id nil: the bot that read the order says it.
Rules.REPLY_GAP_SECONDS = 0.5
function Rules.ReplyPlan(kind, verdict, why, refuser, opts)
	opts = opts or {}
	local plan = {}
	if kind == "danger" or verdict ~= "refuse" then
		return plan
	end
	if not Rules.RefusalAllowed(opts.now, opts.lastRefusalAt) then
		return plan
	end
	if why ~= "nobody-free" then
		plan[1] = { key = why, delay = Rules.INSIST_SECONDS }
	elseif refuser ~= nil then
		plan[1] = {
			id = refuser.id,
			key = refuser.key,
			seconds = refuser.seconds,
			lane = refuser.lane,
			delay = Rules.INSIST_SECONDS,
		}
	else
		plan[1] = { key = "busy", delay = Rules.INSIST_SECONDS }
	end
	return plan
end

-- Does a bot say its "what I do" line (Rules.AckKey) at its first obey of an order of `kind`? Once per ping chain:
-- `acked[id]` is set when it said it for this order or an earlier ping of the same chain. A danger ping: never.
function Rules.ShouldAck(kind, acked, id)
	return kind ~= "danger" and not (acked or {})[id]
end

-- The reason a busy bot gives when nobody goes (a refusal key, not the ack line of the same words, so the team's
-- refusal limit and the insist drop apply): its mode's line, else "busy" ("Can't now").
Rules.BUSY_KEYS = { roshan = "busy-roshan", push = "busy-push", defend = "busy-defend" }
function Rules.BusyKey(state)
	local mode = type(state) == "string" and state:match("^busy:(%a+)") or nil
	return mode ~= nil and Rules.BUSY_KEYS[mode] or "busy"
end

-- What a bot that goes says (maintainer, game 077: "instead of generic 'on my way', change to 'pushing bot', 'on my
-- way' (when checking fog), 'attacking medusa'"): the reply key for an order of `kind` on `lane` ("top" / "mid" /
-- "bot" or nil); `hasTarget`: the order is on an enemy hero. The lines are in bots/lib/data/human_order_lines.lua.
Rules.ACK_KEYS = {
	["on-my-way"] = true,
	pushing = true,
	defending = true,
	attacking = true,
	["clearing-camp"] = true,
	["going-roshan"] = true,
	grouping = true,
}
function Rules.AckKey(kind, lane, hasTarget)
	if kind == "push" and lane ~= nil then
		return "pushing"
	elseif kind == "defend" and lane ~= nil then
		return "defending"
	elseif (kind == "gank" or kind == "focus" or kind == "chase") and hasTarget then
		return "attacking"
	elseif kind == "farm" then
		return "clearing-camp"
	elseif kind == "rosh" then
		return "going-roshan"
	elseif kind == "group" then
		return "grouping"
	end
	return "on-my-way"
end

-- Reply keys that say why nobody goes (the team's REFUSAL_CHAT_SECONDS limit and the insist drop apply to them).
function Rules.IsRefusalKey(key)
	return not Rules.ACK_KEYS[key] and key ~= "which_lane" and key ~= "cancelled"
end

-- Our own fountain area: pings there are not orders (they feed the fountain-ping credit line, #217). `fountain` is
-- Fu.GetTeamFountain() (the spawn area), `building` our fountain building (nil when not found yet): the building is
-- about 1040 from the spawn point (game 077: a ping on it landed at -7518,-6870, the spawn point is -6619,-6336), so a
-- ping on it was outside 900 of the spawn point. Returns true and which point counted ("spawn" / "building"), else
-- false.
Rules.OWN_FOUNTAIN_RADIUS = 900
function Rules.InOwnFountainArea(loc, fountain, building)
	if loc == nil then
		return false
	end
	local r2 = Rules.OWN_FOUNTAIN_RADIUS * Rules.OWN_FOUNTAIN_RADIUS
	for _, point in ipairs({ { fountain, "spawn" }, { building, "building" } }) do
		local spot = point[1]
		if spot ~= nil then
			local dx, dy = loc.x - spot.x, loc.y - spot.y
			if dx * dx + dy * dy <= r2 then
				return true, point[2]
			end
		end
	end
	return false
end

return Rules
