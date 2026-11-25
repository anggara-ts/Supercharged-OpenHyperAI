-- bots/lib/systems/push.lua: GetPushDesire and PushThink run on the stub API without a script error (#12: the
-- high-ground gather, the cap sources and the open-Ancient count run on every push think).
local T = ...

T.test("push: GetPushDesire and PushThink run for every lane", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	T.stub.time = 1800
	local Push = require(GetScriptDirectory() .. "/lib/systems/push")
	local bot = GetBot()
	bot._level = 20
	for lane = 1, 3 do
		local desire = Push.GetPushDesire(bot, lane)
		T.ok(type(desire) == "number", "desire is a number for lane " .. lane)
		Push.PushThink(bot, lane)
	end
end)

T.test("push: a dead-enemies window near their fountain gathers below the high ground", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	T.stub.time = 1800
	local KillWindow = require(GetScriptDirectory() .. "/lib/systems/kill_window")
	local Push = require(GetScriptDirectory() .. "/lib/systems/push")
	local bot = GetBot()
	bot._level = 20
	-- Our lane front stands at their high ground (3500 from the Dire fountain); -delta walks back toward our base.
	local frontFn = _G.GetLaneFrontLocation
	_G.GetLaneFrontLocation = function(_, _, delta)
		local back = -(delta or 0)
		local sign = GetTeam() == TEAM_RADIANT and 1 or -1
		return Vector(sign * (4500 - back * 0.7), sign * (4000 - back * 0.7), 0)
	end
	local enemyTeam = T.stub.teams[GetOpposingTeam()]
	KillWindow.Tick()
	for i = 1, 3 do
		enemyTeam[i]._level = 20
		enemyTeam[i]._alive = false
	end
	-- The two alive ones far from the lane front.
	enemyTeam[4]._loc = Vector(-6000, 6000, 0)
	enemyTeam[5]._loc = Vector(-6000, 6000, 0)
	-- Our other four far away: this bot is alone near their high ground.
	local ourTeam = T.stub.teams[GetTeam()]
	for i = 1, #ourTeam do
		if ourTeam[i] ~= bot then
			ourTeam[i]._loc = Vector(-6000, -6000, 0)
		end
	end
	bot._loc = Vector(3000, 2500, 0)
	T.stub.time = 1801
	KillWindow.Tick()
	T.stub.time = 1802
	local ok, err = pcall(function()
		for lane = 1, 3 do
			Push.GetPushDesire(bot, lane)
		end
		Push.PushThink(bot, 1)
	end)
	_G.GetLaneFrontLocation = frontFn
	T.ok(ok, tostring(err))
	local seen = false
	for _, line in ipairs(T.stub.printed) do
		if string.find(tostring(line), "hg-gather lane=1 need=2", 1, true) then
			seen = true
		end
	end
	T.ok(seen, "a lone bot in a dead-enemies window gathers (need=2)")
	T.ok(bot._hgGatherActive ~= nil and bot._hgGatherActive.spot ~= nil, "gather spot kept for PushThink")
	T.ok(bot._hgGather ~= nil and bot._hgGather[1] ~= nil and bot._hgGather[1].since ~= nil, "lane 1 state kept")
	-- The Roshan-first state and the creep pressure read on the same stub.
	local count = Push.CreepPressureLanes()
	T.ok(type(count) == "number", "pressure lanes")
	local on, why = Push.RoshanFirstState(bot)
	T.eq(on, false, "3 enemies dead: no Roshan first")
	T.ok(type(why) == "string", "why")
end)

T.test("push: a glyphed enemy tower keeps the bot at it (glyph-wait), the end prints glyph-end", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	T.stub.time = 1300
	local Push = require(GetScriptDirectory() .. "/lib/systems/push")
	local bot = GetBot()
	bot._level = 20
	-- Game 074 t=1308: Dire's bottom T1 glyphed, this bot 500 from it, no creeps of ours, nobody else near.
	local enemyTeam = GetOpposingTeam()
	local ourTeam = T.stub.teams[GetTeam()]
	for i = 1, #ourTeam do
		if ourTeam[i] ~= bot then
			ourTeam[i]._loc = Vector(-6000, -6000, 0)
		end
	end
	for _, enemy in ipairs(T.stub.teams[enemyTeam]) do
		enemy._loc = Vector(-6000, 6000, 0)
	end
	bot._loc = Vector(6000, -2700, 0)
	local towerName = enemyTeam == TEAM_DIRE and "npc_dota_badguys_tower1_bot" or "npc_dota_goodguys_tower1_bot"
	local tower = T.stub.newUnit({ name = towerName, team = enemyTeam, loc = Vector(6100, -2200, 0), hero = false })
	local glyphed = true
	tower.HasModifier = function(_, name)
		return glyphed and name == "modifier_fountain_glyph"
	end
	tower.CanBeSeen = function()
		return true
	end
	tower.IsTower = function()
		return true
	end
	tower.GetAttackRange = function()
		return 700
	end
	tower.IsBuilding = function()
		return true
	end
	bot.GetNearbyTowers = function(_, _, enemy)
		return enemy and { tower } or {}
	end
	local moved, attacked = nil, nil
	bot.Action_MoveToLocation = function(_, location)
		moved = location
	end
	bot.Action_AttackUnit = function(_, unit)
		attacked = unit
	end
	local ok, err = pcall(function()
		Push.PushThink(bot, 3)
	end)
	T.ok(ok, tostring(err))
	T.ok(attacked == nil, "the glyphed tower is not attacked")
	T.ok(moved ~= nil, "the bot got a move order")
	T.ok(bot._glyphWait ~= nil and bot._glyphWait.mode == "edge", "no creeps of ours: waits at the edge")
	local function printed(pattern)
		for _, line in ipairs(T.stub.printed) do
			if string.find(tostring(line), pattern, 1, true) then
				return true
			end
		end
		return false
	end
	T.ok(printed("glyph-wait lane=3"), "glyph-wait line")
	T.ok(printed("why=no-creeps"), "why")
	-- Game 078 (maintainer: "standing still is bad"): at the edge with nothing to hit, the bot side-steps along it
	-- instead of a move to its own spot, and stays out of the tower's reach.
	bot._loc = moved
	moved = nil
	T.stub.time = 1303
	ok, err = pcall(function()
		Push.PushThink(bot, 3)
	end)
	T.ok(ok, tostring(err))
	T.ok(moved ~= nil, "a move order at the edge")
	local stepped = moved ~= nil and math.sqrt((moved.x - bot._loc.x) ^ 2 + (moved.y - bot._loc.y) ^ 2) or 0
	T.ok(stepped >= 100, "a side-step, not a stand-still: " .. stepped)
	local fromTower = moved ~= nil and math.sqrt((moved.x - 6100) ^ 2 + (moved.y + 2200) ^ 2) or 0
	T.ok(fromTower > 750, "the step stays outside the tower's reach: " .. fromTower)
	-- The Glyph ends: the next desire think closes the episode.
	glyphed = false
	T.stub.time = 1307
	ok, err = pcall(function()
		Push.GetPushDesire(bot, 3)
	end)
	T.ok(ok, tostring(err))
	T.ok(bot._glyphWait == nil, "episode closed")
	T.ok(printed("glyph-end why=ended lane=3"), "glyph-end line")
	T.ok(printed("moves=2 backs=0 spread=-1"), "glyph-end counts the moves (out of range, one side-step), no ally")
end)

