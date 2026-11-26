-- Rubick stolen spells: a custom handler that declines owns the spell, and a spell with no
-- rubick_hero file is still cast (SmartCast) and has a steal weight.
local T = ...
local Stub = T.stub

local function loadRubick()
	Stub.reset({ hero = "npc_dota_hero_rubick", slot = 2 })
	local ok, result = Stub.load("bots/lib/hero/rubick")
	if not ok then
		error(tostring(result), 0)
	end
	return result
end

local function track(bot)
	local orders = {}
	local function record(kind)
		return function(_, ability)
			orders[#orders + 1] = { kind = kind, ability = ability:GetName() }
		end
	end
	bot.Action_UseAbilityOnEntity = record("entity")
	bot.Action_UseAbility = record("self")
	bot.ActionQueue_UseAbilityOnEntity = record("queue-entity")
	bot.ActionQueue_UseAbility = record("queue-self")
	bot.ActionQueue_UseAbilityOnLocation = record("queue-point")
	bot.Action_ClearActions = function() end
	return orders
end

local function stolen(bot, name, opts)
	opts = opts or {}
	local ability = bot:GetAbilityByName(name)
	ability._ultimate = opts.ultimate == true
	ability.IsFullyCastable = function()
		return true
	end
	ability.GetCastRange = function()
		return opts.range or 800
	end
	ability.GetBehavior = function()
		return opts.behavior or 8
	end
	ability.GetTargetTeam = function()
		return opts.team == nil and 2 or opts.team
	end
	ability.GetTargetType = function()
		return 1
	end
	ability.GetLevel = function()
		return opts.level or 3
	end
	ability.IsToggle = function()
		return opts.toggle == true
	end
	ability.GetToggleState = function()
		return opts.toggled == true
	end
	ability.GetAbilityDamage = function()
		return opts.damage or 0
	end
	return ability
end

local function placeEnemy(bot, hp)
	for _, enemy in ipairs(Stub.teams[GetOpposingTeam()]) do
		enemy._loc = bot._loc + Vector(9000, 0, 0)
	end
	local enemy = Stub.teams[GetOpposingTeam()][1]
	enemy._loc = bot._loc + Vector(100, 0, 0)
	enemy._hp = hp
	return enemy
end

local function logged(pattern)
	for _, line in ipairs(Stub.printed) do
		if string.find(line, pattern, 1, true) then
			return line
		end
	end
	return nil
end

T.test("rubick: a declined Culling Blade is not cast by SmartCast", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	placeEnemy(bot, 2000)
	-- Level 3 cull is 150 + 100 * 3 = 450 (the stolen-spell copy). 2000 is above it, and a team
	-- fight would make SmartCast throw the ultimate if the decline did not own the spell.
	X.ConsiderStolenSpell(stolen(bot, "axe_culling_blade", { ultimate = true, level = 3 }))
	T.eq(#orders, 0, "no order when the target is above the cull threshold")
	T.eq(logged("stolen-cast"), nil, "a decline is not a cast")
end)

T.test("rubick: Culling Blade casts on the custom path under the threshold", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	placeEnemy(bot, 50)
	X.ConsiderStolenSpell(stolen(bot, "axe_culling_blade", { ultimate = true, level = 3 }))
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "entity", "the Axe rule casts on the hero")
	T.eq(orders[1].ability, "axe_culling_blade", "culling blade")
	T.ok(logged("path=custom"), "the cast is logged as the custom path")
end)

T.test("rubick: a spell with no custom file is cast by SmartCast", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	local enemy = placeEnemy(bot, 2000)
	enemy.IsChanneling = function()
		return true
	end
	-- Zeus has no rubick_hero file. A channel in range is the unit-target rule in SmartCast.
	X.ConsiderStolenSpell(stolen(bot, "zuus_lightning_bolt"))
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "queue-entity", "SmartCast queues a unit-target spell")
	T.eq(orders[1].ability, "zuus_lightning_bolt", "lightning bolt")
	T.ok(logged("path=smart"), "the cast is logged as the smart path")
end)

T.test("rubick: a stolen toggle turns on in a fight", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	placeEnemy(bot, 2000)
	-- behavior 516 = NO_TARGET + TOGGLE (docs/BOT_API_RUNTIME.md). Morphling's attribute shift is 516
	-- (datafeed hero_id=10).
	X.ConsiderStolenSpell(stolen(bot, "morphling_morph_agi", { behavior = 516, team = 0, toggle = true }))
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "queue-self", "a toggle is cast on himself")
	T.ok(logged("path=smart"), "no custom file, so SmartCast owns it")
end)

T.test("rubick: a no-target spell with no team casts in a fight", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	placeEnemy(bot, 2000)
	-- Savage Roar: datafeed hero_id=80, behavior 4, target team 0.
	X.ConsiderStolenSpell(stolen(bot, "lone_druid_savage_roar", { behavior = 4, team = 0 }))
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "queue-self", "a self spell is cast with no target")
	T.ok(logged("path=smart"), "no custom file, so SmartCast owns it")
end)

T.test("rubick: steal weights cover heroes with no custom file", function()
	Stub.reset({ hero = "npc_dota_hero_rubick" })
	local ok, list = Stub.load("bots/lib/data/spell_prob_list")
	if not ok then
		error(tostring(list), 0)
	end
	T.eq(list.GetSpellReplaceWeight("bane_nightmare"), 0.2, "a weight in the short list stays")
	T.eq(list.GetSpellReplaceWeight("lone_druid_savage_roar"), 0.3, "lone druid was missing")
	T.eq(list.GetSpellReplaceWeight("morphling_waveform"), 0.4, "morphling was missing")
	T.eq(list.GetSpellReplaceWeight("rubick_telekinesis"), 0.2, "rubick was missing")
	T.eq(list.GetSpellReplaceWeight("pudge_meat_hook"), 0, "an uncovered hero uses the full table")
	T.eq(list.GetSpellReplaceWeight("not_a_real_spell"), 1, "an unknown spell stays replaceable")
end)
