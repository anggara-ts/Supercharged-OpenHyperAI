-- bots/lib/systems/dive_rules.lua: after the early game, does a bot an enemy tower is shooting stop its chase?
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_skywrath_mage" })
	return require(GetScriptDirectory() .. "/lib/systems/dive_rules")
end

local function situation(overrides)
	local s = {
		towerOnBot = true,
		outerTower = true,
		pushing = false,
		hasTarget = true,
		teamDamage = 400,
		targetHealth = 900,
		committed = false,
		botHealth = 1200,
		shotDamage = 150,
	}
	for key, value in pairs(overrides or {}) do
		s[key] = value
	end
	return s
end

T.test("tower chase: no decision when the tower is not on the bot, is a T3/T4, or a push handles it", function()
	local R = rules()
	T.eq(R.TowerChaseDecision(situation({ towerOnBot = false })), nil, "tower on someone else")
	T.eq(R.TowerChaseDecision(situation({ pushing = true })), nil, "push mode steps out itself")
	T.eq(R.TowerChaseDecision(situation({ outerTower = false })), nil, "base fight at a T3/T4")
end)

T.test("tower chase: a target the team can't kill in 2 tower shots: leave", function()
	local R = rules()
	local act, why = R.TowerChaseDecision(situation())
	T.eq(act, "leave", "act")
	T.eq(why, "not-killable", "why")
end)

T.test("tower chase: a target that dies within 2 shots keeps the chase while the bot has the HP", function()
	local R = rules()
	local act, why = R.TowerChaseDecision(situation({ teamDamage = 950 }))
	T.eq(act, "stay", "act")
	T.eq(why, "killable", "why")
	act, why = R.TowerChaseDecision(situation({ committed = true }))
	T.eq(act, "stay", "committed act")
	T.eq(why, "committed", "committed why")
end)

T.test("tower chase: too low for 3 tower shots leaves even for a kill", function()
	local R = rules()
	local act, why = R.TowerChaseDecision(situation({ teamDamage = 950, botHealth = 450 }))
	T.eq(act, "leave", "act")
	T.eq(why, "low-hp", "why")
	act = R.TowerChaseDecision(situation({ teamDamage = 950, botHealth = 451 }))
	T.eq(act, "stay", "one HP above 3 shots stays")
end)

T.test("tower chase: shot at with no hero target: leave", function()
	local R = rules()
	local act, why = R.TowerChaseDecision(situation({ hasTarget = false, teamDamage = 0, targetHealth = 0 }))
	T.eq(act, "leave", "act")
	T.eq(why, "no-target", "why")
end)

T.test("tower chase: entering after a target inside the tower's range decides before the first shot", function()
	local R = rules()
	local act, why = R.TowerChaseDecision(situation({ towerOnBot = false, entering = true }))
	T.eq(act, "leave", "not killable: stop outside")
	T.eq(why, "not-killable", "why")
	act = R.TowerChaseDecision(situation({ towerOnBot = false, entering = true, teamDamage = 950 }))
	T.eq(act, "stay", "killable: go in")
	T.eq(
		R.TowerChaseDecision(situation({ towerOnBot = false, entering = true, hasTarget = false })),
		nil,
		"no hero target: walking past a tower is no chase"
	)
	T.eq(R.TowerChaseDecision(situation({ towerOnBot = false, entering = true, pushing = true })), nil, "push mode")
end)

T.test("tower chase: the enemy heroes' damage counts in the survival check (game 063, Earth Spirit)", function()
	local R = rules()
	-- Killable target, 1200 HP, tower 150 a shot: 3 shots (450) alone are fine ...
	T.eq(R.TowerChaseDecision(situation({ teamDamage = 950, enemyDamage = 0 })), "stay", "tower only")
	-- ... but three heroes doing 800 on top are not.
	local act, why = R.TowerChaseDecision(situation({ teamDamage = 950, enemyDamage = 800 }))
	T.eq(act, "leave", "act")
	T.eq(why, "low-hp", "why")
end)

T.test("tower hold: walk out of range + 200, then on to + 350 before letting go", function()
	local R = rules()
	local run, inside = R.TowerHoldRun(850, 700, false)
	T.eq(run, true, "inside range + 200: run")
	T.eq(inside, true, "inside")
	run, inside = R.TowerHoldRun(960, 700, true)
	T.eq(run, true, "between + 200 and + 350 after being inside: keep walking")
	run, inside = R.TowerHoldRun(1060, 700, true)
	T.eq(run, false, "past + 350: free")
	T.eq(inside, false, "outside")
	run = R.TowerHoldRun(960, 700, false)
	T.eq(run, false, "between + 200 and + 350 coming from outside: free (no flip at the edge)")
end)

