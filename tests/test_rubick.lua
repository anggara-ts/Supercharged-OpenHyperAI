-- Rubick stolen spells (#271): a custom handler that declines owns the spell, a spell with no rubick_hero file is
-- still cast (SmartCast) and has a steal weight, and a stolen order ends Rubick's think.
local T = ...
local Stub = T.stub

local function loadRubick()
	Stub.reset({ hero = "npc_dota_hero_rubick", slot = 2, time = 600 })
	local ok, result = Stub.load("bots/lib/hero/rubick")
	if not ok then
		error(tostring(result), 0)
	end
	return result
end

local function track(bot)
	local orders = {}
	local function record(kind)
		return function(_, ability, target)
			orders[#orders + 1] = { kind = kind, ability = ability:GetName(), target = target }
		end
	end
	bot.Action_UseAbilityOnEntity = record("entity")
	bot.Action_UseAbilityOnLocation = record("point")
	bot.Action_UseAbility = record("self")
	bot.ActionQueue_UseAbilityOnEntity = record("queue-entity")
	bot.ActionQueue_UseAbility = record("queue-self")
	bot.ActionQueue_UseAbilityOnLocation = record("queue-point")
	bot.Action_ClearActions = function() end
	return orders
end

-- An ability of that name in Rubick's hands, castable. opts: ultimate, range, behavior (default 8 = unit target),
-- team (default 2 = enemy), level, toggle, toggled, damage, aoe.
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
	ability.GetAOERadius = function()
		return opts.aoe or 0
	end
	return ability
end

-- Every enemy far away, then enemy `index` (default 1) at `distance` (default 100) from Rubick with `hp` of 3000.
local function placeEnemy(bot, hp, distance, index)
	if index == nil then
		for _, enemy in ipairs(Stub.teams[GetOpposingTeam()]) do
			enemy._loc = bot._loc + Vector(9000, 0, 0)
		end
	end
	local enemy = Stub.teams[GetOpposingTeam()][index or 1]
	enemy._loc = bot._loc + Vector(distance or 100, 0, 0)
	enemy._maxHp = 3000
	enemy._hp = hp
	return enemy
end

-- The bot's mode, with a desire high enough to count (Fu.IsRetreating asks for more than moderate) and away from
-- the fountain.
local function setMode(bot, mode)
	bot.GetActiveMode = function()
		return mode
	end
	bot.GetActiveModeDesire = function()
		return 0.9
	end
	bot.DistanceFromFountain = function()
		return 5000
	end
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
	setMode(bot, BOT_MODE_ATTACK)
	-- 2000 HP of 3000 is above every Culling Blade level (datafeed 275/375/475). The ultimate rule would throw it
	-- at him (a hero below full HP in a fight) if the Axe file's decline did not own the spell.
	placeEnemy(bot, 2000)
	local cull = stolen(bot, "axe_culling_blade", { ultimate = true, level = 3 })
	local abilityInfo = X.ClassifyAbility(cull)
	T.ok(X.SmartCast(cull, abilityInfo) > 0, "the scenario: SmartCast alone would cast it")
	T.eq(X.ConsiderStolenSpell(cull), false, "no order")
	T.eq(#orders, 0, "no order when the target is above the cull threshold")
	T.eq(logged("stolen-cast"), nil, "a decline is not a cast")
end)

T.test("rubick: Culling Blade casts on the custom path under the threshold, and the line names the target", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	local enemy = placeEnemy(bot, 50)
	T.eq(X.ConsiderStolenSpell(stolen(bot, "axe_culling_blade", { ultimate = true, level = 3 })), true, "an order")
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "entity", "the Axe rule casts on the hero")
	T.eq(orders[1].ability, "axe_culling_blade", "culling blade")
	local line = logged("path=custom")
	T.ok(line, "the cast is logged as the custom path")
	local name = string.gsub(enemy:GetUnitName(), "npc_dota_hero_", "")
	T.ok(string.find(line, " target=" .. name .. " hp=50 radius=-", 1, true), line)
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
	T.ok(logged("path=smart why=rule"), "the cast is logged as the smart path")
end)

T.test("rubick: a point-target cast logs the location", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	local enemy = placeEnemy(bot, 2000)
	enemy.IsChanneling = function()
		return true
	end
	X.ConsiderStolenSpell(stolen(bot, "lina_light_strike_array", { behavior = 16 }))
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "queue-point", "a point spell is cast on a location")
	local at = enemy:GetLocation()
	local line = logged("spell=lina_light_strike_array")
	T.ok(line and string.find(line, string.format(" target=%.0f,%.0f ", at.x, at.y), 1, true), tostring(line))
end)

