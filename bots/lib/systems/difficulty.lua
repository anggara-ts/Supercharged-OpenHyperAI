-- Shared bot system: difficulty levels from the lobby's bot difficulty (#232). Pure rules (no bot API calls), so the
-- tests can drive them with plain numbers; bots/lib/systems/difficulty_hooks.lua reads bot:GetDifficulty() and wires
-- the knobs into the cast orders, attack orders, dodges and the gank / smoke / tower-dive rules.
--
-- Maintainer decisions (2026-11-23): today's play is Unfair (the top level, every knob neutral); a lower level only
-- takes things away or adds delay, never bonus gold or XP; Passive does not fight heroes (lane, farm, objectives,
-- like Valve's passive bots). Each bot reads its own difficulty (the lobby sets it per team).
local D = {}

-- The API's DIFFICULTY_* values (the game's [SHy-API] dump, docs/BOT_API_RUNTIME.md): PASSIVE=0, EASY=1, MEDIUM=2,
-- HARD=3, UNFAIR=4, NPX=9; INVALID=5 is not a lobby level. NPX ("new player experience") is taken to be the lobby's
-- "New Player" bot difficulty (maintainer, 2026-11-24: "there is a newplayer difficulty, do we handle that?"); the
-- [SHy-DIFF] start line's raw= shows what a New Player lobby really reports. Before this it fell back to Unfair.
D.NAMES = { [0] = "passive", [1] = "easy", [2] = "medium", [3] = "hard", [4] = "unfair", [9] = "newplayer" }
D.DEFAULT = "unfair"

