-- Pure rules for Phantom Assassin's Blur (#48): plain values in, so Tests/test_pa_blur_rules.lua can check them
-- without the bot API. Valve datafeed hero_id=44 (7.42), phantom_assassin_blur: disjoints incoming projectiles,
-- active_movespeed_bonus 12%, she can't be seen unless within radius 600 of enemy heroes or towers, fade_duration
-- 0.8, break_on_attack 1, duration 20, AbilityCastPoint 0.3, AbilityCooldown 45, AbilityManaCost 40.
local PaBlurRules = {}

-- Datafeed: radius 600 (she shows up within this range of enemy heroes and towers).
PaBlurRules.REVEAL_RADIUS = 600
-- Chase-approach: a target closer than this is reached in a few steps (and Phantom Strike, datafeed cast range
-- 650/750/850/950, covers most of it); farther than APPROACH_MAX is no longer a chase.
PaBlurRules.APPROACH_MIN = 900
PaBlurRules.APPROACH_MAX = 2500
-- "Lone enemy": no other enemy hero within this range of the target.
PaBlurRules.LONE_RADIUS = 1200
-- Keep Blur for a later escape when she is this low.
PaBlurRules.APPROACH_MIN_HP = 0.4
-- Enemy-area hide: no enemy hero within AREA_CLOSE (the 600 reveal radius plus a step) and at most AREA_MAX_SEEN
-- within 1600.
PaBlurRules.AREA_CLOSE = 900
PaBlurRules.AREA_MAX_SEEN = 2

-- Escape. o: retreating, hitByHero (a hero hit her in the last 3.1s), level, hp (0..1), heroesNear (enemy heroes
-- within 740), towerNear (an enemy tower within 878). Returns ok, why. Enemy heroes or a tower near no longer stop
-- the cast (maintainer, game 069): the disjoint, the 12% speed and the 0.8s fade still break the chase.
-- why = clear | hero-near | tower-near | hero-tower-near.
function PaBlurRules.Escape(o)
	if not o.retreating or not o.hitByHero then
		return false, nil
	end
	if o.level < 6 and o.hp > 0.3 then
		return false, nil
	end
	local heroNear = (o.heroesNear or 0) > 0
	if heroNear and o.towerNear then
		return true, "hero-tower-near"
	elseif heroNear then
		return true, "hero-near"
	elseif o.towerNear then
		return true, "tower-near"
	end
	return true, "clear"
end

-- Chase-approach on a lone enemy hero (maintainer, game 069: "used only when hunting solo enemy"). o: hunting (going
-- on someone with a real enemy hero as target), dist (to it), othersNearTarget (other enemy heroes seen within
-- LONE_RADIUS of it in the last 5s), towerNearTarget, attackingOther (her attack target is something else: Blur
-- breaks on attack), hp (0..1), strikeReach (Phantom Strike cast range when it is ready, else 0), manaAfter (mana
-- left after Blur), strikeCost (Phantom Strike mana). Returns ok, why (why = the reason it is skipped, or
-- "approach").
function PaBlurRules.Approach(o)
	if not o.hunting then
		return false, "not-hunting"
	end
	if o.dist < PaBlurRules.APPROACH_MIN then
		return false, "close"
	end
	if o.dist > PaBlurRules.APPROACH_MAX then
		return false, "far"
	end
	if (o.othersNearTarget or 0) > 0 then
		return false, "not-alone"
	end
	if o.towerNearTarget then
		return false, "tower"
	end
	if o.attackingOther then
		return false, "attacking"
	end
	if o.hp < PaBlurRules.APPROACH_MIN_HP then
		return false, "low-hp"
	end
	-- Phantom Strike reaches it now: the jump closes the gap at once.
	if (o.strikeReach or 0) >= o.dist then
		return false, "strike"
	end
	-- Keep the mana for the jump when she arrives.
	if (o.manaAfter or 0) < (o.strikeCost or 0) then
		return false, "mana"
	end
	return true, "approach"
end

-- Enemy-area hide (level 7+, in the enemy half). o: heroesClose (enemy heroes within AREA_CLOSE), heroesSeen
-- (within 1600), towers (enemy towers within 1600). The old rule read the same 1600 list twice
-- ("== 0 and <= 2"), so the "<= 2" part did nothing.
function PaBlurRules.AreaHide(o)
	return (o.heroesClose or 0) == 0 and (o.heroesSeen or 0) <= PaBlurRules.AREA_MAX_SEEN and (o.towers or 0) == 0
end

-- The dodge result 1s after a blur-disjoint decision. w: at (decision time), stunned (a stun was seen on her in the
-- window), cast (Blur went on cooldown). now: game time. Returns nil while the window is open, else the stunned
-- field: yes | no | unknown (the check came more than 3s late, e.g. she was dead or not thinking).
PaBlurRules.RESULT_AFTER = 1.0
function PaBlurRules.DodgeResult(w, now)
	local after = now - w.at
	if after < PaBlurRules.RESULT_AFTER then
		return nil
	end
	if w.stunned then
		return "yes"
	end
	if after > 3 then
		return "unknown"
	end
	return "no"
end

return PaBlurRules
