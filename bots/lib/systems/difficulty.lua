-- Shared bot system: difficulty levels from the lobby's bot difficulty (#232). Pure rules (no bot API calls), so the
-- tests can drive them with plain numbers; bots/lib/systems/difficulty_hooks.lua reads bot:GetDifficulty() and wires
-- the knobs into the cast orders, attack orders, dodges and the gank / smoke / tower-dive rules.
--
-- Maintainer decisions (2026-11-23): today's play is Unfair (the top level, every knob neutral); a lower level only
-- takes things away, never bonus gold or XP; Passive does not fight heroes (lane, farm, objectives,
-- like Valve's passive bots). Each bot reads its own difficulty (the lobby sets it per team).
local D = {}

-- The API's DIFFICULTY_* values (the game's [SHy-API] dump, docs/BOT_API_RUNTIME.md): PASSIVE=0, EASY=1, MEDIUM=2,
-- HARD=3, UNFAIR=4, NPX=9; INVALID=5 is not a lobby level. NPX ("new player experience") is taken to be the lobby's
-- "New Player" bot difficulty (maintainer, 2026-11-24: "there is a newplayer difficulty, do we handle that?"); the
-- [SHy-DIFF] start line's raw= shows what a New Player lobby really reports. Before this it fell back to Unfair.
D.NAMES = { [0] = "passive", [1] = "easy", [2] = "medium", [3] = "hard", [4] = "unfair", [9] = "newplayer" }
D.DEFAULT = "unfair"

-- Knobs per level. Estimates for a human-like player, not game data; the [SHy-DIFF] roll lines show their effect.
-- Maintainer decision (2026-11-27, "proceed using probability based"): no reaction delay on any level. A cast that is
-- allowed goes out on the frame it is decided; a lower level fails some decisions instead. The delay was removed
-- because a held escape never went out: game 086, Puck's Phase Shift against Stifling Dagger was held and the dagger
-- landed; game 087 8:32, Puck's Orb, Rift and Phase Shift switched every think, none was held long enough, she died.
--   reactiveChance  chance a reactive cast goes out (escape, dodge, save, interrupt; hero spells and the dodge
--                   checks). Rolled once per danger episode per bot (D.ReactiveStep), shared by all its reactive
--                   spells and dodges: a failed roll stays failed for the whole episode.
--   castChance      chance any other cast decision goes out (nukes, initiations, items on an enemy hero). Rolled
--                   once per decision (D.CastStep); a failed one is held SKIP_HOLD s, then decided again.
--   lastHitError    s: a last-hit attack goes out up to this much late (uniform 0..value, once per creep). A melee
--                   last-hit window is about one server tick to ~0.1s, so 0.25 misses most hits and 0.12 about half.
--   hunt            hero ganks of team roam: "off", "careful" (more allies than enemies near, or a target under
--                   HUNT_CAREFUL_HP), "on".
--   smoke           Smoke of Deceit: "off", "careful" (SMOKE_CAREFUL_ALLIES heroes together instead of 2), "on".
--   dive            chasing a hero under an enemy tower: "off" (retreat out of its reach), "careful" (retreat
--                   when the tower shoots us and the target is not nearly dead), "on" (today's rules only).
--   fightHeroes     false: no hero hunts / help fights, no attack orders or targeted spells on enemy heroes
--                   (escapes in retreat mode excepted), Valve's attack mode off.
-- Passive takes Easy's mechanics: it never fights, so they only touch its farming and escapes.
-- New Player is the gentlest level that still fights: sloppier than Easy, no ganks, smoke or dives.
D.PROFILES = {
	newplayer = {
		reactiveChance = 0.15,
		castChance = 0.55,
		lastHitError = 0.35,
		hunt = "off",
		smoke = "off",
		dive = "off",
		fightHeroes = true,
	},
	passive = {
		reactiveChance = 0.25,
		castChance = 0.65,
		lastHitError = 0.25,
		hunt = "off",
		smoke = "off",
		dive = "off",
		fightHeroes = false,
	},
	easy = {
		reactiveChance = 0.25,
		castChance = 0.65,
		lastHitError = 0.25,
		hunt = "off",
		smoke = "off",
		dive = "off",
		fightHeroes = true,
	},
	medium = {
		reactiveChance = 0.5,
		castChance = 0.85,
		lastHitError = 0.12,
		hunt = "careful",
		smoke = "careful",
		dive = "careful",
		fightHeroes = true,
	},
	hard = {
		reactiveChance = 0.85,
		castChance = 0.95,
		lastHitError = 0,
		hunt = "on",
		smoke = "on",
		dive = "on",
		fightHeroes = true,
	},
	unfair = {
		reactiveChance = 1,
		castChance = 1,
		lastHitError = 0,
		hunt = "on",
		smoke = "on",
		dive = "on",
		fightHeroes = true,
	},
}

-- A cast decision that went out ends when its last request is older than this; the next request starts a new
-- decision (a new roll). Longer than a mode Think's period: mode Thinks run about 3 times a second (game 063
-- [SHy-PERF]), so a per-frame or per-think caller keeps one decision and one roll.
D.DECISION_GAP = 0.6
-- A failed decision is held this long after its roll, then decided again (a new roll), for every caller: a caller
-- slower than DECISION_GAP (Largo's song toggle, one order a second) does not re-roll on each order.
D.SKIP_HOLD = 1.0
-- A danger episode (D.ReactiveStep) ends when the bot has been out of danger this long: out of retreat and evasive
-- mode, no hero damage and no new threat seen by a dodge check since. Measured from the episode start too, so an
-- episode that starts out of danger (a dodge, a save on an ally) still lasts this long, not one frame.
D.EPISODE_SAFE = 2.0
-- An episode ends after this long at most; the next reactive decision rolls again.
D.EPISODE_CAP = 5.0
-- A cast this soon after the bot was in retreat or evasive mode still counts as reactive: Puck orders her escape
-- Phase Shift from the outpost mode's cast hold (mode 26), up to 0.4s after retreat mode asked for it (game 087
-- [SHy-PUCK] phase cast ... from-mode=4 mode=26).
D.REACTIVE_RECENT = 1.0
D.HUNT_CAREFUL_HP = 0.4
D.SMOKE_CAREFUL_ALLIES = 3
D.DIVE_CAREFUL_HP = 0.25
D.DIVE_RETREAT_DESIRE = 0.9

