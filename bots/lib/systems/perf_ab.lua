-- Shared bot system: [SHy-AB], the reuse in frame_cache.lua timed inside a running game (#251, #52).
--
-- Why: the reuse saves engine calls (16% to 18% fewer per bot per frame in the tests' stub API) but adds Lua work of
-- its own, and outside the game the two cannot be weighed: the stub's "engine" is Lua code with made-up costs, and
-- there the result changed sign with the way LuaJIT ran the scripts (13.4% less time interpreted, 2.5% more compiled).
-- Maintainer, 2026-11-25: "the lua may call fewer API but overall CPU usage (API engine vs Lua) should be measured".
-- Two games, one before and one after, do not show it either: two games of one build differed by 7% to 12% in script
-- time (games 059 and 062, #153).
--
-- How: every frame (one GameTime() value) runs one variant ("arm") of the reuse, for all bots of the team:
--   off     the code from before the reuse;
--   off2    the same again. It must show no difference from `off`: when it does, no other line can be trusted;
--   turbo   only the Turbo check of the frame is kept;
--   lists   only the nearby-hero lists of the frame are kept;
--   filter  only a hero's place in Fu.GetNearbyHeroes's filter is kept;
--   all     the three together.
-- Six frames in a row (a fifth of a second) run the six arms once each, in an order shuffled anew for every six. So
-- nothing that repeats in the game or in the scripts (creep waves, work done once a second) falls on the same arm every
-- time, and the arms are compared on neighbouring frames, where the game is as good as the same. Every arm decides the
-- same things (the reuse never changes an answer), so the game plays as if nothing was switched.
--
-- What is timed: Perf.Wrap (perf.lua) times every entry point the engine calls (each mode's GetDesire and Think, the
-- item and ability thinks, MinionThink) with RealTime(): the Lua code and the engine calls it makes, together. The sum
-- over the team's bots in one frame is that frame's script time. The switch itself runs before the clock starts.
--
-- The line: one per arm and team every 5 minutes, with the totals since the game began.
--   frames=            frames this arm ran
--   ms/frame=          its mean script time per frame (the team's bots together)
--   d= se= z=          the mean of (this arm's frame - the `off` frame of the same six), its standard error, d / se.
--                      z under -3: faster than `off`; over 3: slower; in between: no difference that can be told
--   pct=               d as a share of `off`'s ms/frame
--   faster= slower=    in how many of the blocks= sixes this arm's frame was the cheaper / the dearer one, and
--   sign=              (slower - faster) / sqrt(faster + slower), read like z. A few very long frames do not move it,
--                      so a small gain that is there in most frames shows here first
--   over2= .. over16=  frames of 2 / 4 / 8 / 16 ms and more, and max= the longest one
--   calls= slow=       timed calls, and those of 2 ms and more (the engine's own warning starts there, perf.lua)
--   kb/frame= gc=      Lua memory allocated per frame (a lower bound) and calls a collection sweep ran in (perf.lua)
--   on=                false once the reuse switched itself off (frame_cache.lua): every arm then runs as `off`
--   jit= tick=         LuaJIT's compiler in the game (on / off / na), and the smallest call time seen, in ms: the
--                      step of the clock
--
-- The measurement must never stop a think: when a new frame's bookkeeping raises an error, it ends with one
-- [SHy-ERROR] line and every frame from then on runs the code from before.
--
-- This file and the switch go once the pieces are decided: a build that still has them is not for main.
local FrameCache = require(GetScriptDirectory() .. "/lib/systems/frame_cache")
local PerfAb = {}

-- ARMS[1] is what the others are compared with.
local ARMS = {
	{ name = "off" },
	{ name = "off2" },
	{ name = "turbo", turbo = true },
	{ name = "lists", lists = true },
	{ name = "filter", filter = true },
	{ name = "all", lists = true, filter = true, turbo = true },
}
local REPORT_WINDOW = 300 -- seconds of game time between two reports
local SLOW_CALL = 0.002 -- seconds: perf.lua's, the engine's "took N ms" threshold
local OVER_MS = { 2, 4, 8, 16 }

-- false: no switching and no lines, every piece on.
local active = true
-- true once a frame's bookkeeping raised an error: nothing is switched or timed any more.
local stopped = false
-- An arm (index) that every frame runs: tests and timing outside the game.
local pinned = nil

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
		-- Against ARMS[1], one difference per finished six: their sum, the sum of their squares, and how many were
		-- below and above 0.
		dSum = 0,
		dSq = 0,
		faster = 0,
		slower = 0,
	}
end
local arms = {}
local order = {}
for i = 1, #ARMS do
	arms[i] = NewArm()
	order[i] = i
end
local blocks = 0 -- finished sixes
local blockPos = 0 -- frames of the running six that have begun
local blockMs = {} -- [arm] = the script time of its frame in the running six
local frameAt = nil -- GameTime() of the frame being timed
local frameArm = nil -- its arm (index), nil while nothing is timed
local frameSeconds = 0
local tick = math.huge -- the smallest call time above 0 seen
local reportAt = nil
local jitState = nil

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

-- One report line. Pure: tests read it. `arm` holds the arm's totals, `baseMs` is ARMS[1]'s mean ms per frame.
function PerfAb.Format(now, heroName, name, arm, baseMs, blockCount, on, jitText, tickMs)
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
			.. " on=%s jit=%s tick=%.4f",
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
		tostring(on),
		jitText,
		tickMs
	)
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
	jitState = jitState or JitState()
	local base = arms[1]
	local baseMs = base.frames > 0 and base.ms / base.frames or 0
	local dotaTime, heroName = DotaTime(), HeroName()
	local tickMs = tick < math.huge and tick * 1000 or 0
	for i = 1, #ARMS do
		pcall(
			print,
			PerfAb.Format(
				dotaTime,
				heroName,
				ARMS[i].name,
				arms[i],
				baseMs,
				blocks,
				FrameCache.IsEnabled(),
				jitState,
				tickMs
			)
		)
	end
end

-- The frame that just ended goes into its arm's totals, and into the differences once its six is complete.
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
	if blockPos < #ARMS then
		return
	end
	local baseMs = blockMs[1]
	for i = 2, #ARMS do
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

-- A new frame: the one that ended goes into the totals, and the next arm is switched on.
local function BeginFrame(now)
	if frameArm ~= nil then
		CloseFrame()
	end
	frameSeconds = 0
	FrameCache.BeginFrame(now)
	if not active then
		frameArm = nil
		return
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
	local arm = ARMS[frameArm]
	FrameCache.SetPieces(arm.lists, arm.filter, arm.turbo)
	Report(now)
end

-- Before a timed entry point runs (Perf.Wrap, ahead of its clock): a new GameTime() is a new frame.
function PerfAb.BeforeCall()
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
		stopped = true
		frameArm = nil
		FrameCache.SetPieces(false, false, false)
		pcall(
			print,
			string.format("[SHy-ERROR] t=%.0f %s perf_ab stopped: %s", DotaTime(), HeroName(), tostring(problem))
		)
	end
end

-- After it: its time and its change in Lua memory (nil when memory cannot be read), as Perf's own totals get them.
function PerfAb.AfterCall(seconds, kbDelta)
	if frameArm == nil then
		return
	end
	frameSeconds = frameSeconds + seconds
	local arm = arms[frameArm]
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

-- The arm of the frame being timed ("off", "lists", ...), nil while nothing is switched.
function PerfAb.Arm()
	return frameArm ~= nil and ARMS[frameArm].name or nil
end

-- Every frame from the next one runs this arm (nil: back to the shuffled sixes). The differences against `off` need
-- every arm, so they stand still meanwhile. For tests and timing outside the game.
function PerfAb.Pin(name)
	pinned = nil
	blockPos = 0
	for i = 1, #ARMS do
		if ARMS[i].name == name then
			pinned = i
		end
	end
	return pinned ~= nil
end

-- Off: no arms, no lines, every piece on.
function PerfAb.SetActive(on)
	active = on and true or false
	if not active then
		pinned = nil
		blockPos = 0
		FrameCache.SetPieces(true, true, true)
	end
end

-- The totals so far, by arm name, and the number of finished sixes. For tests.
function PerfAb.Totals()
	local byName = {}
	for i = 1, #ARMS do
		byName[ARMS[i].name] = arms[i]
	end
	return byName, blocks
end

return PerfAb
