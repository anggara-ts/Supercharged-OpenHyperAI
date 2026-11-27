-- bots/lib/systems/chain_rules.lua (#228, [SHy-CHAIN]): a stun or hex ordered on an enemy hero whose running stun
-- outlasts the new one's landing is held until the time left is down to what it needs; a disable that goes through
-- reserves the hero for the team; Fu.IsDisabled calls the hero free for the holding bot once his stun is about to end.
local T = ...
local Stub = T.stub

local function load()
	local bot = Stub.reset({ hero = "npc_dota_hero_sven", time = 600 })
	local Chain = require(GetScriptDirectory() .. "/lib/systems/chain_rules")
	Chain.Reset()
	return bot, Chain
end

local function lines(text)
	local found = {}
	for _, line in ipairs(Stub.printed) do
		if string.find(line, text, 1, true) then
			found[#found + 1] = line
		end
	end
	return found
end

-- A plain fake unit: only what chain_rules asks.
local function fakeHero(props)
	local unit = {
		name = props.name,
		team = props.team,
		loc = props.loc,
		stunned = props.stunned or false,
		hexed = props.hexed or false,
		channeling = props.channeling or false,
		mods = props.mods or {},
		hp = props.hp or 1000,
		maxHp = props.maxHp or 1000,
		mode = props.mode or BOT_MODE_ATTACK,
		attacks = {},
		moves = {},
	}
	unit._loc = props.loc
	function unit:GetLocation()
		return self._loc
	end
	function unit:GetUnitName()
		return self.name
	end
	function unit:GetTeam()
		return self.team
	end
	function unit:IsNull()
		return false
	end
	function unit:IsHero()
		return true
	end
	function unit:IsIllusion()
		return false
	end
	function unit:IsAlive()
		return true
	end
	function unit:IsStunned()
		return self.stunned
	end
	function unit:IsHexed()
		return self.hexed
	end
	function unit:IsChanneling()
		return self.channeling
	end
	function unit:NumModifiers()
		return #self.mods
	end
	function unit:GetModifierName(i)
		local mod = self.mods[i + 1]
		return mod and mod[1] or ""
	end
	function unit:GetModifierRemainingDuration(i)
		local mod = self.mods[i + 1]
		return mod and mod[2] or -1
	end
	function unit:GetHealth()
		return self.hp
	end
	function unit:GetMaxHealth()
		return self.maxHp
	end
	function unit:GetActiveMode()
		return self.mode
	end
	function unit:GetCurrentMovementSpeed()
		return 300
	end
	function unit:GetTarget()
		return self.target
	end
	function unit:Action_AttackUnit(target)
		self.attacks[#self.attacks + 1] = target
	end
	function unit:Action_MoveToUnit(target)
		self.moves[#self.moves + 1] = target
	end
	return unit
end

local function fakeAbility(name, castPoint, values, castRange)
	return {
		GetName = function()
			return name
		end,
		GetCastPoint = function()
			return castPoint
		end,
		GetSpecialValueFloat = function(_, key)
			return values[key] or 0
		end,
		GetCastRange = function()
			return castRange or 600
		end,
	}
end

local function setup()
	local _, Chain = load()
	local sven = fakeHero({ name = "npc_dota_hero_sven", team = TEAM_RADIANT, loc = Vector(0, 0, 0) })
	local lion = fakeHero({ name = "npc_dota_hero_lion", team = TEAM_RADIANT, loc = Vector(300, 0, 0) })
	local axe = fakeHero({ name = "npc_dota_hero_axe", team = TEAM_DIRE, loc = Vector(600, 0, 0) })
	local bolt = fakeAbility("sven_storm_bolt", 0.2, { bolt_speed = 1000, bolt_stun_duration = 1.5 })
	local hex = fakeAbility("lion_voodoo", 0, { duration = 2.4 })
	return Chain, sven, lion, axe, bolt, hex
end

local function stun(unit, left, name)
	unit.stunned = true
	unit.mods = { { "modifier_item_phase_boots", -1 }, { name or "modifier_stunned", left } }
end

T.test("chain: need = cast point + delay + travel + walk + margin", function()
	local _, Chain = load()
	-- Storm Bolt from 600: 0.2 cast point + 600 / 1000 travel.
	T.near(Chain.Need(0.2, 0, 600, 1000, 600, 300), 0.2 + 0.6 + Chain.MARGIN, 1e-9, "bolt in range")
	-- From 900 with 600 range: walk 300 at 300 speed, then 600 of flight.
	T.near(Chain.Need(0.2, 0, 900, 1000, 600, 300), 0.2 + 0.6 + 1 + Chain.MARGIN, 1e-9, "bolt out of range")
	-- Light Strike Array: 0.45 cast point + 0.5 delay, no projectile.
	T.near(Chain.Need(0.45, 0.5, 500, nil, 700, 300), 0.95 + Chain.MARGIN, 1e-9, "LSA")
end)

T.test("chain: hold while the running stun outlasts the landing, cast near its end", function()
	local _, Chain = load()
	T.eq(Chain.Decide(2.0, 0.5, 0, false), "hold", "1.5s too early")
	T.eq(Chain.Decide(0.6, 0.5, 0, false), "cast", "within MIN_HOLD of the end")
	T.eq(Chain.Decide(nil, 0.5, 0, false), "cast", "no running stun")
	T.eq(Chain.Decide(3.0, 0.5, 0, true), "cast", "blocked (channel / retreat / low HP)")
	T.eq(Chain.Decide(3.0, 0.5, Chain.HOLD_CAP, false), "cast", "held for HOLD_CAP already")
	T.eq(Chain.SaneLeft(-1), nil, "a permanent modifier reads -1")
	T.eq(Chain.SaneLeft(30), nil, "a long buff is not a stun")
	T.eq(Chain.SaneLeft(1.2), 1.2, "a stun")
end)

T.test("chain: the countdown self-check switches the rule off when the read does not count down", function()
	local _, Chain = load()
	T.eq(Chain.Countdown(2.0, 10, 1.5, 10.5), "yes", "0.5s later, 0.5s less")
	T.eq(Chain.Countdown(2.0, 10, 2.0, 10.5), "no", "the same value 0.5s later")
	T.eq(Chain.Countdown(2.0, 10, 1.9, 10.1), nil, "too close together")
	T.eq(Chain.Countdown(1.0, 10, 1.8, 10.5), nil, "a new stun refreshed it")
	T.eq(Chain.Record("no"), false, "one failure keeps it on")
	T.eq(Chain.Record("no"), true, "two failures and no pass: off")
	T.eq(Chain.enabled, false, "off")
	Chain.Reset()
	Chain.Record("yes")
	Chain.Record("no")
	T.eq(Chain.Record("no"), false, "a passed check keeps it on")
end)

T.test("chain: Storm Bolt on a hero stunned for 2s more is held; the bot attacks him instead", function()
	local Chain, sven, _, axe, bolt = setup()
	stun(axe, 2.0)
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), true, "held")
	T.eq(#sven.attacks, 1, "one attack order")
	T.ok(sven.attacks[1] == axe, "on the stunned hero")
	T.eq(#lines("[SHy-CHAIN] t=600 sven hold hero=axe spell=sven_storm_bolt left=2.00 need=1.05"), 1, "hold line")
	T.eq(Chain.live, 1, "one live stamp")
	-- 1.0s later 1.0s is left: still more than the 1.05s need + MIN_HOLD? No: 1.0 - 1.05 < 0.15, so it goes.
	Stub.time = 601
	stun(axe, 1.0)
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "cast")
	local cast = lines("[SHy-CHAIN] t=601 sven cast hero=axe spell=sven_storm_bolt left=1.00 need=1.05 gap=-0.05")
	T.eq(#cast, 1, "cast line")
	T.ok(string.find(cast[1], "held=1.00 real=yes", 1, true) ~= nil, "held 1s, the read counted down")
end)

T.test("chain: no hold on a channelling hero, while retreating or at low HP, or for a damage spell", function()
	local Chain, sven, _, axe, bolt = setup()
	stun(axe, 2.0)
	axe.channeling = true
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "channelling")
	axe.channeling = false
	sven.mode = BOT_MODE_RETREAT
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "retreating")
	sven.mode = BOT_MODE_ATTACK
	sven.hp = 200
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "low HP")
	sven.hp = 1000
	local nuke = fakeAbility("lina_laguna_blade", 0.35, {})
	T.eq(Chain.OnCast(sven, nuke, axe, "entity"), false, "a damage spell is never held")
	local ally = fakeHero({ name = "npc_dota_hero_lion", team = TEAM_RADIANT, loc = Vector(100, 0, 0) })
	stun(ally, 2.0)
	T.eq(Chain.OnCast(sven, bolt, ally, "entity"), false, "an ally")
	T.eq(#sven.attacks, 0, "no attack order")
end)

T.test("chain: a root or silence, an unread time or an unlisted modifier never holds", function()
	local Chain, sven, _, axe, bolt = setup()
	axe.mods = { { "modifier_stunned", 2.0 } } -- listed, but the engine does not call him stunned (a root)
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "not stunned")
	stun(axe, 2.0, "modifier_some_new_stun")
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "unlisted modifier")
	-- The disable-looking name comes first, the count names every unlisted modifier.
	local unknown = "[SHy-CHAIN] t=600 sven unknown hero=axe spell=sven_storm_bolt n=2 "
		.. "mods=modifier_some_new_stun,modifier_item_phase_boots"
	T.eq(#lines(unknown), 1)
	stun(axe, -1)
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "a -1 read")
end)

