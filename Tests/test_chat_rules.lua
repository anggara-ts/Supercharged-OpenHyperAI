-- FuncLib/systems/chat_rules.lua (#182): decision chat only with `!debug`, and the welcome's version line.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/chat_rules")
end

T.test("chat rules: dates read as D Mon YYYY", function()
	local R = load()
	T.eq(R.FormatDate("2026.11.22-222"), "22 Nov 2026")
	T.eq(R.FormatDate("2026.11.03-f82a8ea+dirty"), "3 Nov 2026")
	T.eq(R.FormatDate("2027.01.09"), "9 Jan 2027")
	T.eq(R.FormatDate("2026.13.01-1"), nil, "no month 13")
	T.eq(R.FormatDate("unknown"), nil)
	T.eq(R.FormatDate(nil), nil)
end)

T.test("chat rules: a Workshop copy shows the release, a git build shows dev and the commit date", function()
	local R = load()
	local version, date =
		R.WelcomeVersion({ number = "2026.11.22-222", release = "v0.4", releaseNumber = "2026.11.22-222" })
	T.eq(version, "v0.4")
	T.eq(date, "22 Nov 2026")
	-- Customize/version.lua with build_info: number is the commit's, releaseNumber still the release's.
	version, date = R.WelcomeVersion({
		number = "2026.11.23-f82a8ea+dirty",
		release = "v0.4",
		releaseNumber = "2026.11.22-222",
		commit = "f82a8ea",
	})
	T.eq(version, "dev 2026.11.23-f82a8ea+dirty")
	T.eq(date, "23 Nov 2026")
	version, date = R.WelcomeVersion({ number = "2026.11.22-222" })
	T.eq(version, "2026.11.22-222", "no release field: the number")
	T.eq(date, "22 Nov 2026")
	version, date = R.WelcomeVersion(nil)
	T.eq(version, "?")
	T.eq(date, "?")
end)

T.test("chat rules: the shipped Customize/version.lua names its release", function()
	load()
	local Version = require(GetScriptDirectory() .. "/Customize/version")
	T.ok(type(Version.release) == "string" and Version.release:match("^v%d+%.%d+$") ~= nil, "release is not vX.Y")
	T.ok(Version.releaseNumber ~= nil and load().FormatDate(Version.releaseNumber) ~= nil, "release number has no date")
end)

T.test("chat rules: the welcome line gets the version and the date", function()
	local R = load()
	T.eq(
		R.FillWelcomeLine("Supercharged OpenHyperAI {version} (update: {date})", "v0.4", "22 Nov 2026"),
		"Supercharged OpenHyperAI v0.4 (update: 22 Nov 2026)"
	)
	T.eq(R.FillWelcomeLine("100% {other}", "v0.4", "d"), "100% {other}", "other text and placeholders stay")
	local Localization = require(GetScriptDirectory() .. "/FuncLib/systems/localization")
	local first = Localization.Get("welcome")[1]
	T.ok(first:find("{version}", 1, true) and first:find("{date}", 1, true), "the first welcome line has no version")
end)

T.test("chat rules: decision lines only while !debug is on", function()
	local R = load()
	local Utils = require(GetScriptDirectory() .. "/FuncLib/systems/utils")
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
	T.eq(#said, 0, "said without !debug")
	Utils.GameStates.verboseChat = true
	T.eq(R.SayDecision(bot, "Pushing top!", "say_push_top"), true)
	T.eq(#said, 1)
	T.eq(said[1].allChat, false, "team chat")
	Utils.GameStates.verboseChat = nil
	Utils.DebugMode = true
	T.eq(R.IsDebugChat(Utils), true)
	T.eq(R.SayDecision(bot, nil, "say_push_top"), false, "nil text")
	Utils.DebugMode, Utils.GameStates = oldDebug, oldStates
	T.eq(R.IsDebugChat(nil), false)
end)
