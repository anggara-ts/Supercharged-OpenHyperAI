-- Shared bot system: pure rules for human orders (#222): what a human's ping or chat command means, whether the
-- bots agree with a ping, and which bots answer it. No bot API calls here, so Tests/test_human_order_rules.lua can
-- run them with plain numbers; FuncLib/systems/human_orders.lua reads the world and acts on the results.
--
-- The maintainer's design (2026-11-23, issue #222): a ping is a REQUEST (the bots check it and may refuse with a
-- reason); the same ping again within ~5s is INSIST (they go even if they disagree); a chat command (`!push top`)
-- is an ORDER. An X-ping (the "danger" ping) means "back off" around the spot; on our own building it still asks
-- for a defence.
local Rules = {}

-- The same spot (or the same target) pinged again within this many seconds, this close, is an insist.
Rules.INSIST_SECONDS = 5
Rules.INSIST_RADIUS = 300
-- How long an order lasts when nothing ends it earlier (design: "~20-30s or until done").
Rules.ORDER_SECONDS = 25
Rules.DANGER_SECONDS = 6
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
-- `!speak`, `!debug`, `!verbose`): none starts with these words.
local COMMANDS = {
	["!push"] = "push",
	["!def"] = "defend",
	["!defend"] = "defend",
	["!rosh"] = "rosh",
	["!roshan"] = "rosh",
	["!group"] = "group",
	["!no"] = "no",
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

-- "!push top" -> { kind = "push", lane = "top" }; "!push" -> { kind = "push" } (no lane: the bots ask which);
-- any other text -> nil.
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
	if kind == "push" or kind == "defend" then
		local lane = LANE_WORDS[rest]
		return { kind = kind, lane = lane }
	end
	if rest ~= "" then
		return nil
	end
	return { kind = kind }
end

-- Is `ping` the same ping as `prev` again (an insist)? Both: { time =, x =, y =, targetKey = }.
function Rules.IsInsist(prev, ping)
	if prev == nil or ping == nil or prev.time == nil or ping.time == nil or prev.time == ping.time then
		return false
	end
	local age = ping.time - prev.time
	if age <= 0 or age > Rules.INSIST_SECONDS then
		return false
	end
	if prev.targetKey ~= nil and prev.targetKey == ping.targetKey then
		return true
	end
	local dx, dy = (ping.x or 0) - (prev.x or 0), (ping.y or 0) - (prev.y or 0)
	return dx * dx + dy * dy <= Rules.INSIST_RADIUS * Rules.INSIST_RADIUS
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

-- What a ping means. `f` (facts about the ping spot):
--   normal          a normal ping (false: the X / danger ping)
--   enemyHero       a visible enemy hero within HERO_RADIUS; enemyHeroInFight: an ally hero is fighting near it
--   roshan          the spot is at the Roshan pit
--   enemyBuildingDist / ourBuildingDist  distance to the nearest enemy / our lane building in range (nil: none)
--   waveSide        "theirs" (an enemy wave nearer their Ancient) / "ours" (nearer ours) / nil (no enemy wave)
--   campDist        distance to the nearest camp in range (nil: none)
--   visible         the spot is in our vision
--   recentEnemySeen an enemy hero was seen within CHASE_SEEN_SECONDS within CHASE_RADIUS of a fogged spot
-- Returns one of: focus, gank, rosh, push, defend, farm, chase, fog, move, danger.
function Rules.Classify(f)
	if not f.normal then
		if f.ourBuildingDist ~= nil then
			return "defend"
		end
		return "danger"
	end
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
	if not f.visible then
		return f.recentEnemySeen and "chase" or "fog"
	end
	return "move"
end

-- Does the team agree with a request? `via`: "ping" (a request), "insist" or "chat" (orders). `f`:
--   now             DotaTime()
--   aliveAllies     our heroes alive (the human too)
--   available       our bots that could go (alive, not retreating / low / holding the base)
--   enemiesNear     enemy heroes seen near the target
--   baseUnderAttack our base is under siege (defend.lua Defend.GetBaseSiege) and the order is elsewhere
--   tier            the target building's tier (push)
--   ourCreepsNear   our wave is near the target building (push)
--   roshanAlive     (rosh)
-- Returns "go" or "refuse", and the reason.
function Rules.Check(kind, via, f)
	if kind == "rosh" and f.roshanAlive == false then
		return "refuse", "roshan-dead"
	end
	if (f.available or 0) == 0 and kind ~= "danger" then
		return "refuse", "nobody-free"
	end
	if via ~= "ping" then
		return "go", via
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
local MAX_DISTANCE = { focus = 2000, chase = 1500, danger = 1500, gank = 6000, move = 4000 }
function Rules.MaxDistance(kind)
	return MAX_DISTANCE[kind] or math.huge
end

-- A bot's state for an order. `b`: alive, hp (0-1), retreating, inFight, losing, holdingBase.
-- Returns ok, fight, losing, retreat, low-hp, dead or base.
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
	return "ok"
end

-- What a bot in `state` does with an order of `kind`: "obey", "queue" (after its fight) or "ignore".
-- A fighting bot finishes its fight first (a focus or chase call is about that fight, so it obeys); a bot losing
-- its fight may leave it for an order. Retreating, low, dead and base-holding bots don't go.
function Rules.Answer(kind, state)
	if state == "ok" then
		return "obey"
	end
	if state == "fight" or state == "losing" then
		if kind == "focus" or kind == "chase" or kind == "danger" then
			return kind == "danger" and "ignore" or "obey"
		end
		return state == "losing" and "obey" or "queue"
	end
	return "ignore"
end

-- Picks the responders. `cands`: list of { id =, dist =, state =, core = }. Nearest first (a core first for a
-- camp: a core within CORE_FIRST_SLACK farther than the nearest support still gets it), up to `need`; bots
-- beyond MaxDistance are not asked. Returns obey (list of ids), queue (ids), ignore (list of { id =, why = }).
Rules.CORE_FIRST_SLACK = 2500
function Rules.PickResponders(kind, cands, need)
	local maxDist = Rules.MaxDistance(kind)
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
		local ka, kb = key(a), key(b)
		if ka == kb then
			return a.id < b.id
		end
		return ka < kb
	end)
	-- Free bots first; bots still fighting fill the places left (they go after the fight).
	local obey, queue, ignore, waiting = {}, {}, {}, {}
	for _, c in ipairs(sorted) do
		local answer = Rules.Answer(kind, c.state)
		if c.dist > maxDist then
			answer = "far"
		end
		if answer == "obey" and #obey < need then
			obey[#obey + 1] = c.id
		elseif answer == "queue" then
			waiting[#waiting + 1] = c.id
		elseif answer == "ignore" then
			ignore[#ignore + 1] = { id = c.id, why = c.state }
		end
	end
	for _, id in ipairs(waiting) do
		if #obey + #queue < need then
			queue[#queue + 1] = id
		end
	end
	return obey, queue, ignore
end

-- The order's verdict from the check and the pick: refuse (the check said no), queue (everyone who would go is
-- still fighting), or go.
function Rules.Verdict(checkVerdict, obeyCount, queueCount)
	if checkVerdict ~= "go" then
		return "refuse"
	end
	if obeyCount == 0 and queueCount > 0 then
		return "queue"
	end
	if obeyCount == 0 then
		return "refuse"
	end
	return "go"
end

return Rules
