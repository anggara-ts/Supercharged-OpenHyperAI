-- Shared bot system: pure rules for supports stacking a neutral camp on the minute (#229). No bot API calls, so
-- they are tested with plain numbers (tests/test_stack_rules.lua). The runtime part is bots/lib/systems/stack.lua.
--
-- How a stack works: neutral camps spawn new creeps at every full minute when nothing stands in the camp's spawn
-- box. A support hits a creep shortly before the minute and walks away; the creeps follow it out of the box, the
-- new creeps spawn at :00, and the old ones walk back: two sets in one camp.
-- Pull seconds: guides give :53 to :55 for most camps (bo3.gg "Mastering Dota 2 Stacking and Pulling Techniques
-- Guide", 2026; win.gg on 7.23b: small camps moved from :53 to :55). The game files have no stack timing and the
-- exact second per camp is UNVERIFIED for 7.42: the [SHy-STACK] pull / result lines log the order time, the hit
-- time and the distance so a game can tune PULL_SECOND.
local StackRules = {}

-- When the hit should land (second of the minute), by camp type. Unverified, see above.
StackRules.PULL_SECOND = { small = 55, medium = 54, large = 54, ancient = 53 }
StackRules.PULL_SECOND_DEFAULT = 54
-- No attack order before this second (a far melee hero would start walking in too early otherwise).
StackRules.EARLIEST_ORDER = 50
-- The hit must have landed by this second; later, the creeps are still in the box at :00. Leave anyway.
StackRules.LATEST_HIT = 57

-- When a support may start (game seconds): not in the first 3 minutes of the lane (maintainer brief: "laning
-- phase supports only after ~3:00"), and not past 20:00 (the team groups up by then).
StackRules.START_TIME = 3 * 60
StackRules.END_TIME = 20 * 60
-- Until 10:00 (the lane phase) a support stacks at most once per LANING_GAP seconds, so it does not leave its
-- core every minute. After 10:00 it may stack every minute. A guess: tune it after a game.
StackRules.LANE_PHASE_END = 10 * 60
StackRules.LANING_GAP = 120
-- The camp is picked between these seconds of the minute. The bot leaves so it arrives between ARRIVE_FROM and
-- WAIT_BY (not at :15 for a :54 pull: that is half a minute more out of lane). The walk time is the straight
-- distance at the bot's speed times PATH_FACTOR (paths through the jungle are longer than the straight line).
StackRules.PICK_FROM = 15
StackRules.PICK_UNTIL = 44
StackRules.ARRIVE_FROM = 39
StackRules.WAIT_BY = 47
StackRules.PATH_FACTOR = 1.5
-- Farthest camp considered (walking distance is longer than this straight line).
StackRules.MAX_DIST = 3500
-- The bot stops this far from the camp centre to wait (out of the spawn box: its size is not in the bot API,
-- so this is a guess), and the exit point is where it was EXIT_DIST from the camp on its way in.
StackRules.WAIT_DIST = 650
StackRules.EXIT_DIST = 1300
-- No stack with a visible enemy hero this close to the camp or the bot.
StackRules.ENEMY_RADIUS = 1500
StackRules.MIN_HP = 0.6
-- The camp is counted again at this second after the spawn.
StackRules.CHECK_SECOND = 5

-- Second of the minute (0 <= s < 60) and the minute.
function StackRules.Clock(dotaTime)
	local minute = math.floor(dotaTime / 60)
	return dotaTime - minute * 60, minute
end

-- Whether a pos 4/5 bot may start a stack now.
--   f.pos            position 1..5
--   f.time           DotaTime()
--   f.lastStackAt    DotaTime() of this bot's last stack start (nil: none)
--   f.hp             HP ratio
--   f.partnerThreat  the lane core this support plays with is under threat (lane phase only)
--   f.laneBehind     our side is behind on the bot's lane (push.lua's enemy-half flag)
--   f.groupUp        the team wants to push or defend (high push/defend desire, team fight)
--   f.enemyNear      a visible enemy hero within ENEMY_RADIUS of the bot
--   f.otherMode      a mode that must not be cut (retreat, fight, rune, ...)
--   f.wardWanted     the ward mode has a ward to plant
-- Returns ok, why.
function StackRules.CanStart(f)
	if f.pos ~= 4 and f.pos ~= 5 then
		return false, "not-support"
	end
	if f.time < StackRules.START_TIME then
		return false, "too-early"
	end
	if f.time >= StackRules.END_TIME then
		return false, "too-late"
	end
	local sec = StackRules.Clock(f.time)
	if sec < StackRules.PICK_FROM or sec >= StackRules.PICK_UNTIL then
		return false, "not-pick-window"
	end
	if
		f.time < StackRules.LANE_PHASE_END
		and f.lastStackAt ~= nil
		and f.time - f.lastStackAt < StackRules.LANING_GAP
	then
		return false, "laning-gap"
	end
	if (f.hp or 0) < StackRules.MIN_HP then
		return false, "low-hp"
	end
	if f.otherMode then
		return false, "other-mode"
	end
	if f.wardWanted then
		return false, "ward"
	end
	if f.groupUp then
		return false, "group-up"
	end
	if f.enemyNear then
		return false, "enemy-near"
	end
	if f.time < StackRules.LANE_PHASE_END and f.partnerThreat then
		return false, "partner-threat"
	end
	if f.laneBehind then
		return false, "lane-behind"
	end
	return true, "ok"
end

-- The lane core a support plays with (by position, as the laning mode assigns lanes): 5 with 1, 4 with 3.
function StackRules.PartnerPosition(pos)
	if pos == 5 then
		return 1
	elseif pos == 4 then
		return 3
	end
	return nil
end

-- The lane core is under threat when he was hit by a hero in the last seconds, is low, or faces two or more
-- enemy heroes (the support leaving makes it a 1v2).
--   hp, recentlyHit, enemiesNear (visible enemy heroes within 1600 of him), alive
function StackRules.PartnerThreat(alive, hp, recentlyHit, enemiesNear)
	if not alive then
		return false
	end
	return recentlyHit or (hp or 1) < 0.5 or (enemiesNear or 0) >= 2
end

-- Whether a camp can be stacked by this bot this minute.
--   c.ourSide        the camp is on our side by position (Site.CampSide: by == "position", side == ours)
--   c.type           small / medium / large / ancient
--   c.time           DotaTime()
--   c.dist           straight distance bot -> camp
--   c.speed          bot move speed
--   c.enemyNear      a visible enemy hero within ENEMY_RADIUS of the camp
--   c.dangerous      Site.IsCampDangerous (an enemy hero seen near it in the last 5s)
--   c.claimed        another bot stacks it this minute
-- Returns ok, why.
function StackRules.CampOk(c)
	if not c.ourSide then
		return false, "not-our-side"
	end
	if c.type == "ancient" and c.time < StackRules.LANE_PHASE_END then
		return false, "ancient-early"
	end
	if c.dist > StackRules.MAX_DIST then
		return false, "far"
	end
	local sec = StackRules.Clock(c.time)
	local eta = math.max(0, c.dist - StackRules.WAIT_DIST) / math.max(100, c.speed or 300) * StackRules.PATH_FACTOR
	if sec + eta > StackRules.WAIT_BY then
		return false, "late"
	end
	if sec + eta < StackRules.ARRIVE_FROM then
		return false, "early"
	end
	if c.claimed then
		return false, "claimed"
	end
	if c.enemyNear or c.dangerous then
		return false, "enemy"
	end
	return true, "ok"
end

-- The best camp: the nearest allowed one. camps: list of tables for CampOk plus anything else. isUnsafe(c), if
-- given, is asked only for camps that pass CampOk, nearest first, until one is safe (the enemy checks cost engine
-- calls, so they run for a few camps, not all 28). Returns the chosen table (or nil); each camp keeps its reason
-- in camp.why ("enemy" for one isUnsafe turned down). Nil also while a nearer camp only waits for its departure
-- time ("early"): the bot takes that one a few seconds later instead of walking off to a farther one now.
function StackRules.PickCamp(camps, isUnsafe)
	local allowed = {}
	local nearestEarly = math.huge
	for _, c in ipairs(camps or {}) do
		local ok, why = StackRules.CampOk(c)
		c.why = why
		if ok then
			allowed[#allowed + 1] = c
		elseif why == "early" and c.dist < nearestEarly then
			nearestEarly = c.dist
		end
	end
	table.sort(allowed, function(a, b)
		return a.dist < b.dist
	end)
	for _, c in ipairs(allowed) do
		if c.dist > nearestEarly then
			return nil
		end
		if isUnsafe ~= nil and isUnsafe(c) then
			c.why = "enemy"
		else
			return c
		end
	end
	return nil
end

-- Whether any camp only waits for its departure time (picked again a second later, no skip line for it).
function StackRules.AnyEarly(camps)
	for _, c in ipairs(camps or {}) do
		if c.why == "early" then
			return true
		end
	end
	return false
end

-- Second of the minute to give the attack order: the hit should land at the camp's pull second, so a hero who
-- must first walk (distance beyond its attack range) starts earlier. Never before EARLIEST_ORDER.
function StackRules.OrderSecond(campType, distToCreep, attackRange, speed)
	local pull = StackRules.PULL_SECOND[campType or ""] or StackRules.PULL_SECOND_DEFAULT
	local walk = math.max(0, (distToCreep or 0) - (attackRange or 150)) / math.max(100, speed or 300)
	return math.max(StackRules.EARLIEST_ORDER, pull - walk)
end

-- A point `dist` from the camp toward (fromX, fromY): where to stand or walk off to when no walked point is
-- known (the bot started inside EXIT_DIST). Returns x, y.
function StackRules.PointFromCamp(campX, campY, fromX, fromY, dist)
	local dx, dy = fromX - campX, fromY - campY
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then
		return campX + dist, campY
	end
	return campX + dx / len * dist, campY + dy / len * dist
end

-- The result of a stack: creeps counted at the pull and after the spawn (within the camp area). The count is
-- only read when the camp is visible at the check ("unknown" otherwise).
function StackRules.Result(before, after, visible)
	if not visible or after == nil then
		return "unknown"
	end
	if after > (before or 0) then
		return "yes"
	end
	return "no"
end

return StackRules
