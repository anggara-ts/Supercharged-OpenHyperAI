-- bots/dev/perf_ab.lua ([SHy-AB], #268): the harness that times a change against the old code on neighbouring
-- frames of one game. Nothing on main defines an experiment, so these cases define made-up ones. A frame is one
-- GameTime() value.
local T = ...
local Stub = T.stub
local FRAME = 1 / 30
local MODULE = "/dev/perf_ab"
local ARMS = { "off", "off2", "probe.a", "probe.b", "probe.both" }
-- Switches a and b of each arm.
local SWITCHES = {
	off = { false, false },
	off2 = { false, false },
	["probe.a"] = { true, false },
	["probe.b"] = { false, true },
	["probe.both"] = { true, true },
}
local PROBE = {
	name = "probe",
	variants = {
		{ name = "a", on = { "a" } },
		{ name = "b", on = { "b" } },
		{ name = "both", on = { "a", "b" } },
	},
}

-- `clock.now` is what RealTime() answers, so a timed call costs what the case adds to it; GameTime() only moves with
-- Stub.time.
local function setup()
	Stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local clock = { now = 0 }
	RealTime = function()
		return clock.now
	end
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	return Perf, clock
end

-- The same with the made-up experiment defined.
local function setupProbe()
	local Perf, clock = setup()
	local PerfAb = require(GetScriptDirectory() .. MODULE)
	local switch = PerfAb.Define(PROBE)
	return Perf, PerfAb, switch, clock
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

-- Counts GameTime() calls, passing them on.
local function countGameTime()
	local stubTime = GameTime
	local count = { n = 0 }
	GameTime = function()
		count.n = count.n + 1
		return stubTime()
	end
	return count
end

T.test("[SHy-AB] dormant: with no experiment the harness is not loaded and a timed call asks nothing more", function()
	local Perf = setup()
	local think = Perf.Wrap("test.Think", function() end)
	local count = countGameTime()
	-- The first timed call of a bot opens its window; the ones after it are alike.
	nextFrame()
	think()
	count.n = 0
	nextFrame()
	think()
	local dormant = count.n
	T.eq(package.loaded[GetScriptDirectory() .. MODULE], nil, "perf_ab is not loaded by the timer")
	-- Loaded but with nothing defined, it still does not watch.
	local PerfAb = require(GetScriptDirectory() .. MODULE)
	count.n = 0
	nextFrame()
	think()
	T.eq(count.n, dormant, "loaded, nothing defined: the same calls")
	T.eq(PerfAb.Arm(), nil, "and no arm")
	-- Watching costs one GameTime() per timed call, ahead of its clock.
	PerfAb.Define(PROBE)
	count.n = 0
	nextFrame()
	think()
	T.eq(count.n, dormant + 1, "an experiment: one GameTime() more per timed call")
	-- Stopped, the timer is left alone again.
	PerfAb.Stop("test")
	count.n = 0
	nextFrame()
	think()
	T.eq(count.n, dormant, "stopped: as dormant")
	T.eq(#printedWith("[SHy-AB]"), 2 + #ARMS, "one defined line, the last lines of every arm, one stopped line")
end)

T.test("[SHy-AB] dormant: no bot script asks for the harness", function()
	-- Fails in a PR that measures something, on purpose: its experiment comes out before it merges (AGENTS.md). While
	-- such a PR is in testing, list its file here with the issue number.
	local MEASURING = {}
	for _, path in ipairs(T.files("^bots/.*%.lua$")) do
		if path ~= "bots" .. MODULE .. ".lua" and not MEASURING[path] then
			-- The end of a require path: the closing quote keeps comments that name the file out.
			local found = string.find(T.read(path), 'dev/perf_ab"', 1, true)
			T.eq(found, nil, path .. " requires perf_ab.lua")
		end
	end
end)

T.test("[SHy-AB] Define: switches start off, the arms are listed, a second ask gives the same table", function()
	local _, PerfAb, switch = setupProbe()
	T.eq(switch.a, false, "a starts off")
	T.eq(switch.b, false, "b starts off")
	T.eq(table.concat(PerfAb.Arms(), ","), table.concat(ARMS, ","), "off and off2 first, then the variants")
	T.eq(PerfAb.Arm(), nil, "no arm before the first timed call")
	-- A mode file runs once per bot: five definitions, one experiment.
	for _ = 1, 4 do
		T.eq(PerfAb.Define(PROBE), switch, "the same switches")
	end
	T.eq(#PerfAb.Arms(), #ARMS, "no arm added")
	local lines = printedWith("[SHy-AB]")
	T.eq(#lines, 1, "one defined line")
	T.ok(string.find(lines[1], " lich defined exp=probe variants=3 arms=5", 1, true), lines[1])
end)

T.test("[SHy-AB]: a block runs every arm once, in an order shuffled for every block", function()
	local Perf, PerfAb = setupProbe()
	local think = Perf.Wrap("test.Think", function() end)
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
	T.ok(distinctOrders >= 25, "40 blocks, " .. distinctOrders .. " different orders")
	T.eq(distinctFirst, #ARMS, "every arm opens a block now and then")
end)

T.test("[SHy-AB]: an arm's switches are on in its frames only", function()
	local Perf, PerfAb, switch = setupProbe()
	local think = Perf.Wrap("test.Think", function() end)
	for _, name in ipairs(ARMS) do
		T.eq(PerfAb.Pin(name), true, "pin " .. name)
		nextFrame()
		think()
		T.eq(PerfAb.Arm(), name, "the frame's arm")
		T.eq(switch.a, SWITCHES[name][1], name .. ": a")
		T.eq(switch.b, SWITCHES[name][2], name .. ": b")
	end
	T.eq(PerfAb.Pin("probe.nope"), false, "an unknown arm pins nothing")
	T.eq(PerfAb.Pin(nil), true, "back to the shuffled blocks")
	for _ = 1, 3 * #ARMS do
		nextFrame()
		think()
		local expected = SWITCHES[PerfAb.Arm()]
		T.eq(switch.a, expected[1], "a follows the arm")
		T.eq(switch.b, expected[2], "b follows the arm")
	end
end)

T.test("[SHy-AB]: a frame's script time is the sum of its timed calls, in the arm that ran it", function()
	local Perf, PerfAb, _, clock = setupProbe()
	local think = Perf.Wrap("test.Think", function(seconds)
		clock.now = clock.now + seconds
	end)
	PerfAb.Pin("probe.a")
	nextFrame()
	think(0.0015)
	think(0.0015)
	nextFrame()
	think(0.0025)
	nextFrame()
	think(0.0005)
	-- A frame is added to the totals when the next one begins.
	local byName = PerfAb.Totals()
	T.eq(byName["probe.a"].frames, 2, "two frames ended")
	nextFrame()
	think(0)
	local arm = byName["probe.a"]
	T.eq(arm.frames, 3, "three frames ended")
	T.near(arm.ms, 6.0, 1e-9, "3.0 + 2.5 + 0.5 ms")
	T.eq(arm.over[1], 2, "two frames of 2 ms and more")
	T.eq(arm.over[2], 0, "none of 4 ms")
	T.near(arm.max, 3.0, 1e-9, "the longest frame")
	T.eq(arm.calls, 5, "five timed calls")
	T.eq(arm.slow, 1, "one call of 2 ms and more")
	T.eq(byName.off.frames, 0, "no other arm ran")
	local _, blocks = PerfAb.Totals()
	T.eq(blocks, 0, "a pinned arm is compared with nothing")
end)

T.test("[SHy-AB]: each arm is compared with the `off` frame of its own block", function()
	local Perf, PerfAb, _, clock = setupProbe()
	local cost = { off = 0.0020, off2 = 0.0020, ["probe.a"] = 0.0019, ["probe.b"] = 0.0025, ["probe.both"] = 0.0005 }
	local think = Perf.Wrap("test.Think", function()
		clock.now = clock.now + cost[PerfAb.Arm()]
	end)
	for _ = 1, 4 * #ARMS do
		nextFrame()
		think()
	end
	-- The next frame ends the fourth block; five minutes on, it also prints the lines.
	Stub.time = Stub.time + 301
	think()
	local byName, blocks = PerfAb.Totals()
	T.eq(blocks, 4, "four blocks")
	for _, name in ipairs(ARMS) do
		T.eq(byName[name].frames, 4, name .. ": one frame per block")
		T.near(byName[name].ms, 4 * cost[name] * 1000, 1e-9, name .. ": its script time")
	end
	local both, a, b = byName["probe.both"], byName["probe.a"], byName["probe.b"]
	T.near(both.dSum, 4 * -1.5, 1e-9, "both: 1.5 ms under off in every block")
	T.near(both.dSq, 4 * 1.5 * 1.5, 1e-9, "both: the squares")
	T.eq(both.faster, 4, "both: the cheaper frame in every block")
	T.eq(both.slower, 0, "both: never the dearer one")
	T.eq(a.faster, 4, "a: cheaper by a little, every time")
	T.near(b.dSum, 4 * 0.5, 1e-9, "b: 0.5 ms over off")
	T.eq(b.faster, 0, "b: never the cheaper frame")
	T.eq(b.slower, 4, "b: the dearer one in every block")
	T.near(byName.off2.dSum, 0, 1e-9, "off2: no difference")
	T.eq(byName.off2.faster, 0, "off2: an equal frame is not a faster one")
	T.eq(byName.off2.slower, 0, "off2: nor a slower one")
	local lines = printedWith(" arm=")
	T.eq(#lines, #ARMS, "one line per arm")
	for i, name in ipairs(ARMS) do
		T.ok(string.find(lines[i], "[SHy-AB] t=", 1, true), lines[i])
		T.ok(string.find(lines[i], " lich arm=" .. name .. " frames=4 ", 1, true), lines[i])
		T.ok(string.find(lines[i], " blocks=4 ", 1, true), lines[i])
		T.ok(string.find(lines[i], " jit=", 1, true), lines[i])
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
	T.ok(string.find(lines[5], " arm=probe.both frames=4 ms/frame=0.5000 d=-1.5000 ", 1, true), lines[5])
	T.ok(
		string.find(
			lines[5],
			" pct=-75.0 faster=4 slower=0 sign=-2.0 blocks=4 over2=0 over4=0 over8=0 over16=0 max=0.5 ",
			1,
			true
		),
		lines[5]
	)
	T.ok(string.find(lines[4], " arm=probe.b frames=4 ms/frame=2.5000 d=+0.5000 ", 1, true), lines[4])
	T.ok(string.find(lines[4], " pct=+25.0 faster=0 slower=4 sign=+2.0 blocks=4 over2=4 over4=0 ", 1, true), lines[4])
end)

T.test("[SHy-AB]: the line", function()
	setup()
	local PerfAb = require(GetScriptDirectory() .. MODULE)
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
		PerfAb.Format(1500, "lich", "lotus.scan", arm, 2.3122, 12000, "on", 0.0002),
		"[SHy-AB] t=1500 lich arm=lotus.scan frames=12000 ms/frame=2.2710 d=-0.0412 se=0.0074 z=-5.6 pct=-1.8"
			.. " faster=6300 slower=5650 sign=-5.9 blocks=12000 over2=5210 over4=1180 over8=80 over16=2 max=28.4"
			.. " calls=1740000 slow=250 kb/frame=401.2 gc=4100 jit=on tick=0.0002",
		"an arm with a difference"
	)
	local empty = { frames = 0, ms = 0, over = { 0, 0, 0, 0 }, max = 0, calls = 0, slow = 0, allocKb = 0, gc = 0 }
	empty.dSum, empty.dSq, empty.faster, empty.slower = 0, 0, 0, 0
	T.eq(
		PerfAb.Format(-60, "lich", "off", empty, 0, 0, "na", 0),
		"[SHy-AB] t=-60 lich arm=off frames=0 ms/frame=0.0000 d=+0.0000 se=0.0000 z=+0.0 pct=+0.0 faster=0 slower=0"
			.. " sign=+0.0 blocks=0 over2=0 over4=0 over8=0 over16=0 max=0.0 calls=0 slow=0 kb/frame=0.0 gc=0 jit=na"
			.. " tick=0.0000",
		"nothing timed yet"
	)
end)

T.test("[SHy-AB] Define: a definition it cannot use is refused with one line, and the old code runs", function()
	local Perf = setup()
	local PerfAb = require(GetScriptDirectory() .. MODULE)
	local think = Perf.Wrap("test.Think", function() end)
	local tooMany = { name = "wide", variants = {} }
	for i = 1, 11 do
		tooMany.variants[i] = { name = "v" .. i, on = { "s" .. i } }
	end
	local bad = {
		{ nil, "needs a name" },
		{ "probe", "needs a name" },
		{ { name = "has space", variants = PROBE.variants }, "needs a name" },
		{ { name = "none" }, "none: no variants" },
		{ { name = "empty", variants = {} }, "empty: no variants" },
		{ { name = "anon", variants = { { on = { "a" } } } }, "anon: variant 1 needs a name" },
		{
			{ name = "twice", variants = { { name = "a", on = { "a" } }, { name = "a", on = { "b" } } } },
			"two variants",
		},
		{ { name = "bare", variants = { { name = "a" } } }, "bare.a: no switch to turn on" },
		{ { name = "bare2", variants = { { name = "a", on = {} } } }, "bare2.a: no switch to turn on" },
		{ { name = "num", variants = { { name = "a", on = { 1 } } } }, "num.a: a switch name must be a string" },
		{ tooMany, "wide: more than 12 arms in one block" },
	}
	for i, case in ipairs(bad) do
		Stub.printed = {}
		local switch = PerfAb.Define(case[1])
		T.eq(type(switch), "table", "case " .. i .. ": a table comes back")
		T.eq(next(switch), nil, "case " .. i .. ": with no switch in it")
		local lines = printedWith("[SHy-ERROR]")
		T.eq(#lines, 1, "case " .. i .. ": one line")
		T.ok(string.find(lines[1], " lich perf_ab define refused: ", 1, true), lines[1])
		T.ok(string.find(lines[1], case[2], 1, true), lines[1])
		-- A mode file asks once per bot: a name that was refused stays refused, without another line.
		if type(case[1]) == "table" then
			T.eq(PerfAb.Define(case[1]), switch, "case " .. i .. ": the same table again")
			T.eq(#printedWith("[SHy-ERROR]"), 1, "case " .. i .. ": and no second line")
		end
	end
	T.eq(#PerfAb.Arms(), 2, "no arm added")
	nextFrame()
	think()
	T.eq(PerfAb.Arm(), nil, "and nothing is timed")
	-- Ten variants are the most: twelve arms with off and off2.
	table.remove(tooMany.variants)
	tooMany.name = "fits"
	T.eq(PerfAb.Define(tooMany).s10, false, "ten variants fit")
	T.eq(#PerfAb.Arms(), 12, "twelve arms")
end)

T.test("[SHy-AB]: a second experiment adds its arms, and the totals start again", function()
	local Perf, PerfAb, switch, clock = setupProbe()
	local think = Perf.Wrap("test.Think", function()
		clock.now = clock.now + 0.001
	end)
	for _ = 1, 2 * #ARMS + 1 do
		nextFrame()
		think()
	end
	local _, blocks = PerfAb.Totals()
	T.eq(blocks, 2, "two blocks of the first experiment")
	local other = PerfAb.Define({ name = "other", variants = { { name = "x", on = { "x" } } } })
	local byName
	byName, blocks = PerfAb.Totals()
	T.eq(blocks, 0, "the blocks start again")
	T.eq(byName.off.frames, 0, "and so do the frames")
	T.eq(#PerfAb.Arms(), #ARMS + 1, "one arm more")
	-- The frame that was running when it came is not timed.
	think()
	T.eq(PerfAb.Arm(), nil, "the running frame has no arm")
	local seen = {}
	for _ = 1, 3 * (#ARMS + 1) do
		nextFrame()
		think()
		local arm = PerfAb.Arm()
		seen[arm] = (seen[arm] or 0) + 1
		T.eq(other.x, arm == "other.x", arm .. ": the second experiment's switch")
		T.eq(switch.a, SWITCHES[arm] ~= nil and SWITCHES[arm][1], arm .. ": the first experiment's a")
		T.eq(switch.b, SWITCHES[arm] ~= nil and SWITCHES[arm][2], arm .. ": the first experiment's b")
	end
	for _, name in ipairs(PerfAb.Arms()) do
		T.eq(seen[name], 3, name .. ": once per block of six")
	end
end)

T.test("[SHy-AB] Stop: the last lines print, every switch goes off and nothing is defined any more", function()
	local Perf, PerfAb, switch = setupProbe()
	local think = Perf.Wrap("test.Think", function() end)
	PerfAb.Pin("probe.both")
	nextFrame()
	think()
	T.eq(switch.a, true, "a is on")
	Stub.printed = {}
	PerfAb.Stop("selfcheck")
	PerfAb.Stop("again")
	T.eq(switch.a, false, "a is off")
	T.eq(switch.b, false, "b is off")
	T.eq(#printedWith(" arm="), #ARMS, "the lines, once")
	local stops = printedWith(" stopped why=")
	T.eq(#stops, 1, "one stopped line")
	T.ok(string.find(stops[1], "[SHy-AB] t=", 1, true), stops[1])
	T.ok(string.find(stops[1], " lich stopped why=selfcheck", 1, true), stops[1])
	for _ = 1, 2 * #ARMS do
		nextFrame()
		think()
		T.eq(PerfAb.Arm(), nil, "no arm")
		T.eq(switch.a, false, "a stays off")
	end
	local late = PerfAb.Define({ name = "late", variants = { { name = "x", on = { "x" } } } })
	T.eq(next(late), nil, "a later experiment gets no switch")
	T.eq(PerfAb.Define({ name = "late", variants = { { name = "x", on = { "x" } } } }), late, "asked again: the same")
	T.eq(#printedWith("the measurement has ended"), 1, "and one line says why")
end)

T.test("[SHy-AB]: an error in the measurement ends it, not the think", function()
	local Perf, PerfAb, switch = setupProbe()
	local think = Perf.Wrap("test.Think", function(a, b)
		return a + b, "done"
	end)
	PerfAb.Pin("off")
	nextFrame()
	T.eq(think(2, 3), 5, "the first frame runs")
	-- The next arm cannot turn its switch on.
	rawset(switch, "a", nil)
	setmetatable(switch, {
		__newindex = function()
			error("boom")
		end,
	})
	PerfAb.Pin("probe.a")
	nextFrame()
	local sum, word = think(2, 3)
	T.eq(sum, 5, "the think still answers")
	T.eq(word, "done", "with every value")
	local lines = printedWith("[SHy-ERROR]")
	T.eq(#lines, 1, "one line")
	T.ok(string.find(lines[1], " lich perf_ab stopped: ", 1, true), lines[1])
	T.ok(string.find(lines[1], "boom", 1, true), lines[1])
	T.eq(PerfAb.Arm(), nil, "no arm any more")
	T.ok(not switch.a, "the code from before: a")
	T.eq(switch.b, false, "b")
	for _ = 1, 8 do
		nextFrame()
		T.eq(think(1, 1), 2, "later frames run")
	end
	T.eq(#printedWith("[SHy-ERROR]"), 1, "and stay quiet")
	T.eq(switch.b, false, "nothing is switched back on")
end)
