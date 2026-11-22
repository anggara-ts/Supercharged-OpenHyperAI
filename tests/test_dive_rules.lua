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
