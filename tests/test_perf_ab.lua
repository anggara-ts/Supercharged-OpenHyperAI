-- bots/lib/systems/perf_ab.lua ([SHy-AB], #251): the measurement switches the pieces of frame_cache.lua from frame to
-- frame, times every variant ("arm") with the calls Perf.Wrap already times, and must never change what a script is
-- told. A frame is one GameTime() value.
local T = ...
local Stub = T.stub
local FRAME = 1 / 30
local ARMS = { "off", "off2", "turbo", "lists", "filter", "all" }
-- lists, filter, turbo
local PIECES = {
	off = { false, false, false },
	off2 = { false, false, false },
	turbo = { false, false, true },
	lists = { true, false, false },
	filter = { false, true, false },
	all = { true, true, true },
}

-- A Radiant bot with the other four Radiant heroes within 500. `clock.now` is what RealTime() answers, so a timed call
-- costs what the case adds to it; GameTime() only moves with Stub.time. `calls.n` counts the engine's GetNearbyHeroes
-- calls, below the wrapper in global_overrides.lua.
local function setup()
	local bot = Stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local clock = { now = 0 }
	RealTime = function()
		return clock.now
	end
	local calls = { n = 0 }
	local engine = CDOTA_Bot_Script.GetNearbyHeroes
	CDOTA_Bot_Script.GetNearbyHeroes = function(...)
		calls.n = calls.n + 1
		return engine(...)
	end
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local FrameCache = require(GetScriptDirectory() .. "/lib/systems/frame_cache")
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	local PerfAb = require(GetScriptDirectory() .. "/lib/systems/perf_ab")
	return bot, Fu, FrameCache, Perf, PerfAb, clock, calls
end

local function nextFrame()
	Stub.time = Stub.time + FRAME
end

local function printedWith(text)
	local found = {}
	for _, line in ipairs(Stub.printed) do
		if string.find(line, text, 1, true) then
			found[#found + 1] = line
		end
	end
	return found
end

T.test("[SHy-AB]: six frames run the six arms once each, in an order shuffled for every six", function()
	local _, _, _, Perf, PerfAb = setup()
	local think = Perf.Wrap("test.Think", function() end)
	T.eq(PerfAb.Arm(), nil, "no arm before the first timed call")
	local orders, firstArms = {}, {}
	for block = 1, 40 do
		local seen, order = {}, {}
		for _ = 1, #ARMS do
			nextFrame()
			think()
			local arm = PerfAb.Arm()
			think()
			T.eq(PerfAb.Arm(), arm, "a second call in the frame stays in its arm")
			seen[arm] = (seen[arm] or 0) + 1
			order[#order + 1] = arm
		end
		for _, name in ipairs(ARMS) do
			T.eq(seen[name], 1, "block " .. block .. ": " .. name)
		end
		orders[table.concat(order, ",")] = true
		firstArms[order[1]] = true
	end
	local distinctOrders, distinctFirst = 0, 0
	for _ in pairs(orders) do
		distinctOrders = distinctOrders + 1
	end
	for _ in pairs(firstArms) do
		distinctFirst = distinctFirst + 1
	end
	T.ok(distinctOrders >= 30, "40 sixes, " .. distinctOrders .. " different orders")
	T.eq(distinctFirst, #ARMS, "every arm opens a six now and then")
end)

T.test("[SHy-AB]: every arm switches on its own pieces of the frame cache", function()
	local _, _, FrameCache, Perf, PerfAb = setup()
	local think = Perf.Wrap("test.Think", function() end)
	for _, name in ipairs(ARMS) do
		T.eq(PerfAb.Pin(name), true, "pin " .. name)
		nextFrame()
		think()
		T.eq(PerfAb.Arm(), name, "the frame's arm")
		T.eq(FrameCache.lists, PIECES[name][1], name .. ": lists")
		T.eq(FrameCache.filter, PIECES[name][2], name .. ": filter")
		T.eq(FrameCache.turbo, PIECES[name][3], name .. ": turbo")
	end
	T.eq(PerfAb.Pin("nope"), false, "an unknown arm pins nothing")
	-- Unpinned, the pieces follow the arm of each frame.
	for _ = 1, 12 do
		nextFrame()
		think()
		local pieces = PIECES[PerfAb.Arm()]
		T.eq(FrameCache.lists, pieces[1], "lists follows the arm")
		T.eq(FrameCache.filter, pieces[2], "filter follows the arm")
		T.eq(FrameCache.turbo, pieces[3], "turbo follows the arm")
	end
end)

T.test("[SHy-AB]: `off` is the code from before: every question goes to the engine again", function()
	local bot, Fu, _, Perf, PerfAb, _, calls = setup()
	local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
	local think = Perf.Wrap("test.Think", function() end)
	local ally = GetTeamMember(2)
	local filterCalls = 0
	ally.IsInvulnerable = function()
		filterCalls = filterCalls + 1
		return false
	end
	local stubList = GetUnitList
	local scans = 0
	GetUnitList = function(listType)
		if listType == UNIT_LIST_ALLIES then
			scans = scans + 1
		end
		return stubList(listType)
	end
	-- One frame of the same questions, asked twice each.
	local function frame(name)
		PerfAb.Pin(name)
		nextFrame()
		think()
		calls.n, filterCalls, scans = 0, 0, 0
		for _ = 1, 2 do
			bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
			Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
			Fu.IsModeTurbo()
			Utils.IsModeTurbo()
		end
		return calls.n, filterCalls, scans
	end
	local offEngine, offFilter, offScans = frame("off")
	T.eq(offEngine, 4, "off: four list questions, four engine calls")
	T.ok(offFilter >= 2, "off: the hero is checked in both Fu calls")
	T.eq(offScans, 4, "off: four Turbo checks, four reads of the allied units")
	local engineNow, filterNow, scansNow = frame("off2")
	T.eq(engineNow, offEngine, "off2 is off: engine calls")
	T.eq(filterNow, offFilter, "off2 is off: filter")
	T.eq(scansNow, offScans, "off2 is off: Turbo")
	engineNow, filterNow, scansNow = frame("turbo")
	T.eq(engineNow, offEngine, "turbo: lists as off")
	T.eq(filterNow, offFilter, "turbo: filter as off")
	T.eq(scansNow, 2, "turbo: one read for Fu and one for Utils")
	engineNow, filterNow, scansNow = frame("lists")
	T.eq(engineNow, 1, "lists: one engine call for the four")
	T.eq(filterNow, offFilter, "lists: filter as off")
	T.eq(scansNow, offScans, "lists: Turbo as off")
	engineNow, filterNow, scansNow = frame("filter")
	T.eq(engineNow, offEngine, "filter: lists as off")
	T.eq(filterNow, offFilter / 2, "filter: the hero is checked in the first Fu call only")
	T.eq(scansNow, offScans, "filter: Turbo as off")
	engineNow, filterNow, scansNow = frame("all")
	T.eq(engineNow, 1, "all: one engine call")
	T.eq(filterNow, offFilter / 2, "all: one check of the hero")
	T.eq(scansNow, 2, "all: one read each")
end)

T.test("[SHy-AB]: every arm tells the scripts the same", function()
	local bot, Fu, _, Perf, PerfAb = setup()
	local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
	local think = Perf.Wrap("test.Think", function() end)
	-- An enemy in range, an ally the filter leaves out, a Turbo courier.
	local enemy = Stub.teams[TEAM_DIRE][1]
	enemy._loc = bot:GetLocation() + Vector(300, 0, 0)
	GetTeamMember(3).IsInvulnerable = function()
		return true
	end
	local courier = Stub.newUnit({ name = "npc_dota_courier", team = TEAM_RADIANT, hero = false })
	courier.GetCurrentMovementSpeed = function()
		return 1100
	end
	local stubList = GetUnitList
	GetUnitList = function(listType)
		if listType == UNIT_LIST_ALLIES then
			return { GetTeamMember(1), courier }
		end
		return stubList(listType)
	end
	local function names(list)
		if list == nil then
			return "nil"
		end
		local out = {}
		for i = 1, #list do
			out[i] = list[i]:GetUnitName() .. "@" .. tostring(list[i])
		end
		return table.concat(out, ",")
	end
	-- Asked twice, so the second answer of an arm that keeps answers is a kept one.
	local function answers()
		local out = {}
		for _ = 1, 2 do
			out[#out + 1] = names(Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE))
			out[#out + 1] = names(Fu.GetNearbyHeroes(bot, 1200, true))
			out[#out + 1] = names(Fu.GetNearbyHeroes(enemy, 900, true, BOT_MODE_NONE))
			out[#out + 1] = names(bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE))
			out[#out + 1] = names(bot:GetNearbyHeroes(2500, true, BOT_MODE_ATTACK))
			out[#out + 1] = tostring(Fu.IsModeTurbo()) .. "/" .. tostring(Utils.IsModeTurbo())
		end
		return table.concat(out, " | ")
	end
	local expected = nil
	for _, name in ipairs(ARMS) do
		PerfAb.Pin(name)
		nextFrame()
		think()
		local got = answers()
		expected = expected or got
		T.eq(got, expected, "arm " .. name)
	end
	T.ok(string.find(expected, "true/true", 1, true), "the scenario has a Turbo courier: " .. expected)
	T.ok(string.find(expected, "npc_dota_hero_", 1, true), "and heroes in the lists: " .. expected)
end)

T.test("[SHy-AB]: a frame's script time is the sum of its timed calls, in the arm that ran it", function()
	local _, _, _, Perf, PerfAb, clock = setup()
	local think = Perf.Wrap("test.Think", function(seconds)
		clock.now = clock.now + seconds
	end)
	PerfAb.Pin("lists")
	nextFrame()
	think(0.0015)
	think(0.0015)
	nextFrame()
	think(0.0025)
	nextFrame()
	think(0.0005)
	-- A frame is added to the totals when the next one begins.
	local byName = PerfAb.Totals()
	T.eq(byName.lists.frames, 2, "two frames ended")
	nextFrame()
	think(0)
	local lists = byName.lists
	T.eq(lists.frames, 3, "three frames ended")
	T.near(lists.ms, 6.0, 1e-9, "3.0 + 2.5 + 0.5 ms")
	T.eq(lists.over[1], 2, "two frames of 2 ms and more")
	T.eq(lists.over[2], 0, "none of 4 ms")
	T.near(lists.max, 3.0, 1e-9, "the longest frame")
	T.eq(lists.calls, 5, "five timed calls")
	T.eq(lists.slow, 1, "one call of 2 ms and more")
	T.eq(byName.off.frames, 0, "no other arm ran")
	local _, blocks = PerfAb.Totals()
	T.eq(blocks, 0, "a pinned arm is compared with nothing")
end)

T.test("[SHy-AB]: each arm is compared with the `off` frame of its own six", function()
	local _, _, _, Perf, PerfAb, clock = setup()
	local cost = { off = 0.0020, off2 = 0.0020, turbo = 0.0019, lists = 0.0025, filter = 0.0010, all = 0.0005 }
	local think = Perf.Wrap("test.Think", function()
		clock.now = clock.now + cost[PerfAb.Arm()]
	end)
	for _ = 1, 4 * #ARMS do
		nextFrame()
		think()
	end
	-- The 25th frame ends the fourth six; five minutes on, it also prints the lines.
	Stub.time = Stub.time + 301
	think()
	local byName, blocks = PerfAb.Totals()
	T.eq(blocks, 4, "four sixes")
	for _, name in ipairs(ARMS) do
		T.eq(byName[name].frames, 4, name .. ": one frame per six")
		T.near(byName[name].ms, 4 * cost[name] * 1000, 1e-9, name .. ": its script time")
	end
	T.near(byName.all.dSum, 4 * -1.5, 1e-9, "all: 1.5 ms under off in every six")
	T.near(byName.all.dSq, 4 * 1.5 * 1.5, 1e-9, "all: the squares")
	T.eq(byName.all.faster, 4, "all: the cheaper frame in every six")
	T.eq(byName.all.slower, 0, "all: never the dearer one")
	T.eq(byName.turbo.faster, 4, "turbo: cheaper by a little, every time")
	T.near(byName.lists.dSum, 4 * 0.5, 1e-9, "lists: 0.5 ms over off")
	T.eq(byName.lists.faster, 0, "lists: never the cheaper frame")
	T.eq(byName.lists.slower, 4, "lists: the dearer one in every six")
	T.near(byName.off2.dSum, 0, 1e-9, "off2: no difference")
	T.eq(byName.off2.faster, 0, "off2: an equal frame is not a faster one")
	T.eq(byName.off2.slower, 0, "off2: nor a slower one")
	local lines = printedWith("[SHy-AB]")
	T.eq(#lines, #ARMS, "one line per arm")
	for i, name in ipairs(ARMS) do
		T.ok(string.find(lines[i], " lich arm=" .. name .. " frames=4 ", 1, true), lines[i])
		T.ok(string.find(lines[i], " blocks=4 ", 1, true), lines[i])
		T.ok(string.find(lines[i], " on=true jit=", 1, true), lines[i])
	end
	T.ok(
		string.find(
			lines[1],
			" arm=off frames=4 ms/frame=2.0000 d=+0.0000 se=0.0000 z=+0.0 pct=+0.0 faster=0 slower=0 sign=+0.0 ",
			1,
			true
		),
		lines[1]
	)
	T.ok(string.find(lines[6], " arm=all frames=4 ms/frame=0.5000 d=-1.5000 ", 1, true), lines[6])
	T.ok(
		string.find(
			lines[6],
			" pct=-75.0 faster=4 slower=0 sign=-2.0 blocks=4 over2=0 over4=0 over8=0 over16=0 max=0.5 ",
			1,
			true
		),
		lines[6]
	)
	T.ok(string.find(lines[4], " arm=lists frames=4 ms/frame=2.5000 d=+0.5000 ", 1, true), lines[4])
	T.ok(string.find(lines[4], " pct=+25.0 faster=0 slower=4 sign=+2.0 blocks=4 over2=4 over4=0 ", 1, true), lines[4])
end)

T.test("[SHy-AB]: the line", function()
	local _, _, _, _, PerfAb = setup()
	local arm = {
		frames = 12000,
		ms = 27252,
		over = { 5210, 1180, 80, 2 },
		max = 28.44,
		calls = 1740000,
		slow = 250,
		allocKb = 4814400,
		gc = 4100,
		dSum = -494.4,
		dSq = 7900,
		faster = 6300,
		slower = 5650,
	}
	-- d = -494.4 / 12000; se = sqrt((7900 - 12000 * d * d) / 11999 / 12000) = 0.0074; z = d / se; pct = d / 2.3122;
	-- sign = (5650 - 6300) / sqrt(11950).
	T.eq(
		PerfAb.Format(1500, "lich", "lists", arm, 2.3122, 12000, true, "on", 0.0002),
		"[SHy-AB] t=1500 lich arm=lists frames=12000 ms/frame=2.2710 d=-0.0412 se=0.0074 z=-5.6 pct=-1.8 faster=6300"
			.. " slower=5650 sign=-5.9 blocks=12000 over2=5210 over4=1180 over8=80 over16=2 max=28.4 calls=1740000"
			.. " slow=250 kb/frame=401.2 gc=4100 on=true jit=on tick=0.0002",
		"an arm with a difference"
	)
	local empty = { frames = 0, ms = 0, over = { 0, 0, 0, 0 }, max = 0, calls = 0, slow = 0, allocKb = 0, gc = 0 }
	empty.dSum, empty.dSq, empty.faster, empty.slower = 0, 0, 0, 0
	T.eq(
		PerfAb.Format(-60, "lich", "off", empty, 0, 0, false, "na", 0),
		"[SHy-AB] t=-60 lich arm=off frames=0 ms/frame=0.0000 d=+0.0000 se=0.0000 z=+0.0 pct=+0.0 faster=0 slower=0"
			.. " sign=+0.0 blocks=0 over2=0 over4=0 over8=0 over16=0 max=0.0 calls=0 slow=0 kb/frame=0.0 gc=0 on=false"
			.. " jit=na tick=0.0000",
		"nothing timed yet"
	)
end)

T.test("[SHy-AB]: once the reuse switched itself off, every arm runs as off and the lines say so", function()
	local _, _, FrameCache, Perf, PerfAb = setup()
	local think = Perf.Wrap("test.Think", function() end)
	FrameCache.SetEnabled(false)
	for _ = 1, 2 * #ARMS do
		nextFrame()
		think()
		T.eq(FrameCache.lists, false, PerfAb.Arm() .. ": lists")
		T.eq(FrameCache.filter, false, PerfAb.Arm() .. ": filter")
		T.eq(FrameCache.turbo, false, PerfAb.Arm() .. ": turbo")
	end
	Stub.time = Stub.time + 301
	think()
	local lines = printedWith("[SHy-AB]")
	T.eq(#lines, #ARMS, "the lines still print")
	for _, line in ipairs(lines) do
		T.ok(string.find(line, " on=false ", 1, true), line)
	end
	-- So does the frame cache's own line, with the frames the timer told it.
	local counts = printedWith("[SHy-FRAMECACHE]")
	T.eq(#counts, 1, "one counts line")
	T.ok(string.find(counts[1], " counts window=301s frames=13 ", 1, true), counts[1])
	T.ok(string.find(counts[1], " on=false", 1, true), counts[1])
end)

T.test("[SHy-AB] off: no arms, no lines, every piece on", function()
	local _, _, FrameCache, Perf, PerfAb = setup()
	local think = Perf.Wrap("test.Think", function() end)
	PerfAb.Pin("off")
	nextFrame()
	think()
	T.eq(FrameCache.lists, false, "pinned to off first")
	PerfAb.SetActive(false)
	T.eq(FrameCache.lists, true, "lists on")
	T.eq(FrameCache.filter, true, "filter on")
	T.eq(FrameCache.turbo, true, "turbo on")
	for _ = 1, 8 do
		nextFrame()
		think()
		T.eq(PerfAb.Arm(), nil, "no arm")
		T.eq(FrameCache.lists, true, "lists stays on")
	end
	Stub.time = Stub.time + 301
	think()
	T.eq(#printedWith("[SHy-AB]"), 0, "no line")
end)

T.test("[SHy-AB]: an error in the measurement ends it, not the think", function()
	local _, _, FrameCache, Perf, PerfAb = setup()
	local think = Perf.Wrap("test.Think", function(a, b)
		return a + b, "done"
	end)
	nextFrame()
	T.eq(think(2, 3), 5, "the first frame runs")
	FrameCache.BeginFrame = function()
		error("boom")
	end
	nextFrame()
	local sum, word = think(2, 3)
	T.eq(sum, 5, "the think still answers")
	T.eq(word, "done", "with every value")
	local lines = printedWith("[SHy-ERROR]")
	T.eq(#lines, 1, "one line")
	T.ok(string.find(lines[1], " lich perf_ab stopped: ", 1, true), lines[1])
	T.ok(string.find(lines[1], "boom", 1, true), lines[1])
	T.eq(PerfAb.Arm(), nil, "no arm any more")
	T.eq(FrameCache.lists, false, "the code from before: lists")
	T.eq(FrameCache.filter, false, "filter")
	T.eq(FrameCache.turbo, false, "turbo")
	for _ = 1, 8 do
		nextFrame()
		T.eq(think(1, 1), 2, "later frames run")
	end
	T.eq(#printedWith("[SHy-ERROR]"), 1, "and stay quiet")
	T.eq(FrameCache.lists, false, "nothing is switched back on")
end)
