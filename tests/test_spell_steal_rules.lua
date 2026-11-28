-- bots/lib/systems/spell_steal_rules.lua (#290): Rubick's Spell Steal choice by a score, not a chance roll, and the
-- enemy's last spell from bots/lib/systems/enemy_spell_tracker.lua.
local T = ...
local Stub = T.stub

local HERO_ABILITIES = assert(loadstring(T.read("tests/data/hero_abilities.lua"), "hero_abilities"))()

local function load()
	Stub.reset({ hero = "npc_dota_hero_rubick" })
	return require(GetScriptDirectory() .. "/lib/systems/spell_steal_rules")
end

-- Decide with the values Value gives for these spell names (info: what the handle reads, for a spell not in KIND).
local function decide(R, o)
	local incomingValue, incomingKind = 0, "unknown"
	if o.incoming ~= nil then
		incomingValue, incomingKind = R.Value(o.incoming, o.incomingInfo)
	end
	local heldValue = R.Value(o.held, o.heldInfo)
	return R.Decide({
		incoming = o.incoming,
		incomingValue = incomingValue,
		incomingKind = incomingKind,
		held = o.held,
		heldValue = heldValue,
		heldCd = o.heldCd or 0,
		heldDamage = o.heldDamage or 0,
		other = o.other,
		ultHold = o.ultHold or false,
	})
end

-- What the handle of Culling Blade reads (datafeed hero 2: ultimate, unit target, damage 475 at level 3... the API's
-- GetAbilityDamage may read another value; it is not in KIND, so it is scored from the handle).
local CULLING = { isUltimate = true, isAOE = false, isPassive = false, damage = 0 }

T.test("spell steal: a ready Earth Spike is kept over Culling Blade (game 089)", function()
	local R = load()
	local steal, why = decide(R, { incoming = "axe_culling_blade", incomingInfo = CULLING, held = "lion_impale" })
	T.eq(steal, false, "area disable ready: keep")
	T.eq(why, "keep", "why")
end)

T.test("spell steal: Earth Spike on a long cooldown gives way to Culling Blade", function()
	local R = load()
	local steal, why, heldScore = decide(R, {
		incoming = "axe_culling_blade",
		incomingInfo = CULLING,
		held = "lion_impale",
		heldCd = 10,
	})
	T.eq(steal, true, "on cooldown: steal")
	T.eq(why, "held-cooldown", "why")
	T.eq(heldScore, 25, "a quarter of 100")
	-- Real numbers: Earth Spike's cooldown is 14/13/12/11 (datafeed hero 26); a stolen one may run shorter
	-- (stolen_spell_cooldown_percent 10/20/30, datafeed hero 86, unverified), e.g. 7.7 s right after the cast. That
	-- still counts as on cooldown; with 3 s left it is ready for the next fight and kept.
	T.eq(
		(decide(R, { incoming = "axe_culling_blade", incomingInfo = CULLING, held = "lion_impale", heldCd = 7.7 })),
		true,
		"7.7 s left"
	)
	T.eq(
		(decide(R, { incoming = "axe_culling_blade", incomingInfo = CULLING, held = "lion_impale", heldCd = 3 })),
		false,
		"3 s left"
	)
end)

T.test("spell steal: an area disable beats a nuke, not the other way round", function()
	local R = load()
	local steal, why = decide(R, { incoming = "tidehunter_ravage", held = "axe_culling_blade", heldInfo = CULLING })
	T.eq(steal, true, "Ravage over a ready Culling Blade")
	T.eq(why, "better", "why")
	local nuke = { isUltimate = false, isAOE = true, isPassive = false, damage = 245 }
	T.eq(
		(decide(R, { incoming = "lina_dragon_slave", incomingInfo = nuke, held = "lion_impale" })),
		false,
		"a nuke does not replace Earth Spike"
	)
	T.eq(
		(decide(R, { incoming = "lion_voodoo", held = "lina_dragon_slave", heldInfo = nuke })),
		true,
		"Hex over a nuke"
	)
	T.eq((decide(R, { incoming = "lion_impale", held = "lion_voodoo" })), true, "Earth Spike over Hex")
end)

T.test("spell steal: the margin keeps nearly equal spells", function()
	local R = load()
	local steal, why = decide(R, { incoming = "tidehunter_ravage", held = "lion_impale" })
	T.eq(steal, false, "two area disables: keep")
	T.eq(why, "keep", "why")
	T.eq((decide(R, { incoming = "sven_storm_bolt", held = "enigma_black_hole" })), false, "Storm Bolt vs Black Hole")
	T.eq((decide(R, { incoming = "lion_voodoo", held = "shadow_shaman_voodoo" })), false, "two hexes")
	-- 50 (an ultimate) against 35 (an area nuke): equal to the margin is not enough.
	local nuke = { isUltimate = false, isAOE = true, isPassive = false, damage = 245 }
	T.eq(
		(
			decide(
				R,
				{ incoming = "axe_culling_blade", incomingInfo = CULLING, held = "lina_dragon_slave", heldInfo = nuke }
			)
		),
		false,
		"50 vs 35 + 15"
	)
end)

T.test("spell steal: same spell, the holds, empty slots and blind steals", function()
	local R = load()
	T.eq(
		select(2, decide(R, { incoming = "lion_impale", held = "lion_impale", heldCd = 10 })),
		"same",
		"holds it already"
	)
	T.eq(
		select(2, decide(R, { incoming = "lion_impale", held = "axe_culling_blade", other = "lion_impale" })),
		"same",
		"Scepter: in the other slot"
	)
	T.eq(
		select(2, decide(R, { incoming = "tidehunter_ravage", held = "axe_culling_blade", ultHold = true })),
		"hold-ult",
		"stolen ultimate, 60 s hold"
	)
	-- A strong spell ready within 5 s is kept, unless an area disable comes.
	local strong =
		{ held = "lina_laguna_blade", heldInfo = { isUltimate = true, damage = 690 }, heldDamage = 690, heldCd = 2 }
	strong.incoming = "lion_voodoo"
	T.eq(select(2, decide(R, strong)), "hold-strong", "Hex does not replace a ready Laguna Blade")
	strong.incoming = "lion_impale"
	T.eq((decide(R, strong)), true, "Earth Spike does")
	-- Empty slot: anything, also blind.
	T.eq(select(2, decide(R, { incoming = "axe_battle_hunger", held = "rubick_empty1" })), "empty", "empty slot")
	T.eq(select(2, decide(R, { held = "rubick_empty1" })), "empty-blind", "empty slot, last spell not known")
	-- Blind: counts as a nuke, never replaces a ready disable.
	T.eq(select(2, decide(R, { held = "lion_impale" })), "blind-keep", "blind vs Earth Spike")
	T.eq(select(2, decide(R, { held = "lion_impale", heldCd = 10 })), "blind-keep", "blind vs Earth Spike on cooldown")
	T.eq(
		select(2, decide(R, { held = "axe_culling_blade", heldInfo = CULLING, heldCd = 30 })),
		"blind",
		"blind vs an ultimate on cooldown"
	)
end)

T.test("spell steal: values from the hand table and from the handle", function()
	local R = load()
	T.eq((R.Value("lion_impale")), 100, "Earth Spike: area disable")
	T.eq((R.Value("lion_voodoo")), 70, "Hex: single-target disable")
	T.eq(
		select(2, R.Value("earthshaker_echo_slam", { isUltimate = true, damage = 180 })),
		"big",
		"Echo Slam: damage, no stun"
	)
	T.eq(
		select(2, R.Value("some_new_spell", { isUltimate = false, damage = 0 })),
		"utility",
		"unknown: never a disable"
	)
	T.eq(select(2, R.Value("some_new_spell", { isPassive = true })), "weak", "passive")
	T.eq(select(2, R.Value("some_new_spell", { damage = 320 })), "big", "300+ damage")
	T.eq((R.Value("some_new_spell", { damage = 100, isAOE = true })), 35, "area nuke")
	T.eq(select(3, R.Value("some_new_spell")), "none", "nothing read")
	T.eq((R.Value("rubick_empty2")), 0, "empty")
	T.eq(R.HeldScore(100, 4), 100, "4 s left: ready")
	T.eq(R.HeldScore(100, 4.1), 25, "over 4 s: a quarter")
end)

T.test("spell steal: every spell in the hand table exists in the game files", function()
	local R = load()
	local known = {}
	for _, slots in pairs(HERO_ABILITIES) do
		for _, entry in ipairs(slots) do
			known[(string.match(entry, "^[^|]+"))] = true
		end
	end
	for name, kind in pairs(R.KIND) do
		T.ok(known[name], name .. " is not an ability in tests/data/hero_abilities.lua")
		T.ok(R.VALUE[kind] ~= nil, name .. ": unknown kind " .. tostring(kind))
	end
end)

T.test("enemy spells: the cast callback keeps each enemy hero's last spell, not items or allies (#290)", function()
	Stub.reset({ hero = "npc_dota_hero_rubick" })
	local captured = nil
	_G.InstallCastCallback = function(_, callback)
		captured = callback
	end
	local ok, err = Stub.load("bots/heroes/hero_rubick")
	T.ok(ok, tostring(err))
	T.ok(captured ~= nil, "Rubick installs the cast callback")
	local E = require(GetScriptDirectory() .. "/lib/systems/enemy_spell_tracker")
	local enemy = Stub.teams[GetOpposingTeam()][1]
	local heroName = enemy:GetUnitName()
	T.eq(E.LastCast(heroName), nil, "nothing seen yet")
	Stub.time = 300
	captured({ unit = enemy, ability = Stub.newAbility("axe_berserkers_call", enemy, true) })
	Stub.time = 310
	captured({ unit = enemy, ability = Stub.newAbility("axe_culling_blade", enemy, true) })
	local spell, at = E.LastCast(heroName)
	T.eq(spell, "axe_culling_blade", "the last spell")
	T.eq(at, 310, "its time")
	Stub.time = 312
	captured({ unit = enemy, ability = Stub.newAbility("item_blink", enemy, true) })
	T.eq((E.LastCast(heroName)), "axe_culling_blade", "an item is not stolen and does not count")
	local ally = Stub.teams[GetTeam()][2]
	captured({ unit = ally, ability = Stub.newAbility("lion_impale", ally, false) })
	T.eq(E.LastCast(ally:GetUnitName()), nil, "an ally's cast: not kept")
	E.Reset()
	T.eq(E.LastCast(heroName), nil, "Reset forgets it")
end)
