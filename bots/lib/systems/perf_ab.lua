-- Shared bot system: [SHy-AB], a change timed against the old code inside one running game (#268; first used for
-- #251, games 083 and 084). How to run a measurement, step by step: docs/MEASURING_PERFORMANCE.md.
--
-- Why in a game: fewer engine calls are not less time (maintainer, 2026-11-25: "the lua may call fewer API but
-- overall CPU usage (API engine vs Lua) should be measured"), the tests' stub cannot weigh the two (its "engine" is
-- Lua code with made-up costs: for #251 its interpreted run and its compiled run gave opposite answers, and the
-- scripts cannot see which of the two the game does), and two games, one before and one after, differ by 7% to 12%
-- in script time with the same build (#153).
--
-- Dormant: nothing on main requires this file. The PR that measures something does, and defines an experiment:
--   local switch = PerfAb.Define({
--       name = "lotus",                                    -- letters, digits, "_" and "-"
--       variants = {
--           { name = "scan", on = { "scan" } },              -- one switch alone
--           { name = "both", on = { "scan", "count" } },     -- or several together
--       },
--   })
--   if switch.scan then <the new code> else <the old code, unchanged> end
-- Every switch is false (the old code) until a frame of a variant that names it, and again after it. Define never
-- raises an error: a definition it cannot use prints one [SHy-ERROR] line and gets a table without switches, so the
-- old code runs. Asked again with the same name (a mode file runs once per bot) it gives the same table back,
-- refused or not, and prints nothing. A second experiment adds its variants to the first one's; the totals start
-- again from there.
--
-- How: every frame (one GameTime() value) runs one variant ("arm"), for all bots of the team:
--   off     no switch on: the code from before;
--   off2    the same again. It must show no difference from `off`: when it does, no other line can be trusted;
--   <experiment>.<variant>   the switches of that variant on.
-- As many frames in a row as there are arms (a "block") run every arm once, in an order shuffled anew for every
-- block. So nothing that repeats in the game or in the scripts (creep waves, work done once a second) falls on the
-- same arm every time, and the arms are compared on neighbouring frames, where the game is as good as the same. A
-- variant must decide the same things as the old code (tests/decision_trace.lua checks that outside the game), so
-- the game plays as if nothing was switched.
--
-- What is timed: Perf.Wrap (perf.lua) times every entry point the engine calls (each mode's GetDesire and Think, the
-- item and ability thinks, MinionThink) with RealTime(): the Lua code and the engine calls it makes, together. The
-- sum over the team's bots in one frame is that frame's script time. The switching runs before the clock starts.
--
-- The lines: "[SHy-AB] ... defined exp=" once per experiment and team, then one line per arm and team every 5
-- minutes, with the totals since the last experiment was defined:
--   frames=            frames this arm ran
--   ms/frame=          its mean script time per frame (the team's bots together)
--   d= se= z=          the mean of (this arm's frame - the `off` frame of the same block), its standard error, d / se.
--                      z under -3: faster than `off`; over 3: slower; in between: no difference that can be told
--   pct=               d as a share of `off`'s ms/frame
--   faster= slower=    in how many of the blocks= this arm's frame was the cheaper / the dearer one, and
--   sign=              (slower - faster) / sqrt(faster + slower), read like z. A few very long frames do not move it,
--                      so a small gain that is there in most frames shows here first
--   over2= .. over16=  frames of 2 / 4 / 8 / 16 ms and more, and max= the longest one
--   calls= slow=       timed calls, and those of 2 ms and more (the engine's own warning starts there, perf.lua)
--   kb/frame= gc=      Lua memory allocated per frame (a lower bound) and calls a collection sweep ran in (perf.lua)
--   jit= tick=         LuaJIT's compiler as the scripts see it (on / off / na; the game said na in games 083 and 084),
--                      and the smallest call time seen, in ms: the step of the clock
--
-- The measurement must never stop a think. When a new frame's bookkeeping raises an error it ends with one
-- [SHy-ERROR] line; an experiment whose own check fails ends it with PerfAb.Stop(why) ("[SHy-AB] ... stopped
-- why="). Either way every switch is off from then on and the timer is left alone again.
--
-- What stays on main: this file, its hook in perf.lua, its tests. What does not: an experiment. Its Define, its
-- switch tests and the code path that lost come out of the PR before it merges (AGENTS.md, Code conventions).
local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
local PerfAb = {}

local REPORT_WINDOW = 300 -- seconds of game time between two reports
local SLOW_CALL = 0.002 -- seconds: perf.lua's, the engine's "took N ms" threshold
local OVER_MS = { 2, 4, 8, 16 }
-- Arms in one block, `off` and `off2` included. A block is that many frames (12 are 0.4s): much longer, and the
-- frames of one block are no longer neighbours.
local MAX_ARMS = 12
local NAME = "^[%w_%-]+$"

-- variants[1] is what the others are compared with. A variant: name, switch (its experiment's table), on (the
-- switch names it turns on).
local variants = { { name = "off", on = {} }, { name = "off2", on = {} } }
local experiments = {} -- [name] = the table Define gave out: the switches, or an empty one for a refused name
local watching = false -- Perf calls BeforeCall / AfterCall
-- true once the measurement ended (an error, or PerfAb.Stop): nothing is switched or timed any more.
local stopped = false
-- An arm (index) that every frame runs: tests and tests/decision_trace.lua.
local pinned = nil
-- The variant whose switches are on now.
local lit = nil

local function NewArm()
	return {
		frames = 0,
		ms = 0,
		over = { 0, 0, 0, 0 },
		max = 0,
		calls = 0,
		slow = 0,
		allocKb = 0,
		gc = 0,
		-- Against variants[1], one difference per finished block: their sum, the sum of their squares, and how many
		-- were below and above 0.
		dSum = 0,
		dSq = 0,
		faster = 0,
		slower = 0,
	}
end
local arms = {}
local order = {}
local blocks = 0 -- finished blocks
local blockPos = 0 -- frames of the running block that have begun
local blockMs = {} -- [arm] = the script time of its frame in the running block
local frameAt = nil -- GameTime() of the frame being timed
local frameArm = nil -- its arm (index), nil while nothing is timed
local frameSeconds = 0
local tick = math.huge -- the smallest call time above 0 seen
local reportAt = nil
local jitState = nil

-- The totals start again: at the first definition, and at every later one (an arm more changes every block).
local function ResetTotals()
	arms, order, blockMs = {}, {}, {}
	for i = 1, #variants do
		arms[i] = NewArm()
		order[i] = i
	end
	blocks, blockPos = 0, 0
	-- The frame that is running is not timed: it began under the old list of arms.
	frameArm = nil
end
ResetTotals()

-- A Lehmer generator (multiplier 48271, modulus 2^31 - 1). Every product stays a whole number a Lua number holds
-- exactly, so the order is the same on every machine. Returns 1..n.
local seed = 20261125
local function Random(n)
	seed = (seed * 48271) % 2147483647
	return 1 + math.floor(seed / 2147483647 * n)
end
local function Shuffle()
	for i = #order, 2, -1 do
		local j = Random(i)
		order[i], order[j] = order[j], order[i]
	end
end

local function HeroName()
	local name = "-"
	pcall(function()
		name = string.gsub(GetBot():GetUnitName(), "npc_dota_hero_", "")
	end)
	return name
end

-- DotaTime() for a line that reports a fault: it must not be the next fault.
local function Now()
	local ok, now = pcall(DotaTime)
	return ok and type(now) == "number" and now or 0
end

local function JitState()
	if type(jit) ~= "table" or type(jit.status) ~= "function" then
		return "na"
	end
	local ok, on = pcall(jit.status)
	if not ok then
		return "na"
	end
	return on and "on" or "off"
end

local function Set(variant, value)
	for i = 1, #variant.on do
		variant.switch[variant.on[i]] = value
	end
end

-- One report line. Pure: tests read it. `arm` holds the arm's totals, `baseMs` is variants[1]'s mean ms per frame.
function PerfAb.Format(now, heroName, name, arm, baseMs, blockCount, jitText, tickMs)
	local mean = arm.frames > 0 and arm.ms / arm.frames or 0
	local d, se = 0, 0
	if blockCount > 0 then
		d = arm.dSum / blockCount
	end
	if blockCount > 1 then
		local variance = (arm.dSq - blockCount * d * d) / (blockCount - 1)
		se = math.sqrt(math.max(variance, 0) / blockCount)
	end
	local decided = arm.faster + arm.slower
	return string.format(
		"[SHy-AB] t=%.0f %s arm=%s frames=%d ms/frame=%.4f d=%+.4f se=%.4f z=%+.1f pct=%+.1f faster=%d slower=%d"
			.. " sign=%+.1f blocks=%d over2=%d over4=%d over8=%d over16=%d max=%.1f calls=%d slow=%d kb/frame=%.1f gc=%d"
			.. " jit=%s tick=%.4f",
		now,
		heroName,
		name,
		arm.frames,
		mean,
		d,
		se,
		se > 0 and d / se or 0,
		baseMs > 0 and d / baseMs * 100 or 0,
		arm.faster,
		arm.slower,
		decided > 0 and (arm.slower - arm.faster) / math.sqrt(decided) or 0,
		blockCount,
		arm.over[1],
		arm.over[2],
		arm.over[3],
		arm.over[4],
		arm.max,
		arm.calls,
		arm.slow,
		arm.frames > 0 and arm.allocKb / arm.frames or 0,
		arm.gc,
		jitText,
		tickMs
	)
end

local function PrintLines()
	jitState = jitState or JitState()
	local base = arms[1]
	local baseMs = base.frames > 0 and base.ms / base.frames or 0
	local dotaTime, heroName = DotaTime(), HeroName()
	local tickMs = tick < math.huge and tick * 1000 or 0
	for i = 1, #variants do
		pcall(print, PerfAb.Format(dotaTime, heroName, variants[i].name, arms[i], baseMs, blocks, jitState, tickMs))
	end
end

-- `now` is GameTime(): it runs with the game clock, so the window is in game seconds.
local function Report(now)
	if reportAt == nil then
		reportAt = now + REPORT_WINDOW
		return
	end
	if now < reportAt then
		return
	end
	reportAt = now + REPORT_WINDOW
	PrintLines()
end

-- The frame that just ended goes into its arm's totals, and into the differences once its block is complete.
local function CloseFrame()
	local ms = frameSeconds * 1000
	local arm = arms[frameArm]
	arm.frames = arm.frames + 1
	arm.ms = arm.ms + ms
	for i = 1, #OVER_MS do
		if ms >= OVER_MS[i] then
			arm.over[i] = arm.over[i] + 1
		end
	end
	if ms > arm.max then
		arm.max = ms
	end
	if pinned ~= nil then
		return
	end
	blockMs[frameArm] = ms
	if blockPos < #variants then
		return
	end
	local baseMs = blockMs[1]
	for i = 2, #variants do
		local d = blockMs[i] - baseMs
		local other = arms[i]
		other.dSum = other.dSum + d
		other.dSq = other.dSq + d * d
		if d < 0 then
			other.faster = other.faster + 1
		elseif d > 0 then
			other.slower = other.slower + 1
		end
	end
	blocks = blocks + 1
	blockPos = 0
end

-- A new frame: the one that ended goes into the totals, its switches go off and the next arm's go on.
local function BeginFrame(now)
	if frameArm ~= nil then
		CloseFrame()
	end
	frameSeconds = 0
	if lit ~= nil then
		Set(lit, false)
	end
	if pinned ~= nil then
		frameArm = pinned
	else
		if blockPos == 0 then
			Shuffle()
		end
		blockPos = blockPos + 1
		frameArm = order[blockPos]
	end
	lit = variants[frameArm]
	Set(lit, true)
	Report(now)
end

-- The end of the measurement: every switch off (the old code), and Perf stops calling.
local function Halt()
	stopped = true
	frameArm = nil
	lit = nil
	for i = 1, #variants do
		pcall(Set, variants[i], false)
	end
	watching = false
	Perf.Watch(nil, nil)
end

-- Before a timed entry point runs (Perf.Wrap, ahead of its clock): a new GameTime() is a new frame.
local function BeforeCall()
	if stopped then
		return
	end
	local now = GameTime()
	if now == frameAt then
		return
	end
	frameAt = now
	local ok, problem = pcall(BeginFrame, now)
	if not ok then
		Halt()
		pcall(print, string.format("[SHy-ERROR] t=%.0f %s perf_ab stopped: %s", Now(), HeroName(), tostring(problem)))
	end
end

-- After it: its time and its change in Lua memory (nil when memory cannot be read), as Perf's own totals get them.
local function AfterCall(seconds, kbDelta)
	local arm = frameArm ~= nil and arms[frameArm] or nil
	if arm == nil then
		return
	end
	frameSeconds = frameSeconds + seconds
	arm.calls = arm.calls + 1
	if seconds >= SLOW_CALL then
		arm.slow = arm.slow + 1
	end
	if seconds > 0 and seconds < tick then
		tick = seconds
	end
	if kbDelta ~= nil then
		if kbDelta < 0 then
			arm.gc = arm.gc + 1
		else
			arm.allocKb = arm.allocKb + kbDelta
		end
	end
end

-- Checks a definition and turns it into variants. Raises an error (a string) on anything it cannot use.
local function Build(spec)
	if type(spec) ~= "table" or type(spec.name) ~= "string" or not string.find(spec.name, NAME) then
		error("an experiment needs a name of letters, digits, _ and -", 0)
	end
	if type(spec.variants) ~= "table" or #spec.variants == 0 then
		error(spec.name .. ": no variants", 0)
	end
	if #variants + #spec.variants > MAX_ARMS then
		error(spec.name .. ": more than " .. MAX_ARMS .. " arms in one block", 0)
	end
	local switch, built, seen = {}, {}, {}
	for i = 1, #spec.variants do
		local variant = spec.variants[i]
		if type(variant) ~= "table" or type(variant.name) ~= "string" or not string.find(variant.name, NAME) then
			error(spec.name .. ": variant " .. i .. " needs a name of letters, digits, _ and -", 0)
		end
		if seen[variant.name] then
			error(spec.name .. ": two variants named " .. variant.name, 0)
		end
		seen[variant.name] = true
		if type(variant.on) ~= "table" or #variant.on == 0 then
			error(spec.name .. "." .. variant.name .. ": no switch to turn on", 0)
		end
		local on = {}
		for j = 1, #variant.on do
			if type(variant.on[j]) ~= "string" then
				error(spec.name .. "." .. variant.name .. ": a switch name must be a string", 0)
			end
			on[j] = variant.on[j]
			switch[on[j]] = false
		end
		built[i] = { name = spec.name .. "." .. variant.name, switch = switch, on = on }
	end
	return switch, built
end

-- Adds an experiment (see the top of the file) and returns its switches: a table of booleans by switch name, which
-- this file changes from frame to frame. Never raises an error.
function PerfAb.Define(spec)
	local known = type(spec) == "table" and experiments[spec.name] or nil
	if known ~= nil then
		return known
	end
	local problem = nil
	if stopped then
		problem = "the measurement has ended"
	else
		local ok, switch, built = pcall(Build, spec)
		if ok then
			for i = 1, #built do
				variants[#variants + 1] = built[i]
			end
			experiments[spec.name] = switch
			ResetTotals()
			if not watching then
				watching = true
				Perf.Watch(BeforeCall, AfterCall)
			end
			pcall(
				print,
				string.format(
					"[SHy-AB] t=%.0f %s defined exp=%s variants=%d arms=%d",
					Now(),
					HeroName(),
					spec.name,
					#built,
					#variants
				)
			)
			return switch
		end
		problem = switch
	end
	pcall(
		print,
		string.format("[SHy-ERROR] t=%.0f %s perf_ab define refused: %s", Now(), HeroName(), tostring(problem))
	)
	-- No switch in it: whatever the caller reads is nil, and its old code runs. Kept under the name, so that the
	-- next bot's ask gets it without another line.
	local none = {}
	if type(spec) == "table" and type(spec.name) == "string" then
		experiments[spec.name] = none
	end
	return none
end

-- An experiment found out that it cannot go on (its own check failed): the lines print one last time, every switch
-- goes off and nothing is switched or timed any more.
function PerfAb.Stop(why)
	if stopped then
		return
	end
	local wasWatching = watching
	Halt()
	if wasWatching then
		pcall(PrintLines)
	end
	pcall(print, string.format("[SHy-AB] t=%.0f %s stopped why=%s", Now(), HeroName(), tostring(why)))
end

-- The arm of the frame being timed ("off", "lotus.scan", ...), nil while nothing is timed.
function PerfAb.Arm()
	return frameArm ~= nil and variants[frameArm].name or nil
end

-- Every arm's name, `off` and `off2` first.
function PerfAb.Arms()
	local names = {}
	for i = 1, #variants do
		names[i] = variants[i].name
	end
	return names
end

-- Every frame from the next one runs this arm (nil: back to the shuffled blocks). The differences against `off`
-- need every arm, so they stand still meanwhile. For tests and tests/decision_trace.lua. False: no such arm.
function PerfAb.Pin(name)
	pinned = nil
	blockPos = 0
	if name == nil then
		return true
	end
	for i = 1, #variants do
		if variants[i].name == name then
			pinned = i
		end
	end
	return pinned ~= nil
end

-- The totals so far, by arm name, and the number of finished blocks. For tests.
function PerfAb.Totals()
	local byName = {}
	for i = 1, #variants do
		byName[variants[i].name] = arms[i]
	end
	return byName, blocks
end

return PerfAb
