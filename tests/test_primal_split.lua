-- bots/lib/hero/minion_lib/primal_split.lua (#13): a brewling's GetNearby* lists can be nil (game 085, 12:16:
-- "primal_split.lua:357: bad argument #1 to 'pairs' (table expected, got nil)" from GetNearbyTowers, x3), and
-- MinionThink must still run to its casts and orders.
local T = ...
local Stub = T.stub

local LISTS = { "GetNearbyHeroes", "GetNearbyTowers", "GetNearbyLaneCreeps", "GetNearbyCreeps", "GetNearbyBarracks" }

local function castable(unit, name)
	local ability = unit:GetAbilityByName(name)
	ability.IsFullyCastable = function()
		return true
	end
	return ability
end

-- A brewling next to the owner whose every nearby list is nil, and its spells off cooldown.
local function brewling(kind, owner)
	local unit = Stub.newUnit({
		name = "npc_dota_brewmaster_" .. kind .. "_1",
		team = owner:GetTeam(),
		loc = owner:GetLocation(),
		hero = false,
	})
	for _, name in ipairs(LISTS) do
		unit[name] = function()
			return nil
		end
	end
	for _, spell in ipairs({
		"brewmaster_earth_hurl_boulder",
		"brewmaster_storm_dispel_magic",
		"brewmaster_storm_cyclone",
		"brewmaster_storm_wind_walk",
	}) do
		castable(unit, spell)
	end
	unit.orders = {}
	unit.Action_UseAbilityOnEntity = function(_, ability, target)
		unit.orders[#unit.orders + 1] = { "cast", ability:GetName(), target }
	end
	unit.Action_UseAbilityOnLocation = function(_, ability)
		unit.orders[#unit.orders + 1] = { "cast-loc", ability:GetName() }
	end
	unit.Action_UseAbility = function(_, ability)
		unit.orders[#unit.orders + 1] = { "cast-self", ability:GetName() }
	end
	unit.Action_AttackUnit = function(_, target)
		unit.orders[#unit.orders + 1] = { "attack", target }
	end
	unit.Action_MoveToLocation = function()
		unit.orders[#unit.orders + 1] = { "move" }
	end
	return unit
end

local MODES = { "BOT_MODE_NONE", "BOT_MODE_LANING", "BOT_MODE_FARM", "BOT_MODE_PUSH_TOWER_MID", "BOT_MODE_RETREAT" }

for _, kind in ipairs({ "earth", "storm", "fire", "void" }) do
	for _, modeName in ipairs(MODES) do
		T.test("primal split: " .. kind .. " brewling with nil nearby lists, owner " .. modeName, function()
			local owner = Stub.reset({ hero = "npc_dota_hero_brewmaster", time = 700 })
			local mode = _G[modeName]
			owner.GetActiveMode = function()
				return mode
			end
			local PrimalSplit = require(GetScriptDirectory() .. "/lib/hero/minion_lib/primal_split")
			local minion = brewling(kind, owner)
			PrimalSplit.MinionThink(owner, minion)
			T.ok(#minion.orders >= 1, "the brewling still gets an order")
		end)
	end
end

-- Positive control: the ally-tower branch (the line that errored) is reached and casts on the tower's target.
T.test("primal split: earth brewling hurls the boulder at the hero our tower attacks", function()
	local owner = Stub.reset({ hero = "npc_dota_hero_brewmaster", time = 700 })
	local PrimalSplit = require(GetScriptDirectory() .. "/lib/hero/minion_lib/primal_split")
	local minion = brewling("earth", owner)
	local enemy = Stub.teams[TEAM_DIRE][1]
	local tower = Stub.newUnit({
		name = "npc_dota_goodguys_tower1_mid",
		team = owner:GetTeam(),
		loc = owner:GetLocation(),
		hero = false,
	})
	tower.IsBuilding = function()
		return true
	end
	tower.GetAttackTarget = function()
		return enemy
	end
	minion.GetNearbyTowers = function(_, _, enemyTowers)
		if enemyTowers then
			return nil
		end
		return { tower }
	end
	PrimalSplit.MinionThink(owner, minion)
	T.eq(#minion.orders, 1, "one order")
	T.eq(minion.orders[1][1], "cast", "a cast")
	T.eq(minion.orders[1][2], "brewmaster_earth_hurl_boulder", "Hurl Boulder")
	T.ok(minion.orders[1][3] == enemy, "on the tower's target")
	local logged = false
	for _, line in ipairs(Stub.printed) do
		if
			string.find(tostring(line), "[SHy-BREWLING]", 1, true) and string.find(tostring(line), "why=tower", 1, true)
		then
			logged = true
		end
	end
	T.ok(logged, "[SHy-BREWLING] cast=hurl-boulder why=tower printed")
end)
