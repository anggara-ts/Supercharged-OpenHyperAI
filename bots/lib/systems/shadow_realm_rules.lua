-- Pure rules for Dark Willow's Shadow Realm (#48): plain numbers in, so tests/test_shadow_realm_rules.lua can check
-- them without the bot API. Datafeed hero 119 (7.42): duration 5s, untargetable; the next attack has
-- attack_range_bonus 600 and up to damage 120/200/280/360 bonus magic damage, the maximum after
-- max_damage_duration 3s; that attack ends the realm. Cooldown 21/19/17/15. (Re-read 2026-11-22 from
-- https://www.dota2.com/datafeed/herodata?language=english&hero_id=119: duration 5, fade_time 0.3,
-- attack_range_bonus 600, max_damage_duration 3, "becoming untargetable", "Her next attack ... will end Shadow Realm".)
-- A net or stun area still hits her in the realm. Game 092: Bushwhack netted her while the realm was up
-- and her HP fell during it. The datafeed notes say she disjoints projectiles, is phased, and spells that
-- need vision cannot affect her. They do not say a point-targeted area misses. A realm is not safe against
-- a net or stun area. No rule here treats it as safe.
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

-- Cornered realm (#203, game 083 47:06: Puck jaunted to her and rifted, Templar Assassin blinked in, Spirit Breaker
-- charged her; at hp 0.59 in a defend mode no rule cast the ready realm, and she died at 47:07). At any HP, before
-- the silence or stun lands. o: enemiesNear (real enemy heroes within CORNER_RADIUS), alliesNear (our other heroes
-- within CORNER_ALLY_RADIUS), charge (distance to a charging Spirit Breaker while the charge is on her, or nil),
-- jump (an enemy hero jumped next to her just now, ShadowRealmRules.Jump), enemies / ourHeroes (within FIGHT_RADIUS,
-- her included in ourHeroes). Returns "charge" | "crowd" | "jump", or nil.
-- Charge: Charge of Darkness movement_speed bonus 275/325/375/425, windup 1.5s, stun 1.3-2.2s (datafeed hero 71,
-- read 2026-11-26), so from 1200 it lands in about 1.5-2s, after the 0.3s fade and inside the 5s realm.
-- Thresholds 900 / 1200 / 3 enemies: the [SHy-CORNERED] counts (ability_context.lua), judgement values.
ShadowRealmRules.CORNER_RADIUS = 900
ShadowRealmRules.CORNER_ALLY_RADIUS = 1200
ShadowRealmRules.CORNER_ENEMIES = 3
ShadowRealmRules.CHARGE_NEAR = 1200
function ShadowRealmRules.Cornered(o)
	if o.charge ~= nil and o.charge <= ShadowRealmRules.CHARGE_NEAR then
		return "charge"
	end
	if o.enemiesNear >= ShadowRealmRules.CORNER_ENEMIES and o.alliesNear == 0 then
		return "crowd"
	end
	-- A jump-in (Blink Dagger, Puck's Ethereal Jaunt, a leap) with a second enemy hero near and more of theirs than of
	-- ours (the AttackSkip "outnumbered"): an initiation on her, not a lone harass the hit rule handles, and not an
	-- even fight, where a 5s escape walk would take her out of it.
	if o.jump and o.enemies >= 2 and o.enemies > o.ourHeroes then
		return "jump"
	end
	return nil
end

-- An enemy hero that jumped next to her (no modifier shows a blink or a jaunt): within JUMP_NEAR now, and either
-- seen JUMP_CLOSED or more farther away within the last JUMP_WINDOW, or not seen at all in that window (blinked in
-- out of the fog). prevDist / prevAgo: the last sighting (nil: none); trackedAgo: since her own last sample, so a
-- gap in her think (death, a long stun) does not read every enemy as new. enemyMoved: how far HE moved since that
-- sample (his position now against his last position; nil: not measured). Returns "jump" | "appear" | nil.
-- An "appear" counts only after ShadowRealmRules.AppearIsJump (his last-seen spot, or a Blink or jump spell).
-- A tracked "jump" needs his own move of JUMP_CLOSED or more (#203, game 092 t=1008: her Blink closed the distance
-- from 714 to 121 and the line said via=tracked, while he had not moved).
ShadowRealmRules.JUMP_NEAR = 450
ShadowRealmRules.JUMP_CLOSED = 500
ShadowRealmRules.JUMP_WINDOW = 0.6
function ShadowRealmRules.Jump(prevDist, prevAgo, nowDist, trackedAgo, enemyMoved)
	if nowDist > ShadowRealmRules.JUMP_NEAR or trackedAgo == nil or trackedAgo > ShadowRealmRules.JUMP_WINDOW then
		return nil
	end
	if prevDist == nil or prevAgo == nil or prevAgo > ShadowRealmRules.JUMP_WINDOW then
		return "appear"
	end
	if prevDist - nowDist >= ShadowRealmRules.JUMP_CLOSED then
		if enemyMoved ~= nil and enemyMoved < ShadowRealmRules.JUMP_CLOSED then
			return nil
		end
		return "jump"
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

-- An "appear" (ShadowRealmRules.Jump: within JUMP_NEAR with no sighting of his unit in the window) is a jump-in only
-- when it can't have been a walk out of the fog (#203, game 087 t=1108: Brewmaster walked in on lane-defend move
-- orders, kind=appear from=-1, no Blink until 31:32, and the realm went out at full HP in a 2v1). o: seenDist (her
-- distance now to his last-seen spot, GetHeroLastSeenInfo sampled before this sighting; nil: never seen), seenAgo
-- (seconds since that sighting), nowDist, speed (his move speed), jumper (he has a Blink item or a jump spell).
-- The landing (#203, game 089 t=1015, 2313, 2347: Axe with a Blink Dagger showed up 107-144 from her and was read
-- as a walk, seen == to with ago 0.0-0.1): the team's last-seen spot can already be where he landed, sampled a moment
-- before her own sighting. seenSpotAge (seconds since he was first seen at that spot) and seenOffset (that spot to
-- where he is now): a spot first seen under LANDING_AGE ago within LANDING_RADIUS of him is the landing, not the
-- approach (ShadowRealmRules.IsLanding), and the sighting before it is used: prevDist / prevAgo (nil: none).
-- A spot held longer is a reappear in place (game 091 t=757: Puck came out of a 1s Phase Shift where he stood,
-- `phase-probe moved=0`, jump-skip seen=365 to=365): that sample stays, and it reads as a walk.
-- castAgo: seconds since the team saw him cast a jump (a Blink item or a jump spell, enemy_spell_tracker.lua's cast
-- callback; nil: none seen). One within JUMP_CAST_RECENT counts on its own.
-- Proven by the last-seen spot: JUMP_CLOSED (500) or more closer, and more than he could walk in that time + 100.
-- Else a hero with a jump counts, unless he was seen within APPEAR_RECENT less than 500 farther (that was a walk).
-- Returns true, "cast" | "last-seen" | "jumper", or false, "walked" | "unseen" | "near" | "walk-reach"; then the
-- sighting it read (distance, age; nil: none) and whether the newest one was the landing.
ShadowRealmRules.APPEAR_WALK_MARGIN = 100
ShadowRealmRules.APPEAR_RECENT = 2.0
-- Judgement values: a Blink lands at once, and her think samples the last-seen spot every 0.2s, so a landing spot is
-- at most about 0.2-0.3s old when she sees him; 200 covers his walk in that time (550 move speed * 0.3 = 165).
ShadowRealmRules.LANDING_AGE = 0.5
ShadowRealmRules.LANDING_RADIUS = 200
-- Blink Dagger and the jump spells have cast point 0 or near it (judgement), so the cast and the landing come within a
-- second of each other.
ShadowRealmRules.JUMP_CAST_RECENT = 1.0
function ShadowRealmRules.IsLanding(spotAge, offset)
	return spotAge ~= nil
		and offset ~= nil
		and spotAge < ShadowRealmRules.LANDING_AGE
		and offset <= ShadowRealmRules.LANDING_RADIUS
