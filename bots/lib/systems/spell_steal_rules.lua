-- Rubick's Spell Steal choice (#290): what a spell is worth to Rubick, and whether the spell he would get is worth
-- more than the one he holds. Pure: no bot API calls; bots/heroes/hero_rubick.lua reads the handles and passes plain
-- values in. Deterministic (game 089: the old 1-100 roll against a hand "replace weight" gave Berserker's Call away
-- at the first roll and never replaced Earth Spike or Hex, weight 0, so Culling Blade was never stolen again).
--
-- Maintainer decision (2026-11-28, #290): "keeping earth spike make sense for rubick support team fight. but roll is
-- chance based and sounds wrong. also when the stolen spell is on cool down, it is better to steal a new one.
-- prioritizing area disables".
--
-- Spell Steal (Valve datafeed herodata hero_id 86, rubick_spell_steal, 2026-11-28): Rubick gets "the last spell the
-- hero cast", items can't be stolen, cooldown 16/10/4, mana 25, range 1000, a stolen spell lasts 180/240/300 s,
-- Scepter holds 2 stolen spells. stolen_spell_cooldown_percent 10/20/30: what it changes is unverified.
local Rules = {}

-- Value of each kind of spell. Area disables first, then single-target disables, then ultimates and big damage.
Rules.VALUE = {
	area_disable = 100,
	single_disable = 70,
	big = 50,
	nuke = 30,
	utility = 20,
	weak = 10,
}

-- A spell held with more than COOLDOWN_LONG seconds of cooldown left counts at COOLDOWN_FACTOR of its value: a new
-- spell is better than one that can't be cast in the next fight. 4 s, not the ~8 s first named on #290: Earth Spike's
-- cooldown is 14/13/12/11 (datafeed hero 26), so a stolen one may run less than 8 s and would never count as on
-- cooldown.
Rules.COOLDOWN_LONG = 4
Rules.COOLDOWN_FACTOR = 0.25
-- The new spell must be worth more than the held one by MARGIN, so he does not swap between nearly equal spells.
Rules.MARGIN = 15
-- A target whose last spell is not known (the cast callback misses some casts): counts as a nuke, so a blind steal
-- replaces only an empty slot, a weak spell, or a spell on a long cooldown that is not a disable.
Rules.BLIND_VALUE = Rules.VALUE.nuke
-- The old holds, kept: a stolen ultimate that can be cast is kept HOLD_ULT seconds after the steal; a held spell of at
-- least HOLD_STRONG_DAMAGE damage ready within HOLD_STRONG_READY seconds is kept, unless the new spell is an area
-- disable.
Rules.HOLD_ULT = 60
Rules.HOLD_STRONG_DAMAGE = 280
Rules.HOLD_STRONG_READY = 5

-- Hand table for the spells that matter. Each kind was checked against the ability's Valve datafeed description
-- (herodata, 2026-11-28: "stuns", "taunts", "roots", "silences", "puts ... to sleep", "cannot move or attack", ...).
-- Not here: big damage and ultimates without a disable (Culling Blade, Laguna Blade, Finger of Death, Echo Slam:
-- "damaging enemy units", no stun), which the fallback from the handle scores as "big". A spell missing here is
-- never counted as a disable.
Rules.KIND = {
	-- Area disables: stun, root, taunt, sleep, fear or silence on every enemy in an area or a line.
	abyssal_underlord_pit_of_malice = "area_disable",
	axe_berserkers_call = "area_disable",
	bloodseeker_blood_bath = "area_disable",
	centaur_hoof_stomp = "area_disable",
	dark_willow_bramble_maze = "area_disable",
	dark_willow_cursed_crown = "area_disable",
	dark_willow_terrorize = "area_disable",
	death_prophet_silence = "area_disable",
	disruptor_static_storm = "area_disable",
	drow_ranger_wave_of_silence = "area_disable",
	earthshaker_fissure = "area_disable",
	elder_titan_echo_stomp = "area_disable",
	ember_spirit_searing_chains = "area_disable",
	enigma_black_hole = "area_disable",
	faceless_void_chronosphere = "area_disable",
	jakiro_ice_path = "area_disable",
	kunkka_ghostship = "area_disable",
	kunkka_torrent = "area_disable",
	leshrac_split_earth = "area_disable",
	lina_light_strike_array = "area_disable",
	lion_impale = "area_disable",
	magnataur_horn_toss = "area_disable",
	magnataur_reverse_polarity = "area_disable",
	medusa_stone_gaze = "area_disable",
	meepo_earthbind = "area_disable",
	monkey_king_boundless_strike = "area_disable",
	naga_siren_song_of_the_siren = "area_disable",
	nevermore_requiem = "area_disable",
	nyx_assassin_impale = "area_disable",
	oracle_fortunes_end = "area_disable",
	primal_beast_onslaught = "area_disable",
	puck_dream_coil = "area_disable",
	puck_waning_rift = "area_disable",
	sandking_burrowstrike = "area_disable",
	silencer_global_silence = "area_disable",
	slardar_slithereen_crush = "area_disable",
	sven_storm_bolt = "area_disable",
	tidehunter_ravage = "area_disable",
	tiny_avalanche = "area_disable",
	treant_overgrowth = "area_disable",
	warlock_rain_of_chaos = "area_disable",
	winter_wyvern_winters_curse = "area_disable",
	-- Single-target disables: stun, hex, sleep, banish, silence or a channelled hold on one enemy.
	alchemist_unstable_concoction = "single_disable",
	ancient_apparition_cold_feet = "single_disable",
	bane_fiends_grip = "single_disable",
	bane_nightmare = "single_disable",
	batrider_flaming_lasso = "single_disable",
	beastmaster_primal_roar = "single_disable",
	chaos_knight_chaos_bolt = "single_disable",
	crystal_maiden_frostbite = "single_disable",
	doom_bringer_doom = "single_disable",
	dragon_knight_dragon_tail = "single_disable",
	enigma_malefice = "single_disable",
	legion_commander_duel = "single_disable",
	lion_voodoo = "single_disable",
	luna_lucent_beam = "single_disable",
	mars_spear = "single_disable",
	mirana_arrow = "single_disable",
	necrolyte_reapers_scythe = "single_disable",
	night_stalker_void = "single_disable",
	obsidian_destroyer_astral_imprisonment = "single_disable",
	ogre_magi_fireblast = "single_disable",
	primal_beast_pulverize = "single_disable",
	pudge_dismember = "single_disable",
	rattletrap_hookshot = "single_disable",
	shadow_demon_disruption = "single_disable",
	shadow_shaman_shackles = "single_disable",
	shadow_shaman_voodoo = "single_disable",
	skeleton_king_hellfire_blast = "single_disable",
	skywrath_mage_ancient_seal = "single_disable",
	storm_spirit_electric_vortex = "single_disable",
	vengefulspirit_magic_missile = "single_disable",
	windrunner_shackleshot = "single_disable",
	witch_doctor_paralyzing_cask = "single_disable",
	zuus_lightning_bolt = "single_disable",
}

-- Is this a stolen-spell slot with nothing in it?
function Rules.IsEmpty(name)
	return name == nil or name == "" or string.find(name, "^rubick_empty") ~= nil
end

-- Value of a spell and where it came from ("hand", "handle", "none"). info: what the handle reads, or nil:
-- { isPassive=, isUltimate=, isAOE=, damage= }. A spell missing from KIND is never a disable: an ultimate or one of
-- 300+ damage is "big", other damage a "nuke" (+5 when it hits an area), the rest "utility".
function Rules.Value(name, info)
	if Rules.IsEmpty(name) then
		return 0, "empty", "none"
	end
	local kind = Rules.KIND[name]
	if kind ~= nil then
		return Rules.VALUE[kind], kind, "hand"
	end
	if info == nil then
		return Rules.VALUE.utility, "utility", "none"
	end
	if info.isPassive then
		return Rules.VALUE.weak, "weak", "handle"
	end
	local damage = info.damage or 0
	local areaBonus = info.isAOE and 5 or 0
	if info.isUltimate or damage >= 300 then
		return Rules.VALUE.big + areaBonus, "big", "handle"
	end
	if damage > 0 then
		return Rules.VALUE.nuke + areaBonus, "nuke", "handle"
	end
	return Rules.VALUE.utility, "utility", "handle"
end

-- What the held spell is worth now: its value, or COOLDOWN_FACTOR of it with more than COOLDOWN_LONG s of cooldown.
function Rules.HeldScore(value, cooldownLeft)
	if (cooldownLeft or 0) > Rules.COOLDOWN_LONG then
		return value * Rules.COOLDOWN_FACTOR
	end
	return value
end

-- Should Rubick steal now? Returns steal (bool), why, the held spell's score now.
-- o = {
--   incoming = the target's last spell (nil: not known), incomingValue = its Value, incomingKind = its kind,
--   held = the spell that would be replaced (the second slot with Scepter), heldValue, heldCd = its cooldown left,
--   heldDamage = its GetAbilityDamage, other = the other held spell with Scepter (nil without),
--   ultHold = a stolen ultimate that can be cast, stolen less than HOLD_ULT s ago,
-- }
-- why: same (he holds that spell already), hold-ult, hold-strong, empty, blind (target's last spell not known),
-- better, held-cooldown, keep, blind-keep.
function Rules.Decide(o)
	if o.incoming ~= nil and (o.incoming == o.held or o.incoming == o.other) then
		return false, "same", 0
	end
	if o.ultHold then
		return false, "hold-ult", 0
	end
	local heldEmpty = Rules.IsEmpty(o.held)
	local heldScore = heldEmpty and 0 or Rules.HeldScore(o.heldValue or 0, o.heldCd)
	if
		not heldEmpty
		and (o.heldCd or 0) < Rules.HOLD_STRONG_READY
		and (o.heldDamage or 0) >= Rules.HOLD_STRONG_DAMAGE
		and o.incomingKind ~= "area_disable"
	then
		return false, "hold-strong", heldScore
	end
	local incomingScore = o.incoming ~= nil and (o.incomingValue or 0) or Rules.BLIND_VALUE
	if heldEmpty then
		return true, o.incoming ~= nil and "empty" or "empty-blind", 0
	end
	if incomingScore > heldScore + Rules.MARGIN then
		if o.incoming == nil then
			return true, "blind", heldScore
		end
		if (o.heldCd or 0) > Rules.COOLDOWN_LONG then
			return true, "held-cooldown", heldScore
		end
		return true, "better", heldScore
	end
	return false, o.incoming ~= nil and "keep" or "blind-keep", heldScore
end

return Rules
