-- Shared bot system: pure push / Roshan team rules (no bot API calls), so they can be tested with real numbers.
-- Used by bots/lib/systems/push.lua, bots/lib/systems/kill_window.lua and mode_roshan_generic.lua (#12).
local PushRules = {}

-- Respawn seconds of a dead enemy at `level`, from what our own heroes' deaths showed (learned[level] = seconds,
-- the same rules hold for both teams). Enemy heroes can't be asked: GetRespawnTime() on an enemy handle never
-- answered (games 066/067: all 50+ enemy deaths logged `respawn=30s known=false`), so the window used a flat 30s
-- while late-game respawns ran 70-125s (own deaths, `[SHy-DEATH] ... respawned=`), and Roshan calls were dropped
-- as window-short. Nearest learned level wins (ties: the higher one); nothing learned or no level: `default`. A value
-- learned at a lower level never goes under `default` (early samples of 12-20s must not shorten a level-20 window).
-- Returns seconds, source ("learned" or "default"), level used.
function PushRules.RespawnEstimate(learned, level, default)
	if type(learned) ~= "table" or type(level) ~= "number" or level < 1 then
		return default, "default", nil
	end
	local bestLevel, bestGap = nil, nil
	for knownLevel, seconds in pairs(learned) do
		if type(knownLevel) == "number" and type(seconds) == "number" and seconds > 0 then
			local gap = math.abs(knownLevel - level)
			if bestGap == nil or gap < bestGap or gap == bestGap and knownLevel > bestLevel then
				bestLevel, bestGap = knownLevel, gap
			end
		end
	end
	if bestLevel == nil then
		return default, "default", nil
	end
	if bestLevel < level then
		return math.max(learned[bestLevel], default or 0), "learned", bestLevel
	end
	return learned[bestLevel], "learned", bestLevel
end

-- Advantage window (#12, maintainer 2026-11-21: "when a team picks aegis, raise the push desire as long as our base
-- is not being pushed" and "5 enemies death also should affect push desire"). One rule:
--   s.aegis        our team holds the Aegis
--   s.alliesAlive  our heroes alive
--   s.enemiesAlive enemy heroes alive
--   s.dead         enemy heroes dead with more than 5s of respawn left
--   s.deadLong     enemy heroes dead with 20s+ of respawn left
--   s.baseThreat   enemy heroes on our high ground / at our Ancient, or 2+ enemy creeps at our Ancient
--   s.now          DotaTime() (optional): no window before the horn
--   s.enemyHeroes  how many heroes the enemy team has, dead ones included (optional): no window without any
-- Returns desire (nil when no window) and why.
--   every enemy dead: 0.9 (wipe); 3+ dead for 20s+: 0.9; 2+ dead with 4-5 of ours alive: 0.8;
--   Aegis with 4+ alive: 0.8 (0.85 on top of a dead window).
function PushRules.Advantage(s)
	if s == nil then
		return nil, "none"
	end
	if s.baseThreat then
		return nil, "base-threat"
	end
	-- Before the horn, or before the enemy heroes are in the game, "no enemy alive" is not a wipe (#12, game 088:
	-- t=-88 radiant advantage-start why=wipe dead=0 alive=1/0).
	if s.now ~= nil and s.now < 0 then
		return nil, "pre-horn"
	end
	if s.enemyHeroes ~= nil and s.enemyHeroes < 1 then
		return nil, "no-enemy-heroes"
	end
	local alliesAlive = s.alliesAlive or 0
	local enemiesAlive = s.enemiesAlive or 5
	local desire, why = nil, "none"
	if alliesAlive >= 1 and enemiesAlive == 0 then
		desire, why = 0.9, "wipe"
	elseif (s.deadLong or 0) >= 3 and alliesAlive > enemiesAlive then
		desire, why = 0.9, "dead3"
	elseif (s.dead or 0) >= 2 and alliesAlive >= 4 and alliesAlive > enemiesAlive then
		desire, why = 0.8, "dead2"
	end
	if s.aegis and alliesAlive >= 4 then
		if desire == nil then
			desire, why = 0.8, "aegis"
		else
			desire, why = math.max(desire, 0.85), why .. "+aegis"
		end
	end
	return desire, why
end

-- The push cap while every enemy hero is alive and we don't have more alive (#12, game 067 33:00 and game 066
-- 67:54-81:58: `lock-capped why=cap desire=0.41 allies=2 alive=5/5` kept 3 of 5 farming at 0.6-0.77 farm).
--   s.enemiesAlive, s.alliesAlive, s.nwLead (our inventory net worth minus theirs), s.levelLead (our average level
--   minus theirs), s.tier (next target on the lane: 1 = T1, 2 = T2, 3 = high ground, 4 = Ancient)
-- Returns cap, joiners (how many bots, closest to the lane front first, may push above it), why; nil when the cap
-- does not apply. Ahead = 2000+ net worth or 1+ average level, the mirror of the behind-stop rule in push.lua.
function PushRules.FiveAliveCap(s)
	if s == nil or (s.enemiesAlive or 0) < 5 or (s.alliesAlive or 0) > (s.enemiesAlive or 0) then
		return nil, 5, "off"
	end
	local ahead = (s.nwLead or 0) >= 2000 or (s.levelLead or 0) >= 1
	local outer = (s.tier or 3) <= 2
	if ahead and outer then
		return 0.75, 4, "ahead+outer"
	elseif ahead then
		return 0.7, 3, "ahead"
	elseif outer then
		return 0.7, 3, "outer"
	end
	return 0.41, 2, "even"
