-- Helpers that walk the team must see all five members. In the stub, team slots are 1-5 and player IDs
-- are 10-14 (Radiant), so a loop that passes a player ID to GetTeamMember (or a slot to an API that takes
-- a player ID) errors, and a loop that skips a slot changes the answer: each case puts the deciding
-- member in slot 5.
local T = ...
local Stub = T.stub

local function setup()
	local bot = Stub.reset({ hero = "npc_dota_hero_lich", slot = 1 })
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	return bot, Fu, Fu.Utils, Fu.Site
end

T.test("GetNearbyAllyAverageHpPercent averages all five allies", function()
	local bot, _, Utils = setup()
	local ratios = { 0.9, 0.7, 0.5, 0.3, 0.1 }
	for slot = 1, 5 do
		local member = GetTeamMember(slot)
		member._loc = Vector(100 * slot, 0, 0)
		member._hp = member._maxHp * ratios[slot]
	end
	T.near(Utils.GetNearbyAllyAverageHpPercent(bot, 1000), 0.5, 1e-9, "average of 0.9 0.7 0.5 0.3 0.1")
	-- Only slot 5 out of range: the average of the first four.
	GetTeamMember(5)._loc = Vector(5000, 0, 0)
	T.near(Utils.GetNearbyAllyAverageHpPercent(bot, 1000), 0.6, 1e-9, "slots 1-4 only")
end)

T.test("IsTeamPushingSecondTierOrHighGround: nobody near the enemy base", function()
	local bot, _, Utils = setup()
	for slot = 1, 5 do
		GetTeamMember(slot)._loc = Vector(-5000, -5000, 0)
	end
	T.eq(Utils.IsTeamPushingSecondTierOrHighGround(bot), false, "nobody near the enemy base")
end)

T.test("IsTeamPushingSecondTierOrHighGround: slots 4 and 5 at the enemy ancient", function()
	local bot, _, Utils = setup()
	local ancient = GetAncient(GetOpposingTeam())
	for slot = 1, 5 do
		GetTeamMember(slot)._loc = Vector(-5000, -5000, 0)
	end
	GetTeamMember(4)._loc = ancient:GetLocation() - Vector(1000, 0, 0)
	GetTeamMember(5)._loc = ancient:GetLocation() - Vector(1100, 0, 0)
	T.eq(Utils.IsTeamPushingSecondTierOrHighGround(bot), true, "two allies within 3000 of the ancient")
end)

T.test("Site.IsTheClosestOne counts a farming ally in slot 5", function()
	local bot, _, _, Site = setup()
	local camp = Vector(0, 0, 0)
	bot._loc = Vector(1000, 0, 0)
	for slot = 2, 5 do
		GetTeamMember(slot)._loc = Vector(3000, 0, 0)
	end
	T.eq(Site.IsTheClosestOne(bot, camp), true, "bot is closest")
	local ally = GetTeamMember(5)
	ally._loc = Vector(200, 0, 0)
	T.eq(Site.IsTheClosestOne(bot, camp), true, "closer ally is not farming")
	ally.GetActiveMode = function()
		return BOT_MODE_FARM
	end
	T.eq(Site.IsTheClosestOne(bot, camp), false, "closer farming ally in slot 5")
end)

T.test("GetMostUltimateCDUnit pairs slots with player IDs", function()
	local _, Fu = setup()
	local silencer = Stub.newUnit({ name = "npc_dota_hero_silencer", team = TEAM_RADIANT, pid = 14 })
	Stub.teams[TEAM_RADIANT][5] = silencer
	T.eq(Fu.GetMostUltimateCDUnit(), silencer, "Silencer in slot 5 (player ID 14)")
end)