T.test("tower hold: a push pauses it, it resumes after (game 064, Alchemist at Dire's mid T1)", function()
	local R = rules()
	-- t=744 tower-entry-stop: hold until 753.
	local untilTime = 744 + R.HOLD_SECONDS
	T.eq(R.TowerHoldState(748, untilTime, true, false, nil), "keep", "t=748 attack mode, hold runs")
	-- t=750: one push-mode think. It used to clear the hold.
	T.eq(R.TowerHoldState(750, untilTime, true, true, nil), "pause", "t=750 push: pause")
	T.eq(R.TowerHoldState(750.5, untilTime, true, true, true), "pause", "still pushing: still paused")
	-- t=751: attack mode again, he walked back toward the tower: the hold is back (he was chase-stopped instead).
	T.eq(R.TowerHoldState(751, untilTime, true, false, true), "resume", "t=751 push over: resume")
	T.eq(R.TowerHoldState(751.5, untilTime, true, false, nil), "keep", "after the resume")
	-- Given an end time, 9s over is over (the caller freezes the end during a pause: TowerHoldPausedUntil).
	T.eq(R.TowerHoldState(754, untilTime, true, false, true), "expire", "9s over")
	T.eq(R.TowerHoldState(749, untilTime, false, true, nil), "expire", "tower gone")
	-- The retreat file pauses instead of clearing on a push.
	local src = T.read("bots/mode_retreat_generic.lua")
	T.ok(string.find(src, "DiveRules.TowerHoldState(", 1, true) ~= nil, "retreat uses TowerHoldState")
end)

T.test("tower chase: entering only when the bot can't hit the target from outside the tower's range", function()
	local R = rules()
	-- Tower range 700. Melee (150) after a target 500 from the tower: has to walk in (500 + 150 = 650).
	T.eq(R.MustEnterTowerRange(850, 500, 150, 700), true, "melee")
	-- Melee after a target 600 out: hits him from 750, just outside.
	T.eq(R.MustEnterTowerRange(850, 600, 150, 700), false, "melee at the edge")
	-- Ranged (600) after the same target: hits him from 1200 out, no entry.
	T.eq(R.MustEnterTowerRange(850, 600, 600, 700), false, "ranged from outside")
	-- Already inside the range: entering whatever the attack range.
	T.eq(R.MustEnterTowerRange(650, 600, 600, 700), true, "already inside")
end)

T.test("tower approach: dead on paper before the edge leaves there (game 065, 9 of 30 stops died)", function()
	local R = rules()
	local function approach(overrides)
		local s = { outerTower = true, pushing = false, approaching = true, botHealth = 1800, shotDamage = 148 }
		for key, value in pairs(overrides or {}) do
			s[key] = value
		end
		return s
	end
	-- Zeus t=2150 at Dire's top T2: 4 enemy heroes, enemyDmg 5905. Even at full HP that is death: stop before the edge.
	local act, why = R.TowerApproachDecision(approach({ enemyDamage = 5905 }))
	T.eq(act, "leave", "Zeus t=2150: leave")
	T.eq(why, "low-hp", "Zeus t=2150: why")
	-- Tiny t=1529 at Radiant's bottom T2 (enemyDmg 1629, 3 tower shots 363) with 1028 HP: leave.
	T.eq(R.TowerApproachDecision(approach({ botHealth = 1028, shotDamage = 121, enemyDamage = 1629 })), "leave", "Tiny")
	-- Healthy against one hero: no decision here, the edge rule decides later.
	T.eq(R.TowerApproachDecision(approach({ botHealth = 1800, enemyDamage = 400 })), nil, "healthy: no decision")
	-- Not approaching, a push, or a T3/T4: no decision.
	T.eq(R.TowerApproachDecision(approach({ approaching = false, enemyDamage = 5905 })), nil, "not approaching")
	T.eq(R.TowerApproachDecision(approach({ pushing = true, enemyDamage = 5905 })), nil, "push")
	T.eq(R.TowerApproachDecision(approach({ outerTower = false, enemyDamage = 5905 })), nil, "T3")
	-- After such a stop the hold zone is range + 600: at 1200 from a 700 tower the bot still walks out.
	T.eq(R.TowerHoldRun(1200, 700, true, R.APPROACH_MARGIN), true, "approach hold: 1200 still inside")
	T.eq(R.TowerHoldRun(1500, 700, true, R.APPROACH_MARGIN), false, "approach hold: 1500 out")
	T.eq(R.TowerHoldRun(1200, 700, true), false, "edge hold (default margin): 1200 out")
end)

