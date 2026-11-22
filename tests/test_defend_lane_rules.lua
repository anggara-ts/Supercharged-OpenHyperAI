-- bots/lib/systems/defend_lane_rules.lua: a defender keeps its lane, and a defend TP doesn't loop.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_elder_titan" })
	return require(GetScriptDirectory() .. "/lib/systems/defend_lane_rules")
end

T.test("lane pick: game 066 Elder Titan stays on the bottom high ground", function()
	local R = rules()
	-- 81:53: bottom 0.37 with 11 creeps, he stood ~1000 from it; mid read 0.85 with 8 creeps.
	local keep, why = R.KeepLane(
		{ desire = 0.37, creeps = 11, hp = 1, dist = 998 },
		{ desire = 0.85, creeps = 8, hp = 1, dist = 4000 },
		0
	)
	T.eq(keep, true, "keeps bottom")
	T.eq(why, "hold")
	-- 82:15: bottom up to 21 creeps, mid 8.
	T.eq(R.KeepLane({ desire = 0.85, creeps = 21, dist = 900 }, { desire = 0.85, creeps = 8 }, 0), true, "keeps bottom")
end)

T.test("lane pick: the other lane wins when it is clearly worse or the held lane is over", function()
	local R = rules()
	local held = { desire = 0.6, creeps = 4, hp = 1, dist = 800 }
	T.eq((R.KeepLane(held, { desire = 0.85, creeps = 10, hp = 1 }, 0)), false, "10 creeps against 4")
	T.eq((R.KeepLane(held, { desire = 0.85, creeps = 4, hp = 0.6 }, 0)), false, "its building much lower")
	T.eq(
		(R.KeepLane({ desire = 0.05, creeps = 0, dist = 800 }, { desire = 0.85, creeps = 3 }, 0)),
		false,
		"held lane clear"
	)
	-- Out of the held lane's defend mode for 12s: no hold; 4s: hold.
	T.eq((R.KeepLane({ desire = 0.6, creeps = 4 }, { desire = 0.85, creeps = 4 }, 12)), false, "left it")
	T.eq((R.KeepLane({ desire = 0.6, creeps = 4 }, { desire = 0.85, creeps = 4 }, 4)), true, "left it 4s ago")
	-- Heroes, a deeper building or an urgent reason on the other lane always win.
	T.eq((R.KeepLane(held, { desire = 0.7, creeps = 0, heroes = 2 }, 0)), false, "enemy heroes there")
	T.eq((R.KeepLane({ desire = 0.6, creeps = 8, tier = 3 }, { desire = 0.7, creeps = 6, tier = 4 }, 0)), false, "T4")
	for _, why in ipairs({ "group-up", "ancient-last-stand", "ancient-heroes", "base-floor" }) do
		T.eq((R.KeepLane(held, { desire = 0.7, creeps = 0, why = why }, 0)), false, why .. " is never capped")
	end
end)

T.test("defend TP: no repeat to the same lane within 20s, no TP away from a base threat", function()
	local R = rules()
	T.eq(R.DefendTpBlock(100, 2, 90, 2, false, 3000, 6000), "recent", "same lane 10s ago")
	T.eq(R.DefendTpBlock(100, 3, 90, 2, false, 3000, 6000), nil, "other lane")
	T.eq(R.DefendTpBlock(100, 2, 70, 2, false, 3000, 6000), nil, "30s ago")
	-- 82:35: from the Dire base (~1500 from the Ancient) to -3441,-3027 (~12000) with creeps on the high ground.
	T.eq(R.DefendTpBlock(4955, 2, 4915, 2, true, 1500, 12000), "away-from-base", "the walk-back re-TP")
	T.eq(R.DefendTpBlock(4955, nil, nil, 2, true, 9000, 2500), nil, "TP home to the threat is fine")
	T.eq(R.DefendTpBlock(4955, nil, nil, 1, false, 1500, 9000), nil, "no base threat: TP out to a T1")
end)

