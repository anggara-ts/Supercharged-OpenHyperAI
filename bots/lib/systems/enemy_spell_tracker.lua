-- Shared bot system (#34, games 067-068): when our team last saw an enemy hero use a spell or item, and whether it
-- can be ready again. Used by bots/heroes/hero_alchemist.lua (escape-ready and disable-risk rules) and
-- bots/heroes/hero_rubick.lua (#290: each enemy hero's last spell, what Spell Steal would take).
--
-- Bot API facts (docs/BOT_API_RUNTIME.md): GetCooldownTimeRemaining() on an enemy hero's ability reads 0 (game 067:
-- Nyx Assassin's Vendetta read ready 4s and 6s after it was cast), GetCooldown() on an enemy handle gives no value
-- and an enemy's item cooldowns read nothing either (game 068). GetLevel() and GetMana() do read. So "ready" is
-- worked out here from what the team sees:
--   callback  InstallCastCallback(-1, fn) reported the cast. Game 068: it reports enemy casts and items, also out of
--             our vision, but it misses some (Dark Willow's Shadow Realm at 918 and 1743, Nyx's Vendetta at 1749,
--             several Skeleton Walks).
--   modifier  a visible enemy hero has the spell's modifier (Shadow Realm, Skeleton Walk's fade, ...). Seen after a
--             cast the callback already reported, it is the same cast while its buff can still be up from it
--             (EnemySpells.SameCast); the cast time is read back from the modifier's time left when that reads.
-- Game 068 dropped the third source, a hero with an invisibility spell vanishing in our vision: 0 of 11 were new
-- casts (two were Alchemist's own deaths), and a false one put an escape on cooldown, which lets a brew start.
-- State of a spell: "ready" (seen used, and its cooldown has passed since), "cooldown" (seen used, cooldown not
-- passed), "unknown" (never seen used, or the cooldown is not known).
-- One table per team's Lua state (require caches the module), shared by every bot that reads it.
local EnemySpells = {}

-- Cooldowns by level, game data. Escapes: Valve datafeed (herodata, 2026-11-21): Nyx 88, Clinkz 56, Dark Willow
-- 119, Bounty Hunter 62, Weaver 63, Templar Assassin 46, Puck 13, Riki 32, Mirana 9, Sand King 16, Invoker 74.
-- Disables (ConcoctionRules.DISABLE_NAMES, game 068: 123 of 214 callback lines had no cooldown): the same datafeed
-- (2026-11-21), AbilityCooldown, hero id after each line. Not listed: the charge spells (ringmaster_the_box,
-- snapfire_firesnap_cookie: a cast does not put them on cooldown), the ones with cooldown 0 (silencer_glaives_of_wisdom,
-- snapfire_spit_creep), and the four the 7.42 datafeed does not list (drow_ranger_silence, techies_stasis_trap,
-- venomancer_latent_poison, brewmaster_earth_hurl_boulder: a Brewmaster spirit's, not a hero's). Items: 7.42
-- items.txt in pak01_dir.vpk (read 2026-11-21), AbilityCooldown.
-- 7.42a (datafeed patchnotes and herodata, 2026-11-25): huskar_life_break, necrolyte_reapers_scythe, riki_smoke_screen
-- and shadow_shaman_shackles changed.
EnemySpells.COOLDOWNS = {
	nyx_assassin_vendetta = { 80, 70, 60 },
	clinkz_wind_walk = { 24, 21, 18 },
	dark_willow_shadow_realm = { 21, 19, 17, 15 },
	bounty_hunter_wind_walk = { 18, 17, 16, 15 },
	weaver_shukuchi = { 15, 12, 9, 6 },
	templar_assassin_meld = { 11, 9, 7, 5 },
	puck_phase_shift = { 8, 7.5, 7, 6.5 },
	riki_tricks_of_the_trade = { 21, 18, 15, 12 },
	mirana_invis = { 120, 110, 100 },
	sandking_sand_storm = { 40, 34, 28, 22 },
	invoker_ghost_walk = { 40 },
	death_prophet_silence = { 17, 15, 13, 11 }, -- 43
	ancient_apparition_cold_feet = { 15, 13, 11, 9 }, -- 68
	ancient_apparition_ice_blast = { 50, 45, 40 }, -- 68
	antimage_mana_void = { 100, 85, 70 }, -- 1
	arc_warden_spark_wraith = { 4 }, -- 113
	axe_berserkers_call = { 18, 16, 14, 12 }, -- 2
	bane_fiends_grip = { 125, 110, 95 }, -- 3
	bane_nightmare = { 25, 22, 19, 16 }, -- 3
	batrider_flamebreak = { 22, 19, 16, 13 }, -- 65
	batrider_flaming_lasso = { 90, 75, 60 }, -- 65
	beastmaster_primal_roar = { 90, 75, 60 }, -- 38
	bloodseeker_blood_bath = { 15, 14, 13, 12 }, -- 4
	brewmaster_cinder_brew = { 19, 17, 15, 13 }, -- 78
	centaur_hoof_stomp = { 18, 16, 14, 12 }, -- 96
	chaos_knight_chaos_bolt = { 13, 12, 11, 10 }, -- 81
	dark_willow_cursed_crown = { 17, 15, 13, 11 }, -- 119
	dark_willow_terrorize = { 100, 90, 80 }, -- 119
	dawnbreaker_fire_wreath = { 17, 15, 13, 11 }, -- 135
	dawnbreaker_solar_guardian = { 110, 100, 90 }, -- 135
	disruptor_glimpse = { 24, 22, 20, 18 }, -- 87
	disruptor_static_storm = { 100, 85, 70 }, -- 87
	doom_bringer_doom = { 140, 130, 120 }, -- 69
	doom_bringer_infernal_blade = { 13, 10, 7, 4 }, -- 69
	dragon_knight_dragon_tail = { 16, 14, 12, 10 }, -- 49
	drow_ranger_wave_of_silence = { 18, 16, 14, 12 }, -- 6
	earth_spirit_boulder_smash = { 20, 17, 14, 11 }, -- 107
	earth_spirit_geomagnetic_grip = { 13 }, -- 107
	earth_spirit_magnetize = { 100, 90, 80 }, -- 107
	earth_spirit_rolling_boulder = { 16, 12, 8, 4 }, -- 107
	earthshaker_fissure = { 18, 17, 16, 15 }, -- 7
	elder_titan_echo_stomp = { 14, 13, 12, 11 }, -- 103
	enigma_black_hole = { 180, 170, 160 }, -- 33
	enigma_malefice = { 20, 18, 16, 14 }, -- 33
	faceless_void_chronosphere = { 155, 145, 135 }, -- 41
	grimstroke_ink_creature = { 30, 26, 22, 18 }, -- 121
	grimstroke_spirit_walk = { 27, 24, 21, 18 }, -- 121
	gyrocopter_homing_missile = { 26, 21, 16, 11 }, -- 72
	hoodwink_bushwhack = { 15, 14, 13, 12 }, -- 123
	huskar_inner_fire = { 17, 15, 13, 11 }, -- 59
	huskar_life_break = { 15, 13, 11 }, -- 59
	invoker_cold_snap = { 19 }, -- 74
	invoker_tornado = { 27 }, -- 74
	jakiro_ice_path = { 20, 17, 14, 11 }, -- 64
	keeper_of_the_light_will_o_wisp = { 55 }, -- 90
	kez_talon_toss = { 13, 11, 9, 7 }, -- 145
	kunkka_ghostship = { 90, 80, 70 }, -- 23
	kunkka_torrent = { 16, 14, 12, 10 }, -- 23
	largo_frogstomp = { 20, 18, 16, 14 }, -- 155
	legion_commander_duel = { 60, 55, 50 }, -- 104
	leshrac_split_earth = { 11 }, -- 52
	lina_light_strike_array = { 13, 11, 9, 7 }, -- 25
	lion_impale = { 14, 13, 12, 11 }, -- 26
	lion_voodoo = { 24, 20, 16, 12 }, -- 26
	luna_lucent_beam = { 9, 8, 7, 6 }, -- 48
	lycan_howl = { 22, 20, 18, 16 }, -- 77
	magnataur_reverse_polarity = { 115 }, -- 97
	marci_companion_run = { 24, 20, 16, 12 }, -- 136
	marci_unleash = { 80, 70, 60 }, -- 136
	mars_spear = { 14, 13, 12, 11 }, -- 129
	medusa_stone_gaze = { 90 }, -- 94
	mirana_arrow = { 19, 18, 17, 16 }, -- 9
	monkey_king_boundless_strike = { 24, 20, 16, 12 }, -- 114
	morphling_adaptive_strike_agi = { 17, 14, 11, 8 }, -- 10
	muerta_dead_shot = { 16, 14, 12, 10 }, -- 138
	muerta_the_calling = { 30, 28, 26, 24 }, -- 138
	necrolyte_reapers_scythe = { 95 }, -- 36
	nevermore_requiem = { 120, 110, 100 }, -- 11
	night_stalker_crippling_fear = { 30, 25, 20, 15 }, -- 60
	night_stalker_void = { 11, 10, 9, 8 }, -- 60
	nyx_assassin_impale = { 17, 15, 13, 11 }, -- 88
	nyx_assassin_spiked_carapace = { 20, 16, 12, 8 }, -- 88
	obsidian_destroyer_astral_imprisonment = { 18, 16, 14, 12 }, -- 76
	ogre_magi_fireblast = { 14, 12, 10, 8 }, -- 84
	pangolier_gyroshell = { 100, 90, 80 }, -- 120
	phoenix_supernova = { 120 }, -- 110
	primal_beast_onslaught = { 25, 22, 19, 16 }, -- 137
	primal_beast_pulverize = { 45, 40, 35 }, -- 137
	puck_dream_coil = { 80, 75, 70 }, -- 13
	puck_waning_rift = { 15, 14, 13, 12 }, -- 13
	pudge_dismember = { 30, 25, 20 }, -- 14
	pudge_meat_hook = { 18, 16, 14, 12 }, -- 14
	rattletrap_hookshot = { 60, 45, 30 }, -- 51
	riki_smoke_screen = { 16, 15, 14, 13 }, -- 32
	ringmaster_tame_the_beasts = { 16, 14, 12, 10 }, -- 131
	ringmaster_wheel = { 90, 80, 70 }, -- 131
	rubick_telekinesis = { 22, 19, 16, 13 }, -- 86
	sandking_burrowstrike = { 14, 13, 12, 11 }, -- 16
	shadow_shaman_shackles = { 15, 14, 13, 12 }, -- 27
	shadow_shaman_voodoo = { 24, 20, 16, 12 }, -- 27
	silencer_curse_of_the_silent = { 22, 20, 18, 16 }, -- 75
	silencer_global_silence = { 120 }, -- 75
	silencer_last_word = { 22, 18, 14, 10 }, -- 75
	skeleton_king_hellfire_blast = { 14, 12, 10, 8 }, -- 42
	skywrath_mage_ancient_seal = { 14 }, -- 101
	slardar_slithereen_crush = { 8.5, 8, 7.5, 7 }, -- 28
	snapfire_scatterblast = { 17, 14, 11, 8 }, -- 128
	sniper_assassinate = { 20, 15, 10 }, -- 35
	spectre_haunt = { 160, 150, 140 }, -- 67
	spirit_breaker_charge_of_darkness = { 22, 19, 16, 13 }, -- 71
	storm_spirit_electric_vortex = { 20, 18, 16, 14 }, -- 17
	sven_storm_bolt = { 21, 18, 15, 12 }, -- 18
	techies_sticky_bomb = { 16, 13, 10, 7 }, -- 105
	techies_suicide = { 40, 35, 30, 25 }, -- 105
	templar_assassin_psionic_trap = { 11, 8, 5 }, -- 46
	terrorblade_terror_wave = { 85 }, -- 109
	tidehunter_ravage = { 150, 145, 140 }, -- 29
	tiny_avalanche = { 23, 20, 17, 14 }, -- 19
	tusk_snowball = { 21, 19, 17, 15 }, -- 100
	tusk_walrus_punch = { 16, 13, 10 }, -- 100
	undying_bite = { 18 }, -- 85
	vengefulspirit_magic_missile = { 14, 13, 12, 11 }, -- 20
	venomancer_venomous_gale = { 21, 20, 19, 18 }, -- 40
	visage_summon_familiars = { 120, 110, 100 }, -- 92
	void_spirit_resonant_pulse = { 18 }, -- 126
	warlock_rain_of_chaos = { 165 }, -- 37
	windrunner_shackleshot = { 16, 14, 12, 10 }, -- 21
	winter_wyvern_splinter_blast = { 6 }, -- 112
	winter_wyvern_winters_curse = { 100, 90, 80 }, -- 112
	witch_doctor_paralyzing_cask = { 20, 18, 16, 14 }, -- 30
	zuus_lightning_bolt = { 6 }, -- 22
	item_invis_sword = { 25 },
	item_silver_edge = { 23 },
	item_glimmer_cape = { 15 },
	item_shadow_amulet = { 18 },
	item_trickster_cloak = { 25 },
	item_cyclone = { 23 },
	item_wind_waker = { 19 },
	item_sheepstick = { 20 },
	item_orchid = { 18 },
	item_bloodthorn = { 15 },
	item_abyssal_blade = { 35 },
}

-- How long the buff of a listed escape lasts, by level (seconds), for EnemySpells.SameCast. Valve datafeed
-- (herodata, 2026-11-21) "duration" (Sand Storm: AbilityDuration); items: 7.42 items.txt (windwalk_duration,
-- duration). Not listed: Meld and Shadow Amulet last until the hero moves or attacks.
EnemySpells.BUFF_DURATIONS = {
	nyx_assassin_vendetta = { 45, 50, 55 },
	clinkz_wind_walk = { 35, 40, 45 },
	dark_willow_shadow_realm = { 5 },
	bounty_hunter_wind_walk = { 20, 25, 30, 35 },
	weaver_shukuchi = { 4 },
	puck_phase_shift = { 1, 1.75, 2.5, 3.25 },
	mirana_invis = { 18 },
	sandking_sand_storm = { 16, 20, 24, 28 },
	invoker_ghost_walk = { 50 },
	item_invis_sword = { 17 },
	item_silver_edge = { 17 },
	item_glimmer_cape = { 5 },
	item_trickster_cloak = { 6 },
}

-- Modifier on the enemy hero -> the spell or item that put it there. Names from the 7.42 ability strings
-- (DOTA_Tooltip_modifier_<name> in the English ability tooltips, pak01_dir.vpk); Riki's Tricks of the Trade has no
-- listed modifier and is left to the callback.
EnemySpells.MODIFIERS = {
	modifier_nyx_assassin_vendetta = "nyx_assassin_vendetta",
	modifier_clinkz_wind_walk = "clinkz_wind_walk",
	modifier_dark_willow_shadow_realm_buff = "dark_willow_shadow_realm",
	modifier_bounty_hunter_wind_walk = "bounty_hunter_wind_walk",
	modifier_weaver_shukuchi = "weaver_shukuchi",
	modifier_templar_assassin_meld = "templar_assassin_meld",
	modifier_puck_phase_shift = "puck_phase_shift",
	modifier_mirana_moonlight_shadow = "mirana_invis",
	modifier_sandking_sand_storm = "sandking_sand_storm",
	modifier_invoker_ghost_walk_self = "invoker_ghost_walk",
	modifier_item_invisibility_edge_windwalk = "item_invis_sword",
	modifier_item_silver_edge_windwalk = "item_silver_edge",
	modifier_item_glimmer_cape_fade = "item_glimmer_cape",
	modifier_item_shadow_amulet_fade = "item_shadow_amulet",
	modifier_item_trickster_cloak_invis = "item_trickster_cloak",
}

-- A use seen within NEW_CAST_GAP seconds of the last sighting of the same use is the same cast (a modifier read on
-- every think while it lasts).
EnemySpells.NEW_CAST_GAP = 2.0
-- Slack for matching a modifier to a recorded cast: the callback fires at the cast, the buff starts after the cast
-- point and fade, and DotaTime() moves between reads.
EnemySpells.CAST_MATCH = 1.0

-- Game-data cooldown of a spell at a level (the last listed level for higher ones), or nil. Level unknown (nil, 0 or
-- the -1 the cast callback's handle often reads): the shortest listed cooldown, so the spell reads ready again early
-- rather than late (a brew held back once too often costs less than one that blows up on him; a disable read on
-- cooldown while it is ready would hold the early throw back).
function EnemySpells.DataCooldown(name, level)
	local values = EnemySpells.COOLDOWNS[name]
	if values == nil then
		return nil
	end
	if level == nil or level <= 0 then
		return values[#values]
	end
	return values[math.min(#values, level)]
end

-- Game-data buff duration of a listed escape at a level, or nil (not listed, or it lasts until the hero acts).
-- Level unknown: the longest, so a sighting is matched to the earlier cast rather than read as a new one.
function EnemySpells.BuffDuration(name, level)
	local values = EnemySpells.BUFF_DURATIONS[name]
	if values == nil then
		return nil
	end
	if level == nil or level <= 0 then
		return values[#values]
	end
	return values[math.min(#values, level)]
end

-- The cooldown to assume: the API's own GetCooldown() when it reads above 0 (it counts cooldown reduction), else
-- the game data. Returns the seconds (or nil) and the source: "api", "data" or "none".
function EnemySpells.CooldownFor(name, level, apiCooldown)
	if apiCooldown ~= nil and apiCooldown > 0 then
		return apiCooldown, "api"
	end
	local cooldown = EnemySpells.DataCooldown(name, level)
	if cooldown ~= nil then
		return cooldown, "data"
	end
	return nil, "none"
end

-- State of a use seen at `castAt` with `cooldown` seconds, at `now`.
function EnemySpells.StateAt(castAt, cooldown, now)
	if castAt == nil or cooldown == nil or cooldown <= 0 then
		return "unknown"
	end
	if now - castAt < cooldown then
		return "cooldown"
	end
	return "ready"
end

-- #34, game 068: 6 of 10 modifier sightings came 4-21s after the cast the callback had reported, and each was taken
-- for a new cast (the cooldown then ran from the sighting). Is a modifier seen at `now` from the cast recorded at
-- `entryAt`?
--   castAt        the cast time read back from the modifier's time left (nil: it did not read): the same cast when it
--                 is not later than the recorded one (+ CAST_MATCH)
--   buffDuration  the buff's game-data duration (nil: it lasts until the hero acts)
--   cooldown      the recorded cast's cooldown
-- Without castAt: the same cast while its buff can still be up from it and a new cast is not possible yet (under the
-- cooldown); a buff that lasts until the hero acts: while under the cooldown.
function EnemySpells.SameCast(entryAt, cooldown, buffDuration, now, castAt)
	if castAt ~= nil then
		return castAt <= entryAt + EnemySpells.CAST_MATCH
	end
	local underCooldown = cooldown ~= nil and now - entryAt < cooldown
	if buffDuration == nil then
		return underCooldown
	end
	return underCooldown and now - entryAt <= buffDuration + EnemySpells.CAST_MATCH
end

-- The cast time a modifier's time left gives: now - (duration - remaining), or nil when the time left does not read
-- as part of that duration (nil, 0 or below, or above the duration: a talent or another level).
function EnemySpells.CastTimeFromRemaining(now, buffDuration, remaining)
	if buffDuration == nil or remaining == nil or remaining <= 0 or remaining > buffDuration + 0.1 then
		return nil
	end
	return now - (buffDuration - remaining)
end

local casts = {} -- casts[heroName][spellName] = { at=, lastObs=, cooldown=, source=, via=, level= }
local levels = {} -- levels[heroName][spellName] = the level read at the last sighting
local lastCasts = {} -- lastCasts[heroName] = { spell=, at= }: the last spell (not item) the callback reported

-- #290: the last spell an enemy hero was reported casting (Rubick's Spell Steal takes "the last spell the hero cast"
-- and "cannot steal item abilities", datafeed hero 86). Every spell, not only the listed ones; items are skipped.
-- LastCast returns the spell name and when it was cast, or nil when no cast of that hero was reported.
function EnemySpells.NoteLastCast(heroName, spell, now)
	if heroName == nil or spell == nil or string.find(spell, "^item_") ~= nil then
		return
	end
	lastCasts[heroName] = { spell = spell, at = now }
end
function EnemySpells.LastCast(heroName)
	local entry = lastCasts[heroName]
	if entry == nil then
		return nil
	end
	return entry.spell, entry.at
end

-- The level of `spell` of `heroName` read at the last sighting of that hero (nil: never read).
function EnemySpells.KnownLevel(heroName, spell)
	return levels[heroName] and levels[heroName][spell]
end

-- #34, game 068 t=2200: Clinkz's walk was stored with the cooldown of level 2 (21) while it was level 3 (18). A
-- sighting of the hero reads the level of a listed spell: kept for the next cast the callback reports without a
-- level, and a recorded cast whose level was not known gets the cooldown of this level (the cast came before, at
-- this level or lower, so the real cooldown is at least this one). A level that does not read (0 or below) changes
-- nothing; a known cast level is kept (levelling up does not shorten a cooldown that is running).
function EnemySpells.NoteLevel(heroName, spell, level)
	if level == nil or level <= 0 then
		return
	end
	local byHero = levels[heroName]
	if byHero == nil then
		byHero = {}
		levels[heroName] = byHero
	end
	byHero[spell] = level
	local entry = casts[heroName] and casts[heroName][spell]
	if entry ~= nil and (entry.level or 0) <= 0 and entry.source == "data" then
		entry.level = level
		entry.cooldown = EnemySpells.DataCooldown(spell, level)
	end
end

-- Note a use of `spell` by `heroName` seen at `now`. Returns true when it is a new cast, false when it only extends
-- the one already noted: a sighting within NEW_CAST_GAP of the last one, or (via=modifier) a buff still up from the
-- recorded cast (EnemySpells.SameCast). A cast the callback reports is always a new one. castAt: the cast time a
-- modifier's time left gives (EnemySpells.CastTimeFromRemaining), used as the cast time of a new cast.
function EnemySpells.Record(heroName, spell, now, level, apiCooldown, via, castAt)
	local byHero = casts[heroName]
	if byHero == nil then
		byHero = {}
		casts[heroName] = byHero
	end
	if level == nil or level <= 0 then
		level = EnemySpells.KnownLevel(heroName, spell) or level
	end
	local entry = byHero[spell]
	if entry ~= nil and now - entry.lastObs <= EnemySpells.NEW_CAST_GAP then
		entry.lastObs = now
		return false
	end
	if entry ~= nil and via == "modifier" then
		local buffLevel = (entry.level or 0) > 0 and entry.level or level
		local buffDuration = EnemySpells.BuffDuration(spell, buffLevel)
		if EnemySpells.SameCast(entry.at, entry.cooldown, buffDuration, now, castAt) then
			entry.lastObs = now
			return false
		end
	end
	local cooldown, source = EnemySpells.CooldownFor(spell, level, apiCooldown)
	local at = now
	if via == "modifier" and castAt ~= nil and castAt <= now then
		at = castAt
	end
	byHero[spell] = { at = at, lastObs = now, cooldown = cooldown, source = source, via = via, level = level or 0 }
	return true
end

-- State of `spell` of `heroName` at `now` ("ready", "cooldown", "unknown") and the entry it was read from (nil
-- when never seen).
function EnemySpells.State(heroName, spell, now)
	local entry = casts[heroName] and casts[heroName][spell]
	if entry == nil then
		return "unknown", nil
	end
	return EnemySpells.StateAt(entry.at, entry.cooldown, now), entry
end

-- #34, game 069 t=2697: a brew started on Dark Willow the second she cast Shadow Realm (the callback had reported it,
-- castAgo=0.0); she was untargetable for 5s and the brew blew up on him. Is an escape's buff on the hero now?
--   modifier   one of the MODIFIERS is on it (whoever cast it: hidden or untargetable either way)
--   just-cast  a recorded cast of a listed escape within JUST_CAST seconds (or its buff duration, if shorter): the
--              callback fires at the cast, before the buff reads. Not the whole buff: a Skeleton Walk lasts up to
--              45s but ends when Clinkz attacks, and a visible Clinkz after that is a fair target.
-- Returns the spell and "modifier" / "just-cast", or nil.
EnemySpells.JUST_CAST = 1.0
function EnemySpells.JustCast(castAt, now, buffDuration)
	if castAt == nil then
		return false
	end
	return now - castAt >= 0 and now - castAt < math.min(EnemySpells.JUST_CAST, buffDuration or EnemySpells.JUST_CAST)
end
local escapeSpells = {}
for _, spell in pairs(EnemySpells.MODIFIERS) do
	escapeSpells[spell] = true
end
function EnemySpells.EscapeActive(hero, heroName, now)
	for modifier, spell in pairs(EnemySpells.MODIFIERS) do
		local ok, has = pcall(function()
			return hero:HasModifier(modifier)
		end)
		if ok and has then
			return spell, "modifier"
		end
	end
	for spell, entry in pairs(casts[heroName] or {}) do
		if
			escapeSpells[spell] and EnemySpells.JustCast(entry.at, now, EnemySpells.BuffDuration(spell, entry.level))
		then
			return spell, "just-cast"
		end
	end
	return nil
end

local function HeroName(unit)
	local ok, name = pcall(function()
		return unit:GetUnitName()
	end)
	return ok and name or "?"
end

-- remaining: the modifier's time left (via=modifier; -1 when it did not read or for another source).
local function LogSeen(observer, heroName, spell, via, entry, now, remaining)
	pcall(
		print,
		string.format(
			"[SHy-ENEMYCD] t=%.0f %s seen hero=%s spell=%s via=%s level=%d cd=%.1f cdSrc=%s castAgo=%.1f remaining=%.1f",
			DotaTime(),
			observer,
			heroName,
			spell,
			via,
			entry.level or 0,
			entry.cooldown or -1,
			entry.source or "none",
			now - entry.at,
			remaining or -1
		)
	)
end

-- Errors in this module, at most every 30s per place: [SHy-ENEMYCD] t= <observer> error=<where>:<message>
local errorLogAt = {}
local function LogError(observer, where, err)
	if DotaTime() < (errorLogAt[where] or -999) then
		return
	end
	errorLogAt[where] = DotaTime() + 30
	pcall(print, string.format("[SHy-ENEMYCD] t=%.0f %s error=%s:%s", DotaTime(), observer, where, tostring(err)))
end
-- GetCooldown() of an enemy's ability or item: no value on an enemy handle in game 068, so nil when it errors.
local function SafeCooldown(handle)
	local ok, cooldown = pcall(function()
		return handle:GetCooldown()
	end)
	return ok and cooldown or nil
end

-- The level and GetCooldown() of a listed ability or item of the hero (items count as level 1), or nil when the hero
-- does not have it (not learned: level 0).
local function SpellOf(hero, spell)
	if string.sub(spell, 1, 5) == "item_" then
		for slot = 0, 5 do
			local item = hero:GetItemInSlot(slot)
			if item ~= nil and not item:IsNull() and item:GetName() == spell then
				return 1, SafeCooldown(item)
			end
		end
		return nil
	end
	local ability = hero:GetAbilityByName(spell)
	if ability == nil or ability:IsNull() then
		return nil
	end
	return ability:GetLevel(), SafeCooldown(ability)
end

-- The modifier's time left on the hero, or nil when it does not read (GetModifierByName gives the index).
local function ModifierRemaining(hero, modifier)
	local ok, remaining = pcall(function()
		local index = hero:GetModifierByName(modifier)
		if type(index) ~= "number" or index < 0 then
			return nil
		end
		return hero:GetModifierRemainingDuration(index)
	end)
	if ok and type(remaining) == "number" then
		return remaining
	end
	return nil
end

-- level / apiCooldown: read by the caller, else read from the hero now. castAt / remaining: from the modifier's time
-- left (via=modifier).
local function RecordAndLog(observer, hero, heroName, spell, via, now, level, apiCooldown, castAt, remaining)
	if level == nil and hero ~= nil then
		local okSpell, readLevel, readCooldown = pcall(SpellOf, hero, spell)
		if okSpell then
			level, apiCooldown = readLevel, readCooldown
		end
	end
	if EnemySpells.Record(heroName, spell, now, level, apiCooldown, via, castAt) then
		LogSeen(observer, heroName, spell, via, casts[heroName][spell], now, remaining)
	end
end

-- The levels of the listed spells (COOLDOWNS) in the hero's ability slots 0-9, for EnemySpells.NoteLevel.
local function NoteLevelsOf(hero, heroName)
	for slot = 0, 9 do
		local ability = hero:GetAbilityInSlot(slot)
		if ability ~= nil and not ability:IsNull() then
			local name = ability:GetName()
			if EnemySpells.COOLDOWNS[name] ~= nil then
				EnemySpells.NoteLevel(heroName, name, ability:GetLevel())
			end
		end
	end
end

local levelReadAt = {} -- levelReadAt[heroName] = when its levels were last read
local hpSamples = {} -- hpSamples[heroName] = { { at=, hp= }, ... } (oldest first)
local observeAt = -999

-- For the tests: forget every cast, level and sample.
function EnemySpells.Reset()
	casts, levels, levelReadAt, hpSamples, observeAt, lastCasts = {}, {}, {}, {}, -999, {}
end

-- #34, game 068 t=2899: an engage brew started on Clinkz at 9% while Ember Spirit and Vengeful Spirit were killing
-- him with spells (no ally's attack target was Clinkz, so the finish-hit check saw no ally damage); he died 0.2s into
-- the brew. The HP a visible enemy hero lost per second over the last HP_WINDOW seconds, from samples taken every
-- HP_SAMPLE_EVERY seconds while it is in sight (a gap over HP_GAP seconds starts over). Pure: samples is a list of
-- { at=, hp= }, oldest first.
EnemySpells.HP_WINDOW = 1.5
EnemySpells.HP_SAMPLE_EVERY = 0.2
EnemySpells.HP_GAP = 0.5
function EnemySpells.LossRate(samples, now)
	if samples == nil or #samples < 2 then
		return 0
	end
	local last = samples[#samples]
	local first = nil
	for i = 1, #samples do
		if now - samples[i].at <= EnemySpells.HP_WINDOW then
			first = samples[i]
			break
		end
	end
	if first == nil or first == last or last.at - first.at < 0.4 then
		return 0
	end
	return math.max(0, (first.hp - last.hp) / (last.at - first.at))
end
function EnemySpells.AddHpSample(samples, now, hp)
	local last = samples[#samples]
	if last ~= nil and now - last.at > EnemySpells.HP_GAP then
		for i = #samples, 1, -1 do
			samples[i] = nil
		end
		last = nil
	end
	if last ~= nil and now - last.at < EnemySpells.HP_SAMPLE_EVERY then
		return
	end
	samples[#samples + 1] = { at = now, hp = hp }
	while #samples > 1 and now - samples[1].at > EnemySpells.HP_WINDOW + EnemySpells.HP_SAMPLE_EVERY do
		table.remove(samples, 1)
	end
end
-- HP per second `heroName` is losing now (0: not losing, or not seen for long enough).
function EnemySpells.HealthLossRate(heroName, now)
	return EnemySpells.LossRate(hpSamples[heroName], now)
end

-- Runs from a bot's think. `enemies`: the real (not illusion) enemy heroes the team sees, already filtered by the
-- caller. At most every 0.1s. `observer` names the bot in the log lines:
--   [SHy-ENEMYCD] t= <observer> seen hero= spell= via=modifier|callback level= cd= cdSrc=api|data|none castAgo=
--                 remaining=
function EnemySpells.Observe(observer, enemies)
	local now = DotaTime()
	if now - observeAt < 0.1 then
		return
	end
	observeAt = now
	for _, hero in pairs(enemies or {}) do
		local okHero, errHero = pcall(function()
			local heroName = hero:GetUnitName()
			-- The levels change rarely: re-read once per second per hero, before the modifiers use them.
			if now - (levelReadAt[heroName] or -999) >= 1.0 then
				levelReadAt[heroName] = now
				NoteLevelsOf(hero, heroName)
			end
			for modifier, spell in pairs(EnemySpells.MODIFIERS) do
				if hero:HasModifier(modifier) then
					-- Only the hero's own spell or item: Moonlight Shadow covers all of Mirana's allies, a Glimmer Cape
					-- may come from a teammate.
					local level, apiCooldown = SpellOf(hero, spell)
					if level ~= nil and level > 0 then
						local remaining = ModifierRemaining(hero, modifier)
						local castAt =
							EnemySpells.CastTimeFromRemaining(now, EnemySpells.BuffDuration(spell, level), remaining)
						RecordAndLog(
							observer,
							hero,
							heroName,
							spell,
							"modifier",
							now,
							level,
							apiCooldown,
							castAt,
							remaining
						)
					end
				end
			end
			local samples = hpSamples[heroName]
			if samples == nil then
				samples = {}
				hpSamples[heroName] = samples
			end
			EnemySpells.AddHpSample(samples, now, hero:GetHealth())
		end)
		if not okHero then
			LogError(observer, "observe", errHero)
		end
	end
end

-- The cast callback, installed once per team's Lua state. Game 068: it reports enemy casts (items too, and out of our
-- vision) with the keys ability, channel_start, location, player_id, unit; the ability handle's GetLevel() often
-- reads -1 (the level read at the hero's last sighting is used then, EnemySpells.Record). Lines:
--   [SHy-ENEMYCD] t= cast-probe installed=yes|no error=
--   [SHy-ENEMYCD] t= cast-callback n= enemyN= arg=<type> keys=<fields> caster= spell= team=ally|enemy|unknown
--                                    the first 5 calls, and the first 5 calls for an enemy caster (team=unknown: the
--                                    caster's team could not be read)
-- An enemy hero's cast of a spell in COOLDOWNS or in the caller's `interest` name set is recorded with via=callback.
local probeInstalled = false
local callbackCount = 0
local enemyCallbackCount = 0
local probeInterest = {}
local probeTeam = nil -- our team, read when the probe is installed
local function OnCast(info)
	callbackCount = callbackCount + 1
	local caster, ability, playerId = nil, nil, nil
	if type(info) == "table" then
		caster = info.unit or info.caster
		ability = info.ability
		playerId = info.player_id or info.playerid or info.player
	end
	if type(caster) == "number" then
		playerId, caster = caster, nil
	end
	local spell = nil
	if ability ~= nil and type(ability) ~= "string" then
		local okName, name = pcall(function()
			return ability:GetName()
		end)
		spell = okName and name or nil
	elseif type(ability) == "string" then
		spell = ability
	end
	-- The caster's team from its handle, else from the player id; nil when neither reads.
	local casterTeam, heroName = nil, nil
	if caster ~= nil then
		local okTeam, team = pcall(function()
			return caster:GetTeam()
		end)
		casterTeam = okTeam and team or nil
		heroName = HeroName(caster)
	end
	if casterTeam == nil and type(playerId) == "number" then
		local okTeam, team = pcall(GetTeamForPlayer, playerId)
		casterTeam = okTeam and team or nil
		local okName, name = pcall(GetSelectedHeroName, playerId)
		heroName = okName and name or heroName
	end
	local enemy = casterTeam ~= nil and casterTeam ~= probeTeam
	if enemy then
		enemyCallbackCount = enemyCallbackCount + 1
	end
	if callbackCount <= 5 or (enemy and enemyCallbackCount <= 5) then
		local keys = {}
		if type(info) == "table" then
			for key in pairs(info) do
				keys[#keys + 1] = tostring(key)
			end
			table.sort(keys)
		end
		pcall(
			print,
			string.format(
				"[SHy-ENEMYCD] t=%.0f cast-callback n=%d enemyN=%d arg=%s keys=%s caster=%s spell=%s team=%s",
				DotaTime(),
				callbackCount,
				enemyCallbackCount,
				type(info),
				table.concat(keys, ","),
				tostring(heroName),
				tostring(spell),
				casterTeam == nil and "unknown" or enemy and "enemy" or "ally"
			)
		)
	end
	if enemy and spell ~= nil and heroName ~= nil and string.find(heroName, "^npc_dota_hero_") ~= nil then
		EnemySpells.NoteLastCast(heroName, spell, DotaTime())
	end
	if enemy and spell ~= nil and heroName ~= nil and (EnemySpells.COOLDOWNS[spell] ~= nil or probeInterest[spell]) then
		local isHero = string.find(heroName, "^npc_dota_hero_") ~= nil
		if isHero then
			local level, apiCooldown = nil, nil
			if ability ~= nil and type(ability) ~= "string" then
				local okLevel, readLevel = pcall(function()
					return ability:GetLevel()
				end)
				level = okLevel and readLevel or nil
				apiCooldown = SafeCooldown(ability)
			end
			RecordAndLog("callback", caster, heroName, spell, "callback", DotaTime(), level, apiCooldown)
		end
	end
end
function EnemySpells.InstallCastProbe(interest)
	for name in pairs(interest or {}) do
		probeInterest[name] = true
	end
	if probeInstalled then
		return
	end
	probeInstalled = true
	local ok, err = false, "no-function"
	if type(InstallCastCallback) == "function" then
		probeTeam = GetTeam()
		ok, err = pcall(InstallCastCallback, -1, function(info)
			local okCast, errCast = pcall(OnCast, info)
			if not okCast then
				LogError("callback", "cast-callback", errCast)
			end
		end)
	end
	pcall(
		print,
		string.format(
			"[SHy-ENEMYCD] t=%.0f cast-probe installed=%s error=%s",
			DotaTime(),
			ok and "yes" or "no",
			ok and "-" or tostring(err)
		)
	)
end

return EnemySpells