T.test("tower hold: a team siege of the hold tower ends a no-target hold (game 065, Dark Willow)", function()
	local R = rules()
	local untilTime = 941 + R.HOLD_SECONDS
	-- t=944: Dark Willow pushes top, the hold tower is Radiant's top T1, 4 allies at it, the stop was no-target.
	T.eq(R.TowerHoldState(944, untilTime, true, true, nil, true, 4, "no-target"), "siege", "Dark Willow t=944")
	-- Game 064, Alchemist: the same siege but the stop was a chase (not-killable): still a pause, as before.
	T.eq(R.TowerHoldState(750, 744 + R.HOLD_SECONDS, true, true, nil, true, 4, "not-killable"), "pause", "Alchemist")
	-- A low-HP stop keeps the pause too (Nyx at the same siege, 43-50% HP).
	T.eq(R.TowerHoldState(944, untilTime, true, true, nil, true, 4, "low-hp"), "pause", "Nyx low-hp")
	-- Alone or one ally: no siege. Another lane's tower: no siege.
	T.eq(R.TowerHoldState(944, untilTime, true, true, nil, true, 1, "no-target"), "pause", "one ally")
	T.eq(R.TowerHoldState(944, untilTime, true, true, nil, false, 4, "no-target"), "pause", "other lane")
	-- Not pushing: the hold runs.
	T.eq(R.TowerHoldState(945, untilTime, true, false, nil, true, 4, "no-target"), "keep", "not pushing")
end)

T.test("tower hold: the retreat file checks a live hold ahead of the early NONE returns", function()
	local src = T.read("bots/mode_retreat_generic.lua")
	local earlyAt = string.find(src, "return RetreatTag(250, BOT_DESIRE_OVERRIDE * 1.1)", 1, true)
	local noneAt = string.find(src, "return RetreatTag(272, BOT_MODE_DESIRE_NONE)", 1, true)
	local pushAt = string.find(src, "return RetreatTag(254, BOT_MODE_DESIRE_NONE)", 1, true)
	T.ok(earlyAt ~= nil and noneAt ~= nil and pushAt ~= nil, "tags found")
	T.ok(earlyAt < pushAt and earlyAt < noneAt, "hold check before tags 254 and 272")
end)

T.test("tower hold: the clock stops during a pause (game 068, Clinkz at Radiant's mid T1, t=924-932)", function()
	local R = rules()
	-- Stop at t=919.5 (9s hold, ends 928.5); a push pauses it at t=924 with left=4.0.
	local startTime = 919.5
	local remaining, floored = R.TowerHoldPauseLeft(4.0, nil)
	T.near(remaining, 4.0, 0.01, "4s left kept")
	T.eq(floored, nil, "4s left: no floor")
	T.near(R.TowerHoldPausedUntil(926, remaining, startTime), 930, 0.01, "t=926 still paused: the end moves")
	-- t=928 resume: the hold has its 4s back, so it does not run out at t=929 inside the zone.
	local untilTime = R.TowerHoldPausedUntil(928, remaining, startTime)
	T.near(untilTime, 932, 0.01, "t=928 resume: hold until 932")
	T.eq(R.TowerHoldState(929, untilTime, true, false, nil), "keep", "t=929 not expired")
	T.eq(R.TowerHoldState(932.5, untilTime, true, false, nil), "expire", "t=932.5 over")
end)

