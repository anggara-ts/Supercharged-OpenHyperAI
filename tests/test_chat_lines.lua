-- Trash_Talk_Level 2 (the default since 2026-11-18) picks kill lines from these lists with RandomInt(1, #list)
-- (ability_item_usage_generic.lua): an empty or missing list would break the kill chat.
local T = ...
local Stub = T.stub

local KEYS = { "got_first_blood", "got_a_kill", "got_big_kill", "got_big_kill_2", "got_big_kill_3", "random_responses" }

T.test("chat: every kill-chat list has lines", function()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
	for _, key in ipairs(KEYS) do
		local lines = Localization.Get(key)
		T.ok(type(lines) == "table" and #lines > 0, key .. ": no lines")
		for i, line in ipairs(lines) do
			T.ok(type(line) == "string" and line ~= "", key .. "[" .. i .. "]: not a line")
		end
	end
end)

T.test("chat: the default level lets ally bots talk", function()
	local src = T.read("bots/customize/general.lua")
	T.ok(src:find("\nCustomize.Trash_Talk_Level = 2\n", 1, true) ~= nil, "Trash_Talk_Level default is not 2")
end)

-- Characters, not bytes: zh / ja / ru lines are multi-byte UTF-8.
local function charCount(text)
	local _, count = text:gsub("[^\128-\191]", "")
	return count
end

T.test("chat: every locale has the welcome lines, short and without links", function()
	local src = T.read("bots/lib/systems/localization.lua")
	local blocks = 0
	local lineCount = nil
	for block in src:gmatch("\t\twelcome = {\n(.-)\n\t\t},") do
		blocks = blocks + 1
		local count = 0
		for line in block:gmatch('\t\t\t"([^\n]*)",') do
			count = count + 1
			T.ok(line ~= "", "empty welcome line")
			T.ok(charCount(line) <= 120, "welcome line too long: " .. line)
			T.ok(not line:find("http", 1, true), "chat links are not clickable: " .. line)
			T.ok(not line:find("!debug", 1, true), "no !debug hint in the welcome (maintainer, 2026-11-23): " .. line)
			-- "no need to hint !pos and !Xpos Y, or language change in welcome message" (maintainer, 2026-11-23).
			T.ok(not line:find("pos", 1, true), "no !pos / !Xpos Y hint in the welcome: " .. line)
			T.ok(not line:find("!sp", 1, true), "no language (!sp) hint in the welcome: " .. line)
		end
		T.ok(block:find("{version}", 1, true) and block:find("{date}", 1, true), "a welcome without the version line")
		lineCount = lineCount or count
		T.eq(count, lineCount, "every locale has the same number of welcome lines")
	end
	T.eq(blocks, 5, "welcome lines in en, zh, ru, ja and id")
	T.eq(lineCount, 4, "version, update date, then the two Workshop lines")
	T.ok(not src:find("welcome_msgs", 1, true), "the old, never printed welcome_msgs are back")
	T.ok(not src:find("http", 1, true), "a link in chat text (links in chat are not clickable)")
end)

T.test("chat: !lang ru is a language command, and a bad code is not silent", function()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
	T.eq(Localization.LanguageCommand("!lang ru"), "ru")
	T.eq(Localization.LanguageCommand("!LANG RU"), "ru")
	T.eq(Localization.LanguageCommand("!sp zh"), "zh")
	T.eq(Localization.LanguageCommand("!speak ja"), "ja")
	T.eq(Localization.LanguageCommand("!lang"), "")
	T.eq(Localization.LanguageCommand("!pos 2"), nil)
	T.eq(Localization.Supported("id"), true, "Indonesian")
	T.eq(Localization.Supported("xx"), false)
	local TeamMemory = require(GetScriptDirectory() .. "/lib/systems/team_memory")
	T.eq(Localization.TakeLanguageCommand("!lang ru", 2), true)
	T.eq(Localization.GetLocale(), "ru")
	T.ok(
		type(TeamMemory.Get(2, "langReply")) == "string" and TeamMemory.Get(2, "langReply") ~= "",
		"a reply was queued"
	)
	T.eq(Localization.TakeLanguageCommand("!lang nope", 2), true)
	T.eq(Localization.GetLocale(), "ru", "a bad code leaves the language")
	T.eq(Localization.TakeLanguageCommand("hello", 2), false)
end)
