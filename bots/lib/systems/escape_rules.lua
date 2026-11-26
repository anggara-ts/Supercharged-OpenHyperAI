-- Pure rules for escape jumps (#36, Puck): plain numbers in, so tests/test_escape_rules.lua can check them without
-- the bot API.
local EscapeRules = {}

-- Death Prophet's Spirit Siphon breaks beyond cast range + siphon_buffer (datafeed hero 43, 7.42:
-- AbilityCastRange 500, siphon_buffer 250).
EscapeRules.SIPHON_BREAK = 500 + 250

-- Unit vector for an escape jump from (bx, by): away from the enemies (each weighted by 1 / distance, so the
-- nearest counts most) and toward home (hx, hy, our fountain). Game 064, 43:23: Puck's escapes aimed at our
-- Ancient (Fu.GetEscapeLoc) and she died moving away from the fountain (4200 -> 5180 in 3.5s). enemies: a list of
-- { x, y }. homeWeight: share of the home direction (default 0.4). With no enemy, straight home.
function EscapeRules.Direction(bx, by, enemies, hx, hy, homeWeight)
	homeWeight = homeWeight or 0.4
	local awayX, awayY = 0, 0
	for _, enemy in ipairs(enemies or {}) do
		local dx, dy = bx - enemy.x, by - enemy.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist < 1 then
			dist = 1
		end
		-- (dx, dy) / dist is the unit vector, another / dist weights it.
		awayX, awayY = awayX + dx / (dist * dist), awayY + dy / (dist * dist)
	end
	local homeX, homeY = hx - bx, hy - by
	local homeLen = math.sqrt(homeX * homeX + homeY * homeY)
	if homeLen > 1 then
		homeX, homeY = homeX / homeLen, homeY / homeLen
	else
		homeX, homeY = 0, 0
	end
	local awayLen = math.sqrt(awayX * awayX + awayY * awayY)
	if awayLen <= 0 then
		return homeX, homeY
	end
	awayX, awayY = awayX / awayLen, awayY / awayLen
	local x = awayX * (1 - homeWeight) + homeX * homeWeight
	local y = awayY * (1 - homeWeight) + homeY * homeWeight
	local len = math.sqrt(x * x + y * y)
	if len < 0.01 then
		-- Enemies straight between her and home: sideways (any perpendicular beats a step into them).
		return -awayY, awayX
	end
	return x / len, y / len
end

-- The escape direction from (bx, by) for a jump of `length` toward safety (sx, sy: the nearest standing allied tower
-- or our fountain), bent away from the threats only inside that (#36, game 071, 34:06: the exit Orb went away from
-- Undying 106 away but 547 farther from home, toward the Dire top T2, and the Jaunt to it never came).
-- Candidates every BEND_STEP degrees off the safe direction, up to MAX_BEND (any of them still brings her closer to
-- safety); a candidate is out when its path comes closer to an enemy than min(PASS_RADIUS, how near that enemy is now)
-- (she may not walk into or past a threat). Among the rest: the best cos(bend) + AWAY_BEND x (the share pointing away
-- from the enemies, each weighted 1 / distance). Only when every candidate in the cone passes a threat, the whole
-- circle is tried ("away": it may take her farther from home); when that fails too, EscapeRules.Direction
-- ("fallback"). enemies: a list of { x, y }. Returns dx, dy, how ("safe" | "bent" | "away" | "fallback").
EscapeRules.MAX_BEND = 75
EscapeRules.BEND_STEP = 15
EscapeRules.PASS_RADIUS = 350
EscapeRules.AWAY_BEND = 0.5
local function ClosestOnSegment(bx, by, dx, dy, length, px, py)
	local t = (px - bx) * dx + (py - by) * dy
	t = math.max(0, math.min(length, t))
	local cx, cy = bx + dx * t, by + dy * t
	return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