T.test("lane pick: game 068 tier 0 is unknown, both lanes at the T4s are one base defence", function()
	local R = rules()
	-- t=2457: bottom (held) read tier 0 right after its building fell, with 10 creeps and 5 heroes; mid tier 4, 5
	-- creeps, 1 hero. It was "deeper-tier" for mid.
	local keep, why = R.KeepLane(
		{ desire = 0.12, creeps = 10, heroes = 5, hp = 1, tier = 0 },
		{ desire = 0.12, creeps = 5, heroes = 1, hp = 0.99, tier = 4, why = "hg-outnumbered" },
		0
	)
	T.eq(keep, true, "keeps bottom")
	T.eq(why, "hold")
	-- t=2488 / t=2495: mid and bottom both tier 4: whatever the creep split, the same base defence.
	keep, why = R.KeepLane(
		{ desire = 0.85, creeps = 1, tier = 4, hp = 0.97 },
		{ desire = 0.85, creeps = 8, tier = 4, hp = 0.97, why = "hg-creeps-big" },
		0
	)
	T.eq(keep, true, "no switch between two base lanes")
	T.eq(why, "same-base")
	T.eq(
		(R.KeepLane({ desire = 0.6, tier = 5 }, { desire = 0.7, tier = 4, why = "ancient-heroes" }, 0)),
		false,
		"urgent"
	)
	T.eq((R.KeepLane({ desire = 0.6, creeps = 2, tier = 3 }, { desire = 0.7, creeps = 2, tier = 4 }, 0)), false, "T4")
end)

T.test("lane threat: each creep for one lane, base creeps for the lanes at the T4s", function()
	local R = rules()
	local lanes = { 1, 2, 3 }
	T.eq(R.CreepLane({ [1] = 900, [2] = 150, [3] = 2000 }, lanes, 4000), 2, "nearest path")
	T.eq(R.CreepLane({ [1] = 100, [2] = 100, [3] = 100 }, lanes, 900), "base", "by the Ancient")
	T.eq(R.CreepLane({ [1] = 300, [2] = 300, [3] = 900 }, lanes, nil), 1, "tie: first lane")
	-- A bottom creep 2000 from the bottom T3 counts for bottom only; at a T2 it needs 1600.
	T.eq(R.CountsForLane(3, 3, 3, 2000), true)
	T.eq(R.CountsForLane(3, 2, 3, 2000), false, "not mid's")
	T.eq(R.CountsForLane(3, 3, 2, 2000), false, "out of a T2's reach")
	T.eq(R.CountsForLane("base", 2, 4, nil), true, "base creep, mid at the T4s")
	T.eq(R.CountsForLane("base", 1, 3, nil), false, "base creep, top still has its T3")
end)

T.test("high ground: hold the rim, meet the wave, back to the Ancient only for heroes or hits", function()
	local R = rules()
	T.eq(R.HighGroundStep({ heroesAtAncient = 1 }), "ancient-heroes")
	T.eq(R.HighGroundStep({ heroesAtRim = 2, alliesAtRim = 1 }), "hg-back", "outnumbered at the rim")
	T.eq(R.HighGroundStep({ heroesAtRim = 2, alliesAtRim = 3 }), "hg-fight")
	T.eq(R.HighGroundStep({ heroesAtRim = 3, alliesAtRim = 1, stronger = true }), "hg-fight")
	-- Game 068 52:30: wave at the rim, the Ancient hit earlier: meet the wave, don't hug the Ancient.
	T.eq(R.HighGroundStep({ wave = 6, waveSafe = true, ancientHit = true }), "hg-wave")
	T.eq(R.HighGroundStep({ wave = 6, waveSafe = true, waveNear = true }), "hg-near")
	T.eq(R.HighGroundStep({ wave = 6, waveSafe = false }), "hg-spot", "heroes by the wave: hold the rim")
	T.eq(R.HighGroundStep({ wave = 0, ancientHit = true }), "ancient-hit")
	T.eq(R.HighGroundStep({}), "hg-spot", "nothing: hold the rim")
end)

