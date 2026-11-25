-- bots/lib/systems/frame_cache.lua (#52, #251): Fu.GetNearbyHeroes checks a hero once per frame, the nearby-hero lists
-- themselves are asked from the engine on every call, and nothing is kept past the frame. A frame is one GameTime()
-- value, so a case that changes a unit and wants to see it moves the clock too.
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

T.test("Fu.GetNearbyHeroes: the engine is asked on every call, and every call gets a table of its own", function()
	local bot, Fu, _, calls = setup()
	local first = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	local second = Fu.GetNearbyHeroes(bot, 1200, false)
	T.eq(#first, 5, "the five Radiant heroes")
	T.ok(first ~= second, "two tables")
	sameHeroes(first, second, "second call (no mode means BOT_MODE_NONE)")
	sameHeroes(first, bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE), "direct caller")
	T.eq(calls.n, 3, "one engine call each: the lists are not kept")
end)

T.test("Fu.GetNearbyHeroes: a hero that walks in within the frame is in the next list", function()
	local bot, Fu = setup()
	local enemy = Stub.teams[TEAM_DIRE][1]
	T.eq(#Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE), 0, "no enemy near")
	enemy._loc = bot:GetLocation() + Vector(300, 0, 0)
	local seen = Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
	T.eq(#seen, 1, "the list is the engine's latest")
	T.ok(seen[1] == enemy, "that enemy")
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
	T.eq(FrameCache.IsEnabled(), true, "one difference leaves the reuse on")
end)

T.test("frame cache off: every hero is checked on every call and the lists are the same", function()
	local bot, Fu, FrameCache = setup()
	local ally = GetTeamMember(2)
	local asked = 0
	ally.IsInvulnerable = function()
		asked = asked + 1
		return false
	end
	local kept = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	FrameCache.SetEnabled(false)
	T.eq(FrameCache.IsEnabled(), false, "off")
	local before = asked
	sameHeroes(kept, Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), "off, first call")
	local once = asked - before
	T.ok(once >= 1, "checked again in the same frame")
	sameHeroes(kept, Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE), "off, second call")
	T.eq(asked - before, 2 * once, "and on the next call too")
end)

T.test("frame cache: answers that keep changing within a frame switch the reuse off", function()
	local bot, Fu, FrameCache = setup()
	local hero = {}
	local answers = 0
	-- Not a stable engine: every check says the other thing.
	local function flipping()
		answers = answers + 1
		return answers % 2 == 1
	end
	-- The first call works it out; every 64th kept answer is worked out again. The third difference ends it.
	for _ = 1, 1 + 64 * 3 do
		FrameCache.Listed(hero, GameTime(), flipping)
	end
	T.eq(answers, 4, "one answer and three checks")
	T.eq(FrameCache.IsEnabled(), false, "switched off")
	T.eq(FrameCache.filter, false, "the field Fu.GetNearbyHeroes goes by")
	local lines = printedWith("[SHy-FRAMECACHE]")
	T.eq(#lines, 3, "one line per difference")
	T.ok(
		string.find(lines[1], " lich differs what=filter kept=true now=false checked=1 mismatch=1 on=true", 1, true),
		lines[1]
	)
	T.ok(string.find(lines[3], " checked=3 mismatch=3 on=false", 1, true), lines[3])
	FrameCache.Listed(hero, GameTime(), flipping)
	FrameCache.Listed(hero, GameTime(), flipping)
	T.eq(answers, 6, "off: every call works it out again")
	-- The counts line keeps printing, and says the reuse is off.
	Stub.time = Stub.time + 301
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	local counts = printedWith(" counts ")
	T.eq(#counts, 1, "one counts line after 5 minutes")
	T.ok(string.find(counts[1], " filterChecked=3 filterMismatch=3 on=false", 1, true), counts[1])
end)

T.test("frame cache: one change inside a frame is logged and the reuse stays on", function()
	local _, _, FrameCache = setup()
	local hero = {}
	local answers = 0
	-- Only the second answer differs (a hero that bought back inside the frame, say).
	local function once()
		answers = answers + 1
		return answers ~= 2
	end
	local last
	for _ = 1, 1 + 64 * 5 do
		last = FrameCache.Listed(hero, GameTime(), once)
	end
	T.eq(answers, 6, "one answer and five checks")
	-- The check that saw the change and the next one, which no longer saw it.
	T.eq(#printedWith(" differs "), 2, "two differences in five checks")
	T.eq(FrameCache.IsEnabled(), true, "still on")
	T.eq(last, true, "and the answer is the latest")
end)

T.test("frame cache: the [SHy-FRAMECACHE] counts line, every 5 minutes of game time", function()
	local bot, Fu, FrameCache = setup()
	T.eq(
		FrameCache.FormatReport(900, "lich", 300, {
			filter = 2500,
			filterKept = 2100,
			filterChecked = 32,
			filterMismatch = 0,
			frames = 9000,
		}, true),
		"[SHy-FRAMECACHE] t=900 lich counts window=300s frames=9000 filter=2500 filterKept=2100 filterChecked=32"
			.. " filterMismatch=0 on=true",
		"the line"
	)
	-- Five heroes checked once and kept twice, over two frames.
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	Stub.time = Stub.time + FRAME
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	T.eq(#printedWith("[SHy-FRAMECACHE]"), 0, "quiet inside the window")
	-- Only Fu.GetNearbyHeroes calls: they alone bring the line.
	Stub.time = Stub.time + 301
	Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	local lines = printedWith("[SHy-FRAMECACHE]")
	T.eq(#lines, 1, "one line after 5 minutes")
	T.ok(
		string.find(
			lines[1],
			" lich counts window=301s frames=3 filter=15 filterKept=5 filterChecked=0 filterMismatch=0 on=true",
			1,
			true
		),
		lines[1]
	)
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
