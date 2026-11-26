-- Neutral items (ability_item_usage_generic.lua): every neutral with an active in the 7.42 pool has a use rule,
-- and the rules added for 7.42 (#116) run in the stub without an error.
local T = ...
local Stub = T.stub

-- The 20 neutrals whose AbilityBehavior is not PASSIVE, from scripts/npc/neutral_items.txt and items.txt (7.42).
local ACTIVE_NEUTRALS = {
	"item_ash_legion_shield",
	"item_red_ledger",
	"item_polliwog_charm",
	"item_seeds_of_serenity",
	"item_kobold_cup",
	"item_stonefeather_satchel",
	"item_pogo_stick",
	"item_psychic_headband",
	"item_metamorphic_mandible",
	"item_jidi_pollen_bag",
	"item_brick",
	"item_crippling_crossbow",
	"item_mana_draught",
	"item_idol_of_screeauk",
	"item_fallen_sky",
	"item_flicker",
	"item_minotaur_horn",
	"item_heavy_blade",
	"item_demonicon",
	"item_riftshadow_prism",
}

local function loadUsage(opts)
	Stub.reset(opts)
	local ok, usage = Stub.load("ability_item_usage_generic")
	if not ok then
		error(tostring(usage), 0)
	end
	return usage
end

local function printedUse(itemName, why)
	for _, line in ipairs(Stub.printed) do
		if
			string.find(line, "[SHy-NEUTRAL]", 1, true)
			and string.find(line, "use item=" .. itemName .. " why=" .. why, 1, true)
		then
			return true
		end
	end
	return false
end

T.test("neutral items: every 7.42 active neutral has a use rule", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_lich" })
	for _, itemName in ipairs(ACTIVE_NEUTRALS) do
		T.eq(type(Usage.ConsiderItemDesire[itemName]), "function", itemName .. " rule")
	end
end)

T.test("neutral items: Red Ledger replaces only a list that paid nothing for 240 s", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_weaver", time = 1200 })
	local ledger = Stub.newAbility("item_red_ledger", Stub.bot)
	local rule = Usage.ConsiderItemDesire["item_red_ledger"]
	T.eq(rule(ledger), BOT_ACTION_DESIRE_NONE, "first look only records the list")
	Stub.time = 1200 + 120
	T.eq(rule(ledger), BOT_ACTION_DESIRE_NONE, "120 s without a bounty is not stale yet")
	Stub.time = 1200 + 241
	local desire, _, castType = rule(ledger)
	T.ok(desire > 0, "stale list is replaced")
	T.eq(castType, "none", "Red Ledger cast type")
	T.ok(printedUse("item_red_ledger", "stale-list"), "the use is logged")
	T.eq(rule(ledger), BOT_ACTION_DESIRE_NONE, "the new list gets its own 240 s")
end)

T.test("neutral items: Kobold Cup and Brick stay unused with nothing going on", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_ringmaster" })
	local cup = Stub.newAbility("item_kobold_cup", Stub.bot)
	local brick = Stub.newAbility("item_brick", Stub.bot)
	T.eq(Usage.ConsiderItemDesire["item_kobold_cup"](cup), BOT_ACTION_DESIRE_NONE, "Kobold Cup idle")
	T.eq(Usage.ConsiderItemDesire["item_brick"](brick), BOT_ACTION_DESIRE_NONE, "Brick idle")
end)

T.test("neutral items: Kobold Cup helps an ally beside the bot run from an enemy", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_ringmaster", slot = 5, time = 900 })
	local bot = Stub.bot
	local ally = Stub.teams[bot:GetTeam()][1]
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	ally._loc = bot:GetLocation() + Vector(300, 0, 0)
	enemy._loc = bot:GetLocation() + Vector(700, 0, 0)
	ally.GetActiveMode = function()
		return BOT_MODE_RETREAT
	end
	ally.GetActiveModeDesire = function()
		return 0.9
	end
	ally.WasRecentlyDamagedByAnyHero = function()
		return true
	end
	ally.DistanceFromFountain = function()
		return 5000
	end
	local cup = Stub.newAbility("item_kobold_cup", bot)
	local rule = Usage.ConsiderItemDesire["item_kobold_cup"]
	local desire, _, castType, why = rule(cup)
	T.ok(desire > 0, "used for the ally")
	T.eq(castType, "none", "Kobold Cup cast type")
	T.eq(why, "ally-escape", "reason")
	T.ok(printedUse("item_kobold_cup", "ally-escape"), "the use is logged")
	T.eq(rule(cup), BOT_ACTION_DESIRE_NONE, "no second order within the retry gap")
end)

T.test("neutral items: Brick is thrown at the bot's target in a fight (through ItemUsageThink)", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_clinkz", time = 1600 })
	local bot = Stub.bot
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	enemy._loc = bot:GetLocation() + Vector(500, 0, 0)
	bot.GetActiveMode = function()
		return BOT_MODE_ATTACK
	end
	bot.GetTarget = function()
		return enemy
	end
	local brick = Stub.newAbility("item_brick", bot)
	brick.IsFullyCastable = function()
		return true
	end
	brick.IsTrained = function()
		return true
	end
	brick.GetCastRange = function()
		return 600
	end
	brick.GetSpecialValueInt = function(_, key)
		return key == "damage" and 150 or 200
	end
	bot._items[16] = brick
	local orderedItem, orderedTarget = nil, nil
	bot.Action_UseAbilityOnEntity = function(_, item, target)
		orderedItem, orderedTarget = item, target
	end
	Usage.ItemUsageThink()
	T.eq(orderedItem, brick, "Brick ordered")
	T.eq(orderedTarget, enemy, "on the bot's target")
	T.ok(printedUse("item_brick", "fight"), "the use is logged")
	-- The rule's own line only: the neutral-slot use line (#116) is skipped for it.
	local brickLines = 0
	for _, line in ipairs(Stub.printed) do
		if string.find(line, "use item=item_brick", 1, true) then
			brickLines = brickLines + 1
		end
	end
	T.eq(brickLines, 1, "one use line for the Brick")
end)

T.test("neutral items: Mana Draught give rule (pure numbers)", function()
	local Rules = assert(loadstring(T.read("bots/lib/systems/neutral_rules.lua"), "neutral_rules"))()
	-- 90 + 3% of a 1000-mana caster (7.42 items.txt mana_restore, mana_restore_pct).
	T.near(Rules.ManaDraughtRestore(90, 3, 1000), 120, 1e-6, "restore")
	T.ok(Rules.ManaDraughtGiveWorth(0.9, 0.1, 500, 120), "full holder, empty ally")
	T.ok(not Rules.ManaDraughtGiveWorth(0.45, 0.05, 500, 120), "a holder below half drinks it itself")
	T.ok(not Rules.ManaDraughtGiveWorth(0.9, 0.35, 500, 120), "ally not low enough")
	T.ok(not Rules.ManaDraughtGiveWorth(0.55, 0.28, 500, 120), "gap too small")
	T.ok(not Rules.ManaDraughtGiveWorth(0.9, 0.1, 100, 120), "ally misses less than one draught")
end)

T.test("neutral items: Mana Draught goes to an ally out of mana, and a refused order is reported", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_crystal_maiden", slot = 5, time = 1200 })
	local bot = Stub.bot
	bot._maxMana, bot._mana = 1000, 900
	local ally = Stub.teams[bot:GetTeam()][1]
	ally._maxMana, ally._mana = 600, 60
	local draught = Stub.newAbility("item_mana_draught", bot)
	draught.GetCastRange = function()
		return 650
	end
	draught.GetSpecialValueInt = function(_, key)
		return (key == "mana_restore" and 90) or (key == "mana_restore_pct" and 3) or 0
	end
	local rule = Usage.ConsiderItemDesire["item_mana_draught"]
	local desire, target, castType, why = rule(draught)
	T.ok(desire > 0, "given")
	T.eq(target, ally, "to the ally out of mana")
	T.eq(castType, "unit", "cast on the ally")
	T.eq(why, "give", "reason")
	T.ok(printedUse("item_mana_draught", "give"), "the give is logged")
	Stub.time = 1205
	T.eq(rule(draught), BOT_ACTION_DESIRE_NONE, "still ready 5 s later: no second order")
	local refused = false
	for _, line in ipairs(Stub.printed) do
		if
			string.find(line, "give-result item=item_mana_draught", 1, true)
			and string.find(line, "result=refused", 1, true)
		then
			refused = true
		end
	end
	T.ok(refused, "the refused order is logged")
end)

T.test("neutral items: Mana Draught is not given to an ally with an enemy hero near", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_crystal_maiden", slot = 5, time = 1200 })
	local bot = Stub.bot
	bot._maxMana, bot._mana = 1000, 900
	local ally = Stub.teams[bot:GetTeam()][1]
	ally._maxMana, ally._mana = 600, 60
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	enemy._loc = ally:GetLocation() + Vector(500, 0, 0)
	local draught = Stub.newAbility("item_mana_draught", bot)
	T.eq(Usage.ConsiderItemDesire["item_mana_draught"](draught), BOT_ACTION_DESIRE_NONE, "kept")
end)

T.test("neutral items: Mana Draught self rule (pure numbers)", function()
	local Rules = assert(loadstring(T.read("bots/lib/systems/neutral_rules.lua"), "neutral_rules"))()
	-- Game 087: Largo at 0.65 of ~800 mana misses 280, more than one 114 restore.
	T.ok(Rules.ManaDraughtSelfWorth(280, 114, true), "misses a whole restore, calm")
	T.ok(not Rules.ManaDraughtSelfWorth(100, 114, true), "would waste part of it")
	T.ok(not Rules.ManaDraughtSelfWorth(500, 114, false), "an enemy hero could hit it: the effect would end")
	T.ok(not Rules.ManaDraughtSelfWorth(500, 0, true), "no restore read")
end)

local function farFromEveryone(bot)
	for _, team in pairs(Stub.teams) do
		for _, hero in pairs(team) do
			if hero ~= bot then
				hero._loc = Vector(7000, 7000, 0)
			end
		end
	end
end

T.test("neutral items: Mana Draught is drunk at 0.65 MP when nothing can hit the holder (#116, game 087)", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_largo", slot = 5, time = 1700 })
	local bot = Stub.bot
	farFromEveryone(bot)
	bot._maxMana, bot._mana = 800, 520
	local draught = Stub.newAbility("item_mana_draught", bot)
	local rule = Usage.ConsiderItemDesire["item_mana_draught"]
	local desire, target, castType, why = rule(draught)
	T.ok(desire > 0, "drunk")
	T.eq(target, bot, "on self")
	T.eq(castType, "none", "no-target order")
	T.eq(why, "self", "reason")
	T.ok(printedUse("item_mana_draught", "self"), "the use is logged")
	bot._mana = 760
	T.eq(rule(draught), BOT_ACTION_DESIRE_NONE, "kept when it would waste most of the restore")
end)

T.test("neutral items: Mana Draught is kept with an enemy hero close (an enemy hit ends the effect)", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_largo", slot = 5, time = 1700 })
	local bot = Stub.bot
	farFromEveryone(bot)
	bot._maxMana, bot._mana = 800, 200
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	enemy._loc = bot:GetLocation() + Vector(500, 0, 0)
	local draught = Stub.newAbility("item_mana_draught", bot)
	T.eq(Usage.ConsiderItemDesire["item_mana_draught"](draught), BOT_ACTION_DESIRE_NONE, "kept")
end)

-- #116 (game 087): Sven's mushrooms reached Puck, Largo and Brewmaster, none of whom held the kit. Each one's 14 eat
-- orders consumed nothing before it was dropped.
T.test("forager mushrooms: a bot without a Forager's Kit never orders an eat, and drops the mushroom once", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_puck", slot = 2, time = 1630 })
	local bot = Stub.bot
	farFromEveryone(bot)
	_G.GetDroppedItemList = function()
		return {}
	end
	local nut = Stub.newAbility("item_foragers_stats", bot)
	nut.IsFullyCastable = function()
		return true
	end
	nut.IsTrained = function()
		return true
	end
	bot._items[5] = nut
	local eats, drops = 0, 0
	bot.Action_UseAbility = function()
		eats = eats + 1
	end
	bot.Action_UseAbilityOnEntity = function()
		eats = eats + 1
	end
	bot.Action_DropItem = function(_, item)
		if item == nut then
			drops = drops + 1
		end
	end
	for step = 0, 9 do
		Stub.time = 1630 + step
		Usage.EatForage()
		Usage.DropForeignItems()
	end
	T.eq(eats, 0, "no eat order")
	T.eq(drops, 1, "dropped once")
	local noKit, dropLine = nil, nil
	for _, line in ipairs(Stub.printed) do
		if
			string.find(line, "[SHy-FORAGE]", 1, true) and string.find(line, "no-kit item=item_foragers_stats", 1, true)
		then
			noKit = line
		elseif string.find(line, "drop-foreign item=item_foragers_stats", 1, true) then
			dropLine = line
		end
	end
	T.ok(noKit ~= nil and string.find(noKit, "slot=5", 1, true), "no-kit line: " .. tostring(noKit))
	T.ok(dropLine ~= nil and string.find(dropLine, "how=no-kit", 1, true), "drop line: " .. tostring(dropLine))
end)

T.test("neutral items: Witchbane (Heavy Blade) is cast on a location, not a unit (through ItemUsageThink)", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_dazzle", slot = 5, time = 3100 })
	local bot = Stub.bot
	local ally = Stub.teams[bot:GetTeam()][1]
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	ally._loc = bot:GetLocation() + Vector(400, 0, 0)
	ally._hp = ally._maxHp * 0.5
	enemy._loc = ally:GetLocation() + Vector(150, 0, 0)
	ally.GetActiveMode = function()
		return BOT_MODE_ATTACK
	end
	ally.GetActiveModeDesire = function()
		return 0.9
	end
	ally.WasRecentlyDamagedByAnyHero = function()
		return true
	end
	local blade = Stub.newAbility("item_heavy_blade", bot)
	blade.IsFullyCastable = function()
		return true
	end
	blade.IsTrained = function()
		return true
	end
	blade.GetCastRange = function()
		return 700
	end
	bot._items[16] = blade
	local onLocation, onEntity = nil, nil
	bot.Action_UseAbilityOnLocation = function(_, item, loc)
		onLocation = { item = item, loc = loc }
	end
	bot.Action_UseAbilityOnEntity = function(_, item)
		onEntity = item
	end
	Usage.ItemUsageThink()
	T.ok(onLocation ~= nil and onLocation.item == blade, "Witchbane ordered on a location")
	T.ok(onEntity ~= blade, "not on a unit")
	T.near((onLocation.loc - ally:GetLocation()):Length2D(), 0, 1, "on the ally's spot")
	T.ok(printedUse("item_heavy_blade", "ally-fight"), "the use is logged")
end)

T.test(
	"neutral items: madstone bundles near the bot are logged when seen and when gone (item_purchase_generic)",
	function()
		local bot = Stub.reset({ hero = "npc_dota_hero_weaver", slot = 1, time = 300 })
		local bundle = {
			GetName = function()
				return "item_madstone_bundle"
			end,
			IsNull = function()
				return false
			end,
		}
		local onGround = true
		_G.GetDroppedItemList = function()
			if not onGround then
				return {}
			end
			return { { item = bundle, location = bot:GetLocation() + Vector(400, 0, 0) } }
		end
		-- Every other stub hero far away, so the bot is the hero nearest the bundle.
		for _, team in pairs(Stub.teams) do
			for _, hero in pairs(team) do
				if hero ~= bot then
					hero._loc = Vector(7000, 7000, 0)
				end
			end
		end
		local ok, err = Stub.load("item_purchase_generic")
		T.ok(ok, "item_purchase_generic loads: " .. tostring(err))
		for step = 1, 12 do
			Stub.time = 300 + step
			onGround = step <= 5
			pcall(_G.ItemPurchaseThink)
		end
		local seen, gone, waiting = nil, nil, nil
		for _, line in ipairs(Stub.printed) do
			if string.find(line, "madstone-bundle seen", 1, true) then
				seen = line
			elseif string.find(line, "madstone-bundle gone", 1, true) then
				gone = line
			elseif string.find(line, "no-neutral-yet", 1, true) then
				waiting = line
			end
		end
		T.ok(seen ~= nil and string.find(seen, "dist=400", 1, true), "seen: " .. tostring(seen))
		T.ok(gone ~= nil and string.find(gone, "fate=taken", 1, true), "gone: " .. tostring(gone))
		T.ok(waiting ~= nil and string.find(waiting, "bundlesSeen=", 1, true), "summary: " .. tostring(waiting))
		-- #116: the bot was the hero nearest the bundle, so it counts as its own; the first neutral item says so.
		T.ok(gone ~= nil and string.find(gone, "by=weaver", 1, true), "gone names the nearest hero: " .. tostring(gone))
		T.ok(gone ~= nil and string.find(gone, "own=1", 1, true), "own count: " .. tostring(gone))
		bot._items[16] = Stub.newAbility("item_kobold_cup", bot)
		for step = 13, 15 do
			Stub.time = 300 + step
			pcall(_G.ItemPurchaseThink)
		end
		local first, firstCount = nil, 0
		for _, line in ipairs(Stub.printed) do
			if string.find(line, "first-neutral", 1, true) then
				first, firstCount = line, firstCount + 1
			end
		end
		T.ok(first ~= nil and string.find(first, "item=item_kobold_cup own=1", 1, true), "first: " .. tostring(first))
		T.eq(firstCount, 1, "printed once")
	end
)

-- #116 (game 081): a use rule's order on the neutral slot prints one [SHy-NEUTRAL] use line, whatever the target.
T.test("neutral items: an order from the neutral slot prints a use line (unit, point, no target), throttled", function()
	local Usage = loadUsage({ hero = "npc_dota_hero_lich", slot = 5, time = 1500 })
	local bot = Stub.bot
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	local pogo = Stub.newAbility("item_pogo_stick", bot)
	pogo.IsFullyCastable = function()
		return true
	end
	pogo.IsTrained = function()
		return true
	end
	bot._items[16] = pogo
	local answer = { BOT_ACTION_DESIRE_HIGH, enemy, "unit", "test reason" }
	Usage.ConsiderItemDesire["item_pogo_stick"] = function()
		return answer[1], answer[2], answer[3], answer[4]
	end
	local function useLines()
		local lines = {}
		for _, line in ipairs(Stub.printed) do
			if
				string.find(line, "[SHy-NEUTRAL]", 1, true) and string.find(line, "use item=item_pogo_stick", 1, true)
			then
				lines[#lines + 1] = line
			end
		end
		return lines
	end
	Usage.ItemUsageThink()
	local enemyName = string.gsub(enemy:GetUnitName(), "npc_dota_hero_", "")
	local lines = useLines()
	T.eq(#lines, 1, "one use line")
	T.ok(
		lines[1] ~= nil and string.find(lines[1], "why=test_reason target=" .. enemyName .. " cast=unit", 1, true),
		"unit target: " .. tostring(lines[1])
	)
	Stub.time = 1505
	Usage.ItemUsageThink()
	T.eq(#useLines(), 1, "no second line within 10 s")
	Stub.time = 1516
	answer = { BOT_ACTION_DESIRE_HIGH, bot:GetLocation() + Vector(300, 0, 0), "ground", nil }
	Usage.ItemUsageThink()
	lines = useLines()
	T.ok(
		lines[2] ~= nil and string.find(lines[2], "why=- target=loc cast=ground", 1, true),
		"point target: " .. tostring(lines[2])
	)
	Stub.time = 1527
	answer = { BOT_ACTION_DESIRE_HIGH, nil, "none", "escape" }
	Usage.ItemUsageThink()
	lines = useLines()
	T.ok(
		lines[3] ~= nil and string.find(lines[3], "why=escape target=- cast=none", 1, true),
		"no target: " .. tostring(lines[3])
	)
end)

-- #116 (game 085): a bot swap of a backpack item with an occupied main slot never moved the mushroom; only an empty
-- main slot is used, and a bot with six full main slots waits.
T.test("forager mushrooms: swapped only into an empty main slot, else wait-slot (item_purchase_generic)", function()
	local bot = Stub.reset({ hero = "npc_dota_hero_venomancer", slot = 4, time = 1300 })
	for _, team in pairs(Stub.teams) do
		for _, hero in pairs(team) do
			if hero ~= bot then
				hero._loc = Vector(7000, 7000, 0)
			end
		end
	end
	for slot = 0, 5 do
		bot._items[slot] = Stub.newAbility(slot == 5 and "item_clarity" or "item_magic_wand", bot)
	end
	bot._items[6] = Stub.newAbility("item_foragers_health", bot)
	bot._items[16] = Stub.newAbility("item_foragers_kit", bot)
	local swaps = {}
	local originalSwap = _G.CDOTA_Bot_Script.ActionImmediate_SwapItems
	_G.CDOTA_Bot_Script.ActionImmediate_SwapItems = function(_, a, b)
		swaps[#swaps + 1] = { a, b }
		bot._swapCheck = { a = a, b = b, at = DotaTime() }
	end
	local ok, err = Stub.load("item_purchase_generic")
	T.ok(ok, "item_purchase_generic loads: " .. tostring(err))
	for step = 1, 4 do
		Stub.time = 1300 + step * 4
		pcall(_G.ItemPurchaseThink)
	end
	T.eq(#swaps, 0, "no swap with an occupied main slot")
	local waited = false
	for _, line in ipairs(Stub.printed) do
		if string.find(line, "wait-slot item=item_foragers_health slot=6 why=main-full", 1, true) then
			waited = true
		end
	end
	T.ok(waited, "wait-slot logged")
	bot._items[3] = nil
	for step = 5, 6 do
		Stub.time = 1300 + step * 4
		pcall(_G.ItemPurchaseThink)
	end
	T.ok(#swaps >= 1, "swapped once a main slot is free")
	T.ok(swaps[1] ~= nil and swaps[1][1] == 6 and swaps[1][2] == 3, "into the empty slot 3")
	_G.CDOTA_Bot_Script.ActionImmediate_SwapItems = originalSwap
end)
