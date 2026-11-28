-- The ward mode's goal line (#15): bots/lib/systems/ward_goal.lua.
local T = ...

local function Load()
	T.stub.reset({ hero = "npc_dota_hero_dark_willow" })
	return require(GetScriptDirectory() .. "/lib/systems/ward_goal")
end

-- One think every 1/30s from `from` to `to` at spot `key`; returns the lines due (each { at, changed }).
local function Run(Goal, state, key, from, to, lines)
	lines = lines or {}
	local now = from
	while now <= to + 1e-9 do
		local due, changed = Goal.Step(state, key, now)
		if due then
			lines[#lines + 1] = { at = now, changed = changed }
		end
		now = now + 1 / 30
	end
	return lines
end

T.test("ward goal: a point is rounded into its key", function()
	local Goal = Load()
	T.eq(Goal.Key(3796.4, -622.6), "3796,-623", "rounded")
	T.eq(Goal.Key(3796, -622), Goal.Key(3796.2, -621.8), "same spot, same key")
end)

T.test("ward goal: one line for a pick that holds, none per think", function()
	local Goal = Load()
	local lines = Run(Goal, {}, "a", 100, 110)
	T.eq(#lines, 1, "one line")
	T.near(lines[1].at, 100, 1e-6, "on the pick")
	T.eq(lines[1].changed, 0, "no change")
end)

T.test("ward goal: a change prints with changed=1", function()
	local Goal = Load()
	local state = {}
	local lines = Run(Goal, state, "a", 100, 105)
	Run(Goal, state, "b", 105 + 1 / 30, 108, lines)
	T.eq(#lines, 2, "pick and change")
	T.eq(lines[2].changed, 1, "one change")
end)

T.test("ward goal: A -> B -> A inside the throttle still prints, with changed=2", function()
	local Goal = Load()
	local state = {}
	local lines = Run(Goal, state, "a", 100, 100.5)
	Run(Goal, state, "b", 100.5 + 1 / 30, 101, lines)
	Run(Goal, state, "a", 101 + 1 / 30, 105, lines)
	T.eq(#lines, 2, "the pick, then one deferred line")
	T.ok(lines[2].at >= 102 - 1e-6, "not before the 2s throttle")
	T.eq(lines[2].changed, 2, "both changes counted")
end)

T.test("ward goal: a target flipping every think prints at most every 2s", function()
	local Goal = Load()
	local state, lines = {}, {}
	local now = 100
	for i = 1, 300 do
		local due, changed = Goal.Step(state, i % 2 == 0 and "a" or "b", now)
		if due then
			lines[#lines + 1] = { at = now, changed = changed }
		end
		now = now + 1 / 30
	end
	T.eq(#lines, 5, "10s of thinks, one line per 2s")
	T.ok(lines[#lines].changed >= 3, "the flips show in changed=")
end)

T.test("ward goal: changes older than 10s drop out", function()
	local Goal = Load()
	local state = {}
	Run(Goal, state, "a", 100, 101)
	Run(Goal, state, "b", 101 + 1 / 30, 112)
	local _, changed = Goal.Step(state, "b", 112)
	T.eq(changed, 0, "the change at 101 is gone")
end)

T.test("ward goal: back in ward mode after a gap is a new pick, not a change", function()
	local Goal = Load()
	local state = {}
	local lines = Run(Goal, state, "a", 100, 101)
	Run(Goal, state, "b", 130, 131, lines)
	T.eq(#lines, 2, "a line for the new trip")
	T.eq(lines[2].changed, 0, "not counted as a change")
	local again = Run(Goal, state, "b", 140, 141)
	T.eq(#again, 1, "a trip to the same spot after a gap prints too")
end)
