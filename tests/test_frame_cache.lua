-- bots/lib/systems/frame_cache.lua (#52): the engine is asked once per frame for the same nearby-hero question, every
-- caller still gets a list of its own, and nothing is kept past the frame. A frame is one GameTime() value, so a case
-- that moves a unit and wants to see it moves the clock too. Every piece is on here, as it is when nothing switches
-- them (tests/test_perf_ab.lua has the switching).
local T = ...
local Stub = T.stub
local FRAME = 1 / 30

-- A Radiant bot with the other four Radiant heroes within 500 and no enemy hero near. `calls.n` counts the engine's
-- GetNearbyHeroes calls, below the wrapper in global_overrides.lua.
local function setup()
	local bot = Stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local calls = { n = 0 }
	local engine = CDOTA_Bot_Script.GetNearbyHeroes
	CDOTA_Bot_Script.GetNearbyHeroes = function(...)
		calls.n = calls.n + 1
		return engine(...)
	end
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local FrameCache = require(GetScriptDirectory() .. "/lib/systems/frame_cache")
	return bot, Fu, FrameCache, calls
end

local function sameHeroes(a, b, what)
	T.eq(#a, #b, what .. ": length")
	for i = 1, #a do
		T.ok(a[i] == b[i], what .. ": hero " .. i)
	end
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

T.test("frame cache: one engine call per frame for the same question, a table of its own for every caller", function()
	local bot, _, _, calls = setup()
	local first = bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	local second = bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	T.eq(calls.n, 1, "engine calls")
	T.eq(#first, 5, "the five Radiant heroes")
	T.ok(first ~= second, "two callers, two tables")
	sameHeroes(first, second, "second caller")
	-- A caller that changes its list (Fu.GetAroundBotUnitList appends creeps, #121) changes nobody else's.
	table.insert(first, "a creep")
	table.remove(second, 1)
	local third = bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	T.eq(#third, 5, "the next caller still gets the engine's list")
	T.eq(calls.n, 1, "still one engine call")
end)

T.test("frame cache: nothing is kept past the frame", function()
	local bot, _, _, calls = setup()
	local enemy = Stub.teams[TEAM_DIRE][1]
	T.eq(#bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE), 0, "no enemy near")
	enemy._loc = bot:GetLocation() + Vector(300, 0, 0)
	T.eq(#bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE), 0, "same frame: the same answer")
	T.eq(calls.n, 1, "one engine call in the frame")
	Stub.time = Stub.time + FRAME
	local seen = bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	T.eq(#seen, 1, "next frame: the enemy that walked in")
	T.ok(seen[1] == enemy, "that enemy")
	T.eq(calls.n, 2, "asked again in the new frame")
end)

T.test("frame cache: another unit, radius, flag or mode is another question; radii above 1600 are one", function()
	local bot, _, _, calls = setup()
	bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1000, true, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1200, true, BOT_MODE_ATTACK)
	bot:GetNearbyHeroes(1200, true)
	bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	GetTeamMember(2):GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	T.eq(calls.n, 7, "seven questions")
	bot:GetNearbyHeroes(2000, true, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1601, true, BOT_MODE_NONE)
	T.eq(calls.n, 7, "the engine caps the radius at 1600: the 1600 answer")
	for _ = 1, 3 do
		bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
		bot:GetNearbyHeroes(1200, true, BOT_MODE_ATTACK)
		bot:GetNearbyHeroes(1200, true)
	end
	T.eq(calls.n, 7, "each of them kept")
end)

T.test("frame cache: no answer (a unit that cannot be seen) is kept as no answer, not as an empty list", function()
	local bot, _, _, calls = setup()
	local enemy = Stub.teams[TEAM_DIRE][1]
	local asked = 0
	enemy.CanBeSeen = function()
		asked = asked + 1
		return false
	end
	T.eq(enemy:GetNearbyHeroes(900, true, BOT_MODE_NONE), nil, "unseen unit")
	T.eq(enemy:GetNearbyHeroes(900, true, BOT_MODE_NONE), nil, "again")
	T.eq(asked, 1, "the unit was looked at once")
	T.eq(calls.n, 0, "and the engine was not asked for its heroes")
	local empty = bot:GetNearbyHeroes(900, true, BOT_MODE_NONE)
	T.eq(type(empty), "table", "an empty list is a list")
	T.eq(#empty, 0, "with nobody in it")
	T.eq(type(bot:GetNearbyHeroes(900, true, BOT_MODE_NONE)), "table", "also when kept")
end)

T.test("frame cache: arguments that are not plain go to the engine every time", function()
	local bot, _, _, calls = setup()
	for _ = 1, 2 do
		bot:GetNearbyHeroes(1200, 1, BOT_MODE_NONE)
		bot:GetNearbyHeroes(1200, true, 0.5)
		bot:GetNearbyHeroes(0 / 0, true, BOT_MODE_NONE)
		bot:GetNearbyHeroes(1200, true, "0")
	end
	T.eq(calls.n, 8, "nothing kept")
end)

T.test("frame cache: a unit with a GetNearbyHeroes of its own (a test double) answers for itself", function()
	local bot, Fu, _, calls = setup()
	local ally = GetTeamMember(2)
	function bot:GetNearbyHeroes()
		return { ally }
	end
	local heroes = Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
	T.eq(#heroes, 1, "the double's list")
	T.ok(heroes[1] == ally, "its hero")
	T.eq(calls.n, 0, "the engine was not asked")
end)

T.test("Fu.GetNearbyHeroes: a new table per call from one engine call, shared with direct callers", function()
	local bot, Fu, _, calls = setup()
	local first = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	local second = Fu.GetNearbyHeroes(bot, 1200, false)
	T.ok(first ~= second, "two tables")
	sameHeroes(first, second, "second call (no mode means BOT_MODE_NONE)")
	local direct = bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	sameHeroes(first, direct, "direct caller")
	T.eq(calls.n, 1, "one engine call for all three")
end)

T.test("Fu.GetAroundBotUnitList appends its creeps to a list of its own (#121)", function()
	local bot, Fu = setup()
	local creeps = {
		Stub.newUnit({ name = "npc_dota_creep_goodguys_melee", team = TEAM_RADIANT }),
		Stub.newUnit({ name = "npc_dota_creep_goodguys_ranged", team = TEAM_RADIANT }),
	}
	bot.GetNearbyCreeps = function()
		return { creeps[1], creeps[2] }
	end
	local before = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	T.eq(#before, 5, "five heroes")
	T.eq(#Fu.GetAroundBotUnitList(bot, 1200, false), 7, "heroes and creeps")
	T.eq(#Fu.GetAroundBotUnitList(bot, 1200, false), 7, "the same the second time")
	T.eq(#Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), 5, "no creep in the hero list of the same frame")
	T.eq(#bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE), 5, "nor in a direct caller's")
end)

T.test("Fu.GetNearbyHeroes: each hero is checked once per frame, and again in the next", function()
	local bot, Fu = setup()
	local ally = GetTeamMember(2)
	local asked, invulnerable = 0, true
	ally.IsInvulnerable = function()
		asked = asked + 1
		return invulnerable
	end
	local function listed(radius)
		for _, hero in ipairs(Fu.GetNearbyHeroes(bot, radius, false, BOT_MODE_NONE)) do
			if hero == ally then
				return true
			end
		end
		return false
	end
	T.eq(listed(1200), false, "an invulnerable hero is left out")
	local afterFirst = asked
	T.ok(afterFirst >= 1, "it was checked")
	T.eq(listed(1200), false, "same frame, same question")
	T.eq(listed(1000), false, "same frame, another radius")
	T.eq(asked, afterFirst, "not checked again in the frame")
	invulnerable = false
	T.eq(listed(1200), false, "the frame's answer stands until the frame ends")
	Stub.time = Stub.time + FRAME
	T.eq(listed(1200), true, "next frame: vulnerable again, listed again")
	T.ok(asked > afterFirst, "checked again in the new frame")
end)

T.test("Fu.GetNearbyHeroes: a hero's kept place in the filter is checked again now and then", function()
	local bot, Fu, FrameCache = setup()
	-- Five heroes per call, in team-slot order: the 64th kept answer is the fourth hero of the 14th call.
	local ally = GetTeamMember(4)
	local invulnerable = false
	ally.IsInvulnerable = function()
		return invulnerable
	end
	T.eq(#Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), 5, "all five listed")
	-- Not possible in a game: the hero turns invulnerable inside the frame.
	invulnerable = true
	for _ = 1, 12 do
		T.eq(#Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), 5, "the frame's answer stands")
	end
	T.eq(#printedWith(" differs "), 0, "nothing noticed yet")
	T.eq(#Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), 4, "the check takes the new answer")
	local lines = printedWith(" differs ")
	T.eq(#lines, 1, "one line")
	T.ok(
		string.find(lines[1], " lich differs what=filter kept=true now=false checked=1 mismatch=1 on=true", 1, true),
		lines[1]
	)
	T.eq(FrameCache.IsEnabled(), true, "one difference leaves the cache on")
end)

T.test("frame cache off: every call goes to the engine and gives the same lists", function()
	local bot, Fu, FrameCache, calls = setup()
	local kept = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	FrameCache.SetEnabled(false)
	T.eq(FrameCache.IsEnabled(), false, "off")
	local before = calls.n
	sameHeroes(kept, Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), "Fu, cache off")
	sameHeroes(kept, bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE), "direct, cache off")
	T.eq(calls.n, before + 2, "two engine calls")
end)

T.test("frame cache: an engine that answers differently within a frame switches the cache off", function()
	local bot = Stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local extra = Stub.teams[TEAM_DIRE][1]
	local calls = 0
	local engine = CDOTA_Bot_Script.GetNearbyHeroes
	-- Every second engine call lists one more hero: not a stable engine.
	CDOTA_Bot_Script.GetNearbyHeroes = function(...)
		calls = calls + 1
		local list = engine(...)
		if calls % 2 == 0 then
			list[#list + 1] = extra
		end
		return list
	end
	require(GetScriptDirectory() .. "/lib/func_utils")
	local FrameCache = require(GetScriptDirectory() .. "/lib/systems/frame_cache")
	-- The first call asks the engine; every 64th kept answer is asked again. The third difference ends it.
	for _ = 1, 1 + 64 * 3 do
		bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	end
	T.eq(calls, 4, "one question and three checks")
	T.eq(FrameCache.IsEnabled(), false, "switched off")
	local lines = printedWith("[SHy-FRAMECACHE]")
	T.eq(#lines, 3, "one line per difference")
	T.ok(
		string.find(
			lines[1],
			" lich differs what=list radius=1200 enemy=true mode=0 kept=0 now=1 checked=1 mismatch=1 on=true",
			1,
			true
		),
		lines[1]
	)
	T.ok(string.find(lines[3], " checked=3 mismatch=3 on=false", 1, true), lines[3])
	bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	T.eq(calls, 6, "off: every call is an engine call again")
	T.eq(FrameCache.lists, false, "no piece is on any more: lists")
	T.eq(FrameCache.filter, false, "filter")
	T.eq(FrameCache.turbo, false, "turbo")
	FrameCache.SetPieces(true, true, true)
	T.eq(FrameCache.lists, false, "and asking for them does not bring them back")
	-- The counts line keeps printing, and says the cache is off: the timer of the entry points tells every new frame.
	Stub.time = Stub.time + 301
	FrameCache.BeginFrame(GameTime())
	local counts = printedWith(" counts ")
	T.eq(#counts, 1, "one counts line after 5 minutes")
	T.ok(string.find(counts[1], " checked=3 mismatch=3 ", 1, true), counts[1])
	T.ok(string.find(counts[1], " on=false", 1, true), counts[1])
end)

T.test("frame cache: one change inside a frame is logged and the cache stays on", function()
	local bot = Stub.reset({ hero = "npc_dota_hero_lich", time = 600 })
	local extra = Stub.teams[TEAM_DIRE][1]
	local calls = 0
	local engine = CDOTA_Bot_Script.GetNearbyHeroes
	-- Only the second engine call lists one more hero (a hero that bought back inside the frame, say).
	CDOTA_Bot_Script.GetNearbyHeroes = function(...)
		calls = calls + 1
		local list = engine(...)
		if calls == 2 then
			list[#list + 1] = extra
		end
		return list
	end
	require(GetScriptDirectory() .. "/lib/func_utils")
	local FrameCache = require(GetScriptDirectory() .. "/lib/systems/frame_cache")
	local last
	for _ = 1, 1 + 64 * 5 do
		last = bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	end
	T.eq(calls, 6, "one question and five checks")
	-- The check that saw the extra hero and the next one, which no longer saw him.
	T.eq(#printedWith(" differs "), 2, "two differences in five checks")
	T.eq(FrameCache.IsEnabled(), true, "still on")
	T.eq(#last, 0, "and the answer is the engine's latest")
end)

T.test("frame cache: the [SHy-FRAMECACHE] line, every 5 minutes of game time", function()
	local bot, Fu, FrameCache = setup()
	T.eq(
		FrameCache.FormatReport(900, "lich", 300, {
			nearby = 1200,
			kept = 800,
			uncached = 3,
			checked = 12,
			mismatch = 0,
			filter = 2500,
			filterKept = 2100,
			filterChecked = 32,
			filterMismatch = 0,
			frames = 9000,
		}, true),
		"[SHy-FRAMECACHE] t=900 lich counts window=300s frames=9000 nearby=1200 kept=800 uncached=3 checked=12 mismatch=0"
			.. " filter=2500 filterKept=2100 filterChecked=32 filterMismatch=0 on=true",
		"the line"
	)
	-- One question, two kept answers, five heroes checked once and kept twice.
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	bot:GetNearbyHeroes(1200, 1, BOT_MODE_NONE)
	T.eq(#printedWith("[SHy-FRAMECACHE]"), 0, "quiet inside the window")
	Stub.time = Stub.time + 301
	bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE)
	local lines = printedWith("[SHy-FRAMECACHE]")
	T.eq(#lines, 1, "one line after 5 minutes")
	T.ok(
		string.find(
			lines[1],
			" nearby=4 kept=2 uncached=1 checked=0 mismatch=0 filter=10 filterKept=5 filterChecked=0 filterMismatch=0 on=true",
			1,
			true
		),
		lines[1]
	)
end)

T.test("frame cache: frames= counts the frames the timer of the entry points told", function()
	local bot, _, FrameCache = setup()
	bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)
	for _ = 1, 3 do
		Stub.time = Stub.time + FRAME
		FrameCache.BeginFrame(GameTime())
	end
	T.eq(#printedWith("[SHy-FRAMECACHE]"), 0, "quiet inside the window")
	Stub.time = Stub.time + 301
	FrameCache.BeginFrame(GameTime())
	local lines = printedWith("[SHy-FRAMECACHE]")
	T.eq(#lines, 1, "one line")
	T.ok(string.find(lines[1], " lich counts window=301s frames=4 nearby=1 kept=0 ", 1, true), lines[1])
end)

-- Counts GetUnitList calls by list type; `allies`, when given, is what UNIT_LIST_ALLIES answers.
local function countUnitLists(allies)
	local stubList = GetUnitList
	local calls = {}
	GetUnitList = function(listType)
		calls[listType] = (calls[listType] or 0) + 1
		if listType == UNIT_LIST_ALLIES and allies ~= nil then
			return allies
		end
		return stubList(listType)
	end
	return calls
end

T.test("IsModeTurbo (Fu and Utils): the allied units are read once per frame", function()
	local _, Fu = setup()
	local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
	local courier = Stub.newUnit({ name = "npc_dota_courier", team = TEAM_RADIANT, hero = false })
	local speed = 380
	courier.GetCurrentMovementSpeed = function()
		return speed
	end
	local calls = countUnitLists({ GetTeamMember(1), courier })
	for _ = 1, 3 do
		T.eq(Fu.IsModeTurbo(), false, "Fu: a courier at 380 is not Turbo")
		T.eq(Utils.IsModeTurbo(), false, "Utils: the same")
	end
	T.eq(calls[UNIT_LIST_ALLIES], 2, "one read each for the frame")
	speed = 1100
	T.eq(Fu.IsModeTurbo(), false, "Fu: the frame's answer stands")
	T.eq(Utils.IsModeTurbo(), false, "Utils: the frame's answer stands")
	Stub.time = Stub.time + FRAME
	T.eq(Fu.IsModeTurbo(), true, "Fu: next frame, a courier at 1100 is Turbo")
	T.eq(Utils.IsModeTurbo(), true, "Utils: the same")
	T.eq(Fu.IsModeTurbo(), true, "Fu: kept")
	T.eq(calls[UNIT_LIST_ALLIES], 4, "one more read each in the new frame")
end)
