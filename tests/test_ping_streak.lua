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

-- The name in the line: its third word.
local function NameIn(line)
	return line:match("^%S+ %S+ (%l+)%.")
end

T.test("ping streak: the line decodes to the expected text", function()
	local line = Load().Line()
	T.eq(#line, 69, "length")
	T.eq(line:sub(1, 1), "M", "first letter")
	local sum, hash = 0, 0
	for i = 1, #line do
		sum = sum + line:byte(i)
		hash = (hash * 31 + line:byte(i)) % 1000003
	end
	T.eq(sum, 6374, "byte sum")
	T.eq(hash, 656802, "rolling hash")
	T.eq(#(NameIn(line) or ""), 8, "a name of 8 letters")
	T.ok(not line:find("http", 1, true), "no link (links in chat are not clickable)")
end)

T.test("ping streak: the line is not in any Lua source as plain text", function()
	local line = Load().Line()
	local name = NameIn(line) or "?"
	local needles = { name, name:sub(1, 5), name:sub(3), name:reverse() }
	for _, path in ipairs(T.files("^bots/.*%.lua$")) do
		local src = T.read(path):lower()
		for _, needle in ipairs(needles) do
			T.ok(not src:find(needle, 1, true), path .. " has a plain part of the name")
		end
	end
	for _, path in ipairs(T.files("^tests/.*%.lua$")) do
		local src = T.read(path):lower()
		for _, needle in ipairs(needles) do
			T.ok(not src:find(needle, 1, true), path .. " has a plain part of the name")
		end
	end
	-- No word of the line sits in the file that decodes it.
	local own = T.read("bots/lib/systems/ping_streak.lua"):lower()
	for word in line:lower():gmatch("%w+") do
		if #word >= 5 then
			T.ok(not own:find(word, 1, true), "ping_streak.lua has a plain word of the line")
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

-- Game 077: 6 pings on the fountain building (about -7518,-6870) counted nothing: it is ~1040 from the spawn point
-- (-6619,-6336) that Fu.GetTeamFountain() gives. A ping within RADIUS of the building counts too.
T.test("ping streak: a ping on the fountain building counts", function()
	local Streak = Load()
	local fx, fy, bx, by = -6619, -6336, -7480, -6900
	T.eq(Streak.Near(-7518, -6870, fx, fy), false, "the spawn point alone misses the building")
	T.eq(Streak.Near(-7518, -6870, fx, fy, bx, by), true, "on the building")
	T.eq(Streak.Near(-7030, -6646, fx, fy, bx, by), true, "the ground in front of it (the streak that answered)")
	T.eq(Streak.Near(-5000, -5000, fx, fy, bx, by), false, "far from both")
	local state = { count = 0 }
	for i = 1, 4 do
		T.eq(Streak.Step(state, 100 + i, -7518, -6870, fx, fy, 100 + i, bx, by), false, "building ping " .. i)
	end
	T.eq(state.count, 4, "four counted on the building")
	T.eq(Streak.Step(state, 105, -7518, -6870, fx, fy, 105, bx, by), true, "the fifth answers")
	local old = { count = 0 }
	Streak.Step(old, 100, -7518, -6870, fx, fy, 100)
	T.eq(old.count, 0, "without the building the ping does not count")
end)

T.test("ping streak: the item think finds the fountain building and counts pings on it", function()
	T.stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local Usage = dofile("bots/ability_item_usage_generic.lua")
	local Streak = require(GetScriptDirectory() .. "/lib/systems/ping_streak")
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local bot = GetBot()
	local humanSlot = GetTeamMember(1) == bot and 2 or 1
	local human = GetTeamMember(humanSlot)
	local humanId = GetTeamPlayers(GetTeam())[humanSlot]
	IsPlayerBot = function(playerId)
		return playerId ~= humanId
	end
	local said = {}
	bot.ActionImmediate_Chat = function(_, text)
		said[#said + 1] = text
	end
	local fountain = Fu.GetTeamFountain()
	-- The building ~1040 from the spawn point, as in game 077.
	local buildingLoc = Vector(fountain.x - 900, fountain.y - 520, 0)
	local building = T.stub.newUnit({ name = "dota_fountain", team = GetTeam(), loc = buildingLoc, hero = false })
	GetUnitList = function(listType)
		if listType == UNIT_LIST_ALLIED_BUILDINGS then
			return { building }
		end
		return {}
	end
	local pingTime = -100
	human.GetMostRecentPing = function()
		return { time = pingTime, location = Vector(buildingLoc.x - 30, buildingLoc.y + 20, 0), normal_ping = false }
	end
	Usage.WatchFountainPings()
	for _ = 1, 5 do
		T.stub.time = T.stub.time + 1
		pingTime = GameTime() - 0.2
		Usage.WatchFountainPings()
	end
	T.eq(#said, 1, "five pings on the building: the line")
	T.eq(said[1], Streak.Line(), "the credit line")
	local found = false
	for _, line in ipairs(T.stub.printed) do
		if line:find("fountain-building team=", 1, true) then
			found = true
		end
	end
	T.ok(found, "the building is logged once found")
end)

-- Game 078, 26:18-26:23: five pings read by the [SHy-PING] trace (DotaTime when read; the pings' own times are
-- GameTime, a fixed offset away). The first at -7117,-6692 (612 from the spawn point, 419 from the building), four on
-- the fountain building at -7456,-6938. They answered (`[SHy-CHAT] t=1584 alchemist egg team=radiant human=4
-- said=yes`); this replays them, and the fountain-ping line shows each count.
T.test("ping streak: the game 078 streak at 26:18 answers on the fifth ping", function()
	local Streak = Load()
	local fx, fy, bx, by = -6619, -6336, -7456, -6938
	local offset = 90
	local pings = {
		{ 1578.8, -7117, -6692 },
		{ 1580.4, -7512, -6918 },
		{ 1581.5, -7511, -6917 },
		{ 1582.6, -7510, -6913 },
		{ 1583.8, -7508, -6913 },
	}
	local state = { count = 0 }
	for i, ping in ipairs(pings) do
		local at = ping[1] + offset
		local done = Streak.Step(state, at, ping[2], ping[3], fx, fy, at + 0.1, bx, by)
		T.eq(state.near, true, "ping " .. i .. " is near")
		if i < #pings then
			T.eq(done, false, "ping " .. i .. ": not yet")
			T.eq(state.count, i, "ping " .. i .. " counted")
		else
			T.eq(done, true, "the fifth ping answers")
			T.eq(state.count, 0, "then it starts over")
		end
		if i > 1 then
			T.near(state.gap, ping[1] - pings[i - 1][1], 1e-6, "gap " .. i)
		end
	end
	-- The same pings read by a bot a second late are still fresh (within GAP).
	state = { count = 0 }
	local done = false
	for _, ping in ipairs(pings) do
		done = Streak.Step(state, ping[1] + offset, ping[2], ping[3], fx, fy, ping[1] + offset + 1, bx, by)
	end
	T.eq(done, true, "read 1s late: still answers")
end)

T.test("ping streak: the item think logs fountain-ping for each fountain ping", function()
	T.stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local Usage = dofile("bots/ability_item_usage_generic.lua")
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local bot = GetBot()
	local humanSlot = GetTeamMember(1) == bot and 2 or 1
	local human = GetTeamMember(humanSlot)
	local humanId = GetTeamPlayers(GetTeam())[humanSlot]
	IsPlayerBot = function(playerId)
		return playerId ~= humanId
	end
	bot.ActionImmediate_Chat = function() end
	local fountain = Fu.GetTeamFountain()
	local pingTime, pingX = -100, fountain.x + 200
	human.GetMostRecentPing = function()
		return { time = pingTime, location = Vector(pingX, fountain.y, 0), normal_ping = true }
	end
	Usage.WatchFountainPings()
	T.stub.printed = {}
	for _ = 1, 3 do
		T.stub.time = T.stub.time + 1.2
		pingTime = GameTime() - 0.2
		Usage.WatchFountainPings()
		Usage.WatchFountainPings()
	end
	-- A ping far away ends the count, a later far ping logs nothing.
	pingX = fountain.x + 5000
	for _ = 1, 2 do
		T.stub.time = T.stub.time + 1.2
		pingTime = GameTime() - 0.2
		Usage.WatchFountainPings()
	end
	local steps = {}
	for _, line in ipairs(T.stub.printed) do
		if line:find("[SHy-CHAT]", 1, true) and line:find(" fountain-ping ", 1, true) then
			steps[#steps + 1] = line
		end
	end
	T.eq(#steps, 4, "three near pings and the far one that ended the count")
	T.ok(steps[1] ~= nil and steps[1]:find("count=1 near=true gap=- ", 1, true) ~= nil, "the first: count 1")
	T.ok(steps[3] ~= nil and steps[3]:find("count=3 near=true gap=1.2 ", 1, true) ~= nil, "the third: count 3")
	T.ok(steps[4] ~= nil and steps[4]:find("count=0 near=false", 1, true) ~= nil, "the far ping: count 0")
end)
