-- `!about` chat command (#215): one bot per team says the script name, the version and where to send feedback.
-- Pure rules (plain values in, no bot API), so Tests/test_about_rules.lua can run them.
-- Flow: a chat callback (hero_selection.lua before the horn, the team's reply bot in ability_item_usage_generic.lua
-- after it) calls Note() with the shared Role table; the team's first bot (GetTeamPlayers order) calls Decide()
-- from its buyback think, which also runs while the hero is dead, and says Line().
local AboutRules = {}

-- At most one answer per team in this many seconds. ChatGuard (FuncLib/systems/chat_guard.lua) drops the same chat
-- text of a team for 30s anyway, so a shorter window would only log answers nobody sees.
AboutRules.WINDOW = 30
-- A request nobody answered within this many seconds is dropped (typed during the draft, before any hero exists).
AboutRules.STALE = 15

function AboutRules.IsCommand(text)
	if type(text) ~= "string" then
		return false
	end
	return string.lower(text):match("^%s*(.-)%s*$") == "!about"
end

-- Does this chat line ask this team's bots? Humans only; team chat only from an ally (all chat: both teams answer).
function AboutRules.Accepts(text, senderIsBot, teamOnly, senderIsAlly)
	if senderIsBot or not AboutRules.IsCommand(text) then
		return false
	end
	return not teamOnly or senderIsAlly == true
end

-- Records a request on the shared table (Role). Returns true when it was recorded.
function AboutRules.Note(shared, text, senderIsBot, teamOnly, senderIsAlly, now)
	if shared == nil or not AboutRules.Accepts(text, senderIsBot, teamOnly, senderIsAlly) then
		return false
	end
	shared.AboutRequest = { at = now, allChat = not teamOnly }
	return true
end

-- The team's answering bot: the first bot player ID in team order (nil when the team has no bot).
function AboutRules.FirstBotId(playerIds, isBot)
	for _, playerId in ipairs(playerIds or {}) do
		if isBot(playerId) then
			return playerId
		end
	end
	return nil
end

-- What the answering bot does with the shared request at `now`: "none" (nothing to do), "stale", "throttled" or
-- "answer", and the request. Every result but "none" consumes it, so one request gives at most one answer or log line.
function AboutRules.Decide(shared, now)
	local request = shared and shared.AboutRequest
	if request == nil then
		return "none"
	end
	shared.AboutRequest = nil
	if now - request.at > AboutRules.STALE then
		return "stale", request
	end
	local last = shared.AboutAnsweredAt
	if last ~= nil and now >= last and now - last < AboutRules.WINDOW then
		return "throttled", request
	end
	shared.AboutAnsweredAt = now
	return "answer", request
end

-- The version the game prints in [OHA-BUILD]: Customize/version.lua's number, which is build_info.lua's
-- "<commit date>-<sha>[+dirty]" in a git clone and the static release number in a Workshop copy.
function AboutRules.VersionOf(versionModule)
	if type(versionModule) == "table" and versionModule.number ~= nil then
		return tostring(versionModule.number)
	end
	return "unknown"
end

-- The chat line: the localized template with "%s" for the version.
function AboutRules.Line(template, version)
	local versionText = tostring(version or "unknown")
	if type(template) ~= "string" or not template:find("%s", 1, true) then
		return "Supercharged OpenHyperAI by anggara-ts, version " .. versionText .. "."
	end
	return (template:gsub("%%s", function()
		return versionText
	end, 1))
end

return AboutRules
