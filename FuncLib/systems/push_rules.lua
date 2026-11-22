-- Shared bot system: pure push / Roshan team rules (no bot API calls), so they can be tested with real numbers.
-- Used by FuncLib/systems/push.lua, FuncLib/systems/kill_window.lua and mode_roshan_generic.lua (#12).
local PushRules = {}

-- Respawn seconds of a dead enemy at `level`, from what our own heroes' deaths showed (learned[level] = seconds,
-- the same rules hold for both teams). Enemy heroes can't be asked: GetRespawnTime() on an enemy handle never
-- answered (games 066/067: all 50+ enemy deaths logged `respawn=30s known=false`), so the window used a flat 30s
-- while late-game respawns ran 70-125s (own deaths, `[OHA-DEATH] ... respawned=`), and Roshan calls were dropped
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
--   s.wipe: every enemy dead (0.3); s.deadWindow: an advantage window from dead enemies (not the Aegis alone) and
--   s.enemiesNear == 0: 0.4; else 0.5. s.wasCapped: the cap held this bot last think: it lets go 0.05 higher, so
--   HP ticking around the line doesn't flip the push.
-- Returns the HP under which the cap applies.
function PushRules.OwnHpCap(s)
	local below = PushRules.OwnHpCapBelow(s.wipe)
	if not s.wipe and s.deadWindow and (s.enemiesNear or 0) == 0 then
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
	if s.released then
		return "go"
	end
	if not s.groupAllowed or s.atSpot == nil or s.coolDown then
		return "cap"
	end
	if (s.gatherAge or 0) > 45 then
		return "cap"
	end
	return "gather"
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

return PushRules
