-- Pure rules: is an ally escaping right now (#47, PR #238; game 083, 44:51: Winter Wyvern's Cold Embrace froze Dark
-- Willow for 4s in the same second she cast Shadow Realm to get away). A freeze on an ally who is already untargetable,
-- invisible or jumping away holds it in place for the enemies, so a save that disables the ally skips it.
-- Plain values in, so tests/test_ally_escape_rules.lua can check them without the bot API.
local AllyEscapeRules = {}

-- Modifiers of an escape in progress. Names from the 7.42 game files: the DOTA_Tooltip_modifier_<name> strings of the
-- English ability tooltips (pak01_dir.vpk) and the server's modifier list (dark_willow_shadow_realm_fade_time,
-- void_spirit_dissimilate_phase: no tooltip). Most are also EnemySpells.MODIFIERS (enemy_spell_tracker.lua). The
-- Shadow Walk items use the _windwalk fade modifier, not modifier_item_invisibility_edge (the carried item).
AllyEscapeRules.MODIFIERS = {
	"modifier_dark_willow_shadow_realm_buff",
	-- The 0.3s before the buff (datafeed hero 119: fade_time 0.3; game 083: the buff read 0.30s after the cast).
	"modifier_dark_willow_shadow_realm_fade_time",
	"modifier_puck_phase_shift",
	"modifier_templar_assassin_meld",
	"modifier_clinkz_wind_walk",
	"modifier_bounty_hunter_wind_walk",
	"modifier_weaver_shukuchi",
	"modifier_nyx_assassin_vendetta",
	"modifier_invoker_ghost_walk_self",
	"modifier_void_spirit_dissimilate_phase",
	"modifier_item_invisibility_edge_windwalk",
	"modifier_item_silver_edge_windwalk",
	"modifier_item_glimmer_cape_fade",
	"modifier_item_shadow_amulet_fade",
	"modifier_item_trickster_cloak_invis",
}

-- Escape spells and items: cast in the last RECENT seconds (or in their cast point now) counts as escaping, for the
-- moment before a modifier shows and for the jumps that leave none. Names: DOTA_Tooltip_ability_<name> in the 7.42
-- English tooltips; items also in items_all.txt (7.42).
AllyEscapeRules.SPELLS = {
	"dark_willow_shadow_realm",
	"puck_phase_shift",
	"puck_ethereal_jaunt",
	"templar_assassin_meld",
	"clinkz_wind_walk",
	"bounty_hunter_wind_walk",
	"weaver_shukuchi",
	"nyx_assassin_vendetta",
	"invoker_ghost_walk",
	"void_spirit_dissimilate",
	"antimage_blink",
	"queenofpain_blink",
	"mirana_leap",
	"faceless_void_time_walk",
	"storm_spirit_ball_lightning",
	"morphling_waveform",
	"item_blink",
	"item_swift_blink",
	"item_arcane_blink",
	"item_overwhelming_blink",
	"item_force_staff",
	"item_hurricane_pike",
	"item_invis_sword",
	"item_silver_edge",
	"item_glimmer_cape",
	"item_shadow_amulet",
	"item_trickster_cloak",
}

AllyEscapeRules.RECENT = 1.0

-- Jumps that go either way: a blink, leap or push can start a fight as well as end one (game 091, 34:51: Dark Willow
-- blinked onto Axe, `[SHy-ITEM] blink-initiate target=axe dist=1197`, and Cold Embrace skipped her as escaping). One
-- of these counts only when the ally moved away from the enemy heroes or is in retreat mode (JumpIsEscape). Every
-- name is also in SPELLS. The rest of SPELLS (untargetable or invisible) always counts.
AllyEscapeRules.EITHER_WAY = {
	puck_ethereal_jaunt = true,
	antimage_blink = true,
	queenofpain_blink = true,
	mirana_leap = true,
	faceless_void_time_walk = true,
	storm_spirit_ball_lightning = true,
	morphling_waveform = true,
	item_blink = true,
	item_swift_blink = true,
	item_arcane_blink = true,
	item_overwhelming_blink = true,
	item_force_staff = true,
	item_hurricane_pike = true,
}

-- How much further (units) the nearest enemy hero must be after a jump for it to count as moving away.
AllyEscapeRules.AWAY_MARGIN = 100

-- An ally's samples are { t = game time, dist = nearest visible enemy hero, nil for none in range }, oldest first.
-- Returns the newest sample taken before a cast `ago` seconds before `now` (where the ally stood before the jump), or
-- nil.
function AllyEscapeRules.SampleBefore(samples, now, ago)
	if samples == nil or type(ago) ~= "number" then
		return nil
	end
	local castAt = now - ago
	local found = nil
	for _, sample in ipairs(samples) do
		if sample.t < castAt then
			found = sample
		end
	end
	return found
end

-- Did a jump take the ally away from the enemy heroes? before: the sample from before the cast (SampleBefore), or
-- nil; nowDist: the nearest visible enemy hero now, nil for none in range; retreating: the ally is in retreat mode.
-- Returns counts, why: "retreat" (retreat mode), "away" (the nearest enemy is AWAY_MARGIN further, or none is in range
-- now), "initiation" (as close or closer), "unknown" (no sample or no enemy before the jump: only retreat mode counts).
-- A jump still in its cast point has not moved the ally yet: the caller passes no sample.
function AllyEscapeRules.JumpIsEscape(before, nowDist, retreating)
	if retreating then
		return true, "retreat"
	end
	if before == nil or before.dist == nil then
		return false, "unknown"
	end
	if nowDist == nil or nowDist > before.dist + AllyEscapeRules.AWAY_MARGIN then
		return true, "away"
	end
	return false, "initiation"
end

-- Cast within `window` seconds, from an ally's ability: its cooldown (GetCooldown) and the time left on it. A read
-- with the time left above the cooldown is not trusted. Cooldown reduction makes the time left start lower, so the
-- cast reads older than it is: a missed skip, never a false one. Returns justCast, secondsAgo (nil when not on
-- cooldown).
function AllyEscapeRules.JustCast(cooldown, remaining, window)
	if cooldown == nil or remaining == nil or cooldown <= 0 or remaining <= 0 then
		return false, nil
	end
	local ago = cooldown - remaining
	if ago < -0.1 then
		return false, nil
	end
	ago = math.max(ago, 0)
	return ago <= (window or AllyEscapeRules.RECENT), ago
end

return AllyEscapeRules
