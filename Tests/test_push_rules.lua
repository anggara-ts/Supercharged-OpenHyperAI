-- FuncLib/systems/push_rules.lua: advantage window, the all-alive push cap, Roshan over push, respawn estimate;
-- and FuncLib/systems/kill_window.lua learning respawn times from our own deaths (#12).
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/push_rules")
end

T.test("advantage: Aegis and dead enemies open the window, a base threat closes it", function()
	local R = rules()
	-- Game 066 21:44: Dire held the Aegis, 5 alive each.
	local desire, why = R.Advantage({ aegis = true, alliesAlive = 5, enemiesAlive = 5, dead = 0, deadLong = 0 })
	T.eq(desire, 0.8, "aegis desire")
	T.eq(why, "aegis", "aegis why")
	-- Aegis with only 3 alive: no window.
	T.eq(R.Advantage({ aegis = true, alliesAlive = 3, enemiesAlive = 5, dead = 0, deadLong = 0 }), nil, "aegis 3 alive")
	-- Three dead for 20s+: 0.9.
	desire, why = R.Advantage({ alliesAlive = 4, enemiesAlive = 2, dead = 3, deadLong = 3 })
	T.eq(desire, 0.9, "dead3 desire")
	T.eq(why, "dead3", "dead3 why")
	-- Two dead with 4-5 of ours alive: 0.8; with 3 of ours alive: no window.
	T.eq(R.Advantage({ alliesAlive = 4, enemiesAlive = 3, dead = 2, deadLong = 0 }), 0.8, "dead2 with 4")
	T.eq(R.Advantage({ alliesAlive = 3, enemiesAlive = 3, dead = 2, deadLong = 2 }), nil, "dead2 with 3")
	-- Every enemy dead (#87's wipe push).
	T.eq(select(2, R.Advantage({ alliesAlive = 2, enemiesAlive = 0, dead = 5, deadLong = 5 })), "wipe", "wipe")
	-- Aegis on top of a dead window.
	desire, why = R.Advantage({ aegis = true, alliesAlive = 5, enemiesAlive = 3, dead = 2, deadLong = 1 })
	T.eq(desire, 0.85, "dead2+aegis desire")
	T.eq(why, "dead2+aegis", "dead2+aegis why")
	-- Our base is being hit: nothing.
	T.eq(
		R.Advantage({ aegis = true, alliesAlive = 5, enemiesAlive = 0, dead = 5, deadLong = 5, baseThreat = true }),
		nil,
		"base threat"
	)
end)

T.test("five-alive cap: 0.41 for an even game, joiners when ahead or at a T1/T2", function()
	local R = rules()
	-- Game 067 33:00: Radiant mid T1 (tier 1), 5 alive each, about even.
	local cap, joiners, why =
		R.FiveAliveCap({ enemiesAlive = 5, alliesAlive = 5, nwLead = -500, levelLead = 0.2, tier = 1 })
	T.eq(cap, 0.7, "outer cap")
	T.eq(joiners, 3, "outer joiners")
	T.eq(why, "outer", "outer why")
	cap, joiners = R.FiveAliveCap({ enemiesAlive = 5, alliesAlive = 5, nwLead = 2500, levelLead = 0, tier = 2 })
	T.eq(cap, 0.75, "ahead+outer cap")
	T.eq(joiners, 4, "ahead+outer joiners")
	cap, joiners = R.FiveAliveCap({ enemiesAlive = 5, alliesAlive = 5, nwLead = 0, levelLead = 1.2, tier = 3 })
	T.eq(cap, 0.7, "ahead at the high ground")
	T.eq(joiners, 3, "ahead at the high ground joiners")
	cap, joiners, why = R.FiveAliveCap({ enemiesAlive = 5, alliesAlive = 5, nwLead = 0, levelLead = 0, tier = 3 })
	T.eq(cap, 0.41, "even high ground cap")
	T.eq(joiners, 2, "even high ground joiners")
	T.eq(why, "even", "even why")
	-- An enemy dead: the cap is off.
	T.eq(R.FiveAliveCap({ enemiesAlive = 4, alliesAlive = 5, tier = 3 }), nil, "4 alive")
end)

T.test("Roshan over push: a live call wins unless the tower is about to fall", function()
	local R = rules()
	-- Game 067 32:11: 0.99 kill push, the call now goes in at 0.96.
	local desire, yielded = R.PushUnderRosh(0.99, 0.96, 0.1, false)
	T.near(desire, 0.91, 1e-9, "push under the call")
	T.eq(yielded, true, "yielded")
	T.eq(select(2, R.PushUnderRosh(0.99, 0.96, 0.1, true)), false, "finishing a tower")
	T.eq(select(2, R.PushUnderRosh(0.99, 0.96, 3.0, false)), false, "stale Roshan desire")
	T.eq(select(2, R.PushUnderRosh(0.99, 0.3, 0.1, false)), false, "call off")
	-- A plain 0.60 call (held back on the high ground, or a timer call) does not cut a 0.99 push.
	T.eq(select(2, R.PushUnderRosh(0.99, 0.60, 0.1, false)), false, "0.60 call")
	T.eq(R.PushUnderRosh(0.4, 0.6, 0.1, false), 0.4, "push already lower")
end)

T.test("lock branch with every enemy dead: the wipe push goes at 0.9 through the lock", function()
	local R = rules()
	-- Game 067 t=1376: Dire bots in the mid lock, all five Radiant dead, `lock-capped why=cap desire=0.25 alive=4/0`
	-- and no wipe push. Now the own-HP cap starts at 30% in a wipe, and the lock raises to the window.
	T.eq(R.OwnHpCapBelow(true), 0.3, "wipe HP floor")
	T.eq(R.OwnHpCapBelow(false), 0.5, "normal HP floor")
	local wipe = R.Advantage({ alliesAlive = 4, enemiesAlive = 0, dead = 5, deadLong = 5 })
	local desire, cap, raised = R.LockDesire({
		base = 0.55,
		advantage = wipe,
		maxPush = wipe,
		alliesNear = 2,
		enemiesNear = 0,
		enemiesAlive = 0,
		tier = 3,
		nearAncient = true,
		groupHurt = true,
	})
	T.eq(desire, 0.9, "wipe desire in the lock")
	T.eq(cap, nil, "no cap: group-hurt and fewer-than-alive skipped")
	T.eq(raised, "advantage", "raised")
	-- The same bot under 30%: maxPush holds the 0.25 cap.
	desire, cap = R.LockDesire({ base = 0.55, advantage = wipe, maxPush = 0.25, alliesNear = 2, enemiesAlive = 0 })
	T.eq(desire, 0.25, "low HP still capped")
	T.eq(cap, "cap", "cap reason")
end)

T.test("lock branch: the old caps still hold without a window", function()
	local R = rules()
	-- 5 alive each, 3 bots at a T2 within 6000 of the Ancient, no window: fewer-than-alive 0.4.
	local desire, cap = R.LockDesire({
		base = 0.55,
		maxPush = 0.41,
		alliesNear = 3,
		enemiesNear = 0,
		enemiesAlive = 5,
		tier = 2,
		nearAncient = true,
	})
	T.eq(desire, 0.4, "fewer-than-alive")
	T.eq(cap, "fewer-than-alive", "reason")
	-- A joiner (ahead, T2) is past it below the high ground.
	desire, cap = R.LockDesire({
		base = 0.55,
		joinCap = 0.75,
		maxPush = 0.75,
		alliesNear = 3,
		enemiesAlive = 5,
		tier = 2,
		nearAncient = true,
	})
	T.eq(desire, 0.75, "joiner at a T2")
	T.eq(cap, nil, "joiner no cap")
	-- Alone against two, and a hurt group with enemies alive.
	T.eq(
		R.LockDesire({ base = 0.55, advantage = 0.9, maxPush = 0.9, alliesNear = 1, enemiesNear = 2 }),
		0.2,
		"alone-vs-2"
	)
	T.eq(
		R.LockDesire({ base = 0.55, maxPush = 0.65, alliesNear = 3, enemiesAlive = 2, groupHurt = true }),
		0.15,
		"group-hurt"
	)
end)

T.test("respawn estimate: nearest learned level, else the default", function()
	local R = rules()
	T.eq(R.RespawnEstimate({}, 14, 30), 30, "nothing learned")
	T.eq(R.RespawnEstimate({ [12] = 44, [20] = 70 }, nil, 30), 30, "no level")
	T.eq(R.RespawnEstimate({ [12] = 44, [20] = 70 }, 13, 30), 44, "nearest below")
	T.eq(R.RespawnEstimate({ [12] = 44, [20] = 70 }, 18, 30), 70, "nearest above")
	T.eq(R.RespawnEstimate({ [12] = 44, [14] = 52 }, 13, 30), 52, "tie takes the higher level")
	-- Only an early sample (level 3, 14s) for a level-20 enemy: not under the 30s default.
	T.eq(R.RespawnEstimate({ [3] = 14 }, 20, 30), 30, "lower sample floored")
	T.eq(R.RespawnEstimate({ [25] = 20 }, 20, 30), 20, "higher sample as is")
	local seconds, source, level = R.RespawnEstimate({ [25] = 100 }, 25, 30)
	T.eq(seconds, 100, "exact")
	T.eq(source, "learned", "source")
	T.eq(level, 25, "level used")
end)

T.test("kill window: an enemy death uses the respawn time our own death at that level showed", function()
	T.stub.reset({ hero = "npc_dota_hero_lich", time = 1800 })
	local KillWindow = require(GetScriptDirectory() .. "/FuncLib/systems/kill_window")
	KillWindow.Tick()
	-- Our slot 2 dies at level 14; GetRespawnTime() says 52.
	local ally = GetTeamMember(2)
	ally._level = 14
	ally.GetRespawnTime = function()
		return 52
	end
	ally._alive = false
	T.stub.time = 1810
	KillWindow.Tick()
	-- An enemy at level 14 dies: no API answer on enemies, so 52 from what we learned.
	local enemy = T.stub.teams[GetOpposingTeam()][1]
	enemy._level = 14
	enemy._alive = false
	T.stub.time = 1900
	KillWindow.Tick()
	local dead, deadLong, minLeft = KillWindow.DeadCounts()
	T.eq(dead, 1, "one dead")
	T.eq(deadLong, 1, "20s+ left")
	T.near(minLeft, 52, 0.01, "left")
	T.stub.time = 1940
	dead, deadLong = KillWindow.DeadCounts()
	T.eq(dead, 1, "still dead at 40s")
	T.eq(deadLong, 0, "under 20s left")
	local logged = false
	for _, line in ipairs(T.stub.printed) do
		if string.find(tostring(line), "src=learned", 1, true) then
			logged = true
		end
	end
	T.ok(logged, "death line names the learned source")
end)

T.test("fewer-than-alive: an open Ancient and a lead count the enemies seen near (game 068 50:33)", function()
	local R = rules()
	-- Game 068 t=3033-3061: four Dire at Radiant's open Ancient, 18k ahead, no Radiant hero near, five alive.
	local inputs = {
		base = 0.55,
		joinCap = 0.7,
		maxPush = 0.7,
		alliesNear = 4,
		enemiesNear = 0,
		enemiesAlive = 5,
		tier = 4,
		nearAncient = true,
	}
	local desire, cap = R.LockDesire(inputs)
	T.eq(cap, "fewer-than-alive", "T4s up or even: still capped")
	T.eq(desire, 0.4, "capped desire")
	inputs.ancientOpen, inputs.ahead = true, true
	desire, cap = R.LockDesire(inputs)
	T.eq(cap, nil, "open Ancient + lead: no cap")
	T.eq(desire, 0.7, "joiner desire")
	-- Open Ancient but not ahead: the enemies alive count.
	inputs.ahead = false
	T.eq(select(2, R.LockDesire(inputs)), "fewer-than-alive", "open, not ahead")
	-- Open and ahead, but 5 enemies seen near: capped.
	inputs.ahead, inputs.enemiesNear = true, 5
	T.eq(select(2, R.LockDesire(inputs)), "fewer-than-alive", "enemies seen near")
	T.eq(R.FewerThanAliveCount(true, true, 5, 1), 1, "count: seen near")
	T.eq(R.FewerThanAliveCount(true, false, 5, 1), 5, "count: alive")
end)

T.test("high-ground gather: an allowed group waits below the high ground, then goes up (game 068 52:33)", function()
	local R = rules()
	-- Game 068 t=3153: Undying, joiner 1 of 3, alone near Radiant's open base, 5v5 alive.
	local s = {
		nearEnemyFountain = true,
		enemiesAlive = 5,
		alliesAlive = 5,
		alliesNear = 1,
		atSpot = 1,
		need = 3,
		groupAllowed = true,
	}
	T.eq(R.HgGather(s), "gather", "joiner alone: gather")
	s.atSpot = 3
	T.eq(R.HgGather(s), "go", "3 at the spot: go")
	s.atSpot, s.alliesNear = 1, 3
	T.eq(R.HgGather(s), "go", "3 near the bot: go")
	s.alliesNear, s.released = 1, true
	T.eq(R.HgGather(s), "go", "latched release while walking up")
	s.released = nil
	s.groupAllowed = false
	T.eq(R.HgGather(s), "cap", "not an allowed group: the 0.15 cap")
	s.groupAllowed, s.gatherAge = true, 50
	T.eq(R.HgGather(s), "cap", "gave up after 45s")
	s.gatherAge, s.coolDown = 0, true
	T.eq(R.HgGather(s), "cap", "cooling down")
	s.coolDown, s.atSpot = nil, nil
	T.eq(R.HgGather(s), "cap", "no spot found")
	s.atSpot, s.alliesAlive = 1, 4
	T.eq(R.HgGather(s), "cap", "fewer alive than them")
	s.enemiesAlive = 0
	T.eq(R.HgGather(s), "none", "every enemy dead: no high-ground cap")
	T.eq(R.HgGather({ nearEnemyFountain = false }), "none", "not near their fountain")
end)

T.test("own-HP cap: 40% in a dead-enemies window with no enemy near, 5% hysteresis (game 068 2331-2376)", function()
	local R = rules()
	T.eq(R.OwnHpCap({}), 0.5, "normal")
	T.eq(R.OwnHpCap({ wipe = true }), 0.3, "wipe")
	T.eq(R.OwnHpCap({ deadWindow = true, enemiesNear = 0 }), 0.4, "dead window, nobody near")
	T.eq(R.OwnHpCap({ deadWindow = true, enemiesNear = 1 }), 0.5, "dead window, an enemy near")
	T.near(R.OwnHpCap({ wasCapped = true }), 0.55, 1e-9, "capped lets go at 55%")
	T.near(R.OwnHpCap({ deadWindow = true, enemiesNear = 0, wasCapped = true }), 0.45, 1e-9, "dead window capped")
end)

T.test("creep pressure: tier 3+ lanes with our wave at the target, +0.1 per lane up to +0.2", function()
	local R = rules()
	T.ok(R.LaneUnderPressure(3, 900, 4), "wave at their T3")
	T.ok(not R.LaneUnderPressure(2, 500, 4), "T2 still up")
	T.ok(not R.LaneUnderPressure(3, 2500, 4), "wave far from the T3")
	T.ok(not R.LaneUnderPressure(4, 800, 1), "one creep is no wave")
	T.eq(R.CreepPressureBonus(0), 0, "no lane")
	T.near(R.CreepPressureBonus(1), 0.1, 1e-9, "one lane")
	T.near(R.CreepPressureBonus(3), 0.2, 1e-9, "capped at 0.2")
end)

T.test("Roshan first: every enemy alive, their base open, Roshan up, no window (maintainer 2026-11-22)", function()
	local R = rules()
	local s = {
		enemiesAlive = 5,
		enemyPlayers = 5,
		alliesAlive = 5,
		baseOpen = true,
		roshAlive = true,
		ahead = true,
	}
	local on, why = R.RoshanFirst(s)
	T.ok(on, "game 068 52:50: Roshan first")
	T.eq(why, "ahead", "why")
	s.advantage = true
	T.eq(select(2, R.RoshanFirst(s)), "advantage", "an open window still pushes first")
	s.advantage, s.baseThreat = nil, true
	T.eq(select(2, R.RoshanFirst(s)), "base-threat", "never with our base hit")
	s.baseThreat, s.ourAegis = nil, true
	T.eq(select(2, R.RoshanFirst(s)), "have-aegis", "Aegis taken: push")
	s.ourAegis, s.roshAlive = nil, false
	T.eq(select(2, R.RoshanFirst(s)), "rosh-dead", "Roshan down: push (hg-gather)")
	s.roshAlive, s.enemiesAlive = true, 4
	T.eq(select(2, R.RoshanFirst(s)), "enemy-dead", "an enemy dead")
	s.enemiesAlive, s.baseOpen = 5, false
	T.eq(select(2, R.RoshanFirst(s)), "base-closed", "base closed")
	s.baseOpen, s.ahead = true, false
	T.eq(select(2, R.RoshanFirst(s)), "even", "even, no pressure")
	s.pressureLanes = 1
	T.eq(select(2, R.RoshanFirst(s)), "pressure", "even with creep pressure")
	s.alliesAlive = 3
	T.eq(select(2, R.RoshanFirst(s)), "few-alive", "3 of ours alive")
end)

T.test("hit-hero: a hero the enemy tower covers is skipped (game 068 16:52)", function()
	local R = rules()
	-- Game 068 t=1010-1012: Clinkz 323 from Radiant's mid T2, Alchemist behind it, 1006 from Clinkz.
	local s = { targetToTower = 690, towerRange = 700, botToTarget = 1006, botToTower = 323, towerHp = 0.8 }
	local skip, why = R.HitHeroBehindTower(s)
	T.ok(skip, "behind the tower: skip")
	T.eq(why, "behind-tower", "why")
	s.botToTarget = 250
	T.ok(not R.HitHeroBehindTower(s), "the hero is in front of the tower")
	s.botToTarget, s.towerHp = 1006, 0.2
	T.ok(not R.HitHeroBehindTower(s), "tower nearly dead")
	s.towerHp, s.creepsTanking, s.fightOurs = 0.8, true, true
	T.ok(not R.HitHeroBehindTower(s), "creeps tank it and the fight is ours")
	s.fightOurs = false
	T.ok(R.HitHeroBehindTower(s), "creeps tank it but the fight is even")
	T.ok(
		not R.HitHeroBehindTower({ targetToTower = 1200, towerRange = 700, botToTarget = 1500, botToTower = 300 }),
		"far from the tower"
	)
end)

T.test(
	"hit-hero: the path past the tower counts; numbers, a window or a quick kill keep a good chase (game 069)",
	function()
		local R = rules()
		-- Game 069 t=1368: Dire's mid T2 at (2593,2170); Alchemist at (2896,2571) goes for Undying at (3437,2818), 1064
		-- from the tower (outside range + 150), past it. 1 Dire dead: 4 can respond to 2 chasers.
		local tower, bot, target = { 2593, 2170 }, { 2896, 2571 }, { 3437, 2818 }
		local function dist(a, b)
			return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
		end
		local path = R.PointToSegment(tower[1], tower[2], bot[1], bot[2], target[1], target[2])
		T.ok(path <= 850, "the path passes within range + 150 (" .. path .. ")")
		local s = {
			targetToTower = dist(target, tower),
			pathToTower = path,
			towerRange = 700,
			botToTarget = dist(bot, target),
			botToTower = dist(bot, tower),
			towerHp = 0.83,
			responders = 4,
			chasers = 2,
			killTime = 9,
			surviveTime = 6,
		}
		T.ok(s.targetToTower > 850, "Undying outside range + 150")
		local skip, why = R.HitHeroBehindTower(s)
		T.ok(skip, "22:48: blocked")
		T.eq(why, "behind-tower", "why")
		-- Game 069 t=2013-2022: a dead2 window, 3 Dire alive and near against 3 of ours: the chase that paid off.
		s.advantage = true
		T.eq(select(2, R.HitHeroBehindTower(s)), "advantage", "33:30: an open window")
		s.advantage, s.responders, s.chasers = nil, 3, 3
		T.eq(select(2, R.HitHeroBehindTower(s)), "numbers", "33:30: 3 against 3")
		s.responders, s.chasers, s.killTime, s.surviveTime = 4, 2, 3, 6
		T.eq(select(2, R.HitHeroBehindTower(s)), "kill-first", "the target dies first")
		s.killTime, s.surviveTime = 3, 2
		T.ok(R.HitHeroBehindTower(s), "the tower kills us first")
		-- A hero sideways, the path clear of the tower: taken.
		T.eq(
			select(
				2,
				R.HitHeroBehindTower({ targetToTower = 1500, pathToTower = 1200, botToTarget = 900, botToTower = 1300 })
			),
			"clear",
			"clear"
		)
		T.near(R.PointToSegment(0, 5, -10, 0, 10, 0), 5, 1e-9, "point above the segment")
		T.near(R.PointToSegment(20, 0, -10, 0, 10, 0), 10, 1e-9, "past the end")
	end
)

T.test("own-HP cap in an Aegis window: 40% with nobody near, the holder 30% (game 069 1543-1640)", function()
	local R = rules()
	-- Puck at 0.46-0.53 in the Aegis window, no enemy near: not capped any more.
	T.eq(R.OwnHpCap({ window = true, enemiesNear = 0 }), 0.4, "Aegis window, nobody near")
	T.eq(R.OwnHpCap({ window = true, enemiesNear = 2 }), 0.5, "Aegis window, enemies near")
	T.eq(R.OwnHpCap({ window = true, aegisHolder = true, enemiesNear = 2 }), 0.3, "the holder")
end)

T.test("front walk: a lane with no building left stays on its target (game 071 47:20)", function()
	local R = rules()
	-- Game 071 t=2855-2859: Dire's top lane gone, target Dire's mid melee barracks, the top front 2000+ away.
	T.eq(R.FrontWalk({ distanceToFront = 2300, laneTier = 4, hasTarget = true }), "lane-done", "stay on the barracks")
	T.eq(R.FrontWalk({ distanceToFront = 2300, laneTier = 4, hasTarget = false }), "walk", "nothing in reach: walk")
	T.eq(
		R.FrontWalk({ distanceToFront = 2300, laneTier = 3, hasTarget = true }),
		"walk",
		"the lane still has buildings"
	)
	T.eq(R.FrontWalk({ distanceToFront = 1500, laneTier = 4, hasTarget = true }), "stay", "near the front")
	T.eq(R.FrontWalk({ distanceToFront = 2300, recentlyHit = true }), "stay", "hit by a hero")
end)

T.test("lane-done episode ends: target fell, died, left push, 20s cap", function()
	local R = rules()
	local s = { targetAlive = true, botAlive = true, gap = 0.1, outOfPush = 0, age = 5 }
	T.eq(R.LaneDoneEpisodeEnd(s), nil, "running")
	s.age = 20
	T.eq(R.LaneDoneEpisodeEnd(s), "cap", "20s")
	s.age, s.outOfPush = 5, 2.5
	T.eq(R.LaneDoneEpisodeEnd(s), "left-push", "out of push 2s+")
	s.outOfPush, s.gap = 0, 4
	T.eq(R.LaneDoneEpisodeEnd(s), "died", "no think for 3s+")
	s.gap, s.targetAlive = 0.1, false
	T.eq(R.LaneDoneEpisodeEnd(s), "fell", "target dead")
end)