end
function EscapeRules.SafeDirection(bx, by, enemies, sx, sy, length)
	enemies = enemies or {}
	length = length or 1000
	local hx, hy = sx - bx, sy - by
	local hLen = math.sqrt(hx * hx + hy * hy)
	if hLen < 1 then
		local x, y = EscapeRules.Direction(bx, by, enemies, sx, sy)
		return x, y, "fallback"
	end
	hx, hy = hx / hLen, hy / hLen
	local ax, ay = 0, 0
	for _, enemy in ipairs(enemies) do
		local ex, ey = bx - enemy.x, by - enemy.y
		local dist = math.max(1, math.sqrt(ex * ex + ey * ey))
		ax, ay = ax + ex / (dist * dist), ay + ey / (dist * dist)
	end
	local aLen = math.sqrt(ax * ax + ay * ay)
	if aLen > 0 then
		ax, ay = ax / aLen, ay / aLen
	end
	local function clear(dx, dy)
		for _, enemy in ipairs(enemies) do
			local nowDist = math.sqrt((enemy.x - bx) * (enemy.x - bx) + (enemy.y - by) * (enemy.y - by))
			local limit = math.min(EscapeRules.PASS_RADIUS, nowDist) - 1
			if ClosestOnSegment(bx, by, dx, dy, length, enemy.x, enemy.y) < limit then
				return false
			end
		end
		return true
	end
	local function best(maxBend)
		local bestX, bestY, bestScore, bestBend = nil, nil, nil, nil
		for bend = -maxBend, maxBend, EscapeRules.BEND_STEP do
			local rad = math.rad(bend)
			local dx = hx * math.cos(rad) - hy * math.sin(rad)
			local dy = hx * math.sin(rad) + hy * math.cos(rad)
			if clear(dx, dy) then
				local score = math.cos(rad) + EscapeRules.AWAY_BEND * (dx * ax + dy * ay)
				if bestScore == nil or score > bestScore + 1e-9 then
					bestX, bestY, bestScore, bestBend = dx, dy, score, bend
				end
			end
		end
		return bestX, bestY, bestBend
	end
	local x, y, bend = best(EscapeRules.MAX_BEND)
	if x ~= nil then
		return x, y, bend == 0 and "safe" or "bent"
	end
	x, y = best(180)
	if x ~= nil then
		return x, y, "away"
	end
	x, y = EscapeRules.Direction(bx, by, enemies, sx, sy)
	return x, y, "fallback"
end

-- An escape Waning Rift (its move: max_distance 350, cast range 0, cast point 0.1, cooldown 15/14/13/12; silence
-- 2-3.5s in radius 400; datafeed hero 13, 7.42) when she is under RIFT_ESCAPE_HP with an enemy hero on her or at
-- least RIFT_ESCAPE_UNITS creeps / zombies / summons attacking her, and no Jaunt to an Orb gets her out now (#36,
-- game 071, 34:04-34:15: Orb down, a 14-17 creep wave and zombies on her, no escape Rift at any point).
EscapeRules.RIFT_ESCAPE_HP = 0.35
EscapeRules.RIFT_ESCAPE_UNITS = 2
function EscapeRules.EscapeRiftNow(hp, heroOnHer, unitAttackers, exitJauntReady)
	if exitJauntReady == true or (hp or 1) >= EscapeRules.RIFT_ESCAPE_HP then
		return false
	end
	return heroOnHer == true or (unitAttackers or 0) >= EscapeRules.RIFT_ESCAPE_UNITS
end

-- A low-HP shift against units only (no hero hit in the last 1.5s, no stun or projectile due) only delays the death
-- inside a creep wave or among zombies (game 071, t=2051: a second shift in place at 5% HP among 14-17 creeps, dead
-- at 2055). When she can move out (a Rift, or a Jaunt to an Orb that gets her out), she does that instead; a shift is
-- for hero damage or a stun. With no way to move, the shift stays.
function EscapeRules.MoveOutInsteadOfShift(why, heroHit, threatDue, canMoveOut)
	return why == "low-hp-units" and heroHit ~= true and threatDue ~= true and canMoveOut == true
