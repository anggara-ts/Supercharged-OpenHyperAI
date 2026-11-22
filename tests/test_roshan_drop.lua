-- Making room for a Roshan item (#15): Item.TryPickupRoshanDrop / Item.RoshanDropDesire.
-- Game 051: one Banner cost Keeper three items, because every think dropped another item until the first
-- drop order landed, and only the last one was remembered.
local T = ...
local Stub = T.stub

local COSTS = {
	item_boots = 500,
	item_magic_wand = 450,
	item_ogre_axe = 1000,
	item_force_staff = 2200,
	item_glimmer_cape = 2150,
	item_ultimate_scepter = 4200,
	item_ward_observer = 0,
	item_ward_sentry = 0,
	item_clarity = 50,
}

-- A hero with a bag, and a ground the drop / pick-up orders act on only when the test says so (land()).
local function scene(mainItems, backpackItems)
	local unit = Stub.reset({ hero = "npc_dota_hero_keeper_of_the_light" })
	local Item = require(GetScriptDirectory() .. "/lib/systems/item")
	local world = { bag = {}, ground = {}, orders = {}, pending = nil }
	local function newItem(name)
		return {
			GetName = function()
				return name
			end,
			IsNull = function()
				return false
			end,
		}
	end
	for index, name in ipairs(mainItems) do
		world.bag[index - 1] = newItem(name)
	end
	for index, name in ipairs(backpackItems) do
		world.bag[5 + index] = newItem(name)
	end
	unit.GetItemInSlot = function(_, slot)
		return world.bag[slot]
	end
	unit.FindItemSlot = function(_, name)
		for slot = 0, 8 do
			if world.bag[slot] ~= nil and world.bag[slot]:GetName() == name then
				return slot
			end
		end
		return -1
	end
	unit.Action_DropItem = function(_, item)
		world.orders[#world.orders + 1] = "drop " .. item:GetName()
		world.pending = { kind = "drop", item = item }
	end
	unit.Action_PickUpItem = function(_, item)
		world.orders[#world.orders + 1] = "pick " .. item:GetName()
		world.pending = { kind = "pick", item = item }
	end
	unit.Action_MoveToLocation = function()
		world.orders[#world.orders + 1] = "move"
	end
	_G.GetItemCost = function(name)
		return COSTS[name] or 0
	end
	_G.GetDroppedItemList = function()
		return world.ground
	end
	Item.ShouldClaimRoshanDrop = function()
		return true
	end
	function world.putOnGround(name)
		world.ground[#world.ground + 1] = { item = newItem(name), location = unit:GetLocation() }
	end
	-- The last order takes effect.
	function world.land()
		local order = world.pending
		world.pending = nil
		if order == nil then
			return
		end
		if order.kind == "drop" then
			for slot = 0, 8 do
				if world.bag[slot] == order.item then
					world.bag[slot] = nil
				end
			end
			world.ground[#world.ground + 1] = { item = order.item, location = unit:GetLocation() }
		else
			for index, drop in ipairs(world.ground) do
				if drop.item == order.item then
					table.remove(world.ground, index)
					break
				end
			end
			for _, slot in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8 }) do
				if world.bag[slot] == nil then
					world.bag[slot] = order.item
					break
				end
			end
		end
	end
	function world.printed(pattern)
		local count = 0
		for _, line in ipairs(Stub.printed) do
			if string.find(line, pattern) then
				count = count + 1
			end
		end
		return count
	end
	return unit, Item, world
end

local FULL_MAIN = {
	"item_boots",
	"item_magic_wand",
	"item_ogre_axe",
	"item_force_staff",
	"item_glimmer_cape",
	"item_ultimate_scepter",
}

T.test("roshan drop: one item is dropped for the Aegis, however often the think runs", function()
	local unit, Item, world = scene(FULL_MAIN, { "item_ward_observer" })
	world.putOnGround("item_aegis")
	Stub.time = 2294
	for _ = 1, 6 do
		T.ok(Item.TryPickupRoshanDrop(unit), "busy with the Aegis")
		Stub.time = Stub.time + 0.1
	end
	T.eq(table.concat(world.orders, ","), "drop item_magic_wand", "one drop order, the cheapest main item")
	T.eq(world.printed("room dropped magic_wand for=aegis cost=450 backpack%-free=2"), 1, "the drop is logged")
	world.land()
	T.ok(Item.TryPickupRoshanDrop(unit), "takes the Aegis")
	T.eq(world.orders[#world.orders], "pick item_aegis", "into the freed slot")
	world.land()
	Stub.time = Stub.time + 1.5
	T.eq(Item.RoshanDropDesire(unit), 0.97, "the desire stays up for the dropped item")
	T.ok(Item.TryPickupRoshanDrop(unit), "fetches the dropped item")
	T.eq(world.orders[#world.orders], "pick item_magic_wand", "the Magic Wand again")
	world.land()
	T.ok(not Item.TryPickupRoshanDrop(unit), "done")
	T.eq(world.printed("room picked%-up magic_wand"), 1, "the pick-up is logged")
	T.eq(Item.RoshanDropDesire(unit), 0, "nothing left to do")
	T.eq(unit:FindItemSlot("item_magic_wand"), 7, "it came back into the backpack")
end)

T.test("roshan drop: the Banner goes into the backpack and nothing is dropped for it", function()
	-- 7.42: the Banner is used from the backpack (game file: AllowedInBackpack 1).
	local unit, Item, world = scene(FULL_MAIN, { "item_ward_observer" })
	world.putOnGround("item_roshans_banner")
	Stub.time = 2294
	T.ok(Item.TryPickupRoshanDrop(unit), "takes the Banner")
	T.eq(table.concat(world.orders, ","), "pick item_roshans_banner", "picked up, no drop order")
	world.land()
	T.eq(unit:FindItemSlot("item_roshans_banner"), 7, "it sits in the backpack")
	T.ok(not Item.TryPickupRoshanDrop(unit), "done")
	T.eq(world.printed("room dropped"), 0, "nothing was dropped")
	T.eq(Item.RoshanDropDesire(unit), 0, "nothing left to do")
end)

T.test("roshan drop: a full backpack leaves the Banner alone but still makes room for the Aegis", function()
	local unit, Item, world = scene(FULL_MAIN, { "item_ward_observer", "item_ward_observer", "item_ward_observer" })
	world.putOnGround("item_roshans_banner")
	Stub.time = 2294
	T.ok(not Item.TryPickupRoshanDrop(unit), "no room: the Banner is left")
	T.eq(#world.orders, 0, "nothing is dropped")
	T.eq(world.printed("room skip roshans_banner why=bag%-full"), 1, "the skip is logged")
	T.eq(Item.RoshanDropDesire(unit), 0, "and the bot does not stand at it")
	world.ground = {}
	world.putOnGround("item_aegis")
	Stub.time = Stub.time + 31
	T.ok(Item.TryPickupRoshanDrop(unit), "the Aegis is worth an item")
	T.eq(table.concat(world.orders, ","), "drop item_magic_wand", "one drop")
end)

T.test("roshan drop: a dropped item nobody can reach is given up with a line", function()
	local unit, Item, world = scene(FULL_MAIN, {})
	world.putOnGround("item_aegis")
	Stub.time = 3757
	Item.TryPickupRoshanDrop(unit)
	world.land()
	Item.TryPickupRoshanDrop(unit)
	world.land()
	Stub.time = Stub.time + 31
	T.ok(not Item.TryPickupRoshanDrop(unit), "gives up after 30s")
	T.eq(world.printed("room lost magic_wand why=timeout"), 1, "the loss is logged")
	T.eq(Item.RoshanDropDesire(unit), 0, "the desire drops")
end)

T.test("roshan drop: the item put aside for the Aegis comes back, is not sold, and goes back to a main slot", function()
	-- Maintainer, 2026-11-23: put even a high-value item aside for the Aegis, "but do not mark the item to sell".
	local unit, Item, world = scene(FULL_MAIN, { "item_ward_observer" })
	world.putOnGround("item_aegis")
	Stub.time = 2294
	Item.TryPickupRoshanDrop(unit)
	world.land()
	Item.TryPickupRoshanDrop(unit)
	world.land()
	Stub.time = Stub.time + 1.5
	Item.TryPickupRoshanDrop(unit)
	T.eq(world.orders[#world.orders], "pick item_magic_wand", "fetches the Magic Wand")
	world.land()
	T.ok(not Item.TryPickupRoshanDrop(unit), "done")
	T.eq(world.printed("aegis%-room item=magic_wand how=drop pickedBack=yes"), 1, "the result line")
	unit:ActionImmediate_SellItem(unit:GetItemInSlot(unit:FindItemSlot("item_magic_wand")))
	T.eq(world.printed("sell%-skip item=magic_wand why=aegis%-aside"), 1, "the sale is refused")
	-- The Aegis is used: its slot is free, the Magic Wand waits in the backpack.
	for slot = 0, 5 do
		if world.bag[slot] ~= nil and world.bag[slot]:GetName() == "item_aegis" then
			world.bag[slot] = nil
		end
	end
	Stub.time = Stub.time + 60
	T.eq(Item.RoshanDropDesire(unit), 0, "not with allies next to him (their item mode)")
	for _, ally in ipairs(Stub.teams[unit:GetTeam()]) do
		if ally ~= unit then
			ally._loc = Vector(ally._loc.x + 3000, ally._loc.y, 0)
		end
	end
	T.ok(Item.RoshanDropDesire(unit) > 0, "team roam brings it back")
	T.ok(not Item.TryPickupRoshanDrop(unit), "only from team roam's Think")
	unit.GetActiveMode = function()
		return BOT_MODE_TEAM_ROAM
	end
	T.ok(Item.TryPickupRoshanDrop(unit), "puts it down")
	T.eq(world.orders[#world.orders], "drop item_magic_wand", "drop order")
	world.land()
	T.ok(Item.TryPickupRoshanDrop(unit), "picks it up")
	T.eq(world.orders[#world.orders], "pick item_magic_wand", "pick order")
	world.land()
	Stub.time = Stub.time + 1.5
	T.ok(not Item.TryPickupRoshanDrop(unit), "done")
	T.ok(unit:FindItemSlot("item_magic_wand") <= 5, "back in a main slot")
	T.eq(world.printed("aegis%-restore item=magic_wand how=drop pickedBack=yes"), 1, "the restore line")
	T.eq(Item.RoshanDropDesire(unit), 0, "nothing left to do")
end)

T.test("roshan drop: with the whole bag full a cheaper backpack item is left for the item put aside", function()
	local unit, Item, world = scene(FULL_MAIN, { "item_clarity", "item_ward_observer", "item_ward_sentry" })
	world.putOnGround("item_aegis")
	Stub.time = 2294
	Item.TryPickupRoshanDrop(unit)
	T.eq(world.orders[#world.orders], "drop item_magic_wand", "the Aegis is worth an item, even with a full backpack")
	world.land()
	Item.TryPickupRoshanDrop(unit)
	world.land()
	Stub.time = Stub.time + 1.5
	Item.TryPickupRoshanDrop(unit)
	T.eq(world.orders[#world.orders], "drop item_clarity", "the Clarity makes room for the Magic Wand")
	T.eq(world.printed("room left clarity for=magic_wand cost=50"), 1, "logged")
	world.land()
	Item.TryPickupRoshanDrop(unit)
	T.eq(world.orders[#world.orders], "pick item_magic_wand", "then the Magic Wand")
	world.land()
	Stub.time = Stub.time + 1.5
	Item.TryPickupRoshanDrop(unit)
	T.eq(world.printed("aegis%-room item=magic_wand how=drop pickedBack=yes"), 1, "it came back")
	T.eq(world.printed("room dropped"), 1, "one item dropped for the Aegis itself")
end)

-- A team with the Aegis lying next to slot 1, and kills per team slot.
local function claimScene(killsBySlot)
	local unit = Stub.reset({ hero = "npc_dota_hero_keeper_of_the_light" })
	local Item = require(GetScriptDirectory() .. "/lib/systems/item")
	local team = Stub.teams[unit:GetTeam()]
	local kills = {}
	for slot, ally in ipairs(team) do
		kills[ally:GetPlayerID()] = killsBySlot[slot] or 0
	end
	_G.GetHeroKills = function(pid)
		return kills[pid] or 0
	end
	local aegis = {
		GetName = function()
			return "item_aegis"
		end,
		IsNull = function()
			return false
		end,
	}
	local loc = team[1]:GetLocation()
	_G.GetDroppedItemList = function()
		return { { item = aegis, location = loc } }
	end
	local function printed(pattern)
		local count = 0
		for _, line in ipairs(Stub.printed) do
			if string.find(line, pattern) then
				count = count + 1
			end
		end
		return count
	end
	local function short(slot)
		return (string.gsub(team[slot]:GetUnitName(), "npc_dota_hero_", ""))
	end
	return unit, Item, team, loc, printed, short
end

T.test("aegis claim: the best KDA near takes it, one claimer for the team, one line", function()
	local _, Item, team, loc, printed, short = claimScene({ 1, 2, 9, 0, 3 })
	for step = 0, 3 do
		Stub.time = 1869 + step
		for slot = 1, 5 do
			T.eq(Item.ShouldClaimRoshanDrop(team[slot], loc, "item_aegis"), slot == 3, "slot " .. slot)
		end
	end
	T.eq(printed("aegis%-claim hero=" .. short(3) .. " kda=9.00 why=best%-kda"), 1, "one claim line")
	T.eq(printed("aegis%-claim"), 1, "and no other")
	-- The claimer takes it: the Aegis leaves the ground and turns up in his bag.
	_G.GetDroppedItemList = function()
		return {}
	end
	local aegisSlot = {
		GetName = function()
			return "item_aegis"
		end,
	}
	team[3].FindItemSlot = function(_, name)
		return name == "item_aegis" and 2 or -1
	end
	team[3]._items[2] = aegisSlot
	Stub.time = 1873
	Item.RoshanDropDesire(team[1])
	T.eq(printed("aegis%-taken hero=" .. short(3) .. " claimer=" .. short(3) .. " match=yes"), 1, "the result line")
	Stub.time = 1880
	Item.RoshanDropDesire(team[1])
	T.eq(printed("aegis%-taken"), 1, "once")
end)

T.test("aegis claim: a claimer that makes no progress is released to the next best KDA", function()
	local _, Item, team, loc, printed, short = claimScene({ 1, 5, 9, 0, 3 })
	Stub.time = 1869
	T.ok(Item.ShouldClaimRoshanDrop(team[3], loc, "item_aegis"), "slot 3 first")
	for step = 1, 6 do
		Stub.time = 1869 + step * 2
		Item.ShouldClaimRoshanDrop(team[3], loc, "item_aegis")
	end
	T.ok(Item.ShouldClaimRoshanDrop(team[2], loc, "item_aegis"), "slot 2 next")
	T.ok(not Item.ShouldClaimRoshanDrop(team[3], loc, "item_aegis"), "slot 3 is out")
	T.eq(printed("aegis%-claim hero=" .. short(2) .. ".*released=" .. short(3) .. ":stuck"), 1, "the release")
end)

T.test("aegis guard: an ally that is not the claimer keeps away from the Aegis", function()
	local unit, Item, team, loc, printed = claimScene({ 0, 0, 0, 0, 0 })
	local mySlot = nil
	for slot, ally in ipairs(team) do
		if ally == unit then
			mySlot = slot
		end
	end
	local kills = {}
	for slot, ally in ipairs(team) do
		kills[ally:GetPlayerID()] = slot == mySlot and 0 or slot
	end
	_G.GetHeroKills = function(pid)
		return kills[pid] or 0
	end
	unit._loc = loc
	local moved = nil
	unit.Action_MoveToLocation = function(_, where)
		moved = where
	end
	Stub.time = 1869
	T.eq(Item.RoshanDropDesire(unit), 1.02, "above Valve's item mode (1.00 at Roshan drops)")
	T.ok(Item.TryGuardRoshanDrop(unit), "steps away")
	T.ok(moved ~= nil and GetUnitToLocationDistance(unit, loc) < 1, "was at the Aegis")
	T.ok(math.abs(moved.x - loc.x) + math.abs(moved.y - loc.y) > 1000, "moves out of reach")
	T.eq(printed("aegis%-guard what=aegis owner="), 1, "logged")
end)
