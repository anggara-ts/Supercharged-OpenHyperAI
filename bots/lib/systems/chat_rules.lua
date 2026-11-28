-- Bot chat rules (#182): decision lines only with `!chatty`, and the welcome's version line.
-- Pure functions (plain values in) except SayDecision, so tests/test_chat_rules.lua can run them.
local ChatRules = {}

-- Seconds between two [SHy-CHAT] decision lines of one bot.
ChatRules.LOG_GAP = 10

-- Is the old debug mode on (Utils.DebugMode or Utils.GameStates.verboseChat)? Nothing switches it on any more: the
-- `!debug` / `!verbose` chat commands were removed (maintainer, 2026-11-24: "i dont think we need !debug anymore, we
-- have logger anyway"). Kept for code that still reads it; it never turns the decision chat on.
function ChatRules.IsDebugChat(utils)
	if type(utils) ~= "table" then
		return false
	end
	return utils.DebugMode == true or (type(utils.GameStates) == "table" and utils.GameStates.verboseChat == true)
end

-- Is the team's `!chatty` mode on (the heroes' decision chat)? The team chat command `!chatty` toggles
-- Utils.GameStates.chattyChat (maintainer, 2026-11-24: "chatty is for hero chat when doing actions").
function ChatRules.IsChattyChat(utils)
	return type(utils) == "table" and type(utils.GameStates) == "table" and utils.GameStates.chattyChat == true
end

-- A decision line ("Going for X", "Harassing X", "Pushing top", "Defend mid", lotus / wisdom shrine, leaving farm):
-- said in team chat only while `!chatty` is on ("make bots less chatty ... belong to `!debug`", maintainer
-- 2026-11-23; moved from the removed `!debug` to `!chatty` on 2026-11-24). Returns true when it was said. [SHy-CHAT] decision key= said=yes|no, at most once per LOG_GAP per bot.
function ChatRules.SayDecision(bot, text, key)
	if bot == nil or text == nil then
		return false
	end
	local utilsOk, utils = pcall(require, GetScriptDirectory() .. "/lib/systems/utils")
	local on = utilsOk and ChatRules.IsChattyChat(utils)
	if on then
		bot:ActionImmediate_Chat(text, false)
	end
	local now = DotaTime()
	if now >= (bot._decisionChatLogAt or -999) then
		bot._decisionChatLogAt = now + ChatRules.LOG_GAP
		pcall(
			print,
			string.format(
				"[SHy-CHAT] t=%.0f %s decision key=%s said=%s",
				now,
				(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
				tostring(key),
				on and "yes" or "no"
			)
		)
	end
	return on
end

-- Fallback welcome clock when no position line was said (1v1 mid, or the lines never went out): -1:00.
-- Maintainer 2026-11-24: welcome after the position lines, at -1:00. Maintainer 2026-11-28: 30 seconds after the
-- position lines, then how to switch language, the version, the update date, a 5 second pause, and the two
-- Workshop lines.
ChatRules.WELCOME_START = -60
-- Seconds after the team's first "I play position N" line before the first welcome line.
ChatRules.WELCOME_AFTER_POS = 30
-- Seconds to wait after the previous welcome line before saying this one. Line 1 waits WELCOME_AFTER_POS instead.
-- A pair waits 0.5s: the language hint and the !sp line, the version and the date, the changelog and the
-- Workshop page (maintainer 2026-11-28). The !sp line and the version stay 2s apart. The 5 is the pause
-- before the Workshop pair.
ChatRules.WELCOME_GAPS = { 0, 0.5, 2, 0.5, 5, 0.5 }

function ChatRules.WelcomeGap(lineIndex)
	local gap = ChatRules.WELCOME_GAPS[lineIndex]
	if type(gap) ~= "number" then
		return 2
	end
	return gap
end

-- When the version line may start. posSaidAt is the team's first position line (DotaTime), or nil.
function ChatRules.WelcomeStart(posSaidAt)
	if type(posSaidAt) == "number" then
		return posSaidAt + ChatRules.WELCOME_AFTER_POS
	end
	return ChatRules.WELCOME_START
end
-- Whether the first position line waits for the welcome's version line (maintainer 2026-11-23: version first). Off
-- since the welcome moved after them (2026-11-24): the position lines go out at once, the welcome comes later on its own.
ChatRules.POSITION_WAITS_FOR_WELCOME = false
-- The first position line waits at most this many seconds for the team's welcome version line, counted from the
-- welcome's start (or from the bot's first try, when that is later), so a missing welcome never blocks it.
ChatRules.WELCOME_FIRST_WAIT = 5

-- Does a bot's first "I will play position N" still wait for the welcome? "print the bot version at the beginning of
-- the game before ally bot state their position" (maintainer, 2026-11-23). versionSaid: the team's welcome version
-- line was said; firstTryAt: when the bot first wanted to say its line; welcomeStart and now: DotaTime(). Returns
-- true while it waits, else false and why it stopped waiting: "welcome" or "timeout".
function ChatRules.PositionLineWaits(versionSaid, firstTryAt, welcomeStart, now)
	if not ChatRules.POSITION_WAITS_FOR_WELCOME then
		return false, "off"
	end
	if versionSaid then
		return false, "welcome"
	end
	if now >= math.max(welcomeStart, firstTryAt) + ChatRules.WELCOME_FIRST_WAIT then
		return false, "timeout"
	end
	return true, nil
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "2026.11.22", "2026.11.22-222" or "2026.11.23-f82a8ea+dirty" -> "22-Nov-2026"; nil without a date.
function ChatRules.FormatDate(number)
	if type(number) ~= "string" then
		return nil
	end
	local year, month, day = number:match("^(%d%d%d%d)%.(%d%d)%.(%d%d)")
	local monthName = MONTHS[tonumber(month or "")]
	if year == nil or monthName == nil then
		return nil
	end
	return string.format("%d-%s-%s", tonumber(day), monthName, year)
end

-- The welcome's version and date from the bots/customize/version.lua table. A git build (bots/customize/build_info.lua
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

-- Does a bot answer a chat line with small talk / trash talk (Fu.Chat.GetReplyString)? Only an enemy human's all chat
-- (maintainer, game 080: "sending team chat make them reply trashtalk to ally"; "enemy bot can reply with trashtalk
-- when human chat-all"). A bot's line, team chat and an ally's all chat get none: false and why (bot / ally).
-- Commands and their replies are handled before this.
ChatRules.SMALLTALK_SKIP_LOG_GAP = 30
function ChatRules.SmallTalkReply(senderIsBot, teamOnly, senderIsEnemy)
	if senderIsBot then
		return false, "bot"
	end
	if teamOnly or not senderIsEnemy then
		return false, "ally"
	end
	return true, nil
end

return ChatRules
