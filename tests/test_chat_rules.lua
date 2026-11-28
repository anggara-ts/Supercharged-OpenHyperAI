-- bots/lib/systems/chat_rules.lua (#182): decision chat only with `!chatty`, and the welcome's version line.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/lib/systems/chat_rules")
end

T.test("chat rules: dates read as D-Mon-YYYY", function()
	local R = load()
	T.eq(R.FormatDate("2026.11.22-222"), "22-Nov-2026")
	T.eq(R.FormatDate("2026.11.03-f82a8ea+dirty"), "3-Nov-2026")
	T.eq(R.FormatDate("2027.01.09"), "9-Jan-2027")
	T.eq(R.FormatDate("2026.13.01-1"), nil, "no month 13")
	T.eq(R.FormatDate("unknown"), nil)
	T.eq(R.FormatDate(nil), nil)
end)

T.test("chat rules: the welcome comes at -1:00 and the position lines don't wait for it", function()
	local R = load()
	T.eq(R.WELCOME_START, -60, "welcome at -1:00 (maintainer 2026-11-24)")
	local waits, by = R.PositionLineWaits(false, -89, R.WELCOME_START, -89)
	T.eq(waits, false, "position line goes at once")
	T.eq(by, "off")
end)

T.test("chat rules: a Workshop copy shows the release, a git build shows dev and the commit date", function()
	local R = load()
	local version, date =
		R.WelcomeVersion({ number = "2026.11.22-222", release = "v0.4", releaseNumber = "2026.11.22-222" })
	T.eq(version, "v0.4")
	T.eq(date, "22-Nov-2026")
	-- bots/customize/version.lua with build_info: number is the commit's, releaseNumber still the release's.
	version, date = R.WelcomeVersion({
		number = "2026.11.23-f82a8ea+dirty",
		release = "v0.4",
		releaseNumber = "2026.11.22-222",
		commit = "f82a8ea",
	})
	T.eq(version, "dev 2026.11.23-f82a8ea+dirty")
	T.eq(date, "23-Nov-2026")
	version, date = R.WelcomeVersion({ number = "2026.11.22-222" })
	T.eq(version, "2026.11.22-222", "no release field: the number")
	T.eq(date, "22-Nov-2026")
	version, date = R.WelcomeVersion(nil)
	T.eq(version, "?")
	T.eq(date, "?")
end)

T.test("chat rules: the shipped bots/customize/version.lua names its release", function()
	load()
	local Version = require(GetScriptDirectory() .. "/customize/version")
	T.ok(type(Version.release) == "string" and Version.release:match("^v%d+%.%d+$") ~= nil, "release is not vX.Y")
	T.ok(Version.releaseNumber ~= nil and load().FormatDate(Version.releaseNumber) ~= nil, "release number has no date")
end)

T.test("chat rules: the welcome line gets the version and the date", function()
	local R = load()
	T.eq(
		R.FillWelcomeLine("Supercharged OpenHyperAI {version}", "v0.9", "27-Nov-2026"),
		"Supercharged OpenHyperAI v0.9"
	)
	T.eq(R.FillWelcomeLine("Update: {date}", "v0.9", "27-Nov-2026"), "Update: 27-Nov-2026")
	T.eq(R.FillWelcomeLine("100% {other}", "v0.4", "d"), "100% {other}", "other text and placeholders stay")
	local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
	local lines = Localization.Get("welcome")
	T.ok(lines[1]:find("language", 1, true) or lines[1]:find("type", 1, true), "the language hint comes first")
	T.ok(lines[3]:find("{version}", 1, true) and not lines[3]:find("{date}", 1, true), "the version line")
	T.ok(lines[4]:find("{date}", 1, true), "the update line")
	T.eq(#lines, 6, "language hint, version, update, then the two Workshop lines")
	T.eq(R.WELCOME_AFTER_POS, 30, "30 seconds after the position line")
	T.eq(R.WelcomeGap(1), 0)
	T.eq(R.WelcomeGap(2), 2, "the two language lines")
	T.eq(R.WelcomeGap(5), 5, "pause before the Workshop lines")
	T.eq(R.WelcomeGap(6), 2)
	T.eq(R.WelcomeStart(-89), -59, "30 seconds after the first position line")
	T.eq(R.WelcomeStart(nil), R.WELCOME_START, "no position line: the fallback clock")
end)

T.test("chat rules: the first position line waits for the welcome's version line, not for ever", function()
	local R = load()
	-- The wait is off since 2026-11-24 (ChatRules.POSITION_WAITS_FOR_WELCOME); its rule is still tested with it on.
	R.POSITION_WAITS_FOR_WELCOME = true
	local start, wait = -80, R.WELCOME_FIRST_WAIT
	T.ok(wait > 0 and wait <= 10, "a short wait")
	-- Game 075: the bots tried at t=-89, the version line came at t=-80.
	T.eq(R.PositionLineWaits(false, -89, start, -89), true, "before the welcome starts")
	T.eq(R.PositionLineWaits(false, -89, start, start + wait - 0.1), true, "the welcome is late, still in the wait")
	local waits, by = R.PositionLineWaits(true, -89, start, start)
	T.eq(waits, false, "the version line was said")
	T.eq(by, "welcome")
	waits, by = R.PositionLineWaits(false, -89, start, start + wait)
	T.eq(waits, false, "no welcome: the line goes after the wait")
	T.eq(by, "timeout")
	-- A bot that loads after the welcome's start (e.g. at t=-30) waits from its own first try.
	T.eq(R.PositionLineWaits(false, -30, start, -30 + wait - 0.1), true, "late load, still in the wait")
	T.eq(R.PositionLineWaits(false, -30, start, -30 + wait), false, "late load, timed out")
	R.POSITION_WAITS_FOR_WELCOME = false
	-- The welcome and the bots read the same constant and the same team note.
	local laning = T.read("bots/mode_laning_generic.lua")
	T.ok(laning:find("local WELCOME_START = ChatRules.WELCOME_START", 1, true) ~= nil, "the welcome has its own start")
	T.ok(laning:find('TeamMemory.Set(team, "welcomeNext"', 1, true) ~= nil, "the welcome no longer sets welcomeNext")
	local usage = T.read("bots/ability_item_usage_generic.lua")
	T.ok(usage:find('TeamMemory.Get(GetTeam(), "welcomeNext")', 1, true) ~= nil, "the position line reads welcomeNext")
	T.ok(usage:find("welcome-first waited=", 1, true) ~= nil, "no [SHy-CHAT] welcome-first log")
end)

-- Maintainer, 2026-11-24: "chatty is for hero chat when doing actions". The old debug flags (DebugMode, verboseChat;
-- the `!debug` command that set them was removed the same day) never turn the decision chat on.
T.test("chat rules: decision lines only while !chatty is on, not with the old debug flags", function()
	local R = load()
	local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
	local said = {}
	local bot = {
		GetUnitName = function()
			return "npc_dota_hero_lich"
		end,
		ActionImmediate_Chat = function(_, text, allChat)
			said[#said + 1] = { text = text, allChat = allChat }
		end,
	}
	local oldDebug, oldStates = Utils.DebugMode, Utils.GameStates
	Utils.DebugMode = false
	Utils.GameStates = {}
	T.eq(R.IsDebugChat(Utils), false)
	T.eq(R.SayDecision(bot, "Pushing top!", "say_push_top"), false)
	T.eq(#said, 0, "said without !chatty")
	-- The old debug flags (DebugMode, verboseChat): no decision line.
	Utils.GameStates.verboseChat = true
	Utils.DebugMode = true
	T.eq(R.IsDebugChat(Utils), true, "debug on")
	T.eq(R.SayDecision(bot, "Pushing top!", "say_push_top"), false, "debug flags alone: no decision line")
	T.eq(#said, 0)
	Utils.GameStates.verboseChat, Utils.DebugMode = nil, false
	Utils.GameStates.chattyChat = true
	T.eq(R.IsChattyChat(Utils), true, "chatty on")
	T.eq(R.IsDebugChat(Utils), false, "chatty is not debug")
	T.eq(R.SayDecision(bot, "Pushing top!", "say_push_top"), true)
	T.eq(#said, 1)
	T.eq(said[1].allChat, false, "team chat")
	T.eq(R.SayDecision(bot, nil, "say_push_top"), false, "nil text")
	T.eq(R.IsChattyChat(nil), false)
	Utils.DebugMode, Utils.GameStates = oldDebug, oldStates
	T.eq(R.IsDebugChat(nil), false)
end)

-- Game 080, maintainer: "sending team chat make them reply trashtalk to ally"; "enemy bot can reply with trashtalk
-- when human chat-all".
T.test("chat rules: small talk only for an enemy human's all chat", function()
	local R = load()
	T.eq(R.SmallTalkReply(false, false, true), true, "enemy human, all chat: reply")
	T.eq(select(2, R.SmallTalkReply(false, true, false)), "ally", "ally's team chat: none")
	T.eq(R.SmallTalkReply(false, true, false), false)
	T.eq(select(2, R.SmallTalkReply(false, false, false)), "ally", "ally's all chat: none")
	T.eq(select(2, R.SmallTalkReply(true, false, true)), "bot", "a bot's line: none")
	T.eq(R.SmallTalkReply(false, nil, true), true, "team_only missing: all chat")
end)