T.test("push: a lone bot walks to this lane's push group instead of dropping (alone-join, game 085 35:17)", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	T.stub.time = 1800
	local Push = require(GetScriptDirectory() .. "/lib/systems/push")
	local bot = GetBot()
	bot._level = 20
	-- Every lane front in the middle of the map, far from both fountains (no high-ground rules).
	local frontFn = _G.GetLaneFrontLocation
	local function middleFront(_, _, delta)
		return Vector(-(delta or 0) * 0.1, 0, 0)
	end
	-- Four enemies alive (game 085 t=2147: alive 5/4, no window), far away; one dead.
	local enemies = T.stub.teams[GetOpposingTeam()]
	for _, enemy in ipairs(enemies) do
		enemy._level = 20
		enemy._loc = Vector(6500, 6500, 0)
	end
	enemies[5]._alive = false
	-- Two allies at the lane front (the group), two far off, this bot alone 5000 away.
	local ourTeam = T.stub.teams[GetTeam()]
	local slots = {}
	for i = 1, #ourTeam do
		if ourTeam[i] ~= bot then
			slots[#slots + 1] = i
		end
	end
	ourTeam[slots[1]]._loc = Vector(400, 300, 0)
	ourTeam[slots[2]]._loc = Vector(600, 500, 0)
	ourTeam[slots[3]]._loc = Vector(-7000, 6000, 0)
	ourTeam[slots[4]]._loc = Vector(-7200, 6200, 0)
	bot._loc = Vector(-5000, -1000, 0)
	local moved = nil
	bot.Action_MoveToLocation = function(_, location)
		moved = location
	end
	-- The engine's lane desire and the team's push lane (top), which the stub doesn't model.
	local laneDesireFn, whichLane = _G.GetPushLaneDesire, Push.WhichLaneToPush
	_G.GetPushLaneDesire = function()
		return 0.8
	end
	Push.WhichLaneToPush = function()
		return 1
	end
	local desire, gate = nil, nil
	_G.GetLaneFrontLocation = middleFront
	local ok, err = pcall(function()
		for lane = 1, 3 do
			local laneDesire = Push.GetPushDesire(bot, lane)
			if lane == 1 then
				desire, gate = laneDesire, bot._pushGate
			end
		end
		Push.PushThink(bot, 1)
	end)
	_G.GetLaneFrontLocation = frontFn
	_G.GetPushLaneDesire, Push.WhichLaneToPush = laneDesireFn, whichLane
	T.ok(ok, tostring(err))
	local function printed(pattern)
		for _, line in ipairs(T.stub.printed) do
			if string.find(tostring(line), pattern, 1, true) then
				return true
			end
		end
		return false
	end
	T.ok(bot._pushJoin ~= nil and bot._pushJoin[1] ~= nil, "lane 1: joining the group")
	T.eq(gate, nil, "lane 1: no gate dropped the push")
	T.ok(type(desire) == "number" and desire >= 0.5, "lane 1 keeps a push desire: " .. tostring(desire))
	T.ok(moved ~= nil and math.abs(moved.x - 500) < 1 and math.abs(moved.y - 400) < 1, "walks to the group")
	T.ok(printed("push-gate lane=1 why=alone-join group=2 atFront=2"), "alone-join line while walking")
	-- Nobody on the lane: the old drop.
	ourTeam[slots[1]]._loc = Vector(-7000, 6000, 0)
	ourTeam[slots[2]]._loc = Vector(-7000, 6000, 0)
	T.stub.time = 1801
	_G.GetLaneFrontLocation = middleFront
	ok, err = pcall(function()
		Push.GetPushDesire(bot, 1)
	end)
	_G.GetLaneFrontLocation = frontFn
	T.ok(ok, tostring(err))
	T.eq(bot._pushGate, "alone", "no group: dropped as alone")
end)
