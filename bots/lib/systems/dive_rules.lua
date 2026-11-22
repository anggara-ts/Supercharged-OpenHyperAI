-- Shared bot system: pure tower-dive rules (no bot API calls), so they can be tested with real numbers.
local DiveRules = {}

-- After the early game, should a bot that an enemy T1/T2 is shooting stop its chase (mode_retreat_generic.lua,
-- Retreat.ShouldRun)? The early-game anti-dive (#83) covers the first 12 minutes; after that nothing pulled a
-- chaser out of tower range, and most heroes run Valve's attack mode, which has no tower check (#12: game 048,
-- 17:30, Skywrath took Dire's mid T1 while chasing Sniper; game 037, 20:30, Radiant fought behind Dire's bottom
-- T1 - whether the tower was on them there is not in that game's log).
--   s.towerOnBot   the tower is attacking this bot or hit it in the last 1.5s
--   s.entering     the tower is not on the bot yet, but its hero target stands inside the tower's range and the bot
--                  is close enough to follow it in. Game 063: 6 of 23 chase-stops died within 5s, all in retreat:
--                  the stop came once the tower already shot, with 2-3 heroes on the bot.
--   s.outerTower   the tower is a T1 or T2 (fights at a T3/T4 are base fights: no decision there)
--   s.pushing      the bot is in a push mode (PushThink steps out of tower aggro itself)
--   s.hasTarget    the bot has a hero target it can attack
--   s.teamDamage   damage the bot and the allies near can do to that target in the window (2 tower shots)
--   s.targetHealth the target's HP
--   s.committed    the target is in reach and disabled or under 40% HP (IsCommittedKill)
--   s.botHealth    the bot's HP
--   s.shotDamage   one tower shot on this bot, after armor
--   s.enemyDamage  what the visible enemy heroes near the bot can do to it in the same window. Game 063, 23:44-23:52:
--                  Earth Spirit was stopped twice at 85-100% HP with the tower doing 60-80 a shot, and three heroes
--                  killed him 2s after the second stop.
-- The chase stays only when the target dies within the tower's next 2 shots (or is a committed kill) and the bot
-- survives those 2 shots plus one more to walk out, plus the enemy heroes' damage. Returns "stay" or "leave" and
-- the reason, or nil (no decision: the tower is not on the bot and it is not entering after a target, the tower is
-- a T3/T4, or a push mode handles it).
function DiveRules.TowerChaseDecision(s)
	if not s.outerTower or s.pushing then
		return nil
	end
	-- Entering needs a hero target inside the tower's range: a bot walking past a T1/T2 is no chase.
	if not s.towerOnBot and not (s.entering and s.hasTarget) then
		return nil
	end
	if s.botHealth <= s.shotDamage * 3 + (s.enemyDamage or 0) then
		return "leave", "low-hp"
	end
	if not s.hasTarget then
		return "leave", "no-target"
	end
	if s.teamDamage >= s.targetHealth then
		return "stay", "killable"
	end
	if s.committed then
		return "stay", "committed"
	end
	return "leave", "not-killable"
end

-- Before the tower edge: a bot going on someone (attack / roam / team roam / defend ally) toward an enemy T2/T3,
-- up to the tower's range + APPROACH_MARGIN away and not in range yet, while what the visible enemy heroes near can
-- do to it in the window plus 3 tower shots is its HP or more ("dead on paper"). Game 065: 9 of 30 chase-stop /
-- tower-entry-stop lines were followed by the bot's death within 5s, all why=low-hp at the tower edge with 1-4 enemy
-- heroes whose damage was above the bot's HP (e.g. Zeus t=2150 tower-entry-stop hp=396 enemyDmg=5905 enemies=4 at
-- Dire's top T2, dead the same second): by the edge it was too late to walk out.
--   s.outerTower   the tower is a T2 or T3 (the caller's check here; the edge rule's is T1/T2)
--   s.pushing      as in TowerChaseDecision
--   s.approaching  the bot is outside the tower's range, within range + APPROACH_MARGIN, going on someone, and its
--                  hero target is nearer the tower than it is, or it is moving toward the tower
--   s.botHealth, s.shotDamage, s.enemyDamage   as in TowerChaseDecision
-- Returns "leave", "low-hp", or nil (no decision here: the edge rule decides once the bot gets there).
DiveRules.APPROACH_MARGIN = 600
function DiveRules.TowerApproachDecision(s)
	if not s.outerTower or s.pushing or not s.approaching then
		return nil
	end
	if s.botHealth <= s.shotDamage * 3 + (s.enemyDamage or 0) then
		return "leave", "low-hp"
	end
	return nil
end

-- Does a chase after a target inside the tower's range take the bot into it? Yes when the bot already stands inside,
-- or when even the spot on the far side of the target (target distance + the bot's attack range) is inside: a ranged
-- bot that can hit the target from outside the range is not entering. Distances are to the tower.
function DiveRules.MustEnterTowerRange(botDist, targetDist, attackRange, towerRange)
	return botDist <= towerRange or targetDist + attackRange <= towerRange
end

-- After a stop the bot keeps out of that tower for HOLD_SECONDS. Game 063, 23:44: Earth Spirit's first stop ran him
-- for the fixed 2.88s, then team roam and farm walked him back past the tower; he was stopped again at 23:50 and died
-- at 23:52. The hold zone is the tower's range + HOLD_MARGIN; once the bot is inside it, it walks out to
-- HOLD_MARGIN + HOLD_RELEASE so the next mode does not flip with retreat right at the edge.
DiveRules.HOLD_SECONDS = 9
DiveRules.HOLD_MARGIN = 200
DiveRules.HOLD_RELEASE = 150

-- dist: the bot's distance to the tower; range: the tower's attack range; inside: the bot was in the zone at the
-- last check; margin: the zone beyond the range (HOLD_MARGIN, or APPROACH_MARGIN after a stop before the edge).
-- Returns whether to run out now, and the new "inside" state.
function DiveRules.TowerHoldRun(dist, range, inside, margin)
	margin = margin or DiveRules.HOLD_MARGIN
	if dist < range + margin then
		return true, true
	end
	if inside and dist < range + margin + DiveRules.HOLD_RELEASE then
		return true, true
	end
	return false, false
end

-- What the hold does at this check. A push pauses it instead of ending it: PushThink steps out of tower aggro itself,
-- and retreat must not pull a bot out of a team siege. Game 064, 12:24-12:31: Alchemist was stopped at Dire's mid T1
-- (tower-entry-stop), one push-mode think during the hold cleared it, and attack mode walked him back under the
-- tower 7s later (chase-stop). The 9s clock stops while paused (TowerHoldPausedUntil); the hold resumes when the
-- push ends.
--   now, untilTime   game time and the hold's end; towerValid: the tower still stands
--   pushing          the bot is in a push mode now; paused: the last check paused the hold
-- A team siege of the hold tower ends the hold ("siege"): the bot pushes the hold tower's lane, 2+ allied heroes
-- stand at that tower, and the stop was why=no-target (no hero chase: the tower simply shot it during the siege).
-- Game 065, t=941-948: Dark Willow was stopped (no-target) at Radiant's top T1 while her team pushed it; pause and
-- resume alternated with push 0.90 / attack 0.65 / retreat 1.10 and the 9s ran out with her inside the zone. A chase
-- stop (low-hp, not-killable) keeps the pause: game 064, Alchemist was stopped chasing Tiny at the mid T1 his team
-- was pushing, and attack mode walked him back under it once the hold was gone.
--   pushLaneTower    the hold tower is in the lane the bot pushes; alliesAtTower: other allied heroes at it
--   why              the stop's reason
-- Returns "expire" (drop the hold), "siege" (drop it: team siege), "pause", "resume" (first check after a pause)
-- or "keep".
DiveRules.SIEGE_ALLIES = 2
function DiveRules.TowerHoldState(now, untilTime, towerValid, pushing, paused, pushLaneTower, alliesAtTower, why)
	if now > untilTime or not towerValid then
		return "expire"
	end
	if pushing and pushLaneTower and (alliesAtTower or 0) >= DiveRules.SIEGE_ALLIES and why == "no-target" then
		return "siege"
	end
	if pushing then
		return "pause"
	end
	if paused then
		return "resume"
	end
	return "keep"
end

-- The hold's clock stops during a pause. Game 068, t=924-932: Clinkz's hold was paused by a push at left=4.0 and
-- resumed at t=928 with left=0.1 (the clock had run on), 753 from Radiant's mid T1 (zone 900); it ran out at t=929
-- with him inside the zone and attack mode walked him back in (tower-entry-stop t=932, attack/retreat/push flips
-- t=922-936). Undying the same at t=928-933 (resume left=1.3). At the pause the caller stores the time left
-- (TowerHoldPauseLeft: at least HOLD_RESUME_MIN, once per hold - floored: the floor was used; a push/attack flip every
-- second would otherwise keep adding it); on every paused check the end moves to now + that time
-- (TowerHoldPausedUntil), never later than HOLD_MAX_AGE after the stop (startTime): a frozen clock alone would keep a
-- stale hold through a long push.
DiveRules.HOLD_RESUME_MIN = 2
-- 20s: game 069, 48 holds, age at the end median 9.2s, p90 13.4s, longest 18.4s (the first cap, 30s, never bound).
DiveRules.HOLD_MAX_AGE = 20
-- At the pause: the time the hold keeps (left, floored once per hold). Returns remaining and the new floored flag.
function DiveRules.TowerHoldPauseLeft(left, floored)
	left = math.max(left or 0, 0)
	if left < DiveRules.HOLD_RESUME_MIN and not floored then
		return DiveRules.HOLD_RESUME_MIN, true
	end
	return left, floored
end
-- On every paused check: the new end.
function DiveRules.TowerHoldPausedUntil(now, remaining, startTime)
	local untilTime = now + (remaining or 0)
	if startTime ~= nil then
		untilTime = math.min(untilTime, startTime + DiveRules.HOLD_MAX_AGE)
	end
	return untilTime
end

-- Why a hold ends at this check, or nil (it goes on). In order:
--   s.died        the bot died since the stop. Game 068: Puck's hold (stopped t=809, dead t=812) was cleared only at
--                 t=848, 4s after her respawn, with left=-30.3 and why=invalid.
--   s.invalidFor  seconds the tower handle has not read valid (not null, seen and alive), or nil
--   s.fell        the handle is null or reads dead: the tower fell. After HOLD_INVALID_GRACE: "invalid".
--   s.age         seconds since the stop: past HOLD_MAX_AGE the hold ends whatever else ("cap")
--   s.expired     the 9s (paused time not counted) are over ...
--   s.outOfZone   ... and the bot is out of the zone by HOLD_EXPIRE_OUT: "expire". Game 069: 5 holds ran out with the
--                 bot still inside the zone (Alchemist t=759 dist=848 of 900, Zeus t=761 dist=696, dead at t=763; Axe
--                 t=842, Undying t=968, Alchemist t=919 1234 of 1300) and the next mode walked it back under the tower.
--   s.insideZone  the bot is inside the hold zone (+ release)
-- An unseen tower that still stands (out of vision: game 068, 5 of 7 why=invalid clears named a tower that stood for
-- minutes, the bot 1860-3480 away) ends the hold only once the bot is outside the zone ("unseen"); inside it the hold
-- goes on at the stored spot (a tower can be out of sight at night with the bot near it).
DiveRules.HOLD_INVALID_GRACE = 2
DiveRules.HOLD_EXPIRE_OUT = 100
function DiveRules.TowerHoldEnd(s)
	if s.died then
		return "death"
	end
	local invalidLong = s.invalidFor ~= nil and s.invalidFor > DiveRules.HOLD_INVALID_GRACE
	if invalidLong and s.fell then
		return "invalid"
	end
	if s.age ~= nil and s.age > DiveRules.HOLD_MAX_AGE then
		return "cap"
	end
	if s.expired and s.outOfZone then
		return "expire"
	end
	if invalidLong and not s.insideZone then
		return "unseen"
	end
	return nil
end

-- The chase into the enemy high ground while their T3 stands (game 069, 22:48-23:11: Alchemist and Axe chased
-- Undying past Dire's mid T2 up to the T3 at 91-100% HP while the rest of the team went to Roshan; 4 Dire heroes were
-- alive and near, both died under the T3 at t=1388-1391; no stop fired, the approach rule checks only HP). Before the
-- T3's range, a bot going on someone stops when the enemies who can respond outnumber our heroes on the chase, unless
-- an advantage window is open (2+ enemy heroes dead) or the target dies to our damage in the window first. Game 069,
-- 33:30-33:42 must still go: after Dark Willow and Io died, Alchemist, Axe and Puck chased past the bottom T3 into
-- the 3 Dire heroes left and killed Undying (19%) and Nyx (26%).
--   s.highGround   the tower is an enemy T3 that stands (invulnerable counts: the T2 of its lane still stands)
--   s.pushing      in a push mode (no decision)
--   s.approaching  outside the T3's range, within range + APPROACH_MARGIN, going on someone toward it
--   s.responders   enemy heroes alive and not seen far away in the last 5s (unknown ones count)
--   s.chasers      our heroes on the chase: the bot and the allied heroes near it
--   s.enemiesDead  enemy heroes dead now
--   s.teamDamage, s.targetHealth   as in TowerChaseDecision (0 targetHealth: no hero target)
-- Returns "leave", "outnumbered", or nil.
DiveRules.ADVANTAGE_DEAD = 2
function DiveRules.HighGroundChaseDecision(s)
	if not s.highGround or s.pushing or not s.approaching then
		return nil
	end
	if (s.responders or 0) <= (s.chasers or 1) then
		return nil
	end
	if (s.enemiesDead or 0) >= DiveRules.ADVANTAGE_DEAD then
		return nil
	end
	if (s.targetHealth or 0) > 0 and (s.teamDamage or 0) >= s.targetHealth then
		return nil
	end
	return "leave", "outnumbered"
end

-- The walk home from behind an enemy tower. Game 072, 19:48-19:56: after Radiant's dive past Dire's mid T2 and the
-- kill, Puck walked home down the lane through the T2's range (chase-stop why=no-target inside=8.2 inMode=9), lost
-- HP from 0.70 to 0.43 and died at t=1205. A bot farther from home than a standing enemy tower, whose straight way
-- home crosses that tower's range + DETOUR_RING_MARGIN, and that is heading home, takes a path round the tower
-- (mode_outpost_generic.lua drives it; bots/lib/systems/home_detour.lua).
DiveRules.DETOUR_RING_MARGIN = 150
DiveRules.DETOUR_BEHIND_MARGIN = 200
DiveRules.DETOUR_PAST_MARGIN = 300
DiveRules.DETOUR_MAX_SECONDS = 15

-- Does the segment A-B pass within r of C?
function DiveRules.SegmentNearPoint(ax, ay, bx, by, cx, cy, r)
	local sx, sy = bx - ax, by - ay
	local len2 = sx * sx + sy * sy
	local k = len2 > 0 and math.max(0, math.min(1, ((cx - ax) * sx + (cy - ay) * sy) / len2)) or 0
	local dx, dy = ax + sx * k - cx, ay + sy * k - cy
	return dx * dx + dy * dy < r * r
end

-- s.botHome / s.towerHome: the bot's and the tower's distance to home (our fountain); s.crosses: the straight line
-- bot -> home passes within the tower's range + DETOUR_RING_MARGIN. Behind = farther from home than the tower by
-- DETOUR_BEHIND_MARGIN, with the way home through its range.
function DiveRules.BehindTower(s)
	return s.crosses == true and s.botHome > s.towerHome + DiveRules.DETOUR_BEHIND_MARGIN
end

-- Start a detour: behind a standing enemy tower, heading home (retreat mode, or moving toward home), not going on
-- someone (a chase toward our side is not a walk home), no fight on (no enemy hero hit it in the last 1s), and no
-- detour ended in the last few seconds (s.cooldown).
function DiveRules.HomeDetourStart(s)
	return DiveRules.BehindTower(s) and s.headingHome == true and not s.chasing and not s.fight and not s.cooldown
end

-- Why a running detour ends, or nil: "dead", "fight" (an enemy hero hit the bot: the fight modes take it), "past"
-- (nearer home than the tower by DETOUR_PAST_MARGIN, or the straight way home no longer crosses the range),
-- "done" (the last waypoint reached), "timeout" (DETOUR_MAX_SECONDS).
function DiveRules.HomeDetourStop(s)
	if s.dead then
		return "dead"
	end
	if s.fight then
		return "fight"
	end
	if s.botHome < s.towerHome - DiveRules.DETOUR_PAST_MARGIN or not s.crosses then
		return "past"
	end
	if s.done then
		return "done"
	end
	if (s.age or 0) > DiveRules.DETOUR_MAX_SECONDS then
		return "timeout"
	end
	return nil
end

-- Does a path (a list of {x=, y=} points from the bot's spot sx, sy) keep out of the ring round tx, ty? A path that
-- cuts through it means the avoidance zones were not used: walk it not.
function DiveRules.PathAvoids(sx, sy, points, tx, ty, ring)
	local ax, ay = sx, sy
	for _, p in ipairs(points or {}) do
		if DiveRules.SegmentNearPoint(ax, ay, p.x, p.y, tx, ty, ring) then
			return false
		end
		ax, ay = p.x, p.y
	end
	return true
end

return DiveRules