T.test("tower hold: the 2s floor once per hold, kept over many paused checks; a 30s cap from the stop", function()
	local R = rules()
	-- Undying: paused at t=928 with 0.3s left. Several paused checks, then the resume: still 2s.
	local remaining, floored = R.TowerHoldPauseLeft(0.3, nil)
	T.near(remaining, 2, 0.01, "floor 2s")
	T.eq(floored, true, "floor used")
	local untilTime
	for _, now in ipairs({ 928.3, 928.6, 929.0, 929.4 }) do
		untilTime = R.TowerHoldPausedUntil(now, remaining, 920)
	end
	T.near(untilTime - 929.4, 2, 0.01, "resume after 4 paused checks: 2s left")
	-- A second pause in the same hold with 0.5s left: no second floor.
	remaining, floored = R.TowerHoldPauseLeft(0.5, floored)
	T.near(remaining, 0.5, 0.01, "second pause: no second floor")
	T.eq(floored, true, "still floored")
	-- A long push: the frozen clock never goes past stop + HOLD_MAX_AGE.
	untilTime = R.TowerHoldPausedUntil(960, 5, 920)
	T.near(untilTime, 920 + R.HOLD_MAX_AGE, 0.01, "capped")
	T.eq(R.TowerHoldState(960, untilTime, true, true, true), "expire", "past the cap: expire even while pushing")
end)

T.test("tower hold end: death, fell, expire, unseen (game 068)", function()
	local R = rules()
	-- Puck: stopped t=809, dead t=812, the first check after the respawn at t=848 (left=-30.3, tower out of sight).
	T.eq(R.TowerHoldEnd({ died = true, invalidFor = 4, fell = false, expired = true }), "death", "Puck 848")
	-- Puck / Zeus t=1080-1081: Dire's mid T1 fell at t=1078 with them at it.
	T.eq(R.TowerHoldEnd({ invalidFor = 2.5, fell = true, expired = true, insideZone = true }), "invalid", "fell")
	T.eq(R.TowerHoldEnd({ invalidFor = 1, fell = true, expired = false, insideZone = true }), nil, "fell <2s: grace")
	-- Zeus t=813: Dire's mid T1 stood (fell at t=1078), out of vision with Zeus 2239 away, 4.3s left.
	T.eq(R.TowerHoldEnd({ invalidFor = 2.5, fell = false, expired = false, insideZone = false }), "unseen", "Zeus 813")
	-- Out of sight with the bot inside the zone (night): the hold goes on at the stored spot.
	T.eq(R.TowerHoldEnd({ invalidFor = 5, fell = false, expired = false, insideZone = true }), nil, "unseen inside")
	-- Out of sight, the time over and the bot out of the zone: plain expire.
	T.eq(R.TowerHoldEnd({ invalidFor = 5, fell = false, expired = true, outOfZone = true }), "expire", "expire")
	T.eq(R.TowerHoldEnd({ expired = false, insideZone = true }), nil, "valid tower, time left")
end)

T.test("tower hold end: the time alone doesn't end it inside the zone; the 20s cap does (game 069)", function()
	local R = rules()
	-- Alchemist t=759: 11.3s after the stop, left=-0.3, dist=848 of a 900 zone: the hold goes on.
	T.eq(R.TowerHoldEnd({ age = 11.3, expired = true, outOfZone = false, insideZone = true }), nil, "Alchemist 759")
	-- Zeus t=761: dist=696 (inside), dead 2s later: goes on.
	T.eq(R.TowerHoldEnd({ age = 13.4, expired = true, outOfZone = false, insideZone = true }), nil, "Zeus 761")
	-- Walked out past zone + HOLD_EXPIRE_OUT: expire.
	T.eq(R.TowerHoldEnd({ age = 12, expired = true, outOfZone = true }), "expire", "out of the zone")
	-- Still inside after the cap: it ends anyway (the longest game 069 hold was 18.4s).
	T.eq(R.HOLD_MAX_AGE, 20, "cap 20s")
	T.eq(R.TowerHoldEnd({ age = 20.5, expired = true, outOfZone = false, insideZone = true }), "cap", "cap")
	T.eq(R.TowerHoldEnd({ age = 21, died = true }), "death", "death first")
end)