end

-- A Roshan call the team answers outranks a push (#12, game 067 32:11: a 4-bot kill-window call at 0.60 lost to a
-- 0.99 kill push; 20s later every call dropped window-short). Returns the push desire to use and whether it yielded.
--   roshDesire / roshAge: this bot's Roshan desire and how many seconds ago it was computed. Only a gather call
--   (0.9+: a team call, or a kill-window take that fits) wins; a plain 0.60 call (timer, or a kill window held back
--   while the team is on the T2 / high ground or in a fight) does not cut the push.
--   finishingTower: the push is finishing a tower the group can kill in ~5s (that one goes first)
function PushRules.PushUnderRosh(pushDesire, roshDesire, roshAge, finishingTower)
	if type(pushDesire) ~= "number" or type(roshDesire) ~= "number" then
		return pushDesire, false
	end
	if finishingTower or (roshAge or 99) > 1.5 or roshDesire < 0.9 or pushDesire < roshDesire then
		return pushDesire, false
	end
	return math.max(0, roshDesire - 0.05), true
end

-- Push desire in a lane-locked group push (push.lua, the branch that returns before the normal path; game 067:
-- `lock-capped why=cap desire=0.25 alive=4/0` at t=1376, no wipe push with all five Radiant dead). In order:
--   raise to s.advantage (advantage window) or s.joinCap (a joiner of an all-alive push);
--   cap: s.maxPush (own HP, high ground, backdoor and the all-alive cap already folded in);
--   alone-vs-2: one hero against 2+ near it, 0.2;
--   fewer-than-alive: fewer allies near than enemies alive at a T2+ (T3+ for a joiner) within 6000 of their
--     Ancient, 0.4; not in an advantage window, not while gathering below their high ground (s.gathering); with
--     their Ancient open and us ahead it counts the enemies seen near instead (PushRules.FewerThanAliveCount);
--   group-hurt: s.groupHurt (2+ allies under 40%, average under 60%, near their base) while enemies can still
--     punish it, 0.15; never with every enemy dead.
-- Returns desire, the last cap that applied (nil when none), "advantage" / "join" when raised.
function PushRules.LockDesire(s)
	local desire = s.base or 0
	local raised = nil
	if s.advantage ~= nil and desire < s.advantage then
		desire, raised = s.advantage, "advantage"
	elseif s.joinCap ~= nil and desire < s.joinCap then
		desire, raised = s.joinCap, "join"
	end
	local cap = nil
	if s.maxPush ~= nil and s.maxPush < desire then
		desire, cap = s.maxPush, "cap"
	end
	local alliesNear = s.alliesNear or 1
	local enemiesAlive = s.enemiesAlive or 5
	if alliesNear <= 1 and (s.enemiesNear or 0) >= 2 and desire > 0.2 then
		desire, cap = 0.2, "alone-vs-2"
	end
	if
		s.advantage == nil
		and not s.gathering
		and s.nearAncient
		and (s.tier or 1) >= (s.joinCap ~= nil and 3 or 2)
		and alliesNear < PushRules.FewerThanAliveCount(s.ancientOpen, s.ahead, enemiesAlive, s.enemiesNear)
		and desire > 0.4
	then
		desire, cap = 0.4, "fewer-than-alive"
	end
	if s.groupHurt and enemiesAlive > 0 and enemiesAlive >= alliesNear - 2 and desire > 0.15 then
		desire, cap = 0.15, "group-hurt"
	end
	return desire, cap, raised
end

