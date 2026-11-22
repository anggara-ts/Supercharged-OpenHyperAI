-- Pure rules for Io's Relocate save (#47): plain numbers in, so tests/test_relocate_rules.lua can check them without
-- the bot API. 7.42 game file (pak01_dir.vpk scripts/npc/heroes/npc_dota_hero_wisp.txt, wisp_relocate): POINT,
-- cast point 0, cast_delay 3.5 / 3.25 / 3.0 (special_bonus_unique_wisp_relocate_delay -2.0), return_time 12,
-- cooldown 90/80/70, mana 175. wisp_tether radius 1000 (the tether breaks past it). Tooltip notes (abil_en.txt):
-- "If Io is disabled during the cast delay, Relocate is cancelled"; "If an allied hero is Tethered, that hero will
-- teleport along with you. You can break the tether at any time to prevent that hero from teleporting with you."
-- Io has no ability to cancel or redirect the return (only modifier_wisp_relocate_return, "About to return to
-- previous location"), so Io always goes back.
local RelocateRules = {}

RelocateRules.CAST_DELAY = { 3.5, 3.25, 3.0 }
RelocateRules.TALENT_DELAY = 2.0
RelocateRules.RETURN_TIME = 12
RelocateRules.TETHER_RADIUS = 1000
-- The ally must still be tethered when the teleport happens: cast only with this much room under the 1000 radius.
RelocateRules.TETHER_SAFE = 850
-- Save when the HP left runs out within the cast delay plus this margin (maintainer's card: "~0.5s").
RelocateRules.MARGIN = 0.5
-- The damage-rate path only below this HP: one 20% nuke inside the window reads as ~16%/s and would spend a 70-90s
-- ultimate on a healthy hero.
RelocateRules.DPS_MAX_HP = 0.7
RelocateRules.FOCUS_HP = 0.45
RelocateRules.LOW_HP = 0.2
-- After the return the ally goes back with Io only when healed this far.
RelocateRules.RETURN_KEEP_HP = 0.7

-- The cast delay at Relocate level 1-3, minus the talent when it is trained (game file values above).
function RelocateRules.CastDelay(level, talent)
	local delay = RelocateRules.CAST_DELAY[math.max(1, math.min(3, level or 1))]
	if talent then
		delay = delay - RelocateRules.TALENT_DELAY
	end
	return delay
end

-- Adds an HP sample (hp as a ratio 0..1) at most every 0.1s and drops those older than 2.5s.
function RelocateRules.AddSample(samples, now, hp)
	local last = samples[#samples]
	if last ~= nil and now - last.t < 0.1 then
		return samples
	end
	samples[#samples + 1] = { t = now, hp = hp }
	while #samples > 0 and now - samples[1].t > 2.5 do
		table.remove(samples, 1)
	end
	return samples
end

-- HP ratio lost per second over the last `window` seconds (default 1.25): the newest sample against the newest one at
-- least `window` old (else the oldest). 0 when the span is under 0.5s (too little history) or over 2s (a gap).
-- Healing in between lowers it: the net loss is what decides whether the HP lasts.
function RelocateRules.LossRate(samples, window)
	window = window or 1.25
	local last = samples[#samples]
	if last == nil then
		return 0
	end
	local ref = samples[1]
	for i = #samples, 1, -1 do
		if last.t - samples[i].t >= window then
			ref = samples[i]
			break
		end
	end
	local span = last.t - ref.t
	if span < 0.5 or span > 2.0 then
		return 0
	end
	return math.max(0, (ref.hp - last.hp) / span)
end

-- Does the hero need the save now? hp: HP ratio (0..1); dps: HP ratio lost per second (LossRate); delay: the cast
-- delay in seconds; enemiesNear: enemy heroes within 1200 of the hero. Returns needed, why, ttd (seconds of HP left
-- at that rate, nil when it is not losing HP):
--   "dps"   the HP runs out within delay + MARGIN (only at or under DPS_MAX_HP)
--   "focus" at or under FOCUS_HP with 2+ enemy heroes on it
--   "low"   at or under LOW_HP with an enemy hero near (the old rule)
function RelocateRules.SaveNeeded(hp, dps, delay, enemiesNear)
	local ttd = nil
	if dps ~= nil and dps > 0 then
		ttd = hp / dps
	end
	if (enemiesNear or 0) < 1 then
		return false, nil, ttd
	end
	if ttd ~= nil and hp <= RelocateRules.DPS_MAX_HP and ttd <= delay + RelocateRules.MARGIN then
		return true, "dps", ttd
	end
	if hp <= RelocateRules.FOCUS_HP and enemiesNear >= 2 then
		return true, "focus", ttd
	end
	if hp <= RelocateRules.LOW_HP then
		return true, "low", ttd
	end
	return false, nil, ttd
end

-- Shortly before the return: does the tethered ally go back with Io? o.allyAlive, o.tetherUp, o.allyHp (ratio),
-- o.alliesAtOrigin (allied heroes near the spot they return to, not counting Io and the ally), o.enemiesAtOrigin
-- (visible enemy heroes there). Returns "keep" (both go back), "break" (break the tether so the ally stays home) or
-- "none" (no tethered ally to decide for), and why.
function RelocateRules.ReturnDecision(o)
	if not o.allyAlive or not o.tetherUp then
		return "none", "no-tether"
	end
	if o.allyHp < RelocateRules.RETURN_KEEP_HP then
		return "break", "hp"
	end
	if (o.enemiesAtOrigin or 0) > 2 + (o.alliesAtOrigin or 0) then
		return "break", "outnumbered"
	end
	return "keep", "healed"
end

-- Rescue Relocate (maintainer, 2026-11-22: tether a healthy, ready ally and Relocate onto a gank in another lane,
-- like Nature's Prophet's save-teleport). wisp_tether AbilityCastRange 1600 (7.42 game file): the partner must be
-- within it.
RelocateRules.TETHER_CAST_RANGE = 1600
RelocateRules.RESCUE_MIN_DIST = 3000
RelocateRules.PARTNER_MIN_HP = 0.7
-- The ganked ally must still be alive this long after the cast delay (it is what we are going for).
RelocateRules.RESCUE_SURVIVE_MARGIN = 1.0

-- Every offensive Relocate (rescue and the far-teamfight join) lands only when our side after the landing (Io, the
-- tethered partner, allied heroes near the landing point) + this margin >= the enemy heroes seen near it
-- (maintainer, 2026-11-22: "not too outnumbered like 2v5"): 2v5 and 2v4 skip, 3v4, 2v3 and 1v1 go.
RelocateRules.OUTNUMBER_MARGIN = 1

function RelocateRules.NumbersOk(ours, enemies)
	return ours + RelocateRules.OUTNUMBER_MARGIN >= enemies
end

-- Is the ally being ganked, and will it still be alive when Io lands? o.hp (ratio), o.dps (ratio lost per second),
-- o.delay (cast delay), o.damaged (hit by an enemy hero in the last 1.5s), o.enemies (enemy heroes seen near it),
-- o.alliesThere (allied heroes near it, not counting it). Returns ok, why ("go" | "no-gank" | "too-late"), ttd (nil
-- when not losing HP). The numbers after the landing are NumbersOk's job.
--   a gank: hit by a hero, 2+ enemy heroes, and they outnumber it and its allies there;
--   it lives through the delay + RESCUE_SURVIVE_MARGIN at the HP it is losing.
function RelocateRules.RescueCheck(o)
	local ttd = nil
	if o.dps ~= nil and o.dps > 0 then
		ttd = o.hp / o.dps
	end
	local alliesThere = o.alliesThere or 0
	if not o.damaged or o.enemies < 2 or o.enemies <= alliesThere + 1 then
		return false, "no-gank", ttd
	end
	if ttd ~= nil and ttd < o.delay + RelocateRules.RESCUE_SURVIVE_MARGIN then
		return false, "too-late", ttd
	end
	return true, "go", ttd
end

-- A partner's fight power, or nil when it doesn't qualify. o.hp (ratio), o.dist (from Io), o.ultReady (its
-- ultimate castable now, cooldown and mana), o.readySpells (non-passive, non-toggle damage / disable spells castable
-- now, the ultimate included), o.channeling, o.inFight (enemy heroes near it or hit by one), o.laneUnderTower (its
-- lane pushed under our tower). Needs HP >= PARTNER_MIN_HP and the ultimate or 2+ spells ready. Higher is better.
function RelocateRules.PartnerScore(o)
	if o.dist > RelocateRules.TETHER_CAST_RANGE or o.hp < RelocateRules.PARTNER_MIN_HP then
		return nil
	end
	if o.channeling or o.inFight or o.laneUnderTower then
		return nil
	end
	if not o.ultReady and (o.readySpells or 0) < 2 then
		return nil
	end
	return (o.readySpells or 0) + (o.ultReady and 2 or 0) + o.hp
end

-- The relocated ally's own think: rec = { teleportAt, returnAt, released } from Io's cast. Holds TPs (and pulls the
-- ally back to Io when farther than 700, so the tether holds for the return) from the teleport until the return,
-- while the ally is at its fountain (distFountain under 2500: it really came along) and Io has not let it go
-- (released: Io broke the tether, the ally stays home). Returns holdTp, moveBack.
function RelocateRules.AllyHold(rec, now, distFountain, distIo)
	if rec == nil or rec.released or now < rec.teleportAt or now >= rec.returnAt or distFountain >= 2500 then
		return false, false
	end
	return true, distIo ~= nil and distIo > 700
end

return RelocateRules