T.test("chain: the team reservation holds a second disable until the first one lands and ends", function()
	local Chain, sven, lion, axe, bolt, hex = setup()
	-- Sven's bolt goes out (Axe free): lands 0.8s later, stuns 1.5s.
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "bolt goes")
	-- Lion's hex in the same frame waits: the bolt's stun ends at 600 + 0.8 + 1.5.
	T.eq(Chain.OnCast(lion, hex, axe, "entity"), true, "hex held")
	local hold = lines("[SHy-CHAIN] t=600 lion hold hero=axe spell=lion_voodoo left=2.30 need=0.25")
	T.eq(#hold, 1, "hold line from the claim")
	T.ok(string.find(hold[1], "src=claim", 1, true) ~= nil, "src=claim")
	-- Sven's own re-issued order is not held by his own reservation.
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), false, "own claim ignored")
	-- The bolt landed: Lion's hero file now skips Axe (Fu.IsDisabled), until 0.4s or less are left.
	Stub.time = 601
	stun(axe, 1.3)
	T.eq(Chain.ReleaseEarly(lion, axe), false, "1.3s left: still disabled for Lion")
	T.eq(Chain.ReleaseEarly(sven, axe), false, "Sven holds nothing")
	Stub.time = 601.9
	stun(axe, 0.35)
	T.eq(Chain.ReleaseEarly(lion, axe), true, "0.35s left: free for Lion")
	T.eq(Chain.OnCast(lion, hex, axe, "entity"), false, "hex goes")
	T.eq(#lines("[SHy-CHAIN] t=602 lion cast hero=axe spell=lion_voodoo left=0.35 need=0.25 gap=0.10"), 1)
	-- The stamp stays until the hex has landed, so the re-issued order keeps going through.
	T.eq(Chain.ReleaseEarly(lion, axe), true, "still free while the hex is on its way")
	Stub.time = 602.3
	axe.hexed, axe.mods = true, { { "modifier_lion_voodoo", 2.0 } }
	T.eq(Chain.ReleaseEarly(lion, axe), false, "the hex landed")
end)