-- The enemy count the fewer-than-alive cap compares our allies near with (#12, game 068 50:33-51:01: four Dire at
-- Radiant's open Ancient, 18k ahead, no Radiant hero near, were capped at 0.40 because all five Radiant were alive at
-- their fountain; farm then walked them home). With their Ancient open (both T4s down) and us ahead: the enemies seen
-- near the bot. Otherwise: the enemies alive.
function PushRules.FewerThanAliveCount(ancientOpen, ahead, enemiesAlive, enemiesNear)
	if ancientOpen and ahead then
		return enemiesNear or 0
	end
	return enemiesAlive or 5
end

-- HP under which a bot's push is capped at 0.25: 50%, or 30% with every enemy dead (the wipe push's own floor).
function PushRules.OwnHpCapBelow(wipe)
	return wipe and 0.3 or 0.5
end

-- The own-HP cap with its inputs (#12, game 068 2331-2376: in a dead-enemies window with no enemy hero near, bots
-- at 0.50-0.52 flipped between `advantage-push desire=0.80` and `lock-capped desire=0.25` every few seconds).
--   s.wipe: every enemy dead (0.3); s.aegisHolder: this bot holds the Aegis (0.3: it comes back where it falls);
--   s.window: an advantage window (dead enemies or the Aegis; game 069 1543-1640: Puck and Alchemist were held at
--   0.46-0.53 in the Aegis window) and s.enemiesNear == 0: 0.4; else 0.5. s.deadWindow is the older name of
--   s.window. s.wasCapped: the cap held this bot last think: it lets go 0.05 higher, so HP ticking around the line
--   doesn't flip the push.
-- Returns the HP under which the cap applies.
function PushRules.OwnHpCap(s)
	local below = PushRules.OwnHpCapBelow(s.wipe or s.aegisHolder)
	if not s.wipe and not s.aegisHolder and (s.window or s.deadWindow) and (s.enemiesNear or 0) == 0 then
		below = 0.4
	end
	if s.wasCapped then
		below = below + 0.05
	end
	return below
end

