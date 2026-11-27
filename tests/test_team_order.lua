-- The two orders of a team's players (#286, bots/lib/systems/team_order.lua). Game 087: a human (player 1) on
-- Dire with bots 6-9. Our GetTeamPlayers wrapper read 6,1,7,8,9; the engine's list and the GetTeamMember slots
-- read 1,6,7,8,9. The pick loop gave Zeus (6) the pos-2 lineup hero by his engine index 2, and he then played
-- pos 1 by his index 1 in our order. Each case below makes the orders differ and checks that a helper converts
-- through the player ID.
local T = ...
local Stub = T.stub

local function Load()
	return require(GetScriptDirectory() .. "/lib/systems/team_order")
end

T.test("team order: IndexOf and RoleIndex on the game-087 shape", function()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	local TeamOrder = Load()
	local ours = { 6, 1, 7, 8, 9 }
	local engine = { 1, 6, 7, 8, 9 }
	T.eq(TeamOrder.IndexOf(ours, 6), 1, "Zeus: index 1 in our order")
	T.eq(TeamOrder.IndexOf(engine, 6), 2, "Zeus: index 2 in the engine's")
	T.eq(TeamOrder.IndexOf(ours, 1), 2, "the human: index 2 in our order")
	T.eq(TeamOrder.IndexOf(ours, 3), nil, "not listed")
	T.eq(TeamOrder.IndexOf(nil, 6), nil, "no list")
	-- The pick loop walks the engine's list; the role index is the player's index in ours.
	for engineIdx, playerId in ipairs(engine) do
		T.eq(TeamOrder.RoleIndex(ours, playerId, engineIdx), ({ 2, 1, 3, 4, 5 })[engineIdx], "player " .. playerId)
	end
	T.eq(TeamOrder.RoleIndex(ours, 42, 4), 4, "not listed: the fallback")
end)

-- The real wrapper builds our order from the engine's list: with an engine list of 1,6,7,8,9 and player 1 the
-- human, it reads 6,1,7,8,9 (game 087), and asking for the original still gives 1,6,7,8,9.
T.test("team order: the GetTeamPlayers wrapper reorders a Dire team with a human (game 087)", function()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	local engineLists = { [TEAM_RADIANT] = { 0, 2, 3, 4, 5 }, [TEAM_DIRE] = { 1, 6, 7, 8, 9 } }
	GetTeamPlayers = function(team)
		local ids = engineLists[team]
		return { ids[1], ids[2], ids[3], ids[4], ids[5] }
	end
	IsPlayerBot = function(playerId)
		return playerId ~= 1
	end
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local TeamOrder = Load()
	local ours = GetTeamPlayers(TEAM_DIRE)
	local engine = GetTeamPlayers(TEAM_DIRE, true)
	T.eq(table.concat(ours, ","), "6,1,7,8,9", "our order: the human second")
	T.eq(table.concat(engine, ","), "1,6,7,8,9", "the engine's: the human first")
	T.eq(table.concat(GetTeamPlayers(TEAM_RADIANT), ","), "0,2,3,4,5", "Radiant: unchanged")
	T.eq(TeamOrder.RoleIndex(ours, engine[2], 2), 1, "Zeus, engine index 2: role index 1")
	T.eq(TeamOrder.RoleIndex(ours, engine[1], 1), 2, "the human, engine index 1: role index 2")
end)

T.test("team order: Describe shows both orders and flags the mix", function()
	Stub.reset({ hero = "npc_dota_hero_lich" })
	local TeamOrder = Load()
	local names = { "zuus", "marci", "dark_willow", "ringmaster", "winter_wyvern" }
	local fields, mixed = TeamOrder.Describe(
		{ 6, 1, 7, 8, 9 },
		{ 1, 6, 7, 8, 9 },
		{ 1, 6, 7, 8, 9 },
		names,
		{ 1, 2, 3, 4, 5 }
	)
	T.eq(mixed, true, "mixed")
	T.eq(
		fields,
		"players=6,1,7,8,9 engine=1,6,7,8,9 slots=1,6,7,8,9"
			.. " roles=zuus:1,marci:2,dark_willow:3,ringmaster:4,winter_wyvern:5 mixed=yes",
		"the fields"
	)
	local _, same = TeamOrder.Describe({ 0, 2, 3, 4, 5 }, { 0, 2, 3, 4, 5 }, { 0, 2, 3, 4, 5 }, names, {})
	T.eq(same, false, "one order: not mixed")
end)

