-- Pure rules for escape jumps (#36, Puck): plain numbers in, so Tests/test_escape_rules.lua can check them without
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
-- hitting for the 3s. 750 = the Siphon's break distance. Returns hold, why ("siphoned" | "hit-near" | nil).
EscapeRules.TP_HOLD_RANGE = EscapeRules.SIPHON_BREAK
function EscapeRules.HoldTp(siphoned, hitterDist)
	if siphoned then
		return true, "siphoned"
	end
	if hitterDist ~= nil and hitterDist <= EscapeRules.TP_HOLD_RANGE then
		return true, "hit-near"
	end
	return false, nil
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

-- When to Jaunt to the Orb out of an escape shift: in the shift's last JAUNT_BEFORE_END seconds, or before the Orb
-- ends. The Orb flies max_distance / orb_speed (1950 / 750 = 2.6s, datafeed hero 13), less than a rank 4 shift
-- (3.25s), so the Jaunt goes at the earlier one. sinceOrb / orbFlight nil: Orb time unknown, shift end only.
EscapeRules.JAUNT_BEFORE_END = 0.2
EscapeRules.JAUNT_ORB_MARGIN = 0.3
function EscapeRules.ShiftJauntNow(sinceOrder, duration, sinceOrb, orbFlight)
	if sinceOrder >= duration - EscapeRules.JAUNT_BEFORE_END then
		return true
	end
	return sinceOrb ~= nil and orbFlight ~= nil and sinceOrb >= orbFlight - EscapeRules.JAUNT_ORB_MARGIN
end

-- No offensive Waning Rift (the "group" and "target" jumps into enemies) for RIFT_BLOCK seconds after a shift ends
-- when it was an escape shift, she is under ESCAPE_HP, or the enemy heroes outnumber her side (allies counts her).
-- Game 068: t=2329 (escape shift, Rift why=group, dead at 2330), t=2456 (dodge shift, 2 enemies near and no ally,
-- Rift why=group, dead at 2458), t=2788 (35% HP, Rift why=target, dead at 2791). sinceEnd nil: no shift yet.
EscapeRules.RIFT_BLOCK = 2.0
function EscapeRules.RiftBlockedAfterShift(sinceEnd, escapeShift, hp, enemies, allies)
	if sinceEnd == nil or sinceEnd < 0 or sinceEnd > EscapeRules.RIFT_BLOCK then
		return false
	end
	return escapeShift == true or (hp or 1) < EscapeRules.ESCAPE_HP or (enemies or 0) > (allies or 0)
end

-- A dodge Phase Shift goes out in the same think, without waiting for the outpost hold (up to 0.2s), when the hit
-- is due sooner than PHASE_NOW_TTI (#36, game 067 t=3039: Impale tti=0.20, the wait let the stun land first).
-- Phase Shift's cast point is 0.01 (datafeed hero 13). tti nil (unknown): keep the wait.
EscapeRules.PHASE_NOW_TTI = 0.35
function EscapeRules.PhaseDodgeNow(tti)
	return tti ~= nil and tti < EscapeRules.PHASE_NOW_TTI
end
-- cast: the order went out before the hit time (or the time was unknown); late: after it.
function EscapeRules.PhaseDodgeResult(waited, tti)
	if tti == nil or waited < tti then
		return "cast"
	end
	return "late"
end

return EscapeRules
