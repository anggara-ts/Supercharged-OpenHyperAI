-- Shared bot system: a hero's place in Fu.GetNearbyHeroes's filter, worked out once per game frame (#52, #251).
--
-- Fu.GetNearbyHeroes (bots/lib/general_utils/team_info.lua) leaves out heroes that are not valid (dead, unseen,
-- invulnerable, ...) and our own Meepo clones: 17 engine calls for a hero it keeps, for every hero of every call. A
-- hero is in several lists of one frame (the modes, the items and the hero script all ask), so the answer is kept on
-- the hero's handle until GameTime() changes. Nothing in the game moves between two think calls of the same frame, so
-- a kept answer is the one a new check would give: no decision changes. Each team's bots run in one Lua state
-- (bots/lib/systems/perf.lua), so the team shares the answers. Nothing here outlives the frame.
--
-- Measured in games 083 and 084 (#251, an A/B switch that ran it against the old code on neighbouring frames of one
-- game): 0.9% to 2.6% less script time per frame, faster by count in all four team-games. The reuse of the
-- nearby-hero lists themselves was measured too and was slower (0.9% to 2.5% more): it was dropped, and the lists
-- are asked from the engine on every call.
--
-- Self-check: every 64th kept answer is worked out again and compared. "[SHy-FRAMECACHE] ... counts" prints the
-- numbers every 5 minutes (frames= is the number of frames in which Fu.GetNearbyHeroes looked at a hero), and
-- "... differs" names an answer that was not the same. One of those is a change inside a frame (a buyback, say) and
-- costs nothing. When 3 or more differ and they are 2% of the checks of a 5-minute window, the engine does not hold
-- still within a frame: the reuse turns itself off for the rest of the game (on=false), and every hero is checked
-- on every call, as before.
local FrameCache = {}

local CHECK_EVERY = 64
-- Off when this many checked answers of a window differ and they are 1 in MISMATCH_SHARE of its checks or more.
local MIN_MISMATCHES = 3
local MISMATCH_SHARE = 50
local MAX_DIFFER_LINES = 20 -- "differs" lines per game
local REPORT_WINDOW = 300 -- seconds of game time per [SHy-FRAMECACHE] line

-- False once the self-check switched the reuse off (or a test did). Fu.GetNearbyHeroes reads it through Listed.
FrameCache.filter = true
local reportAt = nil
local windowStart = nil
local frameAt = nil -- GameTime() of the last frame counted

local function NewStats()
	return {
		filter = 0, -- heroes Fu.GetNearbyHeroes looked at through FrameCache.Listed
		filterKept = 0, -- of them, already looked at this frame
		filterChecked = 0, -- kept answers worked out again
		filterMismatch = 0, -- of them, different
		frames = 0, -- frames in which a hero was looked at
	}
end
local stats = NewStats()
local differLines = 0

-- Off: every hero is checked on every call, as before this file.
function FrameCache.SetEnabled(on)
	FrameCache.filter = on and true or false
end
function FrameCache.IsEnabled()
	return FrameCache.filter
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
		"[SHy-FRAMECACHE] t=%.0f %s counts window=%.0fs frames=%d filter=%d filterKept=%d filterChecked=%d"
			.. " filterMismatch=%d on=%s",
		now,
		heroName,
		span,
		counts.frames,
		counts.filter,
		counts.filterKept,
		counts.filterChecked,
		counts.filterMismatch,
		tostring(on)
	)
end

-- A new frame (`now` is GameTime(): it runs with the game clock, so the window is in game seconds).
local function NewFrame(now)
	frameAt = now
	stats.frames = stats.frames + 1
	if reportAt == nil then
		reportAt = now + REPORT_WINDOW
		windowStart = now
		return
	end
	if now < reportAt then
		return
	end
	pcall(print, FrameCache.FormatReport(DotaTime(), HeroName(), now - windowStart, stats, FrameCache.filter))
	stats = NewStats()
	reportAt = now + REPORT_WINDOW
	windowStart = now
end

-- A checked answer was not the same. `checked` and `mismatch` are the window's counts.
local function NoteDifference(detail, checked, mismatch)
	if mismatch >= MIN_MISMATCHES and mismatch * MISMATCH_SHARE >= checked then
		FrameCache.filter = false
	end
	if differLines < MAX_DIFFER_LINES or not FrameCache.filter then
		differLines = differLines + 1
		pcall(
			print,
			string.format(
				"[SHy-FRAMECACHE] t=%.0f %s differs what=filter %s checked=%d mismatch=%d on=%s",
				DotaTime(),
				HeroName(),
				detail,
				checked,
				mismatch,
				tostring(FrameCache.filter)
			)
		)
	end
end

-- Whether isListed(hero) holds, asked once per hero per frame (`now` is GameTime()). Off, it is asked every time.
function FrameCache.Listed(hero, now, isListed)
	if now ~= frameAt then
		NewFrame(now)
	end
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