T.test("high-ground chase: stop outnumbered at a standing T3, keep the 33:30 chase (game 069)", function()
	local R = rules()
	-- 22:48-23:11: Alchemist and Axe after Undying past Dire's mid T2 toward the T3; 1 Dire hero dead, the 4 alive
	-- near (Phantom Assassin, Io, Undying, Nyx), the rest of Radiant at Roshan. Undying's HP is not in the log: a
	-- healthy target our 2s damage doesn't kill (illustrative numbers).
	local early = {
		highGround = true,
		pushing = false,
		approaching = true,
		responders = 4,
		chasers = 2,
		enemiesDead = 1,
		teamDamage = 600,
		targetHealth = 1500,
	}
	local act, why = R.HighGroundChaseDecision(early)
	T.eq(act, "leave", "22:48 stop")
	T.eq(why, "outnumbered", "why")
	-- 33:30-33:42: Dark Willow and Io dead, the 3 Dire heroes left near, Alchemist, Axe and Puck on the chase;
	-- Undying and Nyx low (46% / 53% 3.5s before they died).
	local late = {
		highGround = true,
		pushing = false,
		approaching = true,
		responders = 3,
		chasers = 3,
		enemiesDead = 2,
		teamDamage = 600,
		targetHealth = 900,
	}
	T.eq(R.HighGroundChaseDecision(late), nil, "33:30 goes")
	-- Each allowance alone lets it go.
	late.chasers, late.enemiesDead = 2, 2
	T.eq(R.HighGroundChaseDecision(late), nil, "advantage window (2 dead) alone")
	late.enemiesDead, late.chasers = 1, 3
	T.eq(R.HighGroundChaseDecision(late), nil, "ours >= responders alone")
	early.teamDamage = 1600
	T.eq(R.HighGroundChaseDecision(early), nil, "the target dies first")
	early.teamDamage = 600
	early.pushing = true
	T.eq(R.HighGroundChaseDecision(early), nil, "push mode: no decision")
	early.pushing, early.highGround = false, false
	T.eq(R.HighGroundChaseDecision(early), nil, "no standing T3")
end)