end
-- Out of an enemy tower's range when it is hitting her (#36, game 072, 19:56-20:05: the Dire mid T2 hit her alone
-- for 8s, HP 0.70 -> 0.26, she started a TP inside its range, Bramble rooted her, dead at 20:05; her escape rules
-- reacted to heroes and creeps only). towerOnHer: the tower targets her, or it hit her in the last second with no
-- allied creep or other hero in its range to take the shots. Only when her HP is under TOWER_ESCAPE_HP or fell more
-- than TOWER_ESCAPE_LOSS in the last second. outDist: how far she has to move to leave its range (+ a margin). The
-- fastest way: walk when she is within TOWER_WALK_EDGE of the edge, a Rift (max_distance 350, datafeed hero 13)
-- when it gets her out, else the Orb toward safety and a Jaunt once it is out of range, else walk. No Rift that
-- lands her still inside (game 087, t=740: out=455 against a 340 jump; the Rift was ordered three times, she walked
-- anyway and lost 0.76 -> 0.57 HP). Returns nil | "walk" | "rift" | "orb-jaunt".
EscapeRules.TOWER_ESCAPE_HP = 0.65
EscapeRules.TOWER_ESCAPE_LOSS = 0.10
EscapeRules.TOWER_WALK_EDGE = 200
function EscapeRules.TowerEscape(towerOnHer, hp, loss, outDist, orbJauntReady, riftReady, riftDistance)
	if towerOnHer ~= true then
		return nil
	end
	if (hp or 1) >= EscapeRules.TOWER_ESCAPE_HP and (loss or 0) <= EscapeRules.TOWER_ESCAPE_LOSS then
		return nil
	end
	outDist = outDist or 0
	if outDist <= EscapeRules.TOWER_WALK_EDGE then
		return "walk"
	end
	if riftReady == true and outDist <= (riftDistance or 350) then
		return "rift"
	end
	if orbJauntReady == true then
		return "orb-jaunt"
	end
	return "walk"
end
-- A Rift or Orb of hers not out yet (#36, game 087, t=740-741): in its cast point the bot can't cast (canCast is
-- false), so the tower escape fell back to a walk order, which cancelled the Rift; three Rift orders, none went out.
-- No new order while the spell is in its ability phase, or while her own order is younger than the cast point +
-- CAST_ORDER_SLACK and the spell is not on cooldown yet (the order is taken a think later). A spell that never
-- starts (a held or dropped order) stops holding after that window; hero_puck.lua then skips that spell for 1s
-- (X.TowerCastSkipped, tower-escape via=skip-cast), so the walk goes out instead of the same order again.
EscapeRules.CAST_ORDER_SLACK = 0.2
function EscapeRules.CastPending(inPhase, orderAge, castPoint, onCooldown)
	if inPhase == true then
		return true
	end
	if orderAge == nil or onCooldown == true then
		return false
	end
	return orderAge < (castPoint or 0) + EscapeRules.CAST_ORDER_SLACK
