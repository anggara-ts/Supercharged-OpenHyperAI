-- #141: another player's items (bots/lib/systems/foreign_items.lua).
local T = ...

local function load(module)
	return require(GetScriptDirectory() .. "/lib/systems/" .. module)
end

T.test("foreign items: owner rule", function()
	T.stub.reset({ hero = "npc_dota_hero_medusa" })
	local F = load("foreign_items")
	-- Game 062: Nature's Prophet's mushroom in Medusa's bag (stub player IDs are not 1-5 on purpose).
	T.eq(F.IsForeignOwner("item_foragers_mana", 11, 12), true, "another player's mushroom")
	T.eq(F.IsForeignOwner("item_foragers_mana", 12, 12), false, "own mushroom")
	-- A mushroom grown by the kit has no owner on the ground (game 062: Kez ate one without a kit).
	T.eq(F.IsForeignOwner("item_foragers_stats", nil, 12), false, "no owner")
	T.eq(F.IsForeignOwner("item_foragers_stats", -1, 12), false, "invalid owner")
	-- Shareable items (7.42 items.txt ItemShareability) and Rapier / Aegis are never foreign.
	T.eq(F.IsForeignOwner("item_ward_observer", 11, 12), false, "ward handed over by an ally")
	T.eq(F.IsForeignOwner("item_greater_famango", 11, 12), false, "lotus fruit")
	T.eq(F.IsForeignOwner("item_rapier", 15, 12), false, "an enemy's Rapier")
	T.eq(F.IsForeignOwner("item_gem", 15, 12), false, "Gem")
	T.eq(F.IsForeignOwner("item_blink", 11, 12), true, "an ally's Blink Dagger")
end)

T.test("foreign items: drop only when it costs nothing", function()
	T.stub.reset({ hero = "npc_dota_hero_medusa" })
	local F = load("foreign_items")
	T.eq(F.SafeToDrop(0, false, false, false, false), true, "calm")
	T.eq(F.SafeToDrop(1, false, false, false, false), false, "enemy hero near")
	T.eq(F.SafeToDrop(0, true, false, false, false), false, "hit by a hero")
	T.eq(F.SafeToDrop(0, false, true, false, false), false, "retreating")
	T.eq(F.SafeToDrop(0, false, false, true, false), false, "fighting")
	T.eq(F.SafeToDrop(0, false, false, false, true), false, "casting")
end)

T.test("foreign items: the ground owner carries to the bag, and a marked name stays foreign", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_medusa" })
	local F = load("foreign_items")
	local prophet = T.stub.teams[bot:GetTeam()][2]
	local mushroom = T.stub.newAbility("item_foragers_mana", prophet, false)
	local salve = T.stub.newAbility("item_flask", bot, false)
	_G.GetDroppedItemList = function()
		return {
			{ item = mushroom, owner = prophet, location = T.stub.Vector(0, 0, 0) },
			{ item = salve, owner = bot, location = T.stub.Vector(10, 0, 0) },
		}
	end
	local list = F.DropList()
	T.eq(#list, 2, "two drops read")
	local byName = {}
	for _, entry in ipairs(list) do
		byName[entry.name] = entry
	end
	T.eq(byName.item_foragers_mana.ownerPid, prophet:GetPlayerID(), "owner player read from the owner unit")
	T.eq(byName.item_flask.ownerPid, bot:GetPlayerID(), "own drop")
	local foreign, owner, how = F.Check(bot, mushroom)
	T.eq(foreign, true, "the picked-up mushroom is foreign")
	T.eq(owner, (string.gsub(prophet:GetUnitName(), "^npc_dota_hero_", "")), "owner name")
	T.eq(how, "drop-list", "how")
	T.eq(F.Check(bot, salve), false, "own item")
	local other = T.stub.newAbility("item_foragers_health", bot, false)
	-- #116 (game 087): Medusa holds no Forager's Kit, so a mushroom with no known owner is not hers either.
	local noKit, _, noKitHow = F.Check(bot, other)
	T.eq(noKit, true, "a mushroom without a kit")
	T.eq(noKitHow, "no-kit", "how")
	F.MarkName(bot, "item_foragers_health", "unknown", "not-consumed")
	local again, _, why = F.Check(bot, other)
	T.eq(again, true, "marked by name")
	T.eq(why, "not-consumed", "how it was marked")
	T.eq(F.WasDropped(bot, "item_foragers_health"), false, "not dropped yet")
end)

T.test(
	"foreign items: a mushroom of the bot's own Forager's Kit is never marked not-consumed (#116, game 077)",
	function()
		local bot = T.stub.reset({ hero = "npc_dota_hero_puck" })
		local F = load("foreign_items")
		T.eq(F.IsOwnKitForage("item_foragers_mana", "item_foragers_kit"), true, "own kit, own mushroom")
		T.eq(F.IsOwnKitForage("item_foragers_mana", nil), false, "no kit")
		T.eq(F.IsOwnKitForage("item_flask", "item_foragers_kit"), false, "not a mushroom")
		bot._items[16] = T.stub.newAbility("item_foragers_kit", bot, false)
		T.eq(F.NeutralName(bot), "item_foragers_kit", "slot 16 read")
		T.eq(F.MarkName(bot, "item_foragers_mana", "unknown", "not-consumed"), false, "refused")
		local ringcap = T.stub.newAbility("item_foragers_mana", bot, false)
		T.eq(F.Check(bot, ringcap), false, "still the bot's own")
		T.eq(
			F.MarkName(bot, "item_foragers_mana", "nature_prophet", "drop-list"),
			true,
			"a drop-list owner still marks it"
		)
		bot._items[16] = nil
		T.eq(F.MarkName(bot, "item_foragers_health", "unknown", "not-consumed"), true, "no kit: marked as before")
	end
)

T.test("foreign items: a mushroom is the bot's only while it holds or held a Forager's Kit (#116, game 087)", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_puck" })
	local F = load("foreign_items")
	T.eq(F.NoKitForage("item_foragers_stats", false), true, "no kit: not edible")
	T.eq(F.NoKitForage("item_foragers_stats", true), false, "kit: edible")
	T.eq(F.NoKitForage("item_flask", false), false, "not a mushroom")
	local nut = T.stub.newAbility("item_foragers_stats", bot, false)
	local salve = T.stub.newAbility("item_flask", bot, false)
	local foreign, _, how = F.Check(bot, nut)
	T.eq(foreign, true, "Sven's mushroom in Puck's bag")
	T.eq(how, "no-kit", "how")
	T.eq(F.Check(bot, salve), false, "other items are not touched")
	bot._items[16] = T.stub.newAbility("item_foragers_kit", bot, false)
	T.eq(F.Check(bot, nut), false, "with the kit it is his")
	bot._items[16] = T.stub.newAbility("item_mana_draught", bot, false)
	T.eq(F.Check(bot, nut), false, "still his after the kit was replaced")
end)