-- Every knob at today's behaviour (Unfair). The hooks return before any roll or state write when this is true.
function D.IsNeutral(profile)
	return profile.reactiveChance >= 1
		and profile.castChance >= 1
		and profile.lastHitError <= 0
		and profile.hunt == "on"
		and profile.smoke == "on"
		and profile.dive == "on"
		and profile.fightHeroes == true
end
for _, profile in pairs(D.PROFILES) do
	profile.neutral = D.IsNeutral(profile)
end

-- raw: what bot:GetDifficulty() returned (nil when the call failed). Returns level number, name, profile, src.
function D.Resolve(raw)
	if type(raw) == "number" and D.NAMES[raw] ~= nil then
		local name = D.NAMES[raw]
		return raw, name, D.PROFILES[name], "api"
	end
	return 4, D.DEFAULT, D.PROFILES[D.DEFAULT], "default"
end

-- An "other" cast decision for one ability. state: a table kept per unit and ability; roll(): a number in [0, 1),
-- called only for a new decision of a profile with castChance < 1. Returns allowed, rolled (a new roll was drawn).
-- A decision that went out stays open while its requests come within DECISION_GAP; a failed one is held SKIP_HOLD s
-- from its roll (whatever the caller's rate), then decided again.
function D.CastStep(state, now, profile, roll)
	local fresh = state.lastAt == nil
		or (state.skip and now - state.startAt >= D.SKIP_HOLD)
		or (not state.skip and now - state.lastAt > D.DECISION_GAP)
	local rolled = false
	if fresh then
		state.startAt = now
		state.skip = false
		if profile.castChance < 1 then
			state.skip = roll() >= profile.castChance
			rolled = true
		end
	end
	state.lastAt = now
	return not state.skip, rolled
end

-- A reactive cast or dodge (`what`: the ability or dodge check) for one bot. rs: a table kept per bot. One roll per
-- danger episode, shared by every reactive spell and dodge of the bot: Puck's Orb, Rift and Phase Shift together get
-- one roll (three rolls would make Hard's 0.85 a 0.61). A failed roll stays failed until the episode ends
-- (D.EpisodeTick); re-rolling every second would make 0.85 about 0.98. Returns allowed, episode, rolled.
function D.ReactiveStep(rs, now, profile, roll, what)
	local episode = rs.episode
	local rolled = false
	if episode == nil then
		rs.lastId = (rs.lastId or 0) + 1
		episode = { id = rs.lastId, startAt = now, dangerAt = now, refused = {}, fails = 0 }
		episode.allowed = profile.reactiveChance >= 1
			or (profile.reactiveChance > 0 and roll() < profile.reactiveChance)
		rs.episode = episode
		rolled = true
	end
	if not episode.allowed and what ~= nil and not episode.refused[what] then
		-- fails= on the episode-end line: the reactive spells and dodges this episode refused (each counted once).
		episode.refused[what] = true
		episode.fails = episode.fails + 1
	end
	return episode.allowed, episode, rolled
end

-- facts: alive (false: the bot died), danger (in retreat or evasive mode now), hit (hero damage within the last
-- EPISODE_SAFE s). A dodge check that sees a threat sets episode.dangerAt itself. Ends the episode when it is over:
-- returns why ("dead" | "cap" | "safe") and the ended episode, else nil.
function D.EpisodeTick(rs, now, facts)
	local episode = rs.episode
	if episode == nil then
		return nil
	end
	if facts.danger then
		episode.dangerAt = now
	end
	local why = nil
	if facts.alive == false then
		why = "dead"
	elseif now - episode.startAt >= D.EPISODE_CAP then
		why = "cap"
	elseif not facts.hit and now - episode.dangerAt >= D.EPISODE_SAFE then
		why = "safe"
	end
	if why == nil then
		return nil
	end
	rs.episode = nil
	return why, episode
end

-- A last-hit attack on `creep` waits a random 0..lastHitError s after its first order. Returns allowed.
function D.LastHitStep(state, now, profile, roll, creep)
	if profile.lastHitError <= 0 then
		return true
	end
	if state.creep ~= creep then
		state.creep = creep
		state.readyAt = now + roll() * profile.lastHitError
	end
	return now >= state.readyAt
end

-- Team roam's reason (roamWhy) -> "help" (help a core / ally in a fight), "gank" (a hunt on a hero), or nil.
function D.RoamFightKind(why)
	if why == "help-core" or why == "help-ally" then
		return "help"
	end
	if type(why) == "string" and string.find(why, "^hunt%-[%a]+/hero$") then
		return "gank"
	end
	return nil
end

function D.RoamAllowed(profile, kind, targetHp, allies, enemies)
	if kind == nil then
		return true
	end
	if not profile.fightHeroes then
		return false
	end
	if kind ~= "gank" or profile.hunt == "on" then
		return true
	end
	if profile.hunt == "off" then
		return false
	end
	return allies > enemies or (targetHp or 1) < D.HUNT_CAREFUL_HP
end

function D.SmokeAllowed(profile, allies)
	if profile.smoke == "on" then
		return true
	end
	if profile.smoke == "off" then
		return false
	end
	return allies >= D.SMOKE_CAREFUL_ALLIES
end

-- facts: underTower, chasingHero, pushing, towerOnUs, targetHp. Returns a retreat desire (0 = no opinion).
function D.DiveRetreat(profile, facts)
	if profile.dive == "on" or not facts.underTower or not facts.chasingHero or facts.pushing then
		return 0
	end
	if profile.dive == "off" then
		return D.DIVE_RETREAT_DESIRE
	end
	if facts.towerOnUs and (facts.targetHp or 1) >= D.DIVE_CAREFUL_HP then
		return D.DIVE_RETREAT_DESIRE
	end
	return 0
end

-- Second stages of a spell already cast (release, stop, return ...): never rolled, a failed release can kill the bot.
local RELEASE_SUFFIXES = { "_release", "_stop", "_cancel", "_end", "_return", "_break" }
-- Second stages without such a suffix (Concoction's throw before it blows up in the hand, Jaunt out of the orb).
local RELEASE_NAMES = {
	alchemist_unstable_concoction_throw = true,
	elder_titan_return_spirit = true,
	puck_ethereal_jaunt = true,
	techies_focused_detonate = true,
}
function D.IsExemptAbility(name)
	if type(name) ~= "string" or RELEASE_NAMES[name] then
		return true
	end
	-- Map and system abilities (outposts, portals, plus / seasonal), as global_overrides.lua IsHiddenByDesign.
	if
		string.sub(name, 1, 8) == "ability_"
		or string.find(name, "_portal_warp", 1, true) ~= nil
		or string.sub(name, 1, 5) == "plus_"
		or string.sub(name, 1, 9) == "seasonal_"
	then
		return true
	end
	for _, suffix in ipairs(RELEASE_SUFFIXES) do
		if string.sub(name, -#suffix) == suffix then
			return true
		end
	end
	return false
end

return D