T.test("team order: LogOnce prints the team-order line once, when all five slots hold a hero", function()
	Stub.reset({ hero = "npc_dota_hero_lich", time = -80 })
	local TeamOrder = Load()
	local ids = GetTeamPlayers(GetTeam())
	local engine = { ids[1], ids[2], ids[3], ids[4], ids[5] }
	-- Our order lists slot 2's player first.
	GetTeamPlayers = function(_, useOriginal)
		if useOriginal then
			return { engine[1], engine[2], engine[3], engine[4], engine[5] }
		end
		return { engine[2], engine[1], engine[3], engine[4], engine[5] }
	end
	local function Lines()
		local found = {}
		for _, line in ipairs(Stub.printed) do
			if line:find("team-order team=", 1, true) then
				found[#found + 1] = line
			end
		end
		return found
	end
	local roles = { TEAM_RADIANT = { 3, 1, 2, 4, 5 } }
	TeamOrder.LogOnce(GetBot(), roles)
	TeamOrder.LogOnce(GetBot(), roles)
	local lines = Lines()
	T.eq(#lines, 1, "once")
	local line = lines[1] or ""
	local slotIds = {}
	for slot = 1, 5 do
		slotIds[slot] = GetTeamMember(slot):GetPlayerID()
	end
	local first = string.gsub(GetSelectedHeroName(engine[2]), "npc_dota_hero_", "")
	T.ok(line:find("[SHy-ROLE] t=", 1, true) == 1, "tag and time")
	T.ok(line:find("team=radiant", 1, true) ~= nil, "team")
	T.ok(line:find("players=" .. engine[2] .. "," .. engine[1], 1, true) ~= nil, "our order")
	T.ok(line:find("slots=" .. table.concat(slotIds, ","), 1, true) ~= nil, "the slots")
	T.ok(line:find("roles=" .. first .. ":3,", 1, true) ~= nil, "roles by our order")
	T.ok(line:find("mixed=yes", 1, true) ~= nil, "mixed")
end)

T.test("team order: LogOnce waits while a slot is empty, and prints nothing after the horn", function()
	Stub.reset({ hero = "npc_dota_hero_lich", time = -80 })
	local TeamOrder = Load()
	local fourth = Stub.teams[GetTeam()][4]
	Stub.teams[GetTeam()][4] = nil
	TeamOrder.LogOnce(GetBot(), { TEAM_RADIANT = { 1, 2, 3, 4, 5 } })
	local function Count()
		local n = 0
		for _, line in ipairs(Stub.printed) do
			if line:find("team-order", 1, true) ~= nil then
				n = n + 1
			end
		end
		return n
	end
	T.eq(Count(), 0, "slot 4 empty: no line yet")
	Stub.teams[GetTeam()][4] = fourth
	Stub.time = 0
	TeamOrder.LogOnce(GetBot(), { TEAM_RADIANT = { 1, 2, 3, 4, 5 } })
	T.eq(Count(), 0, "after the horn: no line")
end)

-- Fu.GetMostUltimateCDUnit (#286): the alive check read the GetTeamPlayers player at the slot's index. With the
-- orders mixed, an alive Silencer was skipped because another player, dead, sat at his index.
T.test(
	"team order: GetMostUltimateCDUnit finds an alive Silencer whose GetTeamPlayers index names a dead ally",
	function()
		Stub.reset({ hero = "npc_dota_hero_lich", slot = 1 })
		local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
		local ids = GetTeamPlayers(GetTeam())
		local silencer = Stub.newUnit({ name = "npc_dota_hero_silencer", team = GetTeam(), pid = ids[5] })
		Stub.teams[GetTeam()][5] = silencer
		-- Slot 2's hero is dead; our order lists slot 2's player at index 5 (and slot 5's at index 2).
		GetTeamMember(2)._alive = false
		GetTeamPlayers = function()
			return { ids[1], ids[5], ids[3], ids[4], ids[2] }
		end
		T.eq(Fu.GetMostUltimateCDUnit(), silencer, "Silencer in slot 5")
	end
)

-- Role.GetPosition's fallback (#286), used when no player's selected hero has the bot's unit name: it took the
-- player ID + 1 (Radiant) or - 4 (Dire) as the RoleAssignment index. Game 087 had Radiant IDs 0,2,3,4,5 and Dire
-- 6,1,7,8,9, so that named another player's entry or none. It now finds the ID in GetTeamPlayers.
T.test("team order: Role.GetPosition's fallback reads the entry at the player's GetTeamPlayers index", function()
	Stub.reset({ hero = "npc_dota_hero_lich", slot = 1, time = 600 })
	local Role = require(GetScriptDirectory() .. "/lib/systems/role")
	local bot = GetBot()
	local ids = GetTeamPlayers(GetTeam())
	-- Our order lists the bot (slot 1) third.
	GetTeamPlayers = function()
		return { ids[2], ids[3], ids[1], ids[4], ids[5] }
	end
	-- The hero-name lookup finds nobody.
	bot.GetUnitName = function()
		return "npc_dota_hero_not_selected"
	end
	Role.RoleAssignment.TEAM_RADIANT = { 1, 2, 4, 3, 5 }
	Role.RoleAssignment.TEAM_DIRE = { 1, 2, 4, 3, 5 }
	T.eq(Role.GetPosition(bot), 4, "the entry at index 3")
end)