T.test("base split: rim threat per lane, our creeps holding a wave is no threat", function()
	local R = rules()
	T.eq(R.RimThreat({ enemyAtRim = 2, enemyNear = 4, alliedNear = 6 }), "wave", "at the rim: a threat")
	T.eq(R.RimThreat({ enemyAtRim = 0, enemyNear = 4, alliedNear = 5 }), nil, "our creeps hold it")
	T.eq(R.RimThreat({ enemyAtRim = 0, enemyNear = 4, alliedNear = 1 }), "pushed", "our creeps pushed hard")
	T.eq(R.RimThreat({ heroes = 1 }), "heroes")
	T.eq(R.RimThreat({ ancientHit = true }), "ancient-hit")
	T.eq(R.RimThreat({ enemyNear = 1 }), nil, "one stray creep")
	-- Need: 1 per 5 creeps, +1 for a siege / mega creep, everyone for heroes.
	T.eq(R.RimNeed("wave", 4, false), 1)
	T.eq(R.RimNeed("wave", 4, true), 2, "siege")
	T.eq(R.RimNeed("pushed", 10, false), 2)
	T.eq(R.RimNeed("ancient-hit", 0, false), 1, "at least 1")
	T.eq(R.RimNeed("heroes", 0, false), 5)
	T.eq(R.RimNeed(nil, 8, true), 0, "no threat")
end)