T.test("walk home from behind an enemy tower: behind test, start and stop (game 072, Puck at Dire's mid T2)", function()
	local R = rules()
	-- Radiant's fountain near (-7000, -6500); Dire's mid T2 at (2593, 2170) (game 069 log), range 700.
	local home = { x = -7000, y = -6500 }
	local tower = { x = 2593, y = 2170 }
	local ring = 700 + R.DETOUR_RING_MARGIN
	local function dist(a, b)
		return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
	end
	local function situation(at)
		return {
			botHome = dist(at, home),
			towerHome = dist(tower, home),
			crosses = R.SegmentNearPoint(at.x, at.y, home.x, home.y, tower.x, tower.y, ring),
		}
	end
	-- Puck after the kill, behind the T2 toward their high ground: the lane walk home goes through its range.
	local behind = situation({ x = 3300, y = 2900 })
	T.eq(R.BehindTower(behind), true, "behind the T2")
	-- In front of it (between the tower and home): no detour.
	T.eq(R.BehindTower(situation({ x = 1500, y = 1100 })), false, "in front")
	-- Beside it, far off the line home (the way home doesn't cross the range): no detour.
	T.eq(R.BehindTower(situation({ x = 4800, y = -1500 })), false, "way home clear")
	behind.headingHome, behind.fight, behind.cooldown, behind.chasing = true, false, false, false
	T.eq(R.HomeDetourStart(behind), true, "start: retreating home")
	behind.fight = true
	T.eq(R.HomeDetourStart(behind), false, "a fight: no start")
	behind.fight, behind.chasing = false, true
	T.eq(R.HomeDetourStart(behind), false, "a chase toward our side: no start")
	behind.chasing, behind.headingHome = false, false
	T.eq(R.HomeDetourStart(behind), false, "not heading home: no start")
	behind.headingHome, behind.cooldown = true, true
	T.eq(R.HomeDetourStart(behind), false, "cooldown")
	-- Stop: past the tower, a fight, the time, the last waypoint.
	local running = situation({ x = 3300, y = 2900 })
	running.age = 3
	T.eq(R.HomeDetourStop(running), nil, "still behind: go on")
	local past = situation({ x = 1200, y = 2600 })
	past.age = 6
	T.eq(R.HomeDetourStop(past), "past", "round it and nearer home")
	running.fight = true
	T.eq(R.HomeDetourStop(running), "fight", "fight")
	running.fight, running.age = false, R.DETOUR_MAX_SECONDS + 1
	T.eq(R.HomeDetourStop(running), "timeout", "timeout")
	running.age, running.done = 4, true
	T.eq(R.HomeDetourStop(running), "done", "last waypoint")
	T.eq(R.HomeDetourStop({ dead = true }), "dead", "dead")
	-- A path round the tower (through their jungle side) avoids the range; the lane walk doesn't.
	local round = { { x = 3600, y = 1500 }, { x = 3000, y = 900 }, { x = 1800, y = 1000 }, { x = 0, y = -200 } }
	T.eq(R.PathAvoids(3300, 2900, round, tower.x, tower.y, 700), true, "round path")
	local lane = { { x = 2600, y = 2200 }, { x = 0, y = -200 } }
	T.eq(R.PathAvoids(3300, 2900, lane, tower.x, tower.y, 700), false, "lane path crosses")
	T.eq(R.PathAvoids(3300, 2900, {}, tower.x, tower.y, 700), true, "empty path (the caller rejects it)")
end)

-- One hold check as mode_retreat_generic.lua TowerHoldCheck runs it (run first, then the state), on a 700-range tower
-- with the edge margin (zone 900). hold.finish: the team finish is on (DiveRules.TeamFinish; the latch is off while
-- it is). Returns the state and whether the bot runs.
local function holdStep(R, hold, now, dist, pushing)
	local latched = hold.latched == true and not hold.finish
	local run, inside, entered = R.TowerHoldRun(dist, 700, hold.inside, nil, latched)
	local state = R.TowerHoldState(now, hold.untilTime, true, pushing, hold.paused, false, 0, hold.why, latched)
	if state == "pause" then
		hold.paused = true
		return state, false
	end
	hold.paused, hold.inside = nil, inside
	if entered and not hold.finish then
		hold.latched = true
	end
	return state, run
end

T.test("tower hold: a re-entry latches the run, no flip at the edge (game 087, Zeus at Radiant's bottom T1)", function()
	local R = rules()
	-- t=948 tower-entry-stop at 884 (chasing Lion): the stop's own run.
	local hold = { inside = true, untilTime = 948 + R.HOLD_SECONDS, why = "not-killable" }
	local state, run = holdStep(R, hold, 948.2, 884, false)
	T.eq(run, true, "t=948 inside: run")
	T.eq(hold.latched, nil, "the stop's own run does not latch")
	state, run = holdStep(R, hold, 948.6, 1060, false)
	T.eq(run, false, "past + 350: free")
	-- t=949 push 0.34 at 1136: pause (out of the zone).
	state = holdStep(R, hold, 949.0, 1136, true)
	T.eq(state, "pause", "t=949 push out of the zone: pause")
	-- t=949 attack (0.95) at 1021: the resume, out of the zone, no run.
	state, run = holdStep(R, hold, 949.5, 1021, false)
	T.eq(state, "resume", "t=949 attack: resume")
	T.eq(run, false, "1021, coming from outside: free")
	-- Attack walks him back in: the re-entry runs and latches.
	state, run = holdStep(R, hold, 950.5, 890, false)
	T.eq(run, true, "back at 890: run")
	T.eq(hold.latched, true, "re-entry latches")
	-- The latched run has no distance release ...
	state, run = holdStep(R, hold, 952, 1100, false)
	T.eq(run, true, "1100 (past + 350): still runs")
	state, run = holdStep(R, hold, 954, 1700, false)
	T.eq(run, true, "1700: still runs")
	-- ... and no push pause: t=956 push 0.91 used to take over here (push>attack>retreat>push>attack>retreat>push).
	state, run = holdStep(R, hold, 956, 1700, true)
	T.eq(state, "keep", "t=956 push: no pause on a latched hold")
	T.eq(run, true, "t=956: runs")
	-- The end stays TowerHoldEnd's: time over and out of the zone.
	T.eq(R.TowerHoldEnd({ expired = true, outOfZone = true, age = 9.1 }), "expire", "9s over, out: ends")
end)

T.test("tower hold: a resume inside the zone after a push latches (game 087, Zeus at Radiant's mid T1)", function()
	local R = rules()
	local hold = { inside = true, untilTime = 1027 + R.HOLD_SECONDS, why = "not-killable" }
	-- t=1027 stop at 478: run out.
	local state, run = holdStep(R, hold, 1027.3, 478, false)
	T.eq(run, true, "t=1027: run")
	state, run = holdStep(R, hold, 1029.5, 1060, false)
	T.eq(run, false, "out")
	-- t=1030 push at 1099: pause.
	state = holdStep(R, hold, 1030.0, 1099, true)
	T.eq(state, "pause", "t=1030 push at 1099: pause")
	-- The push walks him into the zone: still paused (a push steps out of tower aggro itself; game 064, Alchemist).
	state = holdStep(R, hold, 1030.3, 860, true)
	T.eq(state, "pause", "push inside the zone: still paused")
	T.eq(hold.latched, nil, "no latch during the pause")
	-- The push drops (push-gate cannot-push), team roam has him at 882: the resume is a re-entry and latches.
	state, run = holdStep(R, hold, 1030.6, 882, false)
	T.eq(state, "resume", "team roam: resume")
	T.eq(run, true, "882 of 900: run")
	T.eq(hold.latched, true, "latched")
	-- t=1031 push 0.90 again, team roam (help-core) at 1033: the latched hold keeps running, no new pause.
	state, run = holdStep(R, hold, 1031, 1080, true)
	T.eq(state, "keep", "t=1031 push: no pause")
	T.eq(run, true, "t=1031: runs")
	state, run = holdStep(R, hold, 1033, 1250, false)
	T.eq(run, true, "t=1033 team roam: runs")
	-- The old callers (no mustRun) keep the old rule: a push always pauses.
	T.eq(R.TowerHoldState(1031, hold.untilTime, true, true, nil, false, 0, "not-killable"), "pause", "nil: pause")
	-- A team siege of a no-target hold still ends it, inside the zone too.
	T.eq(R.TowerHoldState(1031, hold.untilTime, true, true, nil, true, 4, "no-target", true), "siege", "siege")
	-- The retreat file runs the hold first and passes it to the state, and latches on a re-entry.
	local src = T.read("bots/mode_retreat_generic.lua")
	T.ok(string.find(src, "hold.why,%s+holdLatched%s+%)") ~= nil, "TowerHoldState gets the latch")
	T.ok(string.find(src, "hold.latched = true", 1, true) ~= nil, "re-entry latches")
end)

T.test(
	"team finish: 3 other healthy allies at the tower, and the bot healthy or creeps in range (decision D9)",
	function()
		local R = rules()
		T.eq(R.FINISH_ALLIES, 3, "3 allies")
		T.eq(R.FINISH_HEALTHY_HP, 0.6, "healthy = the push tower-step-out line")
		-- The threshold: 3 other allies turn it on, 2 do not (fresh, nothing held before).
		T.eq((R.TeamFinish(3, true, false, 950, nil)), true, "3 healthy allies, healthy bot: on")
		T.eq((R.TeamFinish(4, true, true, 950, nil)), true, "4 allies: on")
		T.eq((R.TeamFinish(2, true, true, 950, nil)), false, "2 allies: off")
		T.eq((R.TeamFinish(0, true, true, 950, nil)), false, "no allies: off")
		T.eq((R.TeamFinish(nil, true, true, 950, nil)), false, "nil count: off")
		-- The bot is not counted: the caller counts the others, so the bot plus 2 allies (3 heroes) is still 2.
		T.eq((R.TeamFinish(2, true, true, 950, nil)), false, "bot + 2 allies: off")
		-- An unhealthy bot: on only with allied creeps in the tower's range to take its aggro.
		T.eq((R.TeamFinish(4, false, true, 950, nil)), true, "unhealthy bot, creeps in range: on")
		T.eq((R.TeamFinish(4, false, false, 950, nil)), false, "unhealthy bot, no creeps: off (stay away)")
		-- The full rule stores the time; the result is the new fullAt.
		local on, fullAt = R.TeamFinish(3, true, false, 950, nil)
		T.eq(on, true, "on")
		T.eq(fullAt, 950, "fullAt = now")
		on, fullAt = R.TeamFinish(2, true, false, 950, nil)
		T.eq(fullAt, nil, "off: no fullAt")
	end
)

T.test("team finish: hysteresis - stays on at 2 allies for 2s, ends below 2 or without cover at once", function()
	local R = rules()
	T.eq(R.FINISH_KEEP_ALLIES, 2, "keep at 2")
	T.eq(R.FINISH_KEEP_SECONDS, 2, "for 2s")
	-- On at t=950 with 3; one ally steps out past 1200 at t=951: still on (no latch flip), the time stays 950.
	local on, fullAt = R.TeamFinish(3, true, false, 950, nil)
	on, fullAt = R.TeamFinish(2, true, false, 951, fullAt)
	T.eq(on, true, "t=951, 2 allies: still on")
	T.eq(fullAt, 950, "the last full time is kept")
	-- Back to 3 at t=951.5: on, and the time moves.
	on, fullAt = R.TeamFinish(3, true, false, 951.5, fullAt)
	T.eq(fullAt, 951.5, "t=951.5 back at 3")
	-- 2 allies for more than 2s after the last full check: off.
	on, fullAt = R.TeamFinish(2, true, false, 953.4, fullAt)
	T.eq(on, true, "t=953.4: 1.9s at 2, on")
	on, fullAt = R.TeamFinish(2, true, false, 953.6, fullAt)
	T.eq(on, false, "t=953.6: 2.1s at 2, off")
	T.eq(fullAt, nil, "off clears the time")
	-- Once off, 2 allies do not turn it on again: it needs 3.
	on = R.TeamFinish(2, true, false, 953.7, fullAt)
	T.eq(on, false, "off, 2 allies: stays off")
	-- Below 2 it ends at once, inside the 2s too.
	on, fullAt = R.TeamFinish(3, true, false, 960, nil)
	on, fullAt = R.TeamFinish(1, true, false, 960.5, fullAt)
	T.eq(on, false, "1 ally: off at once")
	-- The bot's cover has no grace: unhealthy with no creeps ends it at once, even with 4 allies.
	on, fullAt = R.TeamFinish(4, true, false, 970, nil)
	on, fullAt = R.TeamFinish(4, false, false, 970.5, fullAt)
	T.eq(on, false, "bot under 60%, no creeps: off at once")
	-- ... and an unhealthy bot inside the 2s at 2 allies keeps it only with creeps.
	on, fullAt = R.TeamFinish(3, false, true, 980, nil)
	on = R.TeamFinish(2, false, true, 981, fullAt)
	T.eq(on, true, "unhealthy, creeps, 2 allies inside 2s: on")
end)

T.test("tower hold: the team finish turns the latch off (decision D9, game 087 Zeus at Radiant's bottom T1)", function()
	local R = rules()
	-- Zeus's bottom T1 hold with 4 allies there: the re-entry does not latch, and the push pauses the hold.
	local hold = { inside = true, untilTime = 948 + R.HOLD_SECONDS, why = "not-killable", finish = true }
	local state, run = holdStep(R, hold, 948.2, 884, false)
	T.eq(run, true, "t=948 the stop's own run")
	state, run = holdStep(R, hold, 948.6, 1060, false)
	T.eq(run, false, "out")
	state, run = holdStep(R, hold, 950.5, 890, false)
	T.eq(run, true, "re-entry at 890 still runs (unlatched hold, not pushing)")
	T.eq(hold.latched, nil, "finish on: the re-entry does not latch")
	state = holdStep(R, hold, 951, 890, true)
	T.eq(state, "pause", "push with the team: the hold pauses")
	-- A hold latched before the finish turned on acts unlatched: the push pauses it again.
	local latched = { inside = true, untilTime = 948 + R.HOLD_SECONDS, why = "not-killable", latched = true }
	state, run = holdStep(R, latched, 952, 1700, false)
	T.eq(run, true, "latched, finish off: runs at 1700")
	latched.finish = true
	state = holdStep(R, latched, 953, 1100, true)
	T.eq(state, "pause", "latched, finish on: the push pauses it")
	T.eq(latched.latched, true, "the stored latch stays")
	-- The finish ends (allies left): the latch rule applies again, no pause.
	latched.finish = nil
	state, run = holdStep(R, latched, 954, 1100, true)
	T.eq(state, "resume", "finish off: the latched hold resumes")
	T.eq(run, true, "and runs")
	state, run = holdStep(R, latched, 954.5, 1100, true)
	T.eq(state, "keep", "push: no pause on the latched hold")
	-- The retreat file reads the finish on every check, ahead of the end checks, and gates the latch on it.
	local src = T.read("bots/mode_retreat_generic.lua")
	local finishAt =
		string.find(src, "DiveRules.TeamFinish(healthy, botHealthy, creeps, now, hold.finishFullAt)", 1, true)
	local endAt = string.find(src, "local endWhy = DiveRules.TowerHoldEnd(", 1, true)
	T.ok(finishAt ~= nil and endAt ~= nil and finishAt < endAt, "finish read before the end checks")
	T.ok(string.find(src, "local holdLatched = hold.latched == true and not hold.finish", 1, true) ~= nil, "latch gate")
	T.ok(string.find(src, "if entered and not hold.finish then", 1, true) ~= nil, "no latch while finish is on")
	T.ok(string.find(src, "tower-hold-finish on=%d healthy=%d", 1, true) ~= nil, "finish line")
end)