end
-- Behind an enemy tower on the way home (#36, game 072, 19:56-20:05: after the team's dive past Dire's mid T2 and
-- the kill, her walk home crossed the T2's range and the tower hit her alone): hop over its range with the Orb and a
-- Jaunt instead of walking through. behind: she is farther from home than the tower; the line home passes within
-- range + TOWER_MARGIN of it; she is within TOWER_HOP_NEAR of its range (about to cross: the Orb flies max_distance
-- 1950, datafeed hero 13, so from the edge it clears the 2 x (range + margin) = 1700 across a 700 range tower); she
-- is heading home.
EscapeRules.TOWER_MARGIN = 150
EscapeRules.TOWER_HOP_NEAR = 300
function EscapeRules.TowerHopWanted(botHome, towerHome, pathToTower, towerDist, range, headingHome)
	if headingHome ~= true or botHome <= towerHome then
		return false
	end
	local clear = (range or 700) + EscapeRules.TOWER_MARGIN
	return pathToTower < clear and towerDist < clear + EscapeRules.TOWER_HOP_NEAR
end
-- The Orb's line for a hop: candidates every 15 degrees up to 60 off the home direction (closest to home first); on
-- each, the first point within orbReach that is closer to home than the tower and outside its range +
-- TOWER_MARGIN is where she Jaunts. Returns dx, dy, hopAt (the distance along the line) or nil when no line clears.
function EscapeRules.HopDirection(bx, by, tx, ty, range, hx, hy, orbReach)
	local ux, uy = hx - bx, hy - by
	local uLen = math.sqrt(ux * ux + uy * uy)
	if uLen < 1 then
		return nil
	end
	ux, uy = ux / uLen, uy / uLen
	local clear = (range or 700) + EscapeRules.TOWER_MARGIN
	local towerHome = math.sqrt((hx - tx) * (hx - tx) + (hy - ty) * (hy - ty))
	for _, bend in ipairs({ 0, 15, -15, 30, -30, 45, -45, 60, -60 }) do
		local rad = math.rad(bend)
		local dx = ux * math.cos(rad) - uy * math.sin(rad)
		local dy = ux * math.sin(rad) + uy * math.cos(rad)
		for along = 100, orbReach or 1950, 50 do
			local px, py = bx + dx * along, by + dy * along
			local toTower = math.sqrt((px - tx) * (px - tx) + (py - ty) * (py - ty))
			local toHome = math.sqrt((hx - px) * (hx - px) + (hy - py) * (hy - py))
			if toHome < towerHome and toTower > clear then
				return dx, dy, along
			end
		end
	end
	return nil
end
-- Is a point (px, py) on the escape side of (bx, by) for the direction (dx, dy)? For a Jaunt to the orb: it must
-- take her the way the escape goes (game 064, t=2600: a danger Jaunt to an orb flying away from base).
function EscapeRules.IsOnEscapeSide(bx, by, px, py, dx, dy)
	return (px - bx) * dx + (py - by) * dy > 0
end

-- Spare mana for an Illusory Orb harass in lane (#36, game 064: 3 orbs in 5 minutes of lane). After the orb, mana
-- for Waning Rift stays (Phase Shift costs no mana, datafeed hero 13), and either the pool is nearly full or the
-- regen over the orb's cooldown pays the orb back.
function EscapeRules.SpareManaOrb(mana, maxMana, regen, orbCost, riftCost, orbCooldown)
	if mana - orbCost < riftCost or maxMana <= 0 then
		return false
	end
	return mana / maxMana >= 0.9 or regen * orbCooldown >= orbCost
end

-- Lane Orb harass keeps the Orb + Jaunt escape when it may be needed (#36, game 067, 3:55: she threw her only Orb
-- at Death Prophet 895 away at about 70% HP; Spirit Siphon caught her at 4:01 with the Orb on cooldown, and she
-- died at 4:08). No harass below HARASS_MIN_HP, or with a real enemy hero (not disabled) closer than
-- HARASS_THREAT_RANGE: the Orb's cooldown (12-9s, datafeed hero 13) is longer than any hero needs to walk 900.
-- nearestDist: the nearest such enemy hero, nil when none. Returns safe, why ("hp" | "threat" | nil).
EscapeRules.HARASS_THREAT_RANGE = 900
EscapeRules.HARASS_MIN_HP = 0.7
function EscapeRules.OrbHarassSafe(hp, nearestDist)
	if hp < EscapeRules.HARASS_MIN_HP then
		return false, "hp"
	end
	if nearestDist ~= nil and nearestDist < EscapeRules.HARASS_THREAT_RANGE then
		return false, "threat"
	end
	return true, nil
end

-- No TP channel (3s, 7.42 items_all.txt item_tpscroll AbilityChannelTime) while Spirit Siphon drains her or an
-- enemy hero that hit her in the last 2s stands within TP_HOLD_RANGE (#36, game 067, 4:05: TP at 23% HP with Death
-- Prophet 82 away, dead at 4:08 inside the channel). Damage does not stop a channel, so the hitter just keeps
-- hitting for the 3s. 750 = the Siphon's break distance.
-- units (#191, optional): the non-hero threats, a table with
--   exitOrb: her exit Orb is in flight and the Jaunt is ready (a Jaunt gets her out at once; game 073 t=2379 and 074
--     t=6323: a TP at 0.09 / 0.14 HP the think after the shift, with the exit Orb out);
--   roshan: Roshan next to her is on her (game 073 t=2379: TP in the pit, dead in the channel);
--   towerAge / unitAge: seconds since an enemy tower / creeps last hit her, the Phase Shift's time not counted
--     (EscapeRules.HitAge); creeps hold only under TP_HOLD_UNIT_HP (game 074 t=6323: 0.14 -> 0.02 in the channel
--     among 4 creeps), a tower at any HP;
--   hp: her HP share.
-- Returns hold, why ("siphoned" | "hit-near" | "exit-orb" | "roshan" | "tower" | "units" | nil).
EscapeRules.TP_HOLD_RANGE = EscapeRules.SIPHON_BREAK
EscapeRules.TP_HOLD_HIT_AGE = 1.5
EscapeRules.TP_HOLD_UNIT_HP = 0.5
function EscapeRules.HoldTp(siphoned, hitterDist, units)
	if siphoned then
		return true, "siphoned"
	end
	if hitterDist ~= nil and hitterDist <= EscapeRules.TP_HOLD_RANGE then
		return true, "hit-near"
	end
	units = units or {}
	if units.exitOrb == true then
		return true, "exit-orb"
	end
	if units.roshan == true then
		return true, "roshan"
	end
	if units.towerAge ~= nil and units.towerAge <= EscapeRules.TP_HOLD_HIT_AGE then
		return true, "tower"
	end
	if
		units.unitAge ~= nil
		and units.unitAge <= EscapeRules.TP_HOLD_HIT_AGE
		and (units.hp or 1) < EscapeRules.TP_HOLD_UNIT_HP
	then
		return true, "units"
	end
	return false, nil
end
-- How long ago a hit was, not counting a Phase Shift that started after it (#191). Inside the shift nothing can hit
-- her, so a plain "hit in the last 1.5s" is false exactly when the shift ends and the TP rule looks again (games 073
-- and 074: both TPs came the think after a full shift). hitAt: the last hit (nil: none); shiftAt / shiftEnd: the
-- last shift's order time and its end (nil: no shift). The shift counts when it started at most TP_HOLD_HIT_AGE
-- after the hit, and for a hit stamped inside the shift (the stamp runs every think and the damage read looks 0.5s
-- back, so it can land after the shift order): then the age starts at the shift's end. Returns the age in seconds,
-- or nil.
function EscapeRules.HitAge(now, hitAt, shiftAt, shiftEnd)
	if hitAt == nil then
		return nil
	end
	if shiftAt ~= nil and shiftEnd ~= nil and hitAt <= shiftEnd and shiftAt - hitAt <= EscapeRules.TP_HOLD_HIT_AGE then
		return math.max(0, shiftAt - hitAt) + math.max(0, now - math.max(shiftEnd, hitAt))
	end
	return now - hitAt
end

-- Phase Shift at low HP while being hit (#36, game 067, 42:07-42:16: Tombstone zombies held her at 1-6% HP for 9s
-- with Phase Shift ready; every Phase rule reacted to heroes or projectiles). Under LOW_HP_PHASE and being hit:
-- "low-hp-units" when a creep hit her in the last second or a unit is attacking her, "low-hp-hit" when only her HP
-- is falling (hpLoss: the drop over the last second, a share of max HP; any source, a single hero too). Game 068:
-- the HP clause fired on hero damage only at t=2656 and t=2666 (one enemy near, so the outnumbered rule could not
-- fire); both shifts held 2.5s and she lived. It is kept, under its own name. nil: no low-HP shift.
EscapeRules.LOW_HP_PHASE = 0.2
EscapeRules.LOW_HP_LOSS = 0.02
function EscapeRules.LowHpPhase(hp, hpLoss, hitByCreep, attackers)
	if hp >= EscapeRules.LOW_HP_PHASE then
		return nil
	end
	if hitByCreep == true or (attackers or 0) >= 1 then
		return "low-hp-units"
	end
	if (hpLoss or 0) >= EscapeRules.LOW_HP_LOSS then
		return "low-hp-hit"
	end
	return nil
end
function EscapeRules.IsLowHpWhy(why)
	return why == "low-hp-units" or why == "low-hp-hit"
end

-- How long a Phase Shift waits for the outpost hold (the mode whose Think gives no order, so the shift's channel is
-- not replaced by a move) before it goes out anyway. A dodge can't wait (0.2s; a close one casts at once,
-- PhaseDodgeNow). A low-HP shift waits only 0.2s while Valve's retreat mode is active from the start of the wait to
-- the cast (game 068: t=810 and t=1204 held the full shift from mode 4); anywhere else it takes the hold first
-- (game 068, t=3499: the 0.2s cast went out in defend mode 12 before the hold, broke after 0.13s, dead at 3501).
-- Every other shift waits up to 0.4s.
EscapeRules.PHASE_WAIT_DODGE = 0.2
EscapeRules.PHASE_WAIT_HOLD = 0.4
function EscapeRules.PhaseMaxWait(why, retreatModeThroughout)
	why = tostring(why)
	if string.sub(why, 1, 5) == "dodge" then
		return EscapeRules.PHASE_WAIT_DODGE
	end
	if EscapeRules.IsLowHpWhy(why) and retreatModeThroughout == true then
		return EscapeRules.PHASE_WAIT_DODGE
	end
	return EscapeRules.PHASE_WAIT_HOLD
end
-- Is a wait (age: seconds since it started) still the one for this cast? A wait is kept for its cap + 0.3s; an
-- older one is from an earlier decision and its fields (escape, Orb first) must not be read (game 068, t=2453: a
-- close dodge cast with waited=3.77, from a retreat wait that never cast). nil age: no wait.
function EscapeRules.PhaseWantFresh(age, maxWait)
	return age ~= nil and age <= (maxWait or EscapeRules.PHASE_WAIT_HOLD) + 0.3
end

-- An escape shift: one she uses to get away, not a dodge in a fight she stays in. Low-HP, Siphon and Roshan shifts
-- always; any other non-dodge shift when she was retreating as the wait started (Valve's retreat mode or a hard
-- retreat) or is under ESCAPE_HP. Game 068: 7 of her 10 deaths came 1-3s after a shift in place (t=2079, 2193,
-- 2330, 2458, 2684, 2791, 3383), with no Orb out to Jaunt to when it ended.
EscapeRules.ESCAPE_HP = 0.5
function EscapeRules.IsEscapeShift(why, retreating, hp)
	why = tostring(why)
	if string.sub(why, 1, 5) == "dodge" then
		return false
	end
	if EscapeRules.IsLowHpWhy(why) or why == "siphon" or why == "roshan" then
		return true
	end
	return retreating == true or (hp or 1) < EscapeRules.ESCAPE_HP
end

-- Throw the Orb toward the escape point first, during the wait for the hold (dead time), so she can Jaunt to it as
-- the shift ends: an escape shift, the Orb ready, Jaunt usable (not rooted: Jaunt is ROOT_DISABLES, game files) and
-- no Orb already out. Game 068, t=2326-2330: a shift in place, the Orb only after it ended, dead at 2330.
function EscapeRules.PhaseOrbFirst(escapeShift, orbReady, jauntReady, rooted, orbOut)
	return escapeShift == true and orbReady == true and jauntReady == true and rooted ~= true and orbOut ~= true
end

-- When to Jaunt to the Orb out of an escape shift. "early": once the shift has covered the damage on the way, after
-- EARLY_JAUNT_AFTER, or from EARLY_JAUNT_MIN when no stun or projectile is due at her (threatDue false); the Jaunt
-- ends the shift but gets her out sooner, and the spot must pass ExitJauntOk. "end": the shift's last
-- JAUNT_BEFORE_END seconds. "orb-end": before the Orb ends; it flies max_distance / orb_speed (1950 / 750 = 2.6s,
-- datafeed hero 13), less than a rank 3-4 shift (2.5 / 3.25s). sinceOrb / orbFlight nil: Orb time unknown.
-- Returns now, when ("early" | "end" | "orb-end" | nil).
EscapeRules.JAUNT_BEFORE_END = 0.2
EscapeRules.JAUNT_ORB_MARGIN = 0.3
EscapeRules.EARLY_JAUNT_MIN = 0.15
EscapeRules.EARLY_JAUNT_AFTER = 0.5
-- With no Orb out at an escape shift's end, the Orb ready again is thrown home in the shift's last 0.15s (its cast
-- point 0.1, datafeed hero 13, ends about with the shift).
EscapeRules.ORB_EXIT_BEFORE_END = 0.15
function EscapeRules.ShiftJauntNow(sinceOrder, duration, sinceOrb, orbFlight, threatDue)
	if sinceOrder >= duration - EscapeRules.JAUNT_BEFORE_END then
		return true, "end"
	end
	if sinceOrb ~= nil and orbFlight ~= nil and sinceOrb >= orbFlight - EscapeRules.JAUNT_ORB_MARGIN then
		return true, "orb-end"
	end
	if
		sinceOrder >= EscapeRules.EARLY_JAUNT_AFTER
		or sinceOrder >= EscapeRules.EARLY_JAUNT_MIN and threatDue ~= true
	then
		return true, "early"
	end
	return false, nil
end

-- No offensive Waning Rift (the "group" and "target" jumps into enemies) when she is under ESCAPE_HP with an enemy
-- hero near, or the enemy heroes outnumber her side (allies counts her), at any time; and for RIFT_BLOCK seconds
-- after an escape shift ends. Game 068: t=2329 (escape shift, Rift why=group, dead at 2330), t=2456 (2 enemies near
-- and no ally), t=2788 (26% HP, Rift why=target). Game 069: group / target Rifts outside the 2s block at about
-- 50-70% HP into 2-4 heroes (t=909, 2091, 2255). sinceEnd nil: no shift yet. Returns blocked, why
-- ("hurt" | "outnumbered" | "after-shift" | nil).
EscapeRules.RIFT_BLOCK = 2.0
function EscapeRules.OffensiveRiftBlocked(sinceEnd, escapeShift, hp, enemies, allies)
	enemies = enemies or 0
	if (hp or 1) < EscapeRules.ESCAPE_HP and enemies >= 1 then
		return true, "hurt"
	end
	if enemies > (allies or 0) then
		return true, "outnumbered"
	end
	if escapeShift == true and sinceEnd ~= nil and sinceEnd >= 0 and sinceEnd <= EscapeRules.RIFT_BLOCK then
		return true, "after-shift"
	end
	return false, nil
end

-- The Orb stays for the escape (Orb + Jaunt) under ESCAPE_HP with an enemy hero within KEEP_ORB_RANGE: no kill,
-- fight, push, farm or lane Orb then, only the escape Orbs (#36, game 069: at 6 of 6 escape shifts the Orb was
-- already out as a fight Orb or on cooldown, so no Orb was there to Jaunt to).
EscapeRules.KEEP_ORB_RANGE = 1200
function EscapeRules.KeepOrbForEscape(hp, enemiesNear)
	return (hp or 1) < EscapeRules.ESCAPE_HP and (enemiesNear or 0) >= 1
end

-- How far the Orb must be for an exit Jaunt: what it can have reached. EXIT_PATH_SHARE of the path it has flown
-- (orb_speed x time since it left; the curve makes the straight line shorter than the path), capped at
-- EXIT_JAUNT_MIN and at least EXIT_JAUNT_FLOOR. A fixed 900 could never pass at Phase Shift rank 1: an Orb thrown
-- with the shift has flown about 750 x 1.05 = 790 of path when the 1.0s shift ends (datafeed hero 13: orb_speed 750,
-- Phase Shift 1 / 1.75 / 2.5 / 3.25s). pathFlown nil (Orb time unknown): EXIT_JAUNT_MIN.
EscapeRules.EXIT_JAUNT_MIN = 900
EscapeRules.EXIT_JAUNT_FLOOR = 400
EscapeRules.EXIT_PATH_SHARE = 0.75
function EscapeRules.ExitJauntNeed(pathFlown)
	if pathFlown == nil then
		return EscapeRules.EXIT_JAUNT_MIN
	end
	return math.max(
		EscapeRules.EXIT_JAUNT_FLOOR,
		math.min(EscapeRules.EXIT_JAUNT_MIN, EscapeRules.EXIT_PATH_SHARE * pathFlown)
	)
end
-- An exit Jaunt goes to an Orb on the escape side, at least `need` away (ExitJauntNeed), with fewer enemy heroes
-- within 700 of it than within 700 of her, and a real gain against the nearest enemy hero: the Orb is at least
-- EXIT_GAIN farther from that hero than she is, and outside its attack range + EXIT_RANGE_MARGIN (#36, game 069
-- t=2547: a Jaunt to an Orb 532 away, 282 closer to home, Io 320 -> 628 away, dead 2s later). meToEnemy /
-- orbToEnemy / enemyRange nil: no enemy hero near, no gain test. Returns ok, why ("wrong-side" | "near" | "crowded"
-- | "no-gain" | "in-range" | nil), gain (orbToEnemy - meToEnemy, or nil).
EscapeRules.EXIT_GAIN = 400
EscapeRules.EXIT_RANGE_MARGIN = 200
function EscapeRules.ExitJauntOk(dist, need, escapeSide, enemiesAtOrb, enemiesHere, meToEnemy, orbToEnemy, enemyRange)
	local gain = meToEnemy ~= nil and orbToEnemy ~= nil and orbToEnemy - meToEnemy or nil
	if escapeSide ~= true then
		return false, "wrong-side", gain
	end
	if (dist or 0) < (need or EscapeRules.EXIT_JAUNT_MIN) then
		return false, "near", gain
	end
	if (enemiesAtOrb or 0) >= math.max(1, enemiesHere or 0) then
		return false, "crowded", gain
	end
	if gain ~= nil then
		if gain < EscapeRules.EXIT_GAIN then
			return false, "no-gain", gain
		end
		if orbToEnemy < (enemyRange or 0) + EscapeRules.EXIT_RANGE_MARGIN then
			return false, "in-range", gain
		end
	end
	return true, nil, gain
end

-- A dodge Phase Shift goes out in the same think when the outpost hold is the active mode (held), or when the hit is
-- due in under PHASE_LAST_CALL (no time left to wait). Otherwise it waits a think for the hold, which was asked for
-- when the stun was first seen (X.AskDodgeHold). Game 069, t=761 (tti 0.20) and t=830 (tti 0.30): cast at once in
-- attack mode, the hold not up (hold-left after=0.03 mode=2 hold-desire=0.00), the shift broke at 0.10s and Impale
-- landed. PHASE_LAST_CALL: the dodge's reaction time 0.11 (DodgeRules.LATENCY 0.1 + cast point 0.01, datafeed hero 13)
-- plus about three frames. tti nil (unknown): keep the wait.
EscapeRules.PHASE_NOW_TTI = 0.35
EscapeRules.PHASE_LAST_CALL = 0.22
function EscapeRules.PhaseDodgeNow(tti, held)
	if tti == nil or tti >= EscapeRules.PHASE_NOW_TTI then
		return false
	end
	return held == true or tti < EscapeRules.PHASE_LAST_CALL
end
-- Ask for the outpost hold before a dodge: an enemy hero is casting a linear stun at her (its cast point, Impale
-- 0.3s, datafeed hero 88), or a linear stun is flying at her with tti under DODGE_HOLD_TTI. The hold then has time
-- to be the active mode when the dodge casts.
EscapeRules.DODGE_HOLD_TTI = 1.0
function EscapeRules.AskDodgeHold(castingAtHer, tti)
	return castingAtHer == true or (tti ~= nil and tti < EscapeRules.DODGE_HOLD_TTI)
end
-- cast: the order went out before the hit time (or the time was unknown); late: after it.
function EscapeRules.PhaseDodgeResult(waited, tti)
	if tti == nil or waited < tti then
		return "cast"
	end
	return "late"
end

return EscapeRules
