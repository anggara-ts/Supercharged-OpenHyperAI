-- FuncLib/systems/defend_lane_rules.lua: a defender keeps its lane, and a defend TP doesn't loop.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_elder_titan" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/defend_lane_rules")
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