T.test("GetAlliesNearLoc returns all five", function()
	local _, Fu = setup()
	for slot = 1, 5 do
		GetTeamMember(slot)._loc = Vector(slot * 10, 0, 0)
	end
	T.eq(#Fu.GetAlliesNearLoc(Vector(0, 0, 0), 500), 5, "allies near the location")
end)

-- Game 077: the human held Radiant slot 5. The reply member (the bot that installs the team's chat callback) was
-- picked as a slot after the human count, so it could be the human, and no bot heard `!push` or `!debug`.
T.test("Role.GetReplyMemberID picks a bot when the human holds the last slot", function()
	local _, Fu = setup()
	local ids = GetTeamPlayers(GetTeam())
	local humanId = ids[5]
	IsPlayerBot = function(playerId)
		return playerId ~= humanId
	end
	local seen = {}
	for _ = 1, 60 do
		Fu.Role.replyMemberID = nil
		local picked = Fu.Role.GetReplyMemberID()
		T.ok(picked ~= nil and picked ~= humanId, "never the human in slot 5")
		seen[picked or -1] = true
	end
	for slot = 1, 4 do
		T.ok(seen[ids[slot]], "the bot in slot " .. slot .. " can be picked")
	end
	-- Humans in slots 1 and 5: only slots 2-4.
	IsPlayerBot = function(playerId)
		return playerId ~= ids[1] and playerId ~= ids[5]
	end
	for _ = 1, 30 do
		Fu.Role.replyMemberID = nil
		local picked = Fu.Role.GetReplyMemberID()
		T.ok(picked == ids[2] or picked == ids[3] or picked == ids[4], "a bot in slots 2-4")
	end
	-- No bot on the team: nobody, and nothing cached.
	IsPlayerBot = function()
		return false
	end
	Fu.Role.replyMemberID = nil
	T.eq(Fu.Role.GetReplyMemberID(), nil, "no bot")
	T.eq(Fu.Role.replyMemberID, nil, "not cached")
end)

T.test("the reply member installs the chat callback and logs each ! command it hears", function()
	local bot = Stub.reset({ hero = "npc_dota_hero_alchemist", slot = 1, time = 600 })
	local Usage = dofile("bots/ability_item_usage_generic.lua")
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local ids = GetTeamPlayers(GetTeam())
	local humanId = ids[5]
	IsPlayerBot = function(playerId)
		return playerId ~= humanId
	end
	local callback = nil
	InstallChatCallback = function(fn)
		callback = fn
	end
	Fu.Role.replyMemberID = bot:GetPlayerID()
	Stub.printed = {}
	Usage.SetTalkMessage()
	T.ok(callback ~= nil, "the chat callback is installed")
	T.eq(Fu.Role.chatListenerId, bot:GetPlayerID(), "the team's listener is recorded")
	local listener = 0
	for _, line in ipairs(Stub.printed) do
		if line:find("[SHy-CHAT]", 1, true) and line:find(" listener team=radiant id=", 1, true) then
			listener = listener + 1
		end
	end
	T.eq(listener, 1, "one listener line")
	if callback == nil then
		return
	end
	Stub.printed = {}
	callback({ string = "!push bot", player_id = humanId, team_only = true })
	callback({ string = "gg wp", player_id = humanId, team_only = false })
	local heard = {}
	for _, line in ipairs(Stub.printed) do
		if line:find("[SHy-CHAT]", 1, true) and line:find(" heard ", 1, true) then
			heard[#heard + 1] = line
		end
	end
	T.eq(#heard, 1, "one heard line for the command, none for plain chat")
	local humanHero = (string.gsub(GetSelectedHeroName(humanId), "npc_dota_hero_", ""))
	T.ok(
		heard[1] ~= nil and heard[1]:find("heard cmd=!push from=" .. humanHero .. " team_only=true", 1, true) ~= nil,
		"cmd, sender hero and team_only"
	)
end)

-- Games 077-078: the first GetReplyMemberID call comes at t=-89, before the team is fully loaded; a pick that read as a
-- bot then may be the human, and then no bot installs the chat callback.
T.test("Role.GetReplyMemberID replaces a cached pick that is no longer a bot", function()
	local _, Fu = setup()
	local ids = GetTeamPlayers(GetTeam())
	local humanId = ids[5]
	local loaded = false
	IsPlayerBot = function(playerId)
		return not loaded or playerId ~= humanId
	end
	Fu.Role.replyMemberID, Fu.Role.chatListenerId = humanId, nil
	T.eq(Fu.Role.GetReplyMemberID(), humanId, "early: the human still reads as a bot")
	loaded = true
	local picked = Fu.Role.GetReplyMemberID()
	T.ok(picked ~= nil and picked ~= humanId, "re-picked among the bots once IsPlayerBot reads right")
	T.eq(Fu.Role.GetReplyMemberID(), picked, "then kept")
	-- Once a bot listens it stays the reply member (no second callback).
	Fu.Role.chatListenerId = ids[2]
	Fu.Role.replyMemberID = humanId
	T.eq(Fu.Role.GetReplyMemberID(), ids[2], "the listener")
end)

-- Game 078: `!debug` switched the mode at t=700 but its reply never reached the chat (an ActionImmediate_Chat from
-- inside the chat callback says nothing). It is said from the bot's next think.
T.test("the !debug reply is said from the next think, not inside the chat callback", function()
	local bot = Stub.reset({ hero = "npc_dota_hero_alchemist", slot = 1, time = 600 })
	local Usage = dofile("bots/ability_item_usage_generic.lua")
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local ids = GetTeamPlayers(GetTeam())
	local humanId = ids[5]
	IsPlayerBot = function(playerId)
		return playerId ~= humanId
	end
	local callback = nil
	InstallChatCallback = function(fn)
		callback = fn
	end
	local chats = {}
	bot.ActionImmediate_Chat = function(_, text)
		if type(text) == "string" and text:find("ebug", 1, true) then
			chats[#chats + 1] = text
		end
	end
	Fu.Role.replyMemberID, Fu.Role.chatListenerId = bot:GetPlayerID(), nil
	Usage.SetTalkMessage()
	T.ok(callback ~= nil, "the chat callback is installed")
	if callback == nil then
		return
	end
	local before = Fu.Utils.DebugMode
	callback({ string = "!debug", player_id = humanId, team_only = true })
	T.eq(Fu.Utils.DebugMode, not before, "the mode switched")
	T.eq(#chats, 0, "nothing said inside the callback")
	Stub.printed = {}
	Usage.SetTalkMessage()
	T.eq(#chats, 1, "said on the next think")
	local logged = false
	for _, line in ipairs(Stub.printed) do
		if line:find("[SHy-CHAT]", 1, true) and line:find(" debug o", 1, true) and line:find("said=yes", 1, true) then
			logged = true
		end
	end
	T.ok(logged, "[SHy-CHAT] debug on|off said=yes")
	Usage.SetTalkMessage()
	T.eq(#chats, 1, "once")
end)
