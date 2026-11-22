-- FuncLib/systems/push.lua: GetPushDesire and PushThink run on the stub API without a script error (#12: the
-- high-ground gather, the cap sources and the open-Ancient count run on every push think).
local T = ...

T.test("push: GetPushDesire and PushThink run for every lane", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	T.stub.time = 1800
	local Push = require(GetScriptDirectory() .. "/FuncLib/systems/push")
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
	local KillWindow = require(GetScriptDirectory() .. "/FuncLib/systems/kill_window")
	local Push = require(GetScriptDirectory() .. "/FuncLib/systems/push")
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
	T.ok(bot._hgGatherState ~= nil and bot._hgGatherState.spot ~= nil, "gather spot kept for PushThink")
end)
