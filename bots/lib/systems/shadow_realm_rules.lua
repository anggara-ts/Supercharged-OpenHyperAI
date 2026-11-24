-- Pure rules for Dark Willow's Shadow Realm (#48): plain numbers in, so tests/test_shadow_realm_rules.lua can check
-- them without the bot API. Datafeed hero 119 (7.42): duration 5s, untargetable; the next attack has
-- attack_range_bonus 600 and up to damage 120/200/280/360 bonus magic damage, the maximum after
-- max_damage_duration 3s; that attack ends the realm. Cooldown 21/19/17/15. (Re-read 2026-11-22 from
-- https://www.dota2.com/datafeed/herodata?language=english&hero_id=119: duration 5, fade_time 0.3,
-- attack_range_bonus 600, max_damage_duration 3, "becoming untargetable", "Her next attack ... will end Shadow Realm".)
local ShadowRealmRules = {}

ShadowRealmRules.DURATION = 5
ShadowRealmRules.MAX_DAMAGE_TIME = 3
-- 7.42 items_all.txt: item_tpscroll AbilityChannelTime 3.0.
ShadowRealmRules.TP_CHANNEL = 3.0

-- The bonus damage after `since` seconds in the realm. The tooltip says the damage "scales" with the time up to the
-- maximum at maxTime; linear from 0 is an assumption (no game file gives the curve).
function ShadowRealmRules.BonusDamage(maxDamage, since, maxTime)
	maxTime = maxTime or ShadowRealmRules.MAX_DAMAGE_TIME
	if maxTime <= 0 or since >= maxTime then
		return maxDamage
	end
	if since <= 0 then
		return 0
	end
	return maxDamage * since / maxTime
end

-- One think of the offensive hold. o: since (seconds in the realm), maxTime, dist (to the target), holdRange (her
-- attack range at the cast + the bonus), predictedDist (to where the target will be in 0.5s), canFollow (she is
-- faster than the target), killNow (the hit with the bonus so far kills it, or it dies to her allies anyway),
-- allyNeeds (an ally the target is hitting is low). Returns:
--   "attack", why: hit now (why = max | end | kill | ally | leave)
--   "close", nil:  step after the target (it is near the edge of the range or past it)
--   "hold", nil:   keep the range and wait for the damage to grow
function ShadowRealmRules.HoldStep(o)
	local maxTime = o.maxTime or ShadowRealmRules.MAX_DAMAGE_TIME
	if o.since >= maxTime then
		return "attack", "max"
	end
	-- Never let the realm run out without the hit (0.6s left: turn and attack).
	if o.since >= ShadowRealmRules.DURATION - 0.6 then
		return "attack", "end"
	end
	if o.killNow then
		return "attack", "kill"
	end
	if o.allyNeeds then
		return "attack", "ally"
	end
	if o.dist <= o.holdRange then
		-- About to walk out of the range and she can't keep up: hit while it is still in range.
		if o.predictedDist > o.holdRange - 25 and not o.canFollow then
			return "attack", "leave"
		end
		if o.dist > o.holdRange - 100 then
			return "close", nil
		end
		return "hold", nil
	end
	return "close", nil
end

-- A TP started now ends inside the realm (its time left covers the channel and a margin).
function ShadowRealmRules.TpFits(since, duration, channel, margin)
	duration = duration or ShadowRealmRules.DURATION
	channel = channel or ShadowRealmRules.TP_CHANNEL
	return duration - since >= channel + (margin or 0.3)
end

-- When to cast (#48, game 069: 18 deaths). Plain numbers in, so the tests can check them.
-- Attack realm: not under 60% HP and not outnumbered (more enemy heroes within 1200 than our heroes there, her
-- included). Game 069: 6 deaths came 2-11s after an attack realm, with the escape realm then on cooldown ([SHy-DEATH]
-- lines: 12:55 3 enemies and 1 ally near her; 14:01 cast at 45% HP; 44:59 4 enemies and 1 ally). The other three
-- (18:29, 30:05, 45:56) had no more enemies than allies near her 3.5s before the death: this gate does not cover them.
ShadowRealmRules.ATTACK_MIN_HP = 0.6
ShadowRealmRules.FIGHT_RADIUS = 1200
-- Returns nil (cast) or why not: "low-hp" | "outnumbered".
function ShadowRealmRules.AttackSkip(hp, enemies, ourHeroes)
	if hp < ShadowRealmRules.ATTACK_MIN_HP then
		return "low-hp"
	end
	if enemies > ourHeroes then
		return "outnumbered"
	end
	return nil
end

-- Escape realm. In retreat: HP under 80% or a hero hit her in the last 2s (game 069, 9:39 15:59 21:13: spent at
-- full HP with one enemy near, then on cooldown at the 16:12 death). Outside retreat: under 60% HP and hit by a
-- hero in the last 2s, in a mode that does not go on a hero (push, defend, farm, rune...: game 069 deaths at 9:09
-- rune, 24:43 push, 42:13 defend); the engaging modes keep their own attack and dodge rules. The old condition
-- (isRetreating or isRetreating and ...) reduced to "retreating". o: retreating, engaging, hp, hit.
-- Returns "retreat" | "hit" (cast), or nil and why not ("full-hp" while retreating, else nil).
ShadowRealmRules.RETREAT_MAX_HP = 0.8
ShadowRealmRules.HIT_ESCAPE_HP = 0.6
function ShadowRealmRules.Escape(o)
	if o.retreating then
		if o.hp < ShadowRealmRules.RETREAT_MAX_HP or o.hit then
			return "retreat"
		end
		return nil, "full-hp"
	end
	if not o.engaging and o.hp < ShadowRealmRules.HIT_ESCAPE_HP and o.hit then
		return "hit"
	end
	return nil
end

-- The release reasons of one realm, both kept (game 069, 44:59: "release=died" lost the first one).
function ShadowRealmRules.JoinRelease(previous, reason)
	if previous == nil or previous == reason then
		return reason
	end
	return previous .. "+" .. reason
end

-- The realm modifier dropped while nothing in our code released it and before it could run out (game 069 5:03,
-- 9:40, 45:55: ended after 0.67-1.17s with release=-). Margin: the end check runs 0.2s after the duration.
function ShadowRealmRules.EarlyDrop(released, since, duration)
	return released == nil and since < (duration or ShadowRealmRules.DURATION) - 0.3
end

-- The cast order (#203, game 079 t=356: the cast line and order 14 times in one second, then release=stale; game
-- 077 t=1345: 41 orders over 1.3s). Shadow Realm has cast point 0 (datafeed hero 119, re-read 2026-11-24), so a cast
-- that went out shows the cooldown (or the modifier) by the next think. One order; if it has not taken after
-- RESEND_AFTER, one more, up to MAX_ORDERS; give up at CAST_GIVE_UP (release=no-cast with what blocked it).
-- since: seconds since the first order; sinceOrder: since the last; orders: orders sent so far.
-- Returns "wait" | "resend" | "give-up".
ShadowRealmRules.RESEND_AFTER = 0.3
ShadowRealmRules.MAX_ORDERS = 3
ShadowRealmRules.CAST_GIVE_UP = 1.0
function ShadowRealmRules.CastStep(since, sinceOrder, orders)
	if since >= ShadowRealmRules.CAST_GIVE_UP then
		return "give-up"
	end
	if sinceOrder >= ShadowRealmRules.RESEND_AFTER and orders < ShadowRealmRules.MAX_ORDERS then
		return "resend"
	end
	return "wait"
end

return ShadowRealmRules
