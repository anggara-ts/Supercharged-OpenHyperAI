-- tests/decision_trace.lua (#268): the offline check that a change leaves every decision of the scripts the same.
-- One hero and a few frames here, so that the tool keeps working; a measurement runs it for every hero.
local T = ...
local Trace = assert(loadfile("tests/decision_trace.lua"))()
local MODULE = "/lib/systems/perf_ab"

local function count(lines, prefix)
	local n = 0
	for _, line in ipairs(lines) do
		if string.sub(line, 1, #prefix) == prefix then
			n = n + 1
		end
	end
	return n
end

local function total(calls)
	local n = 0
	for _, value in pairs(calls) do
		n = n + value
	end
	return n
end

-- A made-up experiment, defined for every hero once its scripts are loaded. With `harmful`, its switch empties the
-- shared helper's nearby-hero lists: a change of what the scripts are told.
local function probe(harmful)
	return function(Fu)
		local PerfAb = require(GetScriptDirectory() .. MODULE)
		local switch = PerfAb.Define({ name = "probe", variants = { { name = "x", on = { "x" } } } })
		local helper = Fu.GetNearbyHeroes
		Fu.GetNearbyHeroes = function(...)
			if harmful and switch.x then
				return {}
			end
			return helper(...)
		end
	end
end

local function run(arm, before)
	return Trace.run(T.stub, { scenario = "attack", frames = 3, heroes = { "hero_lich" }, arm = arm, before = before })
end

T.test("decision trace: the same build gives the same trace, with desires, lists and engine calls in it", function()
	local first = run(nil, nil)
	local second = run(nil, nil)
	T.eq(#first.problems, 0, "every script loads: " .. tostring(first.problems[1]))
	T.eq(first.botFrames, 3, "one hero, one scenario, three frames")
	T.eq(count(first.lines, "== attack lich frame "), 3, "a heading per frame")
	T.ok(count(first.lines, "desire mode_") >= 3 * 10, "every mode's desire in every frame")
	T.ok(count(first.lines, "nearby") >= 3, "nearby-hero lists")
	T.eq(count(first.lines, "think ERROR"), 0, "the item and ability think runs")
	T.ok((first.calls["unit.GetNearbyHeroes"] or 0) >= 3, "engine calls are counted by function")
	T.eq(table.concat(first.lines, "\n"), table.concat(second.lines, "\n"), "the second run says the same")
	local out, same = Trace.compare(first.lines, second.lines, first.calls, second.calls, 3, 3)
	T.eq(same, true, "compare: the same")
	T.eq(out[1], string.format("decisions: the same (%d lines)", #first.lines), "its first line")
	T.eq(out[#out], "  every function is called exactly as often", "its last line")
end)

T.test("decision trace: a variant that changes nothing compares as the same, in every arm", function()
	local off = run("off", probe(false))
	local variant = run("probe.x", probe(false))
	local shuffled = run(nil, probe(false))
	T.ok(#off.lines > 30, "a trace")
	T.eq(table.concat(variant.lines, "\n"), table.concat(off.lines, "\n"), "probe.x against off")
	T.eq(table.concat(shuffled.lines, "\n"), table.concat(off.lines, "\n"), "the shuffled blocks against off")
	-- The harness itself asks GameTime() once per timed call, whatever the arm.
	T.eq(total(variant.calls), total(off.calls), "and the same engine calls")
end)

T.test("decision trace: a variant that changes what a script is told is found", function()
	local off = run("off", probe(true))
	local variant = run("probe.x", probe(true))
	local out, same =
		Trace.compare(off.lines, variant.lines, off.calls, variant.calls, off.botFrames, variant.botFrames)
	T.eq(same, false, "compare: different")
	T.ok(string.find(out[1], "decisions: DIFFERENT", 1, true), out[1])
	T.ok(string.find(out[2], "first difference at line ", 1, true), out[2])
	T.ok(string.find(out[3], "    A: ", 1, true), out[3])
	T.ok(string.find(out[4], "    B: ", 1, true), out[4])
	T.ok(total(variant.calls) < total(off.calls), "and the engine calls it saved are counted")
	local found = false
	for i = 5, #out do
		found = found or string.find(out[i], "unit.", 1, true) ~= nil
	end
	T.ok(found, "with the functions that differ")
end)

T.test("decision trace: an arm the build does not have is an error that lists the arms", function()
	local ok, problem = pcall(run, "probe.nope", probe(false))
	T.eq(ok, false, "no such arm")
	T.ok(
		string.find(tostring(problem), "no arm named probe.nope (arms: off, off2, probe.x)", 1, true),
		tostring(problem)
	)
end)

T.test("decision trace: line numbers in error texts do not make two builds differ", function()
	local result = Trace.run(T.stub, {
		scenario = "retreat",
		frames = 1,
		heroes = { "hero_lich" },
		before = function(Fu)
			Fu.GetNearbyHeroes = function()
				error("bots/lib/general_utils/team_info.lua:296: made up")
			end
		end,
	})
	local text = table.concat(result.lines, "\n")
	T.ok(string.find(text, "team_info.lua:N: made up", 1, true), "the line number is written as N")
	T.eq(string.find(text, "team_info.lua:296", 1, true), nil, "and not as a number")
end)
