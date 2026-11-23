-- Pinging our own fountain area several times in a row (#215): bots/lib/systems/ping_streak.lua.
local T = ...

local function Load()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/lib/systems/ping_streak")
end

-- Our fountain at (0, 0) in these cases.
local function Ping(Streak, state, at, now, x)
	return Streak.Step(state, at, x or 100, 100, 0, 0, now or at)
end

T.test("ping streak: the signature decodes to the expected text", function()
	local Streak = Load()
	local text = Streak.Signature()
	T.eq(#text, 8, "length")
	T.eq(text:sub(1, 1), "d", "first letter")
	local sum, weighted = 0, 0
	for i = 1, #text do
		sum = sum + text:byte(i)
		weighted = weighted + i * text:byte(i)
	end
	T.eq(sum, 842, "byte sum")
	T.eq(weighted, 3855, "weighted byte sum")
	T.ok(text:match("^%l+$") ~= nil, "lower-case letters only")
	local line = Streak.Line()
	T.ok(line:find(text, 1, true) ~= nil, "the line has it")
	T.ok(line:find("forest0xia", 1, true) ~= nil, "the upstream credit")
	T.ok(not line:find("http", 1, true), "no link (links in chat are not clickable)")
end)

T.test("ping streak: the signature is not in any Lua source as plain text", function()
	local text = Load().Signature()
	local needles = { text, text:sub(1, 5), text:sub(3), text:reverse() }
	for _, path in ipairs(T.files("^bots/.*%.lua$")) do
		local src = T.read(path):lower()
		for _, needle in ipairs(needles) do
			T.ok(not src:find(needle, 1, true), path .. " has a plain part of the signature")
		end
	end
	for _, path in ipairs(T.files("^tests/.*%.lua$")) do
		local src = T.read(path):lower()
		for _, needle in ipairs(needles) do
			T.ok(not src:find(needle, 1, true), path .. " has a plain part of the signature")
		end
	end
end)

T.test("ping streak: five fountain pings in a row, each within GAP seconds", function()
	local Streak = Load()
	T.eq(Streak.COUNT, 5, "five pings")
	local state = { count = 0 }
	for i = 1, 4 do
		T.eq(Ping(Streak, state, 100 + i), false, "ping " .. i)
	end
	T.eq(state.count, 4, "four counted")
	T.eq(Ping(Streak, state, 104), false, "the same ping read again does not count")
	T.eq(state.count, 4, "still four")
	T.eq(Ping(Streak, state, 104 + Streak.GAP - 0.5), true, "the fifth ping answers")
	T.eq(state.count, 0, "the streak starts over")
	T.eq(Ping(Streak, state, 110), false, "the next ping starts a new streak")
	T.eq(state.count, 1, "one")
end)

T.test("ping streak: a slow ping, a ping elsewhere or an old ping starts over", function()
	local Streak = Load()
	local state = { count = 0 }
	Ping(Streak, state, 100)
	Ping(Streak, state, 101)
	T.eq(state.count, 2, "two")
	Ping(Streak, state, 101 + Streak.GAP + 0.5)
	T.eq(state.count, 1, "a gap over GAP seconds: a new streak")
	Ping(Streak, state, 106, 106, Streak.RADIUS + 200)
	T.eq(state.count, 0, "a ping outside the fountain area breaks it")
	Ping(Streak, state, 107)
	Ping(Streak, state, 108)
	T.eq(state.count, 2, "two again")
	T.eq(Ping(Streak, state, 109, 109 + Streak.GAP + 1), false, "read too late")
	T.eq(state.count, 0, "an old ping (first read after a long time) breaks it")
	T.eq(Ping(Streak, state, 0), false, "no ping yet (time 0)")
	T.eq(Ping(Streak, state, -100), false, "no ping yet (negative time)")
	T.eq(state.count, 0, "nothing counted")
end)

T.test("ping streak: one answer per team per COOLDOWN seconds", function()
	local Streak = Load()
	local shared = { humans = {} }
	T.eq(Streak.Allow(shared, 600), true, "first")
	T.eq(Streak.Allow(shared, 600 + Streak.COOLDOWN - 1), false, "within the cooldown")
	T.eq(Streak.Allow(shared, 600 + Streak.COOLDOWN), true, "after it")
	T.ok(Streak.COOLDOWN >= 300, "at most once per 5 minutes")
	T.ok(Streak.Team(TEAM_RADIANT) ~= Streak.Team(TEAM_DIRE), "each team has its own state")
	T.ok(Streak.Team(TEAM_RADIANT) == Streak.Team(TEAM_RADIANT), "kept per team")
end)

T.test("ping streak: the item think answers five fountain pings once, in team chat", function()
	T.stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local Usage = dofile("bots/ability_item_usage_generic.lua")
	local Streak = require(GetScriptDirectory() .. "/lib/systems/ping_streak")
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local bot = GetBot()
	-- One team member other than this bot is a human (the stub's players are all bots).
	local humanSlot = GetTeamMember(1) == bot and 2 or 1
	local human = GetTeamMember(humanSlot)
	local humanId = GetTeamPlayers(GetTeam())[humanSlot]
	IsPlayerBot = function(playerId)
		return playerId ~= humanId
	end
	local said = {}
	bot.ActionImmediate_Chat = function(_, text, allChat)
		said[#said + 1] = { text = text, allChat = allChat }
	end
	local fountain = Fu.GetTeamFountain()
	local pingTime, pingX = -100, fountain.x + 200
	human.GetMostRecentPing = function()
		return { time = pingTime, location = Vector(pingX, fountain.y, 0), normal_ping = true }
	end
	local function PingTimes(count)
		for _ = 1, count do
			T.stub.time = T.stub.time + 1
			pingTime = GameTime() - 0.2
			Usage.WatchFountainPings()
			Usage.WatchFountainPings()
		end
	end
	Usage.WatchFountainPings()
	PingTimes(4)
	T.eq(#said, 0, "four pings: nothing yet")
	PingTimes(1)
	T.eq(#said, 1, "the fifth ping: one line")
	T.eq(said[1] and said[1].text, Streak.Line(), "the credit line")
	T.eq(said[1] and said[1].allChat, false, "in team chat")
	PingTimes(10)
	T.eq(#said, 1, "again within the cooldown: no line")
	T.stub.time = T.stub.time + Streak.COOLDOWN
	pingX = fountain.x + Streak.RADIUS + 300
	PingTimes(5)
	T.eq(#said, 1, "pings outside the fountain area: no line")
	pingX = fountain.x + 200
	PingTimes(5)
	T.eq(#said, 2, "after the cooldown: a line again")
end)