end
function ShadowRealmRules.AppearIsJump(o)
	local seenDist, seenAgo = o.seenDist, o.seenAgo
	local landing = seenDist ~= nil and ShadowRealmRules.IsLanding(o.seenSpotAge, o.seenOffset)
	if landing then
		seenDist, seenAgo = o.prevDist, o.prevAgo
	end
	if seenDist == nil or seenAgo == nil then
		seenDist, seenAgo = nil, nil
	end
	if o.castAgo ~= nil and o.castAgo >= 0 and o.castAgo <= ShadowRealmRules.JUMP_CAST_RECENT then
		return true, "cast", seenDist, seenAgo, landing
	end
	local closed = nil
	if seenDist ~= nil then
		closed = seenDist - o.nowDist
	end
	if
		closed ~= nil
		and closed >= ShadowRealmRules.JUMP_CLOSED
		and closed > (o.speed or 0) * seenAgo + ShadowRealmRules.APPEAR_WALK_MARGIN
	then
		return true, "last-seen", seenDist, seenAgo, landing
	end
	if o.jumper then
		if closed ~= nil and seenAgo <= ShadowRealmRules.APPEAR_RECENT and closed < ShadowRealmRules.JUMP_CLOSED then
			return false, "walked", seenDist, seenAgo, landing
		end
		return true, "jumper", seenDist, seenAgo, landing
	end
	if closed == nil then
		return false, "unseen", seenDist, seenAgo, landing
	end
	if closed < ShadowRealmRules.JUMP_CLOSED then
		return false, "near", seenDist, seenAgo, landing
	end
	return false, "walk-reach", seenDist, seenAgo, landing
end

-- An enemy summon for the realm TP gate (#203, game 087 28:29-28:37: a storm brewling's Cyclone and an earth
-- brewling's Hurl Boulder on her, the realm TP read skip-safe, and she died with no enemy hero near): a unit of the
-- enemy team that is not a lane creep (npc_dota_creep_*, the *_siege* catapults) or a ward. A neutral on their team
-- is a dominated one, so it counts. name: the unit name; enemyTeam: the unit is on the other team.
function ShadowRealmRules.IsSummon(name, enemyTeam)
	if not enemyTeam or name == nil or name == "" then
		return false
	end
	if string.find(name, "npc_dota_creep_", 1, true) or string.find(name, "_siege", 1, true) then
		return false
	end
	if string.find(name, "_wards", 1, true) then
		return false
	end
	return true
end

-- The realm modifier dropped while nothing in our code released it and before it could run out (game 069 5:03,
-- 9:40, 45:55: ended after 0.67-1.17s with release=-). Margin: the end check runs 0.2s after the duration.
function ShadowRealmRules.EarlyDrop(released, since, duration)
	return released == nil and since < (duration or ShadowRealmRules.DURATION) - 0.3
end

-- The realm's time is up (since past the duration) and she still reads as alive. Hold this one think before
-- printing release=- (#203, game 092 t=2074: held=5.23 release=- on the tick she died; the death count moves
-- after the think, and her think does not run while dead, so the next think says release=died). An earlier
-- reason (the hit, a mode change) or an early modifier drop ends now. alreadyHeld: this wait already happened.
-- Returns true to keep the record open.
function ShadowRealmRules.HoldRanOut(released, alreadyHeld, ranOut, earlyDrop)
	if earlyDrop or not ranOut or released ~= nil or alreadyHeld then
		return false
	end
	return true
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
