-- The two orders of a team's players (#286). Pure helpers, plus one log line per team.
--
--   * Our order: GetTeamPlayers(team), the wrapper in global_overrides.lua. On a Dire team with a human it puts the
--     human at the index of its lobby slot (game 087: 6,1,7,8,9 with the human, player 1, second). Role.RoleAssignment,
--     Role.GetPosition / GetRoleFromId (by hero name), hero_selection's lane table (through direLaneSlot) and `!pos`
--     all index by this order.
--   * The engine's order: GetTeamPlayers(team, true) and the GetTeamMember(1..5) slots. Game 087 read 1,6,7,8,9:
--     GetTeamMember(1) was the human, GetTeamMember(2) Zeus (#222), and the pick loop, which walks the engine's list,
--     gave Zeus the pos-2 lineup hero by his index 2 there, while he played pos 1 by his index 1 in ours.
--
-- So an index of one order never names the same player in the other. Convert through the player ID.
local TeamOrder = {}

-- The index of playerId in list, or nil.
function TeamOrder.IndexOf(list, playerId)
	if list == nil or playerId == nil then
		return nil
	end
	for i = 1, #list do
		if list[i] == playerId then
			return i
		end
	end
	return nil
end

-- The Role.RoleAssignment index of a player: its index in our GetTeamPlayers order (`rolePlayers`), or `fallback`
-- when it is not listed there.
function TeamOrder.RoleIndex(rolePlayers, playerId, fallback)
	return TeamOrder.IndexOf(rolePlayers, playerId) or fallback
end

local function Join(list)
	local parts = {}
	for i = 1, #(list or {}) do
		parts[#parts + 1] = tostring(list[i])
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

-- The fields of the team-order line. `players` = our order, `engine` = the engine's list, `slotIds` = the player
-- IDs of GetTeamMember(1..5), `names[i]` / `roles[i]` = hero and Role.RoleAssignment entry of players[i].
-- mixed = yes when our order is not the slot order (an index of one names another player in the other).
function TeamOrder.Describe(players, engine, slotIds, names, roles)
	local mixed = false
	for i = 1, math.max(#(players or {}), #(slotIds or {})) do
		if (players or {})[i] ~= (slotIds or {})[i] then
			mixed = true
		end
	end
	local heroRoles = {}
	for i = 1, #(players or {}) do
		heroRoles[#heroRoles + 1] = tostring((names or {})[i] or "?") .. ":" .. tostring((roles or {})[i] or "-")
	end
	return string.format(
		"players=%s engine=%s slots=%s roles=%s mixed=%s",
		Join(players),
		Join(engine),
		Join(slotIds),
		#heroRoles > 0 and table.concat(heroRoles, ",") or "-",
		mixed and "yes" or "no"
	),
		mixed
end

-- `[SHy-ROLE] team-order` once per team (per script VM), before the horn, when all five GetTeamMember slots hold a
-- hero (they spawn at about -90; game 087 printed its first bot lines at t=-88). Shows both orders and the position
-- each hero gets, so a game shows whether the pick and the role used one order.
local logged = false
function TeamOrder.LogOnce(bot, roleAssignment)
	if logged or bot == nil or DotaTime() >= 0 then
		return
	end
	local team = bot:GetTeam()
	if team ~= GetTeam() then
		return
	end
	local slotIds = {}
	for slot = 1, 5 do
		local member = GetTeamMember(slot)
		if member == nil then
			return
		end
		slotIds[slot] = member:GetPlayerID()
	end
	logged = true
	local players = GetTeamPlayers(team) or {}
	local teamKey = team == TEAM_RADIANT and "TEAM_RADIANT" or "TEAM_DIRE"
	local roles = (roleAssignment or {})[teamKey] or {}
	local names, roleList = {}, {}
	for i = 1, #players do
		names[i] = string.gsub(GetSelectedHeroName(players[i]) or "", "npc_dota_hero_", "")
		roleList[i] = roles[i]
	end
	local fields = TeamOrder.Describe(players, GetTeamPlayers(team, true), slotIds, names, roleList)
	print(
		string.format(
			"[SHy-ROLE] t=%.0f %s team-order team=%s %s",
			DotaTime(),
			string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""),
			team == TEAM_RADIANT and "radiant" or "dire",
			fields
		)
	)
end

return TeamOrder