-- Knobs per level. Estimates for a human-like player, not game data; the [SHy-DIFF] held lines show their effect.
--   reactionDelay   s a cast decision must stay true before the order goes out (per ability): the decision's
--                   first order is held, its first order this long or later goes out. Valve's datafeed has
--                   no reaction time; human reaction to a visual cue is ~0.2-0.3s, a casual player's spell use is
--                   slower than that, so Easy 0.8 / Medium 0.4 / Hard 0.15.
--   castSkipChance  chance a new cast decision is dropped (the ability is held SKIP_HOLD s, then decided again).
--   lastHitError    s: a last-hit attack goes out up to this much late (uniform 0..value, once per creep). A melee
--                   last-hit window is about one server tick to ~0.1s, so 0.25 misses most hits and 0.12 about half.
--   dodgeChance     share of incoming skillshots / stuns the bot reacts to (items and hero spells); 0 = never.
--   hunt            hero ganks of team roam: "off", "careful" (more allies than enemies near, or a target under
--                   HUNT_CAREFUL_HP), "on".
--   smoke           Smoke of Deceit: "off", "careful" (SMOKE_CAREFUL_ALLIES heroes together instead of 2), "on".
--   dive            chasing a hero under an enemy tower: "off" (retreat out of its reach), "careful" (retreat
--                   when the tower shoots us and the target is not nearly dead), "on" (today's rules only).
--   fightHeroes     false: no hero hunts / help fights, no attack orders or targeted spells on enemy heroes
--                   (escapes in retreat mode excepted), Valve's attack mode off.
-- Passive takes Easy's mechanics: it never fights, so they only touch its farming and escapes.
-- New Player is the gentlest level that still fights: slower and sloppier than Easy, no ganks, smoke or dives.
D.PROFILES = {
	newplayer = {
		reactionDelay = 1.0,
		castSkipChance = 0.45,
		lastHitError = 0.35,
		dodgeChance = 0,
		hunt = "off",
		smoke = "off",
		dive = "off",
		fightHeroes = true,
	},
	passive = {
		reactionDelay = 0.8,
		castSkipChance = 0.35,
		lastHitError = 0.25,
		dodgeChance = 0,
		hunt = "off",
		smoke = "off",
		dive = "off",
		fightHeroes = false,
	},
	easy = {
		reactionDelay = 0.8,
		castSkipChance = 0.35,
		lastHitError = 0.25,
		dodgeChance = 0,
		hunt = "off",
		smoke = "off",
		dive = "off",
		fightHeroes = true,
	},
	medium = {
		reactionDelay = 0.4,
		castSkipChance = 0.15,
		lastHitError = 0.12,
		dodgeChance = 0.5,
		hunt = "careful",
		smoke = "careful",
		dive = "careful",
		fightHeroes = true,
	},
	hard = {
		reactionDelay = 0.15,
		castSkipChance = 0.05,
		lastHitError = 0,
		dodgeChance = 1,
		hunt = "on",
		smoke = "on",
		dive = "on",
		fightHeroes = true,
	},
	unfair = {
		reactionDelay = 0,
		castSkipChance = 0,
		lastHitError = 0,
		dodgeChance = 1,
		hunt = "on",
		smoke = "on",
		dive = "on",
		fightHeroes = true,
	},
}

-- A cast decision that went out ends when its last request is older than this; the next request starts a new
-- decision. Longer than a mode Think's period: mode Thinks run about 3 times a second (game 063 [SHy-PERF]).
D.DECISION_GAP = 0.6
-- A decision still held (not sent yet) stays open this long after its last request, so a hero file that orders a
-- spell only once a second gets it out on its next order after the reaction delay. With DECISION_GAP alone every
-- such order was a new decision and was held again: game 080 (Hard), Largo ordered Amphibian Rhapsody once a second
-- (hero_largo.lua toggleOrderAt: at most one order per 1s) from t=1699 to 1712 at 18% HP and the song never started
-- ([SHy-DIFF] held kind=reaction ability=largo_amphibian_rhapsody since=0.00 at t=1699 and 1709). 2.5s covers one
-- missed 1s re-order plus think jitter. Kept short because the next order within it goes out with no new delay, even
-- when the hero decided again (another target); a decision left alone for longer starts over.
D.PENDING_GAP = 2.5
-- A skipped decision is held this long after its reaction delay, then decided again (a new roll).
D.SKIP_HOLD = 1.0
-- A dodge roll holds for this long per target (a projectile flies well under 2s), so the per-frame dodge checks
-- see one decision, not a new roll every frame.
D.DODGE_WINDOW = 2.0
D.HUNT_CAREFUL_HP = 0.4
D.SMOKE_CAREFUL_ALLIES = 3
D.DIVE_CAREFUL_HP = 0.25
D.DIVE_RETREAT_DESIRE = 0.9

-- Every knob at today's behaviour (Unfair). The hooks return before any roll or state write when this is true.
function D.IsNeutral(profile)
	return profile.reactionDelay <= 0
		and profile.castSkipChance <= 0
		and profile.lastHitError <= 0
		and profile.dodgeChance >= 1
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

-- Cast hold (reaction delay and skip) for one ability. state: a table kept per unit and ability; roll(): a number
-- in [0, 1), called only for a new decision of a profile with a skip chance. Returns allowed, why.
-- A decision stays open while its requests come within DECISION_GAP once it went out (state.sent), PENDING_GAP
-- while it is still held (reaction or skip). A skipped decision is decided again SKIP_HOLD s after its reaction
-- delay, for every caller (a caller slower than DECISION_GAP no longer re-rolls on each order).
function D.CastStep(state, now, profile, roll)
	local gap = state.sent and D.DECISION_GAP or D.PENDING_GAP
	local fresh = state.lastAt == nil or now - state.lastAt > gap
	if not fresh and state.skip and now - state.startAt >= profile.reactionDelay + D.SKIP_HOLD then
		fresh = true
	end
	if fresh then
		state.startAt = now
		state.sent = false
		state.skip = profile.castSkipChance > 0 and roll() < profile.castSkipChance
	end
	state.lastAt = now
	if state.skip then
		return false, "skip"
	end
	if now - state.startAt < profile.reactionDelay then
		return false, "reaction"
	end
	state.sent = true
	return true, nil
end

-- One dodge decision per target per DODGE_WINDOW. Called only when a threat was seen. Returns allowed.
function D.DodgeStep(latch, now, profile, roll)
	if profile.dodgeChance >= 1 then
		return true
	end
	if profile.dodgeChance <= 0 then
		return false
	end
	if latch.untilAt == nil or now >= latch.untilAt then
		latch.allowed = roll() < profile.dodgeChance
		latch.untilAt = now + D.DODGE_WINDOW
	end
	return latch.allowed
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

-- Second stages of a spell already cast (release, stop, return ...): never held, a late release can kill the bot.
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
