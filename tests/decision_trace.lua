-- What the bot scripts decide and ask in a stub scenario, written down so that two builds can be compared line by
-- line (#268; made for #251). A change that only saves work must leave every line the same.
--
-- For every hero script, in a made-up fight (the bot at the origin, 2 allies and 3 enemy heroes within 1000, one
-- more of each within 1600, the rest far away; every ability and six items castable), each frame runs every mode's
-- GetDesire and then ItemUsageThink, as the engine does, and the trace gets:
--   desire <mode> <value>          what the mode answered
--   order <action>(<arguments>)    every order a script gave (Action*, SetTarget)
--   nearby / nearby fu ...         every nearby-hero list a script was given, by unit:GetNearbyHeroes and by
--                                  Fu.GetNearbyHeroes
--   print <line>                   what it printed (not the timing lines: [SHy-PERF], [SHy-AB], ...)
-- Line numbers in error texts are written as ".lua:N" and tracebacks are left out, so a build with a line more
-- does not differ by that alone.
-- Besides the trace it counts the "engine" calls by function (the stub's unit and ability methods and API globals).
-- The counts say how many calls a change saves; they say nothing about time, which only a game can tell
-- (bots/dev/perf_ab.lua, docs/MEASURING_PERFORMANCE.md).
--
-- From the repo root, with LuaJIT (CI has it; it runs tests/test_decision_trace.lua on every push):
--   luajit tests/decision_trace.lua run <out> [--scenario attack|retreat|both] [--frames N] [--heroes <text>]
--                                             [--arm <name>]
--       writes <out>.trace.txt and <out>.calls.tsv. --arm runs every frame in that arm of the A/B harness ("off",
--       "<experiment>.<variant>"); without it a build with an experiment runs its shuffled blocks.
--   luajit tests/decision_trace.lua compare <outA> <outB>
--       says whether the two traces are the same (exit code 1 when not) and which engine calls differ.
-- Two variants of one build: run once per --arm. Two builds: run in each checkout (git worktree add ../main
-- origin/main), then compare. Keep the output out of the repo or under local/ (git-ignored).
--
-- As a library (tests): local Trace = assert(loadfile("tests/decision_trace.lua"))(); Trace.run(T.stub, opts).
local Trace = {}

local FRAME = 1 / 30
local QUIET_TAGS = { "[SHy-PERF", "[SHy-MEM", "[SHy-AB]", "[SHy-FRAMECACHE]" }
local ITEMS = {
	[0] = "item_black_king_bar",
	[1] = "item_blink",
	[2] = "item_force_staff",
	[3] = "item_magic_wand",
	[4] = "item_glimmer_cape",
	[5] = "item_cyclone",
	[15] = "item_tpscroll",
}

-- Repo files matching a Lua pattern, sorted (git ls-files, as tests/run.lua: the same on every system).
local function repoFiles(pattern)
	local found = {}
	local pipe = io.popen('git ls-files --cached --others --exclude-standard -- "bots/*.lua"')
	for line in pipe:lines() do
		local name = string.match(string.gsub(line, "\r$", ""), pattern)
		if name then
			found[#found + 1] = name
		end
	end
	pipe:close()
	table.sort(found)
	return found
end

-- The made-up fight. `botMode` is the active mode of the bot and its allies.
local function scenario(Stub, heroUnit, botMode)
	local bot = Stub.reset({ hero = heroUnit, slot = 2, time = 1500 })
	local own, other = Stub.teams[TEAM_RADIANT], Stub.teams[TEAM_DIRE]
	local ownSpots = { Vector(250, -150, 0), Vector(-400, 300, 0), Vector(1300, 200, 0), Vector(-6000, -6000, 0) }
	local spot = 0
	for i = 1, 5 do
		local unit = own[i]
		unit._level = 18
		if unit == bot then
			unit._loc = Vector(0, 0, 0)
			unit._hp = 600
		else
			spot = spot + 1
			unit._loc = ownSpots[spot]
			unit._hp = 700
		end
	end
	local otherSpots =
		{ Vector(450, 0, 0), Vector(700, 300, 0), Vector(-300, 800, 0), Vector(1500, 100, 0), Vector(6000, 6000, 0) }
	for i = 1, 5 do
		other[i]._loc = otherSpots[i]
		other[i]._level = 18
		other[i]._hp = 500
	end
	for itemSlot, name in pairs(ITEMS) do
		bot._items[itemSlot] = Stub.newAbility(name, bot, false)
	end
	local U, A = CDOTA_Bot_Script, CDOTABaseAbility_BotScript
	local enemy1 = other[1]
	local function isTalent(ability)
		return string.find(ability._name, "^special_bonus") ~= nil
	end
	local fixed = {
		IsFullyCastable = true,
		GetCastRange = 600,
		GetAOERadius = 300,
		GetManaCost = 50,
		GetAbilityDamage = 150,
		GetSpecialValueInt = 300,
		GetSpecialValueFloat = 1.5,
		GetCastPoint = 0.3,
		GetDuration = 3,
		GetCooldown = 10,
		GetCurrentCharges = 1,
	}
	for name, value in pairs(fixed) do
		A[name] = function()
			return value
		end
	end
	A.IsTrained = function(ability)
		return not isTalent(ability)
	end
	A.GetLevel = function(ability)
		return isTalent(ability) and 0 or 1
	end
	U.GetActiveMode = function(unit)
		return unit._team == bot._team and botMode or BOT_MODE_ATTACK
	end
	U.GetActiveModeDesire = function()
		return 0.6
	end
	U.GetAttackTarget = function(unit)
		return unit._team == bot._team and enemy1 or bot
	end
	U.GetTarget = U.GetAttackTarget
	U.WasRecentlyDamagedByAnyHero = function(unit)
		return unit == bot
	end
	U.GetAttackRange = function()
		return 500
	end
	U.GetAttackDamage = function()
		return 120
	end
	U.GetNetWorth = function()
		return 15000
	end
	return bot
end

-- A script file in its own environment, as the game gives each bot script its own scope.
local function loadScript(path)
	local chunk, err = loadfile(path .. ".lua")
	if chunk == nil then
		return nil, err
	end
	local env = setmetatable({}, { __index = _G })
	setfenv(chunk, env)
	local ok, problem = xpcall(chunk, debug.traceback)
	if not ok then
		return nil, problem
	end
	return env
end

-- opts: scenario ("attack", "retreat" or "both", the default), frames (per hero, default 13), heroes (plain text a
-- hero file name must contain, or a list of file names such as "hero_lich"; default every hero), arm (see the top),
-- before (a function called with Fu for every hero once its scripts are loaded: tests define an experiment there).
-- Returns { lines = the trace, calls = { [function] = count }, botFrames = heroes x scenarios x frames,
-- problems = scripts that did not load }.
function Trace.run(Stub, opts)
	opts = opts or {}
	local frames = opts.frames or 13
	local result = { lines = {}, calls = {}, botFrames = 0, problems = {} }
	local lines, calls = result.lines, result.calls
	local tracing = false

	local function show(value)
		local kind = type(value)
		if kind == "table" then
			if Stub.isVector(value) then
				return string.format("V(%.1f,%.1f)", value.x, value.y)
			end
			local name = rawget(value, "_name")
			if name ~= nil then
				local pid = rawget(value, "_pid")
				return tostring(name) .. (pid and ("#" .. tostring(pid)) or "")
			end
			return "table"
		elseif kind == "number" then
			return string.format("%.4f", value)
		end
		return tostring(value)
	end
	local function showList(list)
		if type(list) ~= "table" then
			return tostring(list)
		end
		local parts = {}
		for i = 1, #list do
			parts[i] = show(list[i])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local function trace(...)
		if tracing then
			-- A traceback says how the code is laid out, not what was decided: only the message stays.
			local text = string.gsub(table.concat({ ... }, " "), "[%s|]*stack traceback:.*$", "")
			lines[#lines + 1] = (string.gsub(text, "%.lua:%d+", ".lua:N"))
		end
	end
	local function count(name)
		if tracing then
			calls[name] = (calls[name] or 0) + 1
		end
	end

	-- Wraps the "engine": every unit and ability method and every API global the stub installed. Stub.reset puts
	-- the plain ones back, so this runs again for every hero.
	local function instrument()
		for name, fn in pairs(CDOTA_Bot_Script) do
			if type(fn) == "function" then
				local key = "unit." .. name
				if string.find(name, "^Action") or name == "SetTarget" then
					CDOTA_Bot_Script[name] = function(...)
						count(key)
						if tracing then
							local parts = {}
							for i = 1, select("#", ...) do
								parts[#parts + 1] = show((select(i, ...)))
							end
							trace("order", name .. "(" .. table.concat(parts, ", ") .. ")")
						end
						return fn(...)
					end
				else
					CDOTA_Bot_Script[name] = function(...)
						count(key)
						return fn(...)
					end
				end
			end
		end
		for name, fn in pairs(CDOTABaseAbility_BotScript) do
			if type(fn) == "function" then
				local key = "ability." .. name
				CDOTABaseAbility_BotScript[name] = function(...)
					count(key)
					return fn(...)
				end
			end
		end
		local names = {}
		for name, fn in pairs(_G) do
			if type(name) == "string" and type(fn) == "function" and string.match(name, "^[A-Z]") then
				names[#names + 1] = name
			end
		end
		for _, name in ipairs(names) do
			local fn = rawget(_G, name)
			rawset(_G, name, function(...)
				count(name)
				return fn(...)
			end)
		end
	end

	local function runHero(heroFile, scenarioName, modeFiles)
		local botMode = scenarioName == "retreat" and BOT_MODE_RETREAT or BOT_MODE_ATTACK
		scenario(Stub, "npc_dota_" .. heroFile, botMode)
		instrument()
		local label = string.gsub(heroFile, "^hero_", "")
		local usage, usageErr = loadScript("bots/ability_item_usage_generic")
		if usage == nil then
			result.problems[#result.problems + 1] = label .. ": ability_item_usage_generic: " .. tostring(usageErr)
			return
		end
		local modes = {}
		for _, modeFile in ipairs(modeFiles) do
			local env, err = loadScript("bots/" .. modeFile)
			if env == nil then
				result.problems[#result.problems + 1] = label .. ": " .. modeFile .. ": " .. tostring(err)
			elseif type(env.GetDesire) == "function" then
				modes[#modes + 1] = { name = modeFile, GetDesire = env.GetDesire }
			end
		end
		local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
		if opts.before ~= nil then
			opts.before(Fu)
		end
		-- What a script is given by the shared helper and by unit:GetNearbyHeroes (the wrapper of
		-- global_overrides.lua, in place by now).
		local insideHelper = 0
		local helper = Fu.GetNearbyHeroes
		if type(helper) == "function" then
			Fu.GetNearbyHeroes = function(unit, radius, enemy, mode)
				insideHelper = insideHelper + 1
				local ok, list = pcall(helper, unit, radius, enemy, mode)
				insideHelper = insideHelper - 1
				if not ok then
					trace("nearby fu ERROR", tostring(list))
					error(list, 0)
				end
				trace("nearby fu", show(unit), tostring(radius), tostring(enemy), tostring(mode), "->", showList(list))
				return list
			end
		end
		local direct = CDOTA_Bot_Script.GetNearbyHeroes
		CDOTA_Bot_Script.GetNearbyHeroes = function(unit, radius, enemy, mode)
			local list = direct(unit, radius, enemy, mode)
			if insideHelper == 0 then
				trace("nearby", show(unit), tostring(radius), tostring(enemy), tostring(mode), "->", showList(list))
			end
			return list
		end
		if opts.arm ~= nil then
			local PerfAb = require(GetScriptDirectory() .. "/dev/perf_ab")
			if not PerfAb.Pin(opts.arm) then
				error(
					"no arm named " .. tostring(opts.arm) .. " (arms: " .. table.concat(PerfAb.Arms(), ", ") .. ")",
					0
				)
			end
		end
		for frame = 1, frames do
			Stub.time = Stub.time + FRAME
			Stub.printed = {}
			tracing = true
			trace("== " .. scenarioName .. " " .. label .. " frame " .. frame)
			for _, mode in ipairs(modes) do
				local ok, desire = pcall(mode.GetDesire)
				trace("desire", mode.name, ok and show(desire) or ("ERROR " .. tostring(desire)))
			end
			trace("-- ItemUsageThink")
			local ok, problem = pcall(usage.ItemUsageThink)
			if not ok then
				trace("think ERROR", tostring(problem))
			end
			for _, line in ipairs(Stub.printed) do
				local quiet = false
				for _, tag in ipairs(QUIET_TAGS) do
					quiet = quiet or string.find(line, tag, 1, true) ~= nil
				end
				if not quiet then
					trace("print", line)
				end
			end
			tracing = false
			result.botFrames = result.botFrames + 1
		end
	end

	local heroFiles = type(opts.heroes) == "table" and opts.heroes or repoFiles("^bots/heroes/(hero_[%w_]+)%.lua$")
	local modeFiles = repoFiles("^bots/(mode_[%w_]+_generic)%.lua$")
	local scenarios = (opts.scenario == nil or opts.scenario == "both") and { "attack", "retreat" } or { opts.scenario }
	local ok, problem = pcall(function()
		for _, scenarioName in ipairs(scenarios) do
			for _, heroFile in ipairs(heroFiles) do
				if type(opts.heroes) ~= "string" or string.find(heroFile, opts.heroes, 1, true) then
					runHero(heroFile, scenarioName, modeFiles)
				end
			end
		end
	end)
	-- The wrapped engine and the made-up fight do not stay behind for whoever uses the stub next.
	tracing = false
	Stub.reset()
	if not ok then
		error(problem, 0)
	end
	return result
end

-- The command line ------------------------------------------------------------------------------------------------
local function readLines(path)
	local file = assert(io.open(path, "r"))
	local found = {}
	for line in file:lines() do
		found[#found + 1] = line
	end
	file:close()
	return found
end

local function readCalls(path)
	local calls, botFrames = {}, 0
	for _, line in ipairs(readLines(path)) do
		local name, value = string.match(line, "^(.-)\t(%d+)$")
		if name == "#bot-frames" then
			botFrames = tonumber(value)
		elseif name then
			calls[name] = tonumber(value)
		end
	end
	return calls, botFrames
end

-- What `compare` prints, and whether the two traces are the same. Pure: the test reads it.
function Trace.compare(linesA, linesB, callsA, callsB, botFramesA, botFramesB)
	local out = {}
	local same = #linesA == #linesB
	local firstDifference = nil
	for i = 1, math.min(#linesA, #linesB) do
		if linesA[i] ~= linesB[i] then
			same = false
			firstDifference = i
			break
		end
	end
	if same then
		out[#out + 1] = string.format("decisions: the same (%d lines)", #linesA)
	else
		out[#out + 1] = string.format("decisions: DIFFERENT (%d lines against %d)", #linesA, #linesB)
		local at = firstDifference or (math.min(#linesA, #linesB) + 1)
		out[#out + 1] = string.format("  first difference at line %d:", at)
		out[#out + 1] = "    A: " .. tostring(linesA[at])
		out[#out + 1] = "    B: " .. tostring(linesB[at])
	end
	local totalA, totalB, names, seen = 0, 0, {}, {}
	for name, n in pairs(callsA) do
		totalA = totalA + n
		seen[name] = true
		names[#names + 1] = name
	end
	for name, n in pairs(callsB) do
		totalB = totalB + n
		if not seen[name] then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	local perA = botFramesA > 0 and totalA / botFramesA or 0
	local perB = botFramesB > 0 and totalB / botFramesB or 0
	out[#out + 1] = string.format(
		"engine calls per bot per frame: A %.1f, B %.1f (%+.2f%%)",
		perA,
		perB,
		perA > 0 and (perB - perA) / perA * 100 or 0
	)
	local differing = 0
	for _, name in ipairs(names) do
		local a, b = callsA[name] or 0, callsB[name] or 0
		if a ~= b then
			differing = differing + 1
			out[#out + 1] = string.format("  %-40s A %d, B %d (%+d)", name, a, b, b - a)
		end
	end
	if differing == 0 then
		out[#out + 1] = "  every function is called exactly as often"
	end
	return out, same
end

local function main(args)
	local command = args[1]
	if command == "compare" and args[2] and args[3] then
		local callsA, framesA = readCalls(args[2] .. ".calls.tsv")
		local callsB, framesB = readCalls(args[3] .. ".calls.tsv")
		local out, same = Trace.compare(
			readLines(args[2] .. ".trace.txt"),
			readLines(args[3] .. ".trace.txt"),
			callsA,
			callsB,
			framesA,
			framesB
		)
		io.write(table.concat(out, "\n"), "\n")
		os.exit(same and 0 or 1)
	end
	if command ~= "run" or args[2] == nil then
		io.write("luajit tests/decision_trace.lua run <out> [--scenario attack|retreat|both] [--frames N]\n")
		io.write("                                         [--heroes <text>] [--arm <name>]\n")
		io.write("luajit tests/decision_trace.lua compare <outA> <outB>\n")
		os.exit(2)
	end
	local opts = {}
	local i = 3
	while args[i] ~= nil do
		local key = string.match(args[i], "^%-%-(%a+)$")
		if key == nil or args[i + 1] == nil then
			io.write("not understood: " .. tostring(args[i]) .. "\n")
			os.exit(2)
		end
		opts[key] = args[i + 1]
		i = i + 2
	end
	opts.frames = tonumber(opts.frames)
	local Stub = assert(loadfile("tests/stub_api.lua"))()
	Stub.install(".")
	local result = Trace.run(Stub, opts)
	local file = assert(io.open(args[2] .. ".trace.txt", "w"))
	file:write(table.concat(result.lines, "\n"), "\n")
	file:close()
	local names = {}
	for name in pairs(result.calls) do
		names[#names + 1] = name
	end
	table.sort(names)
	file = assert(io.open(args[2] .. ".calls.tsv", "w"))
	file:write("#bot-frames\t", result.botFrames, "\n")
	for _, name in ipairs(names) do
		file:write(name, "\t", result.calls[name], "\n")
	end
	file:close()
	for _, problem in ipairs(result.problems) do
		io.write("did not load: ", string.sub(problem, 1, 300), "\n")
	end
	io.write(
		string.format(
			"%d trace lines, %d bot-frames, %d scripts did not load\n",
			#result.lines,
			result.botFrames,
			#result.problems
		)
	)
end

if type(arg) == "table" and type(arg[0]) == "string" and string.find(arg[0], "decision_trace.lua", 1, true) then
	main(arg)
end

return Trace
