-- Bot chat rules (#182): decision lines only with `!debug`, and the welcome's version line.
-- Pure functions (plain values in) except SayDecision, so Tests/test_chat_rules.lua can run them.
local ChatRules = {}

-- Seconds between two [OHA-CHAT] decision lines of one bot.
ChatRules.LOG_GAP = 10

-- Is the `!debug` chat mode on? The team chat command (`!debug` / `!verbose`, ability_item_usage_generic.lua
-- Usage.SetReplyHumanTime) sets Utils.DebugMode and Utils.GameStates.verboseChat; mode_ward_generic.lua reads the
-- same two flags for its ward-coordinates line.
function ChatRules.IsDebugChat(utils)
	if type(utils) ~= "table" then
		return false
	end
	return utils.DebugMode == true or (type(utils.GameStates) == "table" and utils.GameStates.verboseChat == true)
end

-- A decision line ("Going for X", "Harassing X", "Pushing top", "Defend mid", lotus / wisdom shrine, leaving farm):
-- said in team chat only while `!debug` is on. "make bots less chatty ... belong to `!debug`" (maintainer,
-- 2026-11-23). Returns true when it was said. [OHA-CHAT] decision key= said=yes|no, at most once per LOG_GAP per bot.
function ChatRules.SayDecision(bot, text, key)
	if bot == nil or text == nil then
		return false
	end
	local utilsOk, utils = pcall(require, GetScriptDirectory() .. "/FuncLib/systems/utils")
	local on = utilsOk and ChatRules.IsDebugChat(utils)
	if on then
		bot:ActionImmediate_Chat(text, false)
	end
	local now = DotaTime()
	if now >= (bot._decisionChatLogAt or -999) then
		bot._decisionChatLogAt = now + ChatRules.LOG_GAP
		pcall(
			print,
			string.format(
				"[OHA-CHAT] t=%.0f %s decision key=%s said=%s",
				now,
				(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
				tostring(key),
				on and "yes" or "no"
			)
		)
	end
	return on
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "2026.11.22", "2026.11.22-222" or "2026.11.23-f82a8ea+dirty" -> "22 Nov 2026"; nil without a date.
function ChatRules.FormatDate(number)
	if type(number) ~= "string" then
		return nil
	end
	local year, month, day = number:match("^(%d%d%d%d)%.(%d%d)%.(%d%d)")
	local monthName = MONTHS[tonumber(month or "")]
	if year == nil or monthName == nil then
		return nil
	end
	return string.format("%d %s %s", tonumber(day), monthName, year)
end

-- The welcome's version and date from the Customize/version.lua table. A git build (Customize/build_info.lua
-- present: `commit` is set) shows "dev <commit date>-<sha>" and the commit date; a Workshop copy shows the release
-- (`release`, e.g. "v0.4") and the date of its release number (`releaseNumber`, "YYYY.MM.DD-NNN").
function ChatRules.WelcomeVersion(version)
	if type(version) ~= "table" then
		return "?", "?"
	end
	if version.commit ~= nil then
		local number = tostring(version.number or "?")
		return "dev " .. number, ChatRules.FormatDate(number) or "?"
	end
	local releaseNumber = version.releaseNumber or version.number
	return tostring(version.release or releaseNumber or "?"), ChatRules.FormatDate(releaseNumber) or "?"
end

-- Fills "{version}" and "{date}" in a welcome line; other text is kept as it is.
function ChatRules.FillWelcomeLine(line, versionText, dateText)
	local filled = string.gsub(tostring(line), "{(%a+)}", function(name)
		if name == "version" then
			return versionText
		elseif name == "date" then
			return dateText
		end
		return nil
	end)
	return filled
end

return ChatRules
