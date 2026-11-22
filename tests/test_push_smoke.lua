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
	-- The Glyph ends: the next desire think closes the episode.
	glyphed = false
	T.stub.time = 1307
	ok, err = pcall(function()
		Push.GetPushDesire(bot, 3)
	end)
	T.ok(ok, tostring(err))
	T.ok(bot._glyphWait == nil, "episode closed")
	T.ok(printed("glyph-end why=ended lane=3"), "glyph-end line")
end)