T.test("chain: a point disable counts for the bot's target at the point", function()
	local _, Chain = load()
	local lina = fakeHero({ name = "npc_dota_hero_lina", team = TEAM_RADIANT, loc = Vector(0, 0, 0) })
	local axe = fakeHero({ name = "npc_dota_hero_axe", team = TEAM_DIRE, loc = Vector(500, 0, 0) })
	local lsa = fakeAbility("lina_light_strike_array", 0.45, {
		light_strike_array_delay_time = 0.5,
		light_strike_array_stun_duration = 1.6,
	}, 700)
	stun(axe, 2.5)
	T.eq(Chain.OnCast(lina, lsa, Vector(500, 0, 0), "location"), false, "no target: no rule")
	lina.target = axe
	T.eq(Chain.OnCast(lina, lsa, Vector(1500, 0, 0), "location"), false, "point far from the target")
	T.eq(Chain.OnCast(lina, lsa, Vector(520, 0, 0), "location"), true, "held")
	T.eq(#lines("[SHy-CHAIN] t=600 lina hold hero=axe spell=lina_light_strike_array left=2.50 need=1.20"), 1)
end)

T.test("chain: Fu.IsDisabled calls a held hero free only for the holding bot", function()
	local bot, Chain = load()
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local enemy = Stub.teams[TEAM_DIRE][1]
	enemy.IsStunned = function()
		return true
	end
	enemy.IsRooted = function()
		return false
	end
	enemy.IsHexed = function()
		return false
	end
	enemy.IsNightmared = function()
		return false
	end
	enemy.NumModifiers = function()
		return 1
	end
	enemy.GetModifierName = function()
		return "modifier_stunned"
	end
	enemy.GetModifierRemainingDuration = function()
		return 0.3
	end
	T.eq(Fu.IsDisabled(enemy), true, "no hold: stunned is disabled")
	Chain.stamps[bot] =
		{ hero = enemy:GetUnitName(), spell = "lion_voodoo", need = 0.25, startedAt = 600, untilAt = 602 }
	Chain.live = 1
	Stub.time = 600.5
	T.eq(Fu.IsDisabled(enemy), false, "the holding bot sees him free at 0.3s left")
	Chain.stamps[bot] = nil
	Chain.stamps[Stub.teams[TEAM_RADIANT][2]] = { hero = enemy:GetUnitName(), need = 0.25, untilAt = 602 }
	Stub.time = 600.6
	T.eq(Fu.IsDisabled(enemy), true, "another bot's hold does not change this bot's answer")
end)

T.test("chain: a skillshot on a free hero reserves nothing; a point cast into a stun does", function()
	local _, Chain = load()
	local lina = fakeHero({ name = "npc_dota_hero_lina", team = TEAM_RADIANT, loc = Vector(0, 0, 0) })
	local lion = fakeHero({ name = "npc_dota_hero_lion", team = TEAM_RADIANT, loc = Vector(300, 0, 0) })
	local axe = fakeHero({ name = "npc_dota_hero_axe", team = TEAM_DIRE, loc = Vector(500, 0, 0) })
	local lsa = fakeAbility("lina_light_strike_array", 0.45, {
		light_strike_array_delay_time = 0.5,
		light_strike_array_stun_duration = 1.6,
	}, 700)
	local hex = fakeAbility("lion_voodoo", 0, { duration = 2.4 })
	lina.target = axe
	T.eq(Chain.OnCast(lina, lsa, Vector(500, 0, 0), "location"), false, "LSA on a free hero goes")
	T.eq(Chain.claims[TEAM_RADIANT]["npc_dota_hero_axe"], nil, "no reservation: it can miss")
	T.eq(Chain.OnCast(lion, hex, axe, "entity"), false, "the teammate's Hex goes through")
end)

T.test("chain: no hold from farther than HOLD_RANGE (the attack order would walk the bot in)", function()
	local _, Chain = load()
	local kunkka = fakeHero({ name = "npc_dota_hero_kunkka", team = TEAM_RADIANT, loc = Vector(0, 0, 0) })
	local axe = fakeHero({ name = "npc_dota_hero_axe", team = TEAM_DIRE, loc = Vector(1200, 0, 0) })
	local torrent = fakeAbility("kunkka_torrent", 0.4, { delay = 1.6, stun_duration = 1.4 }, 1300)
	kunkka.target = axe
	stun(axe, 4.0)
	T.eq(Chain.OnCast(kunkka, torrent, Vector(1200, 0, 0), "location"), false, "goes through")
	T.eq(#kunkka.attacks, 0, "no attack order")
	T.eq(#lines("[SHy-CHAIN] t=600 kunkka cast hero=axe spell=kunkka_torrent"), 1, "cast line")
	T.eq(#lines("why=far"), 1, "why=far")
end)

T.test("chain: the cast guard refuses a held order before the engine sees it", function()
	local bot = Stub.reset({ hero = "npc_dota_hero_sven", time = 600 })
	local engine = { n = 0 }
	CDOTA_Bot_Script.Action_UseAbilityOnEntity = function()
		engine.n = engine.n + 1
	end
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local Chain = require(GetScriptDirectory() .. "/lib/systems/chain_rules")
	Chain.Reset()
	local axe = fakeHero({ name = "npc_dota_hero_axe", team = TEAM_DIRE, loc = bot._loc + Vector(500, 0, 0) })
	local bolt = fakeAbility("sven_storm_bolt", 0.2, { bolt_speed = 1000, bolt_stun_duration = 1.5 })
	bolt.IsHidden = function()
		return false
	end
	local attacks = {}
	bot.Action_AttackUnit = function(_, target)
		attacks[#attacks + 1] = target
	end
	stun(axe, 2.5)
	bot:Action_UseAbilityOnEntity(bolt, axe)
	T.eq(engine.n, 0, "held: the engine got no cast order")
	T.eq(#attacks, 1, "an attack order instead")
	T.eq(#lines("[SHy-CHAIN] t=600 sven hold hero=axe spell=sven_storm_bolt"), 1, "hold line")
	axe.stunned, axe.mods = false, {}
	Stub.time = 600.5
	bot:Action_UseAbilityOnEntity(bolt, axe)
	T.eq(engine.n, 1, "free hero: the order reaches the engine")
	T.eq(#lines("error where="), 0, "no hook error")
end)

T.test("chain: Dream Coil's break stun is a listed stun (game 088)", function()
	local Chain, sven, _, axe, bolt = setup()
	stun(axe, 2.0, "modifier_puck_coil_break_stun")
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), true, "held")
	T.eq(#lines("mod=modifier_puck_coil_break_stun"), 1, "hold line names the coil stun")
	T.eq(#lines("unknown"), 0, "no unknown line")
end)

T.test("chain: a hold on a hero in Cold Embrace walks to him, no attack into the cocoon", function()
	local Chain, sven, _, axe, bolt = setup()
	stun(axe, 3.0, "modifier_winter_wyvern_cold_embrace")
	T.eq(Chain.OnCast(sven, bolt, axe, "entity"), true, "held until the cocoon ends")
	T.eq(#sven.attacks, 0, "no attack order")
	T.eq(#sven.moves, 1, "one move order")
	T.ok(sven.moves[1] == axe, "to the frozen hero")
end)

T.test("chain: the unknown line keeps a disable-looking name past the cap and counts every name", function()
	local _, Chain = load()
	-- Game 088 t=1445 (Rubick): 12 names hit the old cap of 12; a stun after them would have been cut.
	local names = {
		"modifier_rubick_curiosity",
		"modifier_rubick_curiosity_from_heroes_tracker",
		"modifier_item_ring_of_basilius_effect",
		"modifier_rubick_spell_steal",
		"modifier_abyssal_underlord_atrophy_aura_effect",
		"modifier_abyssal_underlord_pit_of_malice_slow",
		"modifier_abyssal_underlord_firestorm_burn",
		"modifier_item_shadow_amulet_fade",
		"modifier_item_polliwog_charm_buff",
		"modifier_item_dustofappearance",
		"modifier_lion_finger_of_death",
		"modifier_item_phase_boots_active",
		"modifier_item_magic_wand",
		"modifier_some_new_stun",
	}
	local mods, count = Chain.UnknownNames(names, 12)
	T.eq(count, 14, "every unlisted name counted")
	T.ok(string.find(mods, "^modifier_some_new_stun,modifier_rubick_curiosity,") ~= nil, "stun first, then in order")
	T.eq(select(2, string.gsub(mods, ",", ",")) + 1, 12, "cut at the cap")
	T.ok(string.find(mods, "magic_wand", 1, true) == nil, "the last plain name is cut")
	T.eq(Chain.UnknownNames({}, 12), "", "an empty list")
end)
