-- Shared bot system: one engine call per game frame for the hero lists every bot asks for again and again (#52).
--
-- Counted outside the game (the tests' stub API, one bot in a five-on-five fight, every hero script): 79
-- GetNearbyHeroes engine calls per bot per frame (modes 38, items 31, the hero script 9), 50 of them an exact repeat of
-- a call already made in that frame: the same unit, radius, enemy flag and mode. Fu.HasForbiddenModifier alone asked
-- "allies within 800 of this enemy" 24 times.
--
-- What is kept: the engine's answer for one (unit, radius, enemy flag, mode), until GameTime() changes. Nothing in the
-- game moves between two think calls of the same frame, so a kept answer is the one a new call would give: no decision
-- changes (Fu.GetCachedUnitList does the same for GetUnitList). Each team's bots run in one Lua state
-- (bots/lib/systems/perf.lua), so the team shares the answers. Every question comes from a think: the two callbacks
-- the scripts install (cast, chat) only note what happened and ask for no hero list. One that did would have to ask
-- the engine itself, since its answer could be a frame old for the thinks that follow.
--
-- Callers change the list they get (Fu.GetAroundBotUnitList appends creeps to it, #121), so the kept list is never
-- handed out: FrameCache.NearbyHeroesCopy gives every caller its own table, as the engine does. FrameCache.NearbyHeroes
-- returns the kept list itself and is only for code that reads it (Fu.GetNearbyHeroes builds its own result from it).
--
-- Asked from the engine as before, never kept: a radius that is not a number, an enemy flag that is not true or false,
-- a mode that is not a whole number.
--
-- Three pieces, each a field its callers test first, so a piece that is off costs that one test and then runs the code
-- from before this file:
--   FrameCache.lists   the nearby-hero lists of the frame (unit:GetNearbyHeroes in global_overrides.lua and
--                      Fu.GetNearbyHeroes);
--   FrameCache.filter  a hero's place in Fu.GetNearbyHeroes's filter, worked out once per frame (FrameCache.Listed);
--   FrameCache.turbo   the Turbo check of the frame (Fu.IsModeTurbo, Utils.IsModeTurbo).
-- Fewer engine calls are not yet less time: the pieces add Lua work of their own. bots/lib/systems/perf_ab.lua switches
-- them from frame to frame and times every variant in the game (#251). Until the pieces are decided there, each one
-- is on in some frames and off in others.
--
-- Self-check: every 64th kept answer (a list, or a hero's place in Fu.GetNearbyHeroes's filter) is asked again and
-- compared. "[SHy-FRAMECACHE] ... counts" prints the numbers every 5 minutes, also once the cache is off (frames= is
-- the number of frames the timed entry points saw: 30 a second when GameTime() changes with every think), and
-- "... differs" names an answer that was not the same. One of those is a change inside a frame (a buyback, say) and
-- costs nothing. When 3 or more differ and they are 2% of the checks of a 5-minute window, the engine does not hold
-- still within a frame: every piece turns itself off for the rest of the game.
local FrameCache = {}

-- The engine caps the radius at 1600 (the GetNearbyHeroes wrapper in global_overrides.lua): two radii above it are
-- one query.
local MAX_RADIUS = 1600
local CHECK_EVERY = 64
-- Off when this many checked answers of a window differ and they are 1 in MISMATCH_SHARE of its checks or more.
local MIN_MISMATCHES = 3
local MISMATCH_SHARE = 50
local MAX_DIFFER_LINES = 20 -- "differs" lines per game
local REPORT_WINDOW = 300 -- seconds of game time per [SHy-FRAMECACHE] line

-- The engine call behind unit:GetNearbyHeroes (set by global_overrides.lua, which owns the wrapper).
local source = nil
-- False once the self-check switched everything off (or a test did).
local enabled = true
-- The pieces that were asked for (FrameCache.SetPieces). The fields say what is on: these, while `enabled` holds.
local wantLists, wantFilter, wantTurbo = true, true, true
FrameCache.lists = true
FrameCache.filter = true
FrameCache.turbo = true
local reportAt = nil
local windowStart = nil

local function NewStats()
	return {
		nearby = 0, -- questions that can be kept
		kept = 0, -- of them, answered without the engine
		uncached = 0, -- questions that came here and are never kept (odd arguments, a test double)
		checked = 0, -- kept answers asked from the engine again
		mismatch = 0, -- of them, different
		filter = 0, -- heroes Fu.GetNearbyHeroes looked at through FrameCache.Listed
		filterKept = 0, -- of them, already looked at this frame
		filterChecked = 0, -- kept filter answers worked out again
		filterMismatch = 0, -- of them, different
		frames = 0, -- frames the timed entry points saw (FrameCache.BeginFrame)
	}
end
local stats = NewStats()
local differLines = 0

local function ApplyPieces()
	FrameCache.lists = enabled and wantLists
	FrameCache.filter = enabled and wantFilter
	FrameCache.turbo = enabled and wantTurbo
end

function FrameCache.SetNearbyHeroesSource(fn)
	source = fn
end

-- Which pieces are on from now (perf_ab.lua asks for another set every frame; tests pick one).
function FrameCache.SetPieces(lists, filter, turbo)
	wantLists = lists and true or false
	wantFilter = filter and true or false
	wantTurbo = turbo and true or false
	ApplyPieces()
end

-- Off: no piece is on, whatever was asked for: every call goes to the engine, as before this file.
function FrameCache.SetEnabled(on)
	enabled = on and true or false
	ApplyPieces()
end
function FrameCache.IsEnabled()
	return enabled
end

local function Fetch(unit, radius, isEnemy, mode)
	if source ~= nil then
		return source(unit, radius, isEnemy, mode)
	end
	return unit:GetNearbyHeroes(radius, isEnemy, mode)
end

-- A number for the (enemy flag, mode) pair, or nil when the arguments are not the plain kind that is kept.
local function SlotOf(radius, isEnemy, mode)
	if type(radius) ~= "number" or radius ~= radius then
		return nil
	end
	if isEnemy ~= true and isEnemy ~= false then
		return nil
	end
	local modeKey = 0
	if mode ~= nil then
		if type(mode) ~= "number" or mode < 0 or mode % 1 ~= 0 then
			return nil
		end
		modeKey = mode + 1
	end
	return modeKey * 2 + (isEnemy and 1 or 0)
end

-- The unit's kept answers of this frame for one slot, by radius. They live on the handle (as bot._perf does) and are
-- emptied in place when the frame changes, so a frame costs no new table.
local function MemoFor(unit, slot, now)
	local bySlot = unit._frameNearby
	if bySlot == nil then
		bySlot = {}
		unit._frameNearby = bySlot
	end
	local memo = bySlot[slot]
	if memo == nil then
		memo = { at = now }
		bySlot[slot] = memo
	elseif memo.at ~= now then
		for key in pairs(memo) do
			memo[key] = nil
		end
		memo.at = now
	end
	return memo
end

local function SameList(a, b)
	if a == nil or b == nil then
		return a == b
	end
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function HeroName()
	local name = "-"
	pcall(function()
		name = string.gsub(GetBot():GetUnitName(), "npc_dota_hero_", "")
	end)
	return name
end

-- One report line. Pure: tests read it.
function FrameCache.FormatReport(now, heroName, span, counts, on)
	return string.format(
		"[SHy-FRAMECACHE] t=%.0f %s counts window=%.0fs frames=%d nearby=%d kept=%d uncached=%d checked=%d mismatch=%d"
			.. " filter=%d filterKept=%d filterChecked=%d filterMismatch=%d on=%s",
		now,
		heroName,
		span,
		counts.frames or 0,
		counts.nearby,
		counts.kept,
		counts.uncached,
		counts.checked,
		counts.mismatch,
		counts.filter,
		counts.filterKept,
		counts.filterChecked or 0,
		counts.filterMismatch or 0,
		tostring(on)
	)
end

-- `now` is GameTime(): it runs with the game clock, so the window is in game seconds.
local function Report(now)
	if reportAt == nil then
		reportAt = now + REPORT_WINDOW
		windowStart = now
		return
	end
	if now < reportAt then
		return
	end
	pcall(print, FrameCache.FormatReport(DotaTime(), HeroName(), now - windowStart, stats, enabled))
	stats = NewStats()
	reportAt = now + REPORT_WINDOW
	windowStart = now
end

-- A new frame began (`now` is GameTime()): told by the timer of the entry points (perf_ab.lua), once per frame, so the
-- line also prints while no piece is on.
function FrameCache.BeginFrame(now)
	stats.frames = stats.frames + 1
	Report(now)
end

-- A checked answer was not the same. `checked` and `mismatch` are the window's counts for that kind of answer.
local function NoteDifference(what, detail, checked, mismatch)
	if mismatch >= MIN_MISMATCHES and mismatch * MISMATCH_SHARE >= checked then
		enabled = false
		ApplyPieces()
	end
	if differLines < MAX_DIFFER_LINES or not enabled then
		differLines = differLines + 1
		pcall(
			print,
			string.format(
				"[SHy-FRAMECACHE] t=%.0f %s differs what=%s %s checked=%d mismatch=%d on=%s",
				DotaTime(),
				HeroName(),
				what,
				detail,
				checked,
				mismatch,
				tostring(enabled)
			)
		)
	end
end

-- A kept list asked from the engine again. Returns the answer to use (the new one when they differ).
local function Check(unit, radius, isEnemy, mode, kept)
	stats.checked = stats.checked + 1
	local fresh = Fetch(unit, radius, isEnemy, mode)
	if SameList(kept, fresh) then
		return kept
	end
	stats.mismatch = stats.mismatch + 1
	NoteDifference(
		"list",
		string.format(
			"radius=%s enemy=%s mode=%s kept=%s now=%s",
			tostring(radius),
			tostring(isEnemy),
			tostring(mode),
			kept ~= nil and tostring(#kept) or "nil",
			fresh ~= nil and tostring(#fresh) or "nil"
		),
		stats.checked,
		stats.mismatch
	)
	return fresh
end

-- What unit:GetNearbyHeroes(radius, isEnemy, mode) answers this frame. The list is shared by every caller of the
-- frame: read it, never change it (FrameCache.NearbyHeroesCopy for a list of your own). `now` is GameTime(), for a
-- caller that has just read it; left out, it is read here.
function FrameCache.NearbyHeroes(unit, radius, isEnemy, mode, now)
	-- The answers are kept on the handle, which is a table in the game: anything else is asked as before.
	if type(unit) ~= "table" then
		stats.uncached = stats.uncached + 1
		return Fetch(unit, radius, isEnemy, mode)
	end
	-- A unit that carries a GetNearbyHeroes of its own (a test double) answers for itself.
	if rawget(unit, "GetNearbyHeroes") ~= nil then
		stats.uncached = stats.uncached + 1
		return unit:GetNearbyHeroes(radius, isEnemy, mode)
	end
	local slot = FrameCache.lists and SlotOf(radius, isEnemy, mode) or nil
	if slot == nil then
		stats.uncached = stats.uncached + 1
		return Fetch(unit, radius, isEnemy, mode)
	end
	now = now or GameTime()
	local memo = MemoFor(unit, slot, now)
	local key = math.min(radius, MAX_RADIUS)
	local kept = memo[key]
	stats.nearby = stats.nearby + 1
	if kept == nil then
		local list = Fetch(unit, radius, isEnemy, mode)
		-- false stands for "no answer" (a unit that cannot be seen), which is not an empty list.
		memo[key] = list or false
		Report(now)
		return list
	end
	stats.kept = stats.kept + 1
	local list = kept or nil
	if stats.kept % CHECK_EVERY == 0 then
		list = Check(unit, radius, isEnemy, mode, list)
		memo[key] = list or false
	end
	return list
end

-- The same answer in a table of the caller's own.
function FrameCache.NearbyHeroesCopy(unit, radius, isEnemy, mode)
	local list = FrameCache.NearbyHeroes(unit, radius, isEnemy, mode)
	if list == nil then
		return nil
	end
	local copy = {}
	for i = 1, #list do
		copy[i] = list[i]
	end
	return copy
end

-- Whether isListed(hero) holds, asked once per hero per frame (`now` is GameTime()). Fu.GetNearbyHeroes's filter makes
-- 17 engine calls for a hero it keeps, it ran for every hero of every call, and a hero is in several lists of a frame.
function FrameCache.Listed(hero, now, isListed)
	stats.filter = stats.filter + 1
	if type(hero) ~= "table" then
		return isListed(hero)
	end
	if FrameCache.filter and hero._listedAt == now then
		stats.filterKept = stats.filterKept + 1
		local listed = hero._listed
		if stats.filterKept % CHECK_EVERY == 0 then
			stats.filterChecked = stats.filterChecked + 1
			local fresh = isListed(hero)
			if fresh ~= listed then
				stats.filterMismatch = stats.filterMismatch + 1
				NoteDifference(
					"filter",
					string.format("kept=%s now=%s", tostring(listed), tostring(fresh)),
					stats.filterChecked,
					stats.filterMismatch
				)
				hero._listed = fresh
				listed = fresh
			end
		end
		return listed
	end
	local listed = isListed(hero)
	hero._listedAt, hero._listed = now, listed
	return listed
end

return FrameCache
