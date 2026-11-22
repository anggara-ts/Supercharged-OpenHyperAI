-- Items cast from the backpack (ability_item_usage_generic.lua, #15): Smoke of Deceit and Roshan's Banner reach their
-- use rule from a backpack slot; the backpack swap-cooldown gate still holds an item just moved into a main slot.
-- Game 069: the gate stamped every backpack item on every think, so a Banner in slot 7 never reached its rule
-- (23 x [OHA-BANNER] plant-skip why=stash, no plant).
local T = ...
local Stub = T.stub

local function loadUsage(opts)
	Stub.reset(opts)
	local ok, usage = Stub.load("ability_item_usage_generic")
	if not ok then
		error(tostring(usage), 0)
	end
	return usage
end

local function castable(item)
	item.IsFullyCastable = function()
		return true
	end
	item.IsTrained = function()
		return true
	end
	return item
end

-- Replaces an item's use rule with one that counts its calls and asks for nothing.
local function spyRule(Usage, itemName)
	local calls = { n = 0 }
	Usage.ConsiderItemDesire[itemName] = function()
		calls.n = calls.n + 1
		return BOT_ACTION_DESIRE_NONE
	end
	return calls
end

for _, itemName in ipairs({ "item_smoke_of_deceit", "item_roshans_banner" }) do
	T.test("backpack items: " .. itemName .. " in slot 7 reaches its use rule", function()
		local Usage = loadUsage({ hero = "npc_dota_hero_vengefulspirit", time = 2500 })
		local bot = Stub.bot
		bot._items[7] = castable(Stub.newAbility(itemName, bot))
		local calls = spyRule(Usage, itemName)
		Usage.ItemUsageThink()
		Usage.ItemUsageThink()
		T.ok(calls.n >= 1, itemName .. " rule ran (" .. calls.n .. " calls in 2 thinks; 0 before the fix)")
	end)
end

T.test("backpack items: another item in the backpack is not used from there", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_vengefulspirit", time = 2500 })
	local bot = Stub.bot
	bot._items[7] = castable(Stub.newAbility("item_magic_wand", bot))
	local calls = spyRule(Usage, "item_magic_wand")
	Usage.ItemUsageThink()
	T.eq(calls.n, 0, "no use rule for a backpack Magic Wand")
end)

T.test("backpack items: an item just moved from the backpack into a main slot waits for the swap cooldown", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_vengefulspirit", time = 2500 })
	local bot = Stub.bot
	local wand = castable(Stub.newAbility("item_magic_wand", bot))
	bot._items[7] = wand
	local calls = spyRule(Usage, "item_magic_wand")
	Usage.ItemUsageThink()
	bot._items[7] = nil
	bot._items[0] = wand
	Usage.ItemUsageThink()
	T.eq(calls.n, 0, "held while the 6s swap cooldown runs (same game time)")
	T.ok(not Usage.WasInBackpackRecently("item_blink"), "an item never seen in the backpack is not held")
	T.ok(Usage.WasInBackpackRecently("item_magic_wand"), "the moved wand is held")
end)