-- The high-ground cap (#12): near the enemy fountain, with enemies alive, a push of fewer than s.need allies near the
-- bot (3; 2 in a window of 2+ dead) is capped at 0.15. Game 068 52:33-54:00: the five-alive rule let 3 Dire join
-- (`lock-capped why=cap desire=0.15 allies=1-2 alive=5/5 hg=true five=ahead joiners=3`), the cap cut each of them to
-- 0.15 before the 3 could meet, and Undying went up alone and died. A bot of an allowed group push instead gathers
-- at a spot below the high ground (out of tower range) at the push desire and goes up when s.need are there.
--   s.nearEnemyFountain: the lane front is within 5000 of their fountain
--   s.enemiesAlive, s.alliesAlive; s.alliesNear: allies within 1600 of the bot (itself included);
--   s.atSpot: allies within 1600 of the gather spot (nil when there is no spot)
--   s.groupAllowed: an advantage window, or a joiner of an all-alive push the later caps let up the high ground
--   s.released: the group went up less than ~12s ago (latched, so walking up doesn't drop the count and turn back)
--   s.gatherAge: seconds this bot has been gathering; s.coolDown: a gather that gave up less than 30s ago
--   s.atFront: our heroes at this lane's front (PushRules.HgGatherLane's count); 3+ there with no more enemies alive
--     than that: the group is already up, "go" (game 085 50:43: Shadow Fiend, Sniper and Phoenix at the mid T3
--     against 1-2 alive were held at 0.15). A bot arriving alone then walks up to them instead of waiting below.
--   s.otherLane: the team gathers on another lane (PushRules.HgGatherLane): "cap" here, but only after the "go"
--     checks, so a group that is already there is never held back by it
-- Returns "none" (no high-ground cap), "go" (enough allies: no cap, latch the release), "cap" (0.15) or "gather".
function PushRules.HgGather(s)
	if not s.nearEnemyFountain or (s.enemiesAlive or 5) == 0 then
		return "none"
	end
	if (s.alliesAlive or 0) < (s.enemiesAlive or 5) then
		return "cap"
	end
	local need = s.need or 3
	if (s.alliesNear or 1) >= need or (s.atSpot or 0) >= need then
		return "go"
	end
	local atFront = s.atFront or 0
	if atFront >= 3 and (s.enemiesAlive or 5) <= atFront then
		return "go"
	end
	if s.released then
		return "go"
	end
	if s.otherLane then
		return "cap"
	end
	if not s.groupAllowed or s.atSpot == nil or s.coolDown then
		return "cap"
	end
	if (s.gatherAge or 0) > 45 then
		return "cap"
	end
	return "gather"
end

-- A push's hero target behind an enemy tower (#12, game 068 16:52-16:58: push's hit-hero step walked Clinkz past
-- Radiant's mid T2 toward Alchemist 1006 away; he died next to the tower. Game 069 22:48: Undying stood 1064 from
-- Dire's mid T2, outside range + 150, and Alchemist and Axe chased him past it up to the T3 and died). Covered: the
-- hero is farther from us than the tower and either stands within the tower's range + 150 or the straight path to him
-- passes within it (s.pathToTower). Taken anyway when:
--   the tower is under 25%; our creeps tank it and more of ours than theirs are near (s.creepsTanking, s.fightOurs);
--   an advantage window is open (s.advantage); the enemies who can respond (alive and not seen far away,
--   s.responders) are no more than our heroes on the chase (s.chasers; game 069 33:30: 3 alive, all near, against 3
--   of ours, in a dead2 window: the deep chase killed two and the T3 and barracks fell);
--   the target dies before the tower kills us (s.killTime <= 5s and under s.surviveTime).
-- Returns skip, why.
function PushRules.HitHeroBehindTower(s)
	local reach = (s.towerRange or 700) + 150
	if (s.targetToTower or math.huge) > reach and (s.pathToTower or math.huge) > reach then
		return false, "clear"
	end
	if (s.botToTarget or 0) <= (s.botToTower or 0) then
		return false, "in-front"
	end
	if (s.towerHp or 1) < 0.25 then
		return false, "tower-low"
	end
	if s.creepsTanking and s.fightOurs then
		return false, "creeps-tank"
	end
	if s.advantage then
		return false, "advantage"
	end
	if s.responders ~= nil and s.chasers ~= nil and s.responders <= s.chasers then
		return false, "numbers"
	end
	if s.killTime ~= nil and s.killTime <= 5 and s.killTime < (s.surviveTime or 0) then
		return false, "kill-first"
	end
	return true, "behind-tower"
end

-- PushThink's walk to the lane front (#12, game 071 47:20-47:41): a bot 2000+ from its lane's front walks there,
-- unless a hero hit it in the last 3s, or the lane has none of its own buildings left (s.laneTier 4: T3 and both
-- barracks down) and a target building was found (another lane's barracks or the T4s): then the bot stays on that
-- target ("lane-done") instead of walking back to a front with nothing to take.
-- Returns "walk", "lane-done" or "stay".
function PushRules.FrontWalk(s)
	if (s.distanceToFront or 0) <= 2000 or s.recentlyHit then
		return "stay"
	end
	if (s.laneTier or 0) >= 4 and s.hasTarget then
		return "lane-done"
	end
	return "walk"
end

-- Finish hold (#12, game 072 10:11-10:38): once a tower can be finished (FinishTower: 2+ allies whose 5s damage beats
-- its HP), the push stays on it through the other gates while: the tower stands, our base is not hit, 2+ of ours are
-- at it, fewer enemy heroes than ours are near it, the bot is above 30% HP, our 5s damage still beats its HP, and for
-- 15s at most. A Glyph pauses it (game 074 21:48-22:06, maintainer live 2026-11-23): while the tower has the Glyph the
-- hold is kept ("glyph": the bots wait at the tower, PushRules.GlyphWait) without the damage and 15s checks; the
-- caller stops the 15s clock for the Glyph's duration (s.age excludes it). Was: a Glyph dropped the hold every think.
-- Returns keep, why.
function PushRules.FinishHold(s)
	if not s.towerAlive then
		return false, "fell"
	end
	if s.baseThreat then
		return false, "base"
	end
	if (s.allies or 0) < 2 then
		return false, "alone"
	end
	if (s.enemiesNear or 0) >= (s.allies or 0) then
		return false, "enemies"
	end
	if (s.hp or 1) < 0.3 then
		return false, "low-hp"
	end
	if s.glyphed then
		return true, "glyph"
	end
	if (s.damage5s or 0) < (s.towerHp or 0) then
		return false, "slow"
	end
	if (s.age or 0) > 15 then
		return false, "timeout"
	end
	return true, "ok"
end

-- Glyph of Fortification, 7.42 (abilities_english.txt in pak01_dir.vpk, DOTA_Tooltip_ability_fountain_glyph*):
-- structures invulnerable for 7s, lane creeps for 3s, towers get multishot with 5 additional targets "excludes tier 1
-- towers", 2 charges. Nothing in the game files changes the tower's damage per target (the 7.37 "+100% damage" note
-- is Elder Titan's innate Tip the Scales, not the Glyph).
PushRules.GLYPH_STRUCTURE_SECONDS = 7
PushRules.GLYPH_MULTISHOT_TARGETS = 6

-- Tier of a tower from its unit name (npc_dota_badguys_tower2_mid -> 2); nil for anything else.
function PushRules.TowerTier(name)
	return tonumber(string.match(name or "", "tower(%d)"))
end

-- Seconds of Glyph left on a building: the modifier's remaining time when the API gives one (`read`), else 7s from
-- when the bot first saw it (`elapsed`). Returns seconds, source ("modifier" or "timer").
function PushRules.GlyphLeft(read, elapsed)
	if type(read) == "number" and read >= 0 then
		return read, "modifier"
	end
	return math.max(0, PushRules.GLYPH_STRUCTURE_SECONDS - (elapsed or 0)), "timer"
end

-- What a pusher does while the enemy tower in front has the Glyph (#12). The tower can't be hit for 7s, its creeps for
-- 3s; the group waits it out at the tower and hits what it can:
--   "back"  - leave as before (the lane-front step back): HP under 30%, or more enemy heroes than ours near the tower.
--   "edge"  - wait just outside the tower's range, hitting creeps and heroes outside it, at every tier: a tier 2+ tower
--             ("multishot": it hits 5 more targets, so our creeps don't keep it off us), a tier 1 tower ("tier1", or
--             "no-creeps" with none of ours in its range).
-- Game 074 (maintainer: "if we have nearby ally creep, no need to back off except when outnumbered") had a "stay" mode
-- at a tier 1 with our creeps under it. Game 078 replaced it (maintainer, 2026-11-24: "i'd like to revert how bot react
-- to t1 glyph ... standing still under t1 ... i like how they dont attack creep under shield"; "agree to walk back and
-- wait at the edge. but standing still is bad. enemy could easily land disables or setup team fight to standstill
-- heroes"): game 078 t=508 Puck stood under Dire's mid T1 at 49% HP in mode=stay.
-- s: tier, hp, allies, enemies (heroes within 1200 of the tower), creeps (ours in its range). Returns mode, why.
function PushRules.GlyphWait(s)
	if (s.hp or 1) < 0.3 then
		return "back", "low-hp"
	end
	if (s.enemies or 0) > (s.allies or 0) then
		return "back", "outnumbered"
	end
	if (s.tier or 1) >= 2 then
		return "edge", "multishot"
	end
	if (s.creeps or 0) < 1 then
		return "edge", "no-creeps"
	end
	return "edge", "tier1"
end

-- The edge wait's arc (#12, game 078): the waiting bots stay within this many radians either side of the line from
-- the tower back along the lane toward our side (no walk around the tower to its far side), and about this far from each other, so one
-- AoE disable can't catch the group.
PushRules.GLYPH_EDGE_ARC = 0.8
PushRules.GLYPH_SPREAD = 300

-- A point `radius` from the tower (tx, ty) in the direction of (px, py), kept within `maxAngle` radians of (bx, by),
-- the unit vector from the tower toward our side (back along the lane). Returns x, y.
function PushRules.GlyphEdgePoint(tx, ty, px, py, bx, by, radius, maxAngle)
	local dx, dy = px - tx, py - ty
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1 then
		dx, dy = bx, by
	else
		dx, dy = dx / length, dy / length
	end
	local cosMax = math.cos(maxAngle)
	if dx * bx + dy * by < cosMax then
		-- Past the arc's end: the end on the side the point is on (rotate b by +-maxAngle).
		local side = (bx * dy - by * dx) >= 0 and 1 or -1
		local sinMax = math.sin(maxAngle) * side
		dx, dy = bx * cosMax - by * sinMax, bx * sinMax + by * cosMax
	end
	return tx + dx * radius, ty + dy * radius
end

-- Distance from (x, y) to the nearest of `points` ({ x =, y = } each), or nil with none.
function PushRules.NearestDistance(x, y, points)
	local best = nil
	for _, point in ipairs(points or {}) do
		local distance = math.sqrt((point.x - x) ^ 2 + (point.y - y) ^ 2)
		if best == nil or distance < best then
			best = distance
		end
	end
	return best
end

-- The next side-step of a bot waiting at a glyphed tower's edge with nothing to hit (#12, game 078: no standing
-- still). s: tx, ty (tower), x, y (bot), bx, by (unit vector tower -> our side), radius (the edge), step (distance
-- of one step), side (1 or -1: the way it goes this time; the caller flips it after every step), maxAngle (the arc),
-- allies ({ x =, y = } of the other waiting allies or where they are walking to), minGap (spread), passable (optional
-- function(x, y) -> bool). Candidates: `side` then the other way, one step then two, each put on the edge arc; a
-- candidate that lands within a third of a step of the bot (the arc's end) is no move, and one that is not passable
-- (trees, cliffs) would leave the bot standing: both are skipped. The first one minGap+ from every ally wins, else the one farthest
-- from its nearest ally. Returns x, y, the side taken, the nearest ally's distance there (nil: no ally).
function PushRules.GlyphSideStep(s)
	local tx, ty, x, y = s.tx, s.ty, s.x, s.y
	local ux, uy = x - tx, y - ty
	local length = math.sqrt(ux * ux + uy * uy)
	if length < 1 then
		ux, uy = s.bx, s.by
	else
		ux, uy = ux / length, uy / length
	end
	-- The tangent at the bot (90 degrees from the tower -> bot direction).
	local px, py = -uy, ux
	local side = (s.side or 1) >= 0 and 1 or -1
	local step = s.step or 250
	local minGap = s.minGap or PushRules.GLYPH_SPREAD
	local best, bestGap = nil, -1
	for _, try in ipairs({ { side, 1 }, { -side, 1 }, { side, 2 }, { -side, 2 } }) do
		local cx, cy = PushRules.GlyphEdgePoint(
			tx,
			ty,
			x + px * step * try[1] * try[2],
			y + py * step * try[1] * try[2],
			s.bx,
			s.by,
			s.radius,
			s.maxAngle or PushRules.GLYPH_EDGE_ARC
		)
		if math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2) >= step / 3 and (s.passable == nil or s.passable(cx, cy)) then
			local gap = PushRules.NearestDistance(cx, cy, s.allies)
			if gap == nil or gap >= minGap then
				return cx, cy, try[1], gap
			end
			if gap > bestGap then
				best, bestGap = { cx, cy, try[1] }, gap
			end
		end
	end
	if best == nil then
		-- Every candidate was skipped (blocked all around): go back onto the edge.
		local cx, cy =
			PushRules.GlyphEdgePoint(tx, ty, x, y, s.bx, s.by, s.radius, s.maxAngle or PushRules.GLYPH_EDGE_ARC)
		return cx, cy, -side, PushRules.NearestDistance(cx, cy, s.allies)
	end
	return best[1], best[2], best[3], bestGap
end

-- The walk out of a glyphed tower's reach (#12, games 089 t=880-887 at the top T2 and 091 t=1657-1664 at the bottom
-- T2; maintainer, game 091: "dire team still move aside perpendicular to radiant bottom lane, hit obstacle and stand
-- still being hit by radiant t2 when glyphed"). One move order to the edge on the bot's own bearing (up to 0.8 rad
-- off the lane) sent Wraith King, Zeus and Winter Wyvern into the trees beside the lane: they got 455-566 from the
-- tower against a reach of about 850 (`glyph-end ... moves=1`) and Winter Wyvern went from 84% to 25% HP.
-- Now the bot walks to the first of these candidates, and takes the next one when it has not gained
-- GLYPH_REPATH_GAIN from the tower in GLYPH_REPATH_SECONDS (PushRules.GlyphExitStalled).
PushRules.GLYPH_EXIT_ARC = 0.35 -- the bot's own bearing, kept this close to the lane (spreads bots a little)
PushRules.GLYPH_REPATH_SECONDS = 1
PushRules.GLYPH_REPATH_GAIN = 50

-- Exit candidates, best first. s: tx, ty (tower), x, y (bot), bx, by (unit vector tower -> our side along the lane),
-- radius (the edge: reach + 100), lane ({ x =, y = }: a point on the lane path toward our side at least radius from the
-- tower, or nil), towerHit (the tower hit the bot: straight back along the lane first), passable (optional
-- function(x, y) -> bool). Kinds: "own" (the bot's bearing within GLYPH_EXIT_ARC), "back" (straight back along the
-- lane), "lane" (the lane point), "side" (the arc's two ends, the bot's side first). Not tower hit: own, back, lane,
-- sides; tower hit: back, lane, own, sides. Ground that can't be walked is left out, except the lane point (the lane
-- is walkable); "own" is left out when it is within 100 of "back". Never empty (falls back to "back").
-- Returns a list of { x =, y =, kind = }.
function PushRules.GlyphExitPoints(s)
	local tx, ty, bx, by, radius = s.tx, s.ty, s.bx, s.by, s.radius
	local ox, oy = PushRules.GlyphEdgePoint(tx, ty, s.x, s.y, bx, by, radius, PushRules.GLYPH_EXIT_ARC)
	local backX, backY = tx + bx * radius, ty + by * radius
	local own = { x = ox, y = oy, kind = "own" }
	local back = { x = backX, y = backY, kind = "back" }
	-- The arc's ends: rotate b by +-GLYPH_EDGE_ARC, the end on the bot's side of the lane line first.
	local ux, uy = s.x - tx, s.y - ty
	local botSide = (bx * uy - by * ux) >= 0 and 1 or -1
	local sides = {}
	for _, sign in ipairs({ botSide, -botSide }) do
		local cosA, sinA = math.cos(PushRules.GLYPH_EDGE_ARC), math.sin(PushRules.GLYPH_EDGE_ARC) * sign
		sides[#sides + 1] =
			{ x = tx + (bx * cosA - by * sinA) * radius, y = ty + (bx * sinA + by * cosA) * radius, kind = "side" }
	end
	local order
	if s.towerHit then
		order = { back, s.lane, own, sides[1], sides[2] }
	else
		order = { own, back, s.lane, sides[1], sides[2] }
	end
	local points = {}
	for i = 1, 5 do
		local point = order[i]
		if point ~= nil then
			if point == s.lane then
				points[#points + 1] = { x = point.x, y = point.y, kind = "lane" }
			elseif
				not (point == own and math.sqrt((ox - backX) ^ 2 + (oy - backY) ^ 2) < 100)
				and (s.passable == nil or s.passable(point.x, point.y))
			then
				points[#points + 1] = point
			end
		end
	end
	if #points == 0 then
		points[1] = back
	end
	return points
end

-- Has the walk out stalled? p: the bot's progress on the current candidate ({} at the start; this keeps best =
-- the farthest distance from the tower so far, bestAt = when it last grew by GLYPH_REPATH_GAIN). distance: now, from
-- the tower. True when the bot has not gained GLYPH_REPATH_GAIN for GLYPH_REPATH_SECONDS (standing against trees);
-- the clock then starts again for the next candidate.
function PushRules.GlyphExitStalled(p, distance, now)
	if p.best == nil or distance >= p.best + PushRules.GLYPH_REPATH_GAIN then
		p.best, p.bestAt = math.max(distance, p.best or 0), now
		return false
	end
	if now - p.bestAt >= PushRules.GLYPH_REPATH_SECONDS then
		p.best, p.bestAt = distance, now
		return true
	end
	return false
end

-- How much a tower counts in a fight estimate (Fu.WeAreStronger) while it has the Glyph: per target its damage is
-- unchanged, so a tier 1 tower (no multishot) counts as usual (1). A tier 2+ tower hits up to 6 targets at once, so
-- against a group it deals its damage to each hero of the group in its range (`heroesInRange`, at least 1, at most 6).
-- Was a flat 2 for every glyphed tower.
function PushRules.GlyphTowerFactor(towerName, glyphed, heroesInRange)
	if not glyphed then
		return 1
	end
	local tier = PushRules.TowerTier(towerName)
	if tier == nil or tier < 2 then
		return 1
	end
	return math.min(math.max(heroesInRange or 1, 1), PushRules.GLYPH_MULTISHOT_TARGETS)
end

-- When a lane-done episode ends (push.lua LaneDoneTick): the target fell, the bot died or stopped thinking for 3s+,
-- it was out of push mode for 2s+, or 20s passed. Returns the reason or nil.
function PushRules.LaneDoneEpisodeEnd(s)
	if not s.targetAlive then
		return "fell"
	end
	if not s.botAlive or (s.gap or 0) > 3 then
		return "died"
	end
	if (s.outOfPush or 0) > 2 then
		return "left-push"
	end
	if (s.age or 0) >= 20 then
		return "cap"
	end
	return nil
end

-- Distance from point (px, py) to the segment (ax, ay)-(bx, by).
function PushRules.PointToSegment(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local lengthSq = dx * dx + dy * dy
	local t = 0
	if lengthSq > 0 then
		t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSq))
	end
	local cx, cy = ax + t * dx, ay + t * dy
	return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
end

-- A lane our creeps press (#12, maintainer idea 2026-11-22): the lane's next target is their T3 or deeper (tier 3+:
-- T1 and T2 down) and our lane front, with 2+ of our creeps, stands within 1500 of that target. Such a wave pulls
-- their heroes home.
function PushRules.LaneUnderPressure(tier, frontToTarget, creepsAtFront)
	return (tier or 1) >= 3 and (frontToTarget or math.huge) <= 1500 and (creepsAtFront or 0) >= 2
end

-- Roshan desire bonus for creep pressure: +0.1 per pressed lane, at most +0.2.
function PushRules.CreepPressureBonus(lanes)
	return math.min(0.2, 0.1 * math.max(0, lanes or 0))
end

-- Aegis first (#12, maintainer decision 2026-11-22: "forcing a 5v5 on the enemy high ground with every enemy alive
-- is a gamble; taking the Aegis first is safer"). Roshan comes before the high-ground push when:
--   every enemy is alive (s.enemiesAlive >= s.enemyPlayers), their base is open (s.baseOpen: a lane's next target is
--   a T3 or deeper), Roshan is (assumed) alive, we don't hold the Aegis, no advantage window is open (dead enemies
--   still push first), our base is not threatened, 4+ of ours are alive, and we are ahead or our creeps press a lane
--   (s.ahead / s.pressureLanes; an even game has no high-ground push to replace, and a 5v5 Roshan there is the same
--   gamble).
-- Returns on, why.
function PushRules.RoshanFirst(s)
	if s == nil then
		return false, "none"
	end
	if s.baseThreat then
		return false, "base-threat"
	end
	if s.advantage then
		return false, "advantage"
	end
	if s.ourAegis then
		return false, "have-aegis"
	end
	if not s.roshAlive then
		return false, "rosh-dead"
	end
	if (s.enemiesAlive or 0) < (s.enemyPlayers or 5) then
		return false, "enemy-dead"
	end
	if not s.baseOpen then
		return false, "base-closed"
	end
	if (s.alliesAlive or 0) < 4 then
		return false, "few-alive"
	end
	if not s.ahead and (s.pressureLanes or 0) < 1 then
		return false, "even"
	end
	return true, s.ahead and "ahead" or "pressure"
end

-- The team's high-ground gather lane (#12, game 085 50:43: Ringmaster, 15000 away, set the gather lane to bot because
-- he asked first, and the three heroes at the mid T3 were capped to 0.15). Worked out from the team's positions only,
-- so every bot gets the same answer whichever asks:
--   s.counts[lane]: our heroes at that lane's front (within 3000 of it or 1600 of its gather spot)
--   s.kept: the lane a gathering bot within 4000 of its spot set less than 3s ago (nil when none). It stays unless
--     another lane has strictly more allies, so the pick doesn't flip on a tie.
--   s.advLane: the group push's locked lane (nil when none); s.hgLanes[lane]: its front is near their fountain
-- The lane with the most allies; on a tie the advantage push's lane, then the lowest tied lane. With nobody at any
-- front: the kept lane, the advantage lane, the lowest high-ground lane, then lane 1.
-- Returns lane, why (kept / most-allies / adv-lane / first-hg / first).
function PushRules.HgGatherLane(s)
	local counts = s.counts or {}
	local best = 0
	for lane = 1, 3 do
		best = math.max(best, counts[lane] or 0)
	end
	local kept, advLane = s.kept, s.advLane
	if kept ~= nil and (counts[kept] or 0) >= best then
		return kept, "kept"
	end
	if best >= 1 then
		local tied, first = 0, nil
		for lane = 1, 3 do
			if (counts[lane] or 0) == best then
				tied = tied + 1
				first = first or lane
			end
		end
		if tied > 1 and advLane ~= nil and (counts[advLane] or 0) == best then
			return advLane, "adv-lane"
		end
		return first, "most-allies"
	end
	if advLane ~= nil then
		return advLane, "adv-lane"
	end
	for lane = 1, 3 do
		if s.hgLanes ~= nil and s.hgLanes[lane] then
			return lane, "first-hg"
		end
	end
	return 1, "first"
end

-- The push gate for a bot with no ally within 1600 while 3+ enemies are alive (#12, game 085 35:17-35:56: bots that
-- reached the top push one after another each counted as "alone" and went back to farm: `push-gate why=alone` from
-- Phoenix, Shadow Fiend, Ringmaster and Sniper while the others pushed top).
--   s.alliesNear: allies within 1600 (itself included); s.enemiesAlive; s.enemiesNear: enemy heroes within 1600
--   s.window: an advantage window, or a joiner of an all-alive group push (as before: it may come alone)
--   s.group: other allies on this lane's push: within 3000 of its front, or in its push mode within 6000 of it
--   s.joinAge: seconds this bot has been walking to that group
-- Returns "pass" (not alone), "window", "join" (walk to the group: push-gate why=alone-join) or "drop", and why.
PushRules.ALONE_JOIN_MAX_SECONDS = 45
function PushRules.AloneGate(s)
	if (s.alliesNear or 1) > 1 or (s.enemiesAlive or 5) < 3 then
		return "pass", "not-alone"
	end
	local enemiesNear = s.enemiesNear or 0
	if s.window and enemiesNear == 0 then
		return "window", "window"
	end
	if enemiesNear > 0 then
		return "drop", "alone"
	end
	if (s.group or 0) >= 2 then
		if (s.joinAge or 0) > PushRules.ALONE_JOIN_MAX_SECONDS then
			return "drop", "join-timeout"
		end
		return "join", "alone-join"
	end
	return "drop", "alone"
end

return PushRules
