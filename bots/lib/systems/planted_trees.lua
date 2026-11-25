-- Shared bot system (#7): tree spots the bot API does not list. GetNearbyTrees never listed a tree that Hoodwink's
-- Acorn Shot planted (games 064-065: 22 of 22 `[SHy-HOODWINK] planted-tree listed=false`, the nearest listed tree
-- 276-1284 away from the spot), so a temporary tree is remembered from the cast that makes it:
--   acorn   Hoodwink's Acorn Shot cast on the ground: one tree at the spot for 20s (the hero file's game data note).
--   sprout  Nature's Prophet's Sprout, cast by either team, seen through the cast callback
--           (`InstallCastCallback(-1, fn)`, enemy_spell_tracker.lua; game 082: its `location` key held the spot, 400-
--           760 from a human Furion at cast range 775). Datafeed hero_id=53 (7.42, 2026-11-26): "Sprouts a ring of
--           trees around a unit", duration 2.5/3/3.5/4s, cast range 625/700/775/850. The ring's radius is not in
--           the game data, so the cast spot itself is kept as the tree spot (an assumption:
--           `[SHy-HOODWINK] bushwhack-result netted=` on a `tree=sprout` net tells whether it holds).
-- Every bot runs in one Lua state (team_memory.lua), so this table is shared; a tree is a tree for either team.
local PlantedTrees = {}

PlantedTrees.SPROUT_DURATION = { 2.5, 3, 3.5, 4 }
-- Sprout's longest cast range (850) plus room for cast-range items and talents and for a unit target that walked.
PlantedTrees.SPROUT_MAX_REACH = 850 + 400
PlantedTrees.ACORN_DURATION = 20

local spots = {} -- { kind, location, plantedAt, expiresAt, team }
local installed = false

-- Sprout's duration at an ability level; the cast callback's handle often reads level -1
-- (docs/BOT_API_RUNTIME.md), so anything but 1-4 gives the shortest one.
function PlantedTrees.SproutDuration(level)
	local durations = PlantedTrees.SPROUT_DURATION
	if type(level) == "number" and level >= 1 and level <= #durations then
		return durations[math.floor(level)]
	end
	return durations[1]
end

-- Is a reported cast spot a real place? nil when it is, else the reason it is not: no-location (nil or not a
-- vector), origin (0,0: an unset vector), far (beyond maxReach from the caster, when the caster's spot is known).
function PlantedTrees.SpotProblem(spot, casterLocation, maxReach)
	if spot == nil then
		return "no-location"
	end
	local ok, x, y = pcall(function()
		return spot.x, spot.y
	end)
	if not ok or type(x) ~= "number" or type(y) ~= "number" then
		return "no-location"
	end
	if math.abs(x) < 1 and math.abs(y) < 1 then
		return "origin"
	end
	if casterLocation ~= nil and maxReach ~= nil then
		local dx, dy = x - casterLocation.x, y - casterLocation.y
		if dx * dx + dy * dy > maxReach * maxReach then
			return "far"
		end
	end
	return nil
end

local function Prune(now)
	for i = #spots, 1, -1 do
		if spots[i].expiresAt < now then
			table.remove(spots, i)
		end
	end
end

function PlantedTrees.Add(kind, location, now, duration, team)
	Prune(now)
	local spot = { kind = kind, location = location, plantedAt = now, expiresAt = now + duration, team = team }
	spots[#spots + 1] = spot
	return spot
end

-- Remembered tree spots within maxDist of a location that still stand at time standingAt (>= now).
function PlantedTrees.Near(location, maxDist, now, standingAt)
	Prune(now)
	local found = {}
	local maxDistSqr = maxDist * maxDist
	for _, spot in ipairs(spots) do
		local dx, dy = spot.location.x - location.x, spot.location.y - location.y
		if spot.expiresAt >= (standingAt or now) and dx * dx + dy * dy <= maxDistSqr then
			found[#found + 1] = spot
		end
	end
	return found
end

-- Every remembered spot still standing (the probe in hero_hoodwink.lua reads and marks them).
function PlantedTrees.All(now)
	Prune(now)
	return spots
end

function PlantedTrees.Clear()
	spots = {}
end

-- The cast listener: a Sprout, from either team, is remembered at its cast spot.
-- cast: { spell, caster, heroName, team, ability, location } (enemy_spell_tracker.lua).
function PlantedTrees.OnCast(cast)
	if cast == nil or cast.spell ~= "furion_sprout" then
		return
	end
	local now = DotaTime()
	local casterLocation = nil
	if cast.caster ~= nil then
		local ok, location = pcall(function()
			return cast.caster:GetLocation()
		end)
		casterLocation = ok and location or nil
	end
	local level = nil
	if cast.ability ~= nil and type(cast.ability) ~= "string" then
		local ok, read = pcall(function()
			return cast.ability:GetLevel()
		end)
		level = ok and read or nil
	end
	local problem = PlantedTrees.SpotProblem(cast.location, casterLocation, PlantedTrees.SPROUT_MAX_REACH)
	local duration = PlantedTrees.SproutDuration(level)
	local fromCaster = -1
	if problem == nil and casterLocation ~= nil then
		local dx, dy = cast.location.x - casterLocation.x, cast.location.y - casterLocation.y
		fromCaster = math.sqrt(dx * dx + dy * dy)
	end
	if problem == nil then
		PlantedTrees.Add("sprout", cast.location, now, duration, cast.team)
	end
	pcall(
		print,
		string.format(
			"[SHy-TREES] t=%.0f %s sprout kept=%s why=%s team=%s level=%s dur=%.1f fromCaster=%d at=%s",
			now,
			(string.gsub(tostring(cast.heroName), "npc_dota_hero_", "")),
			tostring(problem == nil),
			problem or "ok",
			tostring(cast.team),
			tostring(level),
			duration,
			math.floor(fromCaster),
			problem == nil and string.format("%d,%d", math.floor(cast.location.x), math.floor(cast.location.y)) or "-"
		)
	)
end

-- Starts listening to casts (one cast callback for the whole Lua state, through enemy_spell_tracker.lua).
function PlantedTrees.Install()
	if installed then
		return
	end
	installed = true
	local ok, EnemySpells = pcall(require, GetScriptDirectory() .. "/lib/systems/enemy_spell_tracker")
	if ok and EnemySpells ~= nil and EnemySpells.AddCastListener ~= nil then
		EnemySpells.AddCastListener(PlantedTrees.OnCast)
	end
end

return PlantedTrees