local function bots(list)
	local result = {}
	for _, b in ipairs(list) do
		result[#result + 1] = { id = b[1], dist = { top = b[2], bot = b[3] } }
	end
	return result
end
local function counted(assign, lane)
	local n = 0
	for _, l in pairs(assign) do
		if l == lane then
			n = n + 1
		end
	end
	return n
end

T.test("base split: two waves on two rims split by need, nearest first", function()
	local R = rules()
	local five =
		bots({ { "a", 500, 6000 }, { "b", 900, 5500 }, { "c", 6000, 400 }, { "d", 5000, 800 }, { "e", 4000, 1500 } })
	local rims = {
		{ lane = "top", why = "wave", need = 2, alive = true },
		{ lane = "bot", why = "pushed", need = 3, alive = true },
	}
	local assign, count = R.AssignRims(rims, five, {})
	T.eq(count.top, 2)
	T.eq(count.bot, 3)
	T.eq(assign.a, "top")
	T.eq(assign.c, "bot")
	-- 1-1: two small waves, the other three stay out of the defence.
	rims[1].need, rims[2].need = 1, 1
	assign, count = R.AssignRims(rims, five, {})
	T.eq(count.top, 1)
	T.eq(count.bot, 1)
	T.eq(assign.a, "top")
	T.eq(assign.c, "bot")
	T.eq(assign.b, nil, "not needed")
end)

T.test("base split: a bot keeps its rim mid-wave, a cleared rim frees its bots, heroes pull the group", function()
	local R = rules()
	local two = bots({ { "a", 4000, 500 }, { "b", 4500, 3000 } })
	-- a was sent top; a new bottom wave appears next to him: he stays top while the top wave lives.
	local rims = {
		{ lane = "top", why = "wave", need = 1, alive = true },
		{ lane = "bot", why = "wave", need = 1, alive = true },
	}
	local assign = R.AssignRims(rims, two, { a = "top" })
	T.eq(assign.a, "top", "no rim-to-rim walk")
	T.eq(assign.b, "bot")
	-- The top wave is cleared: a is free, but bottom has b already: a leaves the defence.
	rims[1] = { lane = "top", why = nil, need = 0, alive = false }
	assign = R.AssignRims(rims, two, assign)
	T.eq(assign.b, "bot", "b keeps bottom while its wave lives")
	T.eq(assign.a, nil, "a leaves the defence")
	-- Enemy heroes at the top rim: everyone goes there.
	rims[1] = { lane = "top", why = "heroes", need = 5, alive = true, heroes = 2 }
	assign = R.AssignRims(rims, two, assign)
	T.eq(assign.a, "top")
	T.eq(assign.b, "top")
end)

T.test("base split: a hero pull is not kept after the heroes leave; a held wave frees its bots after 5s", function()
	local R = rules()
	local five =
		bots({ { "a", 500, 6000 }, { "b", 900, 5500 }, { "c", 1200, 400 }, { "d", 1500, 800 }, { "e", 2000, 1500 } })
	local rims = { { lane = "top", why = "heroes", need = 5, alive = true, heroes = 2 } }
	local assign, count, keep = R.AssignRims(rims, five, {})
	T.eq(count.top, 5, "everyone to the heroes")
	-- The heroes left, 3 creeps remain: 1 kept (the nearest), 4 freed.
	rims[1] = { lane = "top", why = "wave", need = 1, alive = true }
	assign, count = R.AssignRims(rims, five, keep)
	T.eq(count.top, 1)
	T.eq(assign.a, "top")
	T.eq(assign.b, nil, "freed")
	-- RimAlive: threatened, or the wave lives up to 5s after the last threat.
	T.eq(R.RimAlive("wave", 3, 0), true)
	T.eq(R.RimAlive(nil, 3, 4), true, "our creeps hold it, 4s")
	T.eq(R.RimAlive(nil, 3, 6), false, "held for 6s: free the bots")
	T.eq(R.RimAlive(nil, 0, 1), false, "cleared")
end)

T.test("early start (game 069): the next wave's ETA against the defender's", function()
	local R = rules()
	-- A wave 4000 out: 4000 / 325 = 12.3s.
	local waveEta = R.WaveEta(4000)
	T.near(waveEta, 12.3, 0.1)
	-- A defender 6000 away walking at 300: 20s, later than the wave minus 3s: start now.
	local myEta, via = R.DefenderEta(6000, 300, false, nil)
	T.near(myEta, 20, 0.01)
	T.eq(via, "walk")
	T.eq(R.StartEarly(waveEta, myEta), true, "6000 away: start")
	-- 1500 away: 5s, it can wait.
	T.eq(R.StartEarly(waveEta, (R.DefenderEta(1500, 300, false, nil))), false, "1500 away: not yet")
	-- 9000 away with a TP ready: 3s channel + 600 walk from the tower = 5s beats 30s of walking; not yet.
	myEta, via = R.DefenderEta(9000, 300, true, 600)
	T.near(myEta, 5, 0.01)
	T.eq(via, "tp")
	T.eq(R.StartEarly(waveEta, myEta), false, "TP ready: not yet")
	-- RimThreat: the next wave counts only while our creeps meeting it are fewer, and within 25s.
	T.eq(R.RimThreat({ waveEta = 12, waveCreeps = 4, waveAllied = 1 }), "early")
	T.eq(R.RimThreat({ waveEta = 12, waveCreeps = 4, waveAllied = 4 }), nil, "our creeps meet it")
	T.eq(R.RimThreat({ waveEta = 40, waveCreeps = 4, waveAllied = 0 }), nil, "too far off")
	T.eq(R.RimNeed("early", 4, true), 2)
end)

T.test("lane defence (game 069): after a lane-back, stay back 4s unless even for 3s", function()
	local R = rules()
	T.eq(R.LaneStayBack(100, false, nil, nil), true, "outnumbered")
	-- Back at 100 (hold to 104): even again at 101, still back at 102; even for 3s at 104 or the hold over.
	T.eq(R.LaneStayBack(102, true, 104, 101), true, "even for 1s")
	T.eq(R.LaneStayBack(103.5, true, 104, 100.5), false, "even for 3s")
	T.eq(R.LaneStayBack(104, true, 104, 103.9), false, "hold over")
	T.eq(R.LaneStayBack(102, true, nil, nil), false, "no hold, even: go")
end)
