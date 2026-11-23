-- `!about` chat command (#215): bots/lib/systems/about_rules.lua, the version it shows and the localized lines.
local T = ...
local Stub = T.stub

local function Rules()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/lib/systems/about_rules")
end

-- Loads bots/customize/version.lua with build_info.lua present (a table) or missing (nil), as in a clone or a Workshop copy.
local function LoadVersion(buildInfo)
	Stub.reset({ hero = "npc_dota_hero_lich" })
	local infoName = GetScriptDirectory() .. "/customize/build_info"
	local versionName = GetScriptDirectory() .. "/customize/version"
	package.loaded[infoName] = nil
	package.loaded[versionName] = nil
	local oldPreload = package.preload[infoName]
	package.preload[infoName] = function()
		if buildInfo == nil then
			error("module '" .. infoName .. "' not found")
		end
		return buildInfo
	end
	local ok, version = pcall(require, versionName)
	package.preload[infoName] = oldPreload
	package.loaded[infoName] = nil
	package.loaded[versionName] = nil
	T.ok(ok, "bots/customize/version.lua failed to load: " .. tostring(version))
	return version
end

T.test("about: only the exact command matches", function()
	local About = Rules()
	T.eq(About.IsCommand("!about"), true, "!about")
	T.eq(About.IsCommand("  !ABOUT "), true, "case and spaces")
	T.eq(About.IsCommand("what is !about"), false, "a line that mentions it")
	T.eq(About.IsCommand("!about me"), false, "with an argument")
	T.eq(About.IsCommand(nil), false, "nil")
end)

T.test("about: humans only; team chat only from an ally", function()
	local About = Rules()
	T.eq(About.Accepts("!about", false, false, false), true, "enemy human in all chat")
	T.eq(About.Accepts("!about", false, true, true), true, "ally human in team chat")
	T.eq(About.Accepts("!about", false, true, false), false, "enemy team chat")
	T.eq(About.Accepts("!about", true, false, true), false, "a bot")
end)

T.test("about: one answer per request, throttled, stale requests dropped", function()
	local About = Rules()
	local shared = {}
	T.eq(About.Decide(shared, 100), "none", "no request")
	T.eq(About.Note(shared, "!about", false, true, true, 100), true, "noted")
	local result, request = About.Decide(shared, 101)
	T.eq(result, "answer", "first request")
	T.eq(request.allChat, false, "team chat request")
	T.eq(About.Decide(shared, 102), "none", "the request is consumed")
	About.Note(shared, "!about", false, false, false, 110)
	T.eq(About.Decide(shared, 110), "throttled", "again within the window")
	About.Note(shared, "!about", false, false, false, 101 + About.WINDOW)
	result, request = About.Decide(shared, 101 + About.WINDOW)
	T.eq(result, "answer", "after the window")
	T.eq(request.allChat, true, "all chat request")
	About.Note(shared, "!about", false, false, false, 500)
	T.eq(About.Decide(shared, 500 + About.STALE + 1), "stale", "typed during the draft")
	T.ok(About.WINDOW >= 10, "at most one answer per 10s")
end)

T.test("about: the first bot of the team answers", function()
	local About = Rules()
	local bots = { [7] = false, [3] = true, [9] = true }
	local isBot = function(playerId)
		return bots[playerId] == true
	end
	T.eq(About.FirstBotId({ 7, 3, 9 }, isBot), 3, "first bot after a human")
	T.eq(About.FirstBotId({ 7 }, isBot), nil, "no bot")
end)

T.test("about: the same version text as the welcome (release, or dev <number> in a git build)", function()
	local About = Rules()
	local source = T.read("bots/customize/version.lua")
	local release = source:match('release%s*=%s*"([^"]+)"')
	T.ok(release ~= nil, "no release in bots/customize/version.lua")
	T.eq(About.VersionOf(LoadVersion(nil)), release, "Workshop copy")
	local clone = { version = "2026.11.23-abc1234", commit = "abc1234def", dirty = false }
	T.eq(About.VersionOf(LoadVersion(clone)), "dev 2026.11.23-abc1234", "clone")
	local dirty = { version = "2026.11.23-abc1234", commit = "abc1234def", dirty = true }
	T.eq(About.VersionOf(LoadVersion(dirty)), "dev 2026.11.23-abc1234+dirty", "dirty")
	local ChatRules = require(GetScriptDirectory() .. "/lib/systems/chat_rules")
	local versionModule = LoadVersion(clone)
	T.eq(About.VersionOf(versionModule), (ChatRules.WelcomeVersion(versionModule)), "same as the welcome")
	T.eq(About.VersionOf(nil), "unknown", "no version module")
end)

T.test("about: every language has one line with the version and no URL", function()
	local About = Rules()
	local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
	-- The same module name localization.lua uses when GetScriptDirectory() is "bots".
	local CustomLoader = require("bots.lib.systems.custom_loader")
	local saved = CustomLoader.Localization
	for _, locale in ipairs({ "en", "zh", "ru", "ja" }) do
		CustomLoader.Localization = locale
		local template = Localization.Get("say_about")
		T.ok(type(template) == "string", locale .. ": no say_about")
		local _, count = template:gsub("%%s", "")
		T.eq(count, 1, locale .. ": %s count")
		T.ok(not template:find("http", 1, true), locale .. ": has a URL")
		local line = About.Line(template, "2026.11.23-abc1234")
		T.ok(line:find("2026.11.23-abc1234", 1, true) ~= nil, locale .. ": version missing")
		T.ok(line:find("dekampes", 1, true) ~= nil, locale .. ": author missing")
	end
	CustomLoader.Localization = saved
	T.eq(About.Line(nil, "1.0"), "Supercharged OpenHyperAI by dekampes, version 1.0.", "fallback line")
end)