T.test("rubick: a unit-target answer with no unit gives no order and no line", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	placeEnemy(bot, 2000)
	X.SmartCast = function()
		return BOT_ACTION_DESIRE_HIGH, nil
	end
	T.eq(X.ConsiderStolenSpell(stolen(bot, "zuus_lightning_bolt")), false, "nothing to cast on")
	T.eq(#orders, 0, "no order")
	T.eq(logged("stolen-cast"), nil, "no line")
end)

T.test("rubick: a stolen toggle turns on in a fight, once", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_ATTACK)
	placeEnemy(bot, 2000)
	local rot = stolen(bot, "pudge_rot", { behavior = 516, team = 0, toggle = true })
	X.ConsiderStolenSpell(rot)
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].kind, "queue-self", "a toggle is cast on himself")
	T.ok(logged("why=toggle-on"), "no custom file, so SmartCast owns it")
	-- The state still reads off right after the order (Pudge's Rot, game 020): no second order for 1.5s.
	Stub.time = Stub.time + 0.5
	X.ConsiderStolenSpell(rot)
	T.eq(#orders, 1, "not toggled again while the state catches up")
	Stub.time = Stub.time + 1.5
	X.ConsiderStolenSpell(rot)
	T.eq(#orders, 2, "toggled again once the lock is over")
end)

T.test("rubick: a stolen toggle that is on stays on in a fight", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_ATTACK)
	placeEnemy(bot, 2000)
	X.ConsiderStolenSpell(stolen(bot, "pudge_rot", { behavior = 516, team = 0, toggle = true, toggled = true }))
	T.eq(#orders, 0, "an order would turn it off")
end)

T.test("rubick: a stolen toggle goes off while retreating and once the enemies are gone", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_RETREAT)
	placeEnemy(bot, 2000, 800)
	X.ConsiderStolenSpell(stolen(bot, "pudge_rot", { behavior = 516, team = 0, toggle = true, toggled = true }))
	T.eq(#orders, 1, "off while retreating with an enemy 800 away")
	T.ok(logged("why=toggle-off"), "logged as toggle-off")
	orders = track(bot)
	setMode(bot, BOT_MODE_ATTACK)
	placeEnemy(bot, 2000, 5000)
	local nova = stolen(bot, "leshrac_pulse_nova", { behavior = 516, team = 0, toggle = true, toggled = true })
	X.ConsiderStolenSpell(nova)
	T.eq(#orders, 1, "off with no enemy within 1600")
end)

T.test("rubick: a stolen attribute shift is never toggled", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_ATTACK)
	placeEnemy(bot, 2000)
	-- behavior 516 = NO_TARGET + TOGGLE (datafeed hero_id=10).
	X.ConsiderStolenSpell(stolen(bot, "morphling_morph_agi", { behavior = 516, team = 0, toggle = true }))
	T.eq(#orders, 0, "it moves Rubick's own Strength away")
end)

T.test("rubick: a no-target spell with no team needs an enemy within its radius", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_ROAM)
	-- Savage Roar: datafeed hero_id=80, behavior 4, target team 0.
	local roar = stolen(bot, "lone_druid_savage_roar", { behavior = 4, team = 0, aoe = 350 })
	placeEnemy(bot, 2000, 1000)
	X.ConsiderStolenSpell(roar)
	T.eq(#orders, 0, "an enemy 1000 away is out of a 350 roar")
	placeEnemy(bot, 2000, 300)
	X.ConsiderStolenSpell(roar)
	T.eq(#orders, 1, "one cast with an enemy at 300")
	T.eq(orders[1].kind, "queue-self", "a self spell is cast with no target")
	T.ok(logged("radius=350"), "the line prints the radius it used")
end)

T.test("rubick: a no-target ultimate with no team keeps the ultimate rule", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_ATTACK)
	-- Ravage: datafeed behavior 4, target team 0, an ultimate.
	local ravage = stolen(bot, "tidehunter_ravage", { ultimate = true, behavior = 4, team = 0, aoe = 400 })
	placeEnemy(bot, 2000, 100)
	X.ConsiderStolenSpell(ravage)
	T.eq(#orders, 0, "one enemy is not enough for an ultimate")
	-- A second enemy within 1600 but outside the radius still is not.
	placeEnemy(bot, 2000, 1000, 2)
	X.ConsiderStolenSpell(ravage)
	T.eq(#orders, 0, "two enemies in 1600, one within the radius")
	placeEnemy(bot, 2000, 300, 2)
	X.ConsiderStolenSpell(ravage)
	T.eq(#orders, 1, "two enemies within the radius")
end)

T.test("rubick: every spell a handler names returns cast or true", function()
	local handlers = {}
	for _, path in ipairs(T.files("^bots/lib/hero/rubick_hero/.*%.lua$")) do
		handlers[#handlers + 1] = path
	end
	T.ok(#handlers >= 21, #handlers .. " handler files")
	for _, path in ipairs(handlers) do
		local source = T.read(path)
		local body = string.match(source, "function X%.ConsiderStolenSpell%(%w+%)(.-)\nend\n")
		T.ok(body, path .. ": ConsiderStolenSpell")
		local names = {}
		for name in string.gmatch(body, 'abilityName == "([%w_]+)"') do
			names[name] = true
		end
		for name in pairs(names) do
			loadRubick()
			local bot = GetBot()
			track(bot)
			local ok, module = Stub.load(path)
			T.ok(ok, path .. ": " .. tostring(module))
			local ability = stolen(bot, name)
			local okCall, answer = pcall(module.ConsiderStolenSpell, ability)
			T.ok(okCall, path .. " " .. name .. ": " .. tostring(answer))
			T.ok(answer == "cast" or answer == true, path .. " " .. name .. " returns " .. tostring(answer))
		end
	end
end)

T.test("rubick: a stolen order ends the think, so Telekinesis does not clear it", function()
	Stub.reset({ hero = "npc_dota_hero_rubick", slot = 2, time = 600 })
	local bot = GetBot()
	local zeusBolt = stolen(bot, "zuus_lightning_bolt")
	bot._slots[3] = zeusBolt
	local ok, hero = Stub.load("heroes/hero_rubick")
	T.ok(ok, tostring(hero))
	local orders = track(bot)
	local enemy = placeEnemy(bot, 2000, 300)
	enemy.IsChanneling = function()
		return true
	end
	enemy.GetLevel = function()
		return 20
	end
	-- Telekinesis lifts a channelling enemy (hero_rubick.lua ConsiderTelekinesis) with Action_UseAbilityOnEntity,
	-- which would clear the queued stolen cast if the think went on.
	local telekinesis = bot:GetAbilityByName("rubick_telekinesis")
	telekinesis.IsFullyCastable = function()
		return true
	end
	telekinesis.GetCastRange = function()
		return 1000
	end
	T.ok(hero.ConsiderTelekinesis() > 0, "the scenario: Telekinesis would lift him")
	hero.SkillsComplement()
	T.ok(#orders >= 1, "the stolen bolt is cast")
	T.eq(orders[1].ability, "zuus_lightning_bolt", "the stolen bolt first")
	T.eq(#orders, 1, "and nothing after it in the same think")
end)

T.test("rubick: steal scores cover heroes with no custom file, and Morphling's hero lookup is unchanged", function()
	-- #290 replaced the replace weights (spell_prob_list.lua, which #272 extended to Lone Druid, Morphling and
	-- Rubick) with bots/lib/systems/spell_steal_rules.lua: their disables are in its hand table, the rest is scored
	-- from the handle and never as a disable.
	Stub.reset({ hero = "npc_dota_hero_rubick" })
	local ok, rules = Stub.load("bots/lib/systems/spell_steal_rules")
	if not ok then
		error(tostring(rules), 0)
	end
	T.eq(select(2, rules.Value("bane_nightmare")), "single_disable", "a listed disable")
	T.eq(select(2, rules.Value("lone_druid_savage_roar")), "area_disable", "lone druid's fear")
	T.eq(select(2, rules.Value("morphling_adaptive_strike_agi")), "single_disable", "morphling's stun")
	T.eq(select(2, rules.Value("rubick_telekinesis")), "single_disable", "an enemy rubick's lift")
	T.eq(select(2, rules.Value("morphling_waveform", { damage = 0 })), "utility", "an unlisted spell: not a disable")
	T.eq(select(2, rules.Value("lone_druid_spirit_link", { isPassive = true })), "weak", "a passive stays low")
	T.eq(select(2, rules.Value("not_a_real_spell")), "utility", "an unknown spell")
	local okFull, full = Stub.load("bots/lib/data/spell_list")
	if not okFull then
		error(tostring(full), 0)
	end
	-- hero_morphling.lua finds a replicated spell's hero here: the three heroes must not be in it.
	T.eq(full.GetSpellHeroName("lone_druid_savage_roar"), nil, "lone druid is not in the full table")
	T.eq(full.GetSpellHeroName("morphling_waveform"), nil, "nor morphling")
	T.eq(full.GetSpellHeroName("rubick_telekinesis"), nil, "nor rubick")
	T.eq(full.GetSpellHeroName("pudge_meat_hook"), "npc_dota_hero_pudge", "a listed spell's hero")
	T.eq(full.GetSpellReplaceWeight("pudge_meat_hook"), 0, "and its weight")
end)

-- Pre-existing bugs in the stolen-spell copies, fixed as in the heroes' own files on main.

T.test("rubick: stolen Culling Blade uses the datafeed damage and goes through debuff immunity", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	-- Level 3: datafeed 475 (the copy had 150 + 100 * 3 = 450). 460 HP is a kill now.
	local enemy = placeEnemy(bot, 460)
	enemy.IsMagicImmune = function()
		return true
	end
	X.ConsiderStolenSpell(stolen(bot, "axe_culling_blade", { ultimate = true, level = 3 }))
	T.eq(#orders, 1, "culled at 460 HP through BKB (datafeed immunity 3)")
	T.eq(orders[1].target, enemy, "on that hero")
end)

T.test("rubick: stolen Mist Coil reads damage_heal and finishes an enemy", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	local enemy = placeEnemy(bot, 100, 400)
	enemy.GetActualIncomingDamage = function(_, damage)
		return damage * 0.75
	end
	local coil = stolen(bot, "abaddon_death_coil", { range = 625 })
	coil.GetSpecialValueInt = function(_, key)
		-- Valve datafeed hero_id=102: damage_heal 95/170/245/320; there is no target_damage.
		return key == "damage_heal" and 320 or 0
	end
	X.ConsiderStolenSpell(coil)
	T.eq(#orders, 1, "one cast")
	T.eq(orders[1].target, enemy, "the coil kills the enemy at 100 HP")
end)

T.test("rubick: stolen Burning Barrage uses its range and arrow width", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	setMode(bot, BOT_MODE_ATTACK)
	local enemy = placeEnemy(bot, 2000, 600)
	bot.GetTarget = function()
		return enemy
	end
	-- Valve datafeed hero_id=56: no cast range, "range" 850, "projectile_width" 200.
	local barrage = stolen(bot, "clinkz_burning_barrage", { range = 0, behavior = 16 })
	barrage.GetSpecialValueInt = function(_, key)
		return ({ range = 850, projectile_width = 200 })[key] or 0
	end
	barrage.IsTrained = function()
		return true
	end
	X.ConsiderStolenSpell(barrage)
	T.eq(#orders, 1, "cast at an enemy 600 away")
end)

T.test("rubick: an empty stolen slot does not stop the think", function()
	Stub.reset({ hero = "npc_dota_hero_rubick", slot = 2, time = 600 })
	local bot = GetBot()
	local ok, hero = Stub.load("heroes/hero_rubick")
	T.ok(ok, tostring(hero))
	track(bot)
	bot._slots[3] = nil
	local steal = bot:GetAbilityByName("rubick_spell_steal")
	steal.IsFullyCastable = function()
		return true
	end
	placeEnemy(bot, 2000, 300)
	local okThink, problem = pcall(hero.SkillsComplement)
	T.ok(okThink, "no error with slot 3 empty: " .. tostring(problem))
end)

T.test("rubick: every steal weight is on the 0 keep .. 1 replace scale", function()
	Stub.reset({ hero = "npc_dota_hero_rubick" })
	local okFull, full = Stub.load("bots/lib/data/spell_list")
	if not okFull then
		error(tostring(full), 0)
	end
	for heroName, spells in pairs(full.spells) do
		for spellName, data in pairs(spells) do
			T.ok(data.weight >= 0 and data.weight <= 1, heroName .. " " .. spellName .. " weight " .. data.weight)
		end
	end
end)

-- Last will: a stolen spell is lost when Rubick dies (datafeed hero_id=86, Spell Steal "until he dies").

-- Rubick at `hp` of 1000, hit a moment ago, alone (no team fight), with one enemy `distance` away who deals
-- `incoming` in two seconds.
local function aboutToDie(bot, hp, incoming, distance)
	for _, ally in ipairs(Stub.teams[GetTeam()]) do
		if ally ~= bot then
			ally._loc = bot._loc - Vector(9000, 0, 0)
		end
	end
	bot._hp = hp
	bot.WasRecentlyDamagedByAnyHero = function()
		return true
	end
	local enemy = placeEnemy(bot, 2500, distance or 500)
	enemy.GetEstimatedDamageToTarget = function()
		return incoming
	end
	return enemy
end

T.test("rubick: last will casts a held stolen nuke at an enemy when he is about to die", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	local enemy = aboutToDie(bot, 150, 400)
	-- Out of a fight, the enemy healthy: no other SmartCast rule would cast it.
	X.ConsiderStolenSpell(stolen(bot, "lina_laguna_blade_like", { behavior = 8, damage = 0 }))
	T.eq(#orders, 1, "cast before he dies")
	T.eq(orders[1].target, enemy, "at the enemy in range")
	T.ok(logged("why=last-will"), "logged as the last will")
	T.ok(logged(" self_hp=150 incoming=400"), "with his HP and the damage he expects")
end)

T.test("rubick: last will waits while he can still live", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	aboutToDie(bot, 600, 400)
	local nuke = stolen(bot, "lina_laguna_blade_like", { behavior = 8 })
	X.ConsiderStolenSpell(nuke)
	T.eq(#orders, 0, "60% HP is not a last will")
	aboutToDie(bot, 600, 700)
	X.ConsiderStolenSpell(nuke)
	T.eq(#orders, 0, "at 60% HP he can still walk away")
	aboutToDie(bot, 150, 100)
	X.ConsiderStolenSpell(nuke)
	T.eq(#orders, 0, "the enemies near would not kill him in two seconds")
	aboutToDie(bot, 150, 400, 1400)
	X.ConsiderStolenSpell(nuke)
	T.eq(#orders, 0, "the only enemy is out of reach")
end)

T.test("rubick: last will casts a stolen ultimate on one enemy, and a no-target ally spell out of a fight", function()
	local X = loadRubick()
	local bot = GetBot()
	local orders = track(bot)
	local enemy = aboutToDie(bot, 150, 400)
	local finger = stolen(bot, "lion_finger_of_death", { ultimate = true, behavior = 8 })
	T.eq(
		X.ConsiderUltimate(finger, X.ClassifyAbility(finger), {}, {}, 1000, 300, false),
		BOT_ACTION_DESIRE_NONE,
		"the scenario: the ultimate rule alone would hold it (no fight, one enemy)"
	)
	X.ConsiderStolenSpell(finger)
	T.eq(#orders, 1, "an ultimate needs no second enemy now")
	T.eq(orders[1].target, enemy, "at the enemy")
	orders = track(bot)
	X.ConsiderStolenSpell(stolen(bot, "omniknight_guardian_angel_like", { behavior = 4, team = 1 }))
	T.eq(#orders, 1, "a no-target ally spell without a team fight")
	T.eq(orders[1].kind, "queue-self", "cast around him")
end)

T.test("rubick: last will throws his own Fade Bolt", function()
	Stub.reset({ hero = "npc_dota_hero_rubick", slot = 2, time = 600 })
	local bot = GetBot()
	local ok, hero = Stub.load("heroes/hero_rubick")
	T.ok(ok, tostring(hero))
	local bolt = bot:GetAbilityByName("rubick_fade_bolt")
	bolt.IsFullyCastable = function()
		return true
	end
	bolt.GetCastRange = function()
		return 800
	end
	local enemy = aboutToDie(bot, 150, 400)
	local desire, target = hero.ConsiderFadeBolt()
	T.eq(desire, BOT_ACTION_DESIRE_VERYHIGH, "the bolt goes before he dies")
	T.eq(target, enemy, "at the enemy")
	T.ok(logged("own-cast spell=rubick_fade_bolt path=own why=last-will"), "logged")
	-- Healthy, the bolt is left to the usual rules (here the team-fight rule may still throw it, at HIGH).
	bot._hp = 900
	Stub.printed = {}
	Stub.time = Stub.time + 5
	T.ok(hero.ConsiderFadeBolt() < BOT_ACTION_DESIRE_VERYHIGH, "no last-will desire at 90% HP")
	T.eq(logged("why=last-will"), nil, "and no last-will line")
end)
