-- bots/lib/systems/danger_map_rules.lua and bots/lib/systems/danger_map.lua (#227): reach circles, the danger count,
-- missing enemies, isolated targets, the far side and the farm skip decision.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_wisp" })
	return require(GetScriptDirectory() .. "/lib/systems/danger_map_rules")
end

-- Game 073 t=1291-1320: Undying (Dire, 1-3 of 5 Dire alive) farmed alone in the Dire bottom jungle ([SHy-FARM]
-- camp-switch to=4352,48) and died at 3984,1702 to all five Radiant heroes (allies=0). Their last-seen spots are not
-- in the log: the points below are SYNTHETIC, 1900-2600 from the camp and seen 2-3s earlier, the way a gank walks in.
local CAMP = { x = 4352, y = 48 }
local GANK = {
	{ x = 2600, y = 700, unseen = 2, speed = 330 },
	{ x = 3000, y = 2200, unseen = 3, speed = 350 },
	{ x = 5000, y = 2600, unseen = 2, speed = 300 },
	{ x = 2400, y = -1200, unseen = 3, speed = 310 },
}
-- Game 062 lane towers (tests/test_farm_rules.lua: from the [SHy-FARM] withdraw points).
local RADIANT_TOWERS = {
	{ x = -6350, y = 1456 },
	{ x = -6510, y = -1271 },
	{ x = -6596, y = -3808 },
	{ x = -1524, y = -1507 },
	{ x = -3291, y = -3026 },
	{ x = -4908, y = -4441 },
	{ x = 4460, y = -6378 },
	{ x = -760, y = -6261 },
	{ x = -3946, y = -5845 },
}
local DIRE_TOWERS = {
	{ x = -4875, y = 6047 },
	{ x = 271, y = 6036 },
	{ x = 3946, y = 5845 },
	{ x = 1128, y = 1116 },
	{ x = 2991, y = 2550 },
	{ x = 4557, y = 4039 },
	{ x = 6300, y = -1841 },
	{ x = 6435, y = 782 },
	{ x = 6406, y = 3426 },
}

T.test("danger map: reach grows with time unseen, capped at 10s", function()
	local R = rules()
	T.eq(R.Reach(0, 300, 5), 1500, "visible: 5s of walking")
	T.eq(R.Reach(4, 300, 5), 2700, "unseen 4s")
	T.eq(R.Reach(60, 300, 5), 4500, "unseen 60s counts as 10s")
	T.eq(R.Reach(0, nil, 0), 0, "default speed, no horizon")
end)

T.test("danger map: game 073 Undying camp - four Radiant heroes could reach it within 5s", function()
	local R = rules()
	T.eq(R.Danger(GANK, CAMP.x, CAMP.y), 4, "all four within reach + 1200")
	-- The same heroes seen 6000+ away a second ago are no danger at the camp.
	local far = {
		{ x = -3000, y = -2000, unseen = 1, speed = 330 },
		{ x = -2500, y = -3000, unseen = 1, speed = 330 },
	}
	T.eq(R.Danger(far, CAMP.x, CAMP.y), 0, "far enemies")
	T.eq(R.Missing(GANK), 0, "all seen within 3s")
	local missing = {
		{ x = 0, y = 0, unseen = 12 },
		{ x = 0, y = 0, unseen = 30 },
		{ x = 0, y = 0, unseen = 10 },
		{ x = 0, y = 0, unseen = 9 },
	}
	T.eq(R.Missing(missing), 3, "unseen 10s or more")
end)

T.test("danger map: a respawned enemy is read at its fountain, not where it died", function()
	local R = rules()
	local x, y, unseen = R.EnemyPosition(3500, 2500, 40, 5, -7174, -6671)
	T.eq(x, -7174, "fountain x")
	T.eq(y, -6671, "fountain y")
	T.eq(unseen, 5, "unseen since the respawn")
	x, y, unseen = R.EnemyPosition(3500, 2500, 2, 5, -7174, -6671)
	T.eq(x, 3500, "seen after the respawn: last-seen spot")
	T.eq(unseen, 2, "its own unseen time")
	x = R.EnemyPosition(3500, 2500, 40, nil, -7174, -6671)
	T.eq(x, 3500, "no respawn noted")
end)

T.test("danger map: isolated target", function()
	local R = rules()
	local target = { x = 0, y = 0, unseen = 1, speed = 300 }
	T.eq(R.Isolated(target, { target }), true, "alone")
	T.eq(R.Isolated(target, { target, { x = 1000, y = 0, unseen = 0, speed = 300 } }), false, "an enemy 1000 away")
	T.eq(R.Isolated(target, { target, { x = 8000, y = 0, unseen = 20, speed = 300 } }), true, "missing far away")
	T.eq(R.Isolated(target, { target, { x = 3500, y = 0, unseen = 20, speed = 300 } }), false, "missing, could be near")
	T.eq(R.Isolated({ x = 0, y = 0, unseen = 5 }, {}), false, "target not seen for 5s")
end)

T.test("danger map: far side follows the living towers", function()
	local R = rules()
	T.eq(R.FarSide(-1454, -3356, RADIANT_TOWERS, DIRE_TOWERS), false, "Radiant mid jungle camp")
	T.eq(R.FarSide(2663, 3483, RADIANT_TOWERS, DIRE_TOWERS), true, "Dire jungle (game 073 PA death t=1159)")
	-- A camp by our bottom T1: own side; with our bottom T1 and T2 down, nearer the Dire bottom T1.
	T.eq(R.FarSide(3200, -4800, RADIANT_TOWERS, DIRE_TOWERS), false, "bottom T1 alive")
	local fallen = {}
	for _, tower in ipairs(RADIANT_TOWERS) do
		if not (tower.x == 4460 or tower.x == -760) then
			fallen[#fallen + 1] = tower
		end
	end
	T.eq(R.FarSide(3200, -4800, fallen, DIRE_TOWERS), true, "bottom T1 and T2 down")
	T.eq(R.FarSide(0, 0, {}, DIRE_TOWERS), true, "no towers of ours")
end)

T.test("danger map: farm skip decision", function()
	local R = rules()
	T.eq(
		R.FarmSkipWhy({ danger = 4, missing = 0, allies = 0, farSide = false }),
		"danger",
		"game 073 Undying: own camp"
	)
	T.eq(R.FarmSkipWhy({ danger = 4, missing = 0, allies = 1, farSide = false }), nil, "an ally at the camp")
	T.eq(R.FarmSkipWhy({ danger = 2, missing = 0, allies = 0, farSide = false }), nil, "own side, 2")
	T.eq(R.FarmSkipWhy({ danger = 2, missing = 0, allies = 0, farSide = true }), "danger-far", "far side, 2")
	T.eq(R.FarmSkipWhy({ danger = 0, missing = 3, allies = 0, farSide = true }), "missing-far", "far, 3 missing")
	-- No farm stall: missing enemies alone never close our own jungle.
	T.eq(R.FarmSkipWhy({ danger = 1, missing = 5, allies = 0, farSide = false }), nil, "own side, 5 missing")
	T.eq(R.FarmSkipWhy({ danger = 5, missing = 5, allies = 0, farSide = true, strictness = 0 }), nil, "off")
end)

T.test("danger map: team snapshot from the last-seen info", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	local DangerMap = require(GetScriptDirectory() .. "/lib/systems/danger_map")
	-- Stub: the five Dire heroes stand at 4500..4900, 4750..4950 and are visible.
	T.eq(DangerMap.Danger(Vector(4700, 4800, 0)), 5, "all five next to the spot")
	T.eq(DangerMap.Danger(Vector(-4700, -4800, 0)), 0, "our side of the map")
	T.eq(DangerMap.Missing(), 0, "none missing")
	local enemy = GetUnitList(UNIT_LIST_ENEMY_HEROES)[1]
	T.eq(DangerMap.Isolated(enemy), false, "four others next to it")
	T.eq(DangerMap.AlliesNear(GetBot():GetLocation(), 1500, GetBot()), 4, "our four others")
	local why, info = DangerMap.FarmSkip(GetBot(), Vector(4700, 4800, 0), true)
	T.eq(why, "danger", "enemy camp with all five there")
	T.eq(info.danger, 5, "danger")
	T.eq(info.ownTower, -1, "no tower of ours in the stub")
end)

T.test("danger map: own-tower cover in the team snapshot", function()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	-- One tier 2 tower of ours 707 from the spot, before the first snapshot reads the towers.
	T.stub.towers[GetTeam()][TOWER_MID_2] = T.stub.newUnit({
		name = "npc_dota_goodguys_tower2_mid",
		team = GetTeam(),
		loc = Vector(4200, 4300, 0),
		hero = false,
	})
	local DangerMap = require(GetScriptDirectory() .. "/lib/systems/danger_map")
	local spot = Vector(4700, 4800, 0)
	T.eq(DangerMap.SeenDanger(spot), 5, "the five Dire heroes are visible")
	local towerDist, covered, tower = DangerMap.OwnTower(spot)
	T.near(towerDist, 707, 1, "tower distance")
	T.eq(covered, true, "within 1800 of a tier 2 tower")
	T.eq(tower and tower.tier, 2, "tier")
	local why, info = DangerMap.FarmSkip(GetBot(), spot, false, true)
	T.eq(why, "danger-visible", "a wave under our tower: five seen enemies still skip it")
	T.near(info.ownTower, 707, 1, "ownTower in the numbers")
	why = DangerMap.FarmSkip(GetBot(), spot, false, false)
	T.eq(why, "danger", "a camp there: no tower cover")
end)

-- Game 084 t=1023-1029: Underlord (Radiant) at our mid T2, no enemy seen ([SHy-STUCK] enemies=0), skipped the wave
-- ("farm-skip spot=wave why=danger danger=4 missing=4 allies=0 dist=845") and the mid lane front ("spot=lane2
-- why=danger danger=4 missing=4 dist=361 alt=camp:none"), then left farm. Our mid T1 fell at t=960. Mid T2 at
-- -2999,-2752: the game 062 withdraw point -3291,-3026 is the tower moved 400 toward our fountain (NearestOwnTower);
-- the same back-step on mid T1 (-1524,-1507) gives -1229,-1237, which a defend call logged as at=-1234,-1232.
-- The enemies' last-seen spots are not logged: SYNTHETIC, on the Dire half, unseen 12-30s.
local G084_TOWERS = {
	{ x = -2999, y = -2752, tier = 2 }, -- mid T2
	{ x = -4623, y = -4160, tier = 3 }, -- mid T3 (withdraw point -4908,-4441 moved back 400)
}
local G084_BOT = { x = -2247, y = -2102 } -- [SHy-FLIP] t=1029 at=
local G084_FRONT = { x = -1983, y = -1856 } -- 361 from the bot toward the Dire fountain
local G084_MISSING = {
	{ x = 1000, y = 1000, unseen = 15, speed = 300 },
	{ x = 2000, y = 500, unseen = 20, speed = 300 },
	{ x = 500, y = 2500, unseen = 12, speed = 300 },
	{ x = -500, y = 1500, unseen = 30, speed = 300 },
	{ x = 6000, y = 6000, unseen = 0, speed = 300 }, -- the fifth, seen at their fountain
}

T.test("danger map: game 084 Underlord - the wave at our mid T2 is kept with 4 enemies missing", function()
	local R = rules()
	local fx, fy = G084_FRONT.x, G084_FRONT.y
	T.eq(R.Danger(G084_MISSING, fx, fy), 4, "danger=4 as logged")
	T.eq(R.Missing(G084_MISSING), 4, "missing=4 as logged")
	T.eq(R.Danger(G084_MISSING, fx, fy, nil, nil, R.SEEN_RECENT), 0, "none of them seen")
	local towerDist, covered = R.OwnTowerCover(fx, fy, G084_TOWERS)
	T.near(towerDist, 1355, 5, "front to mid T2")
	T.eq(covered, true, "tier 2: within 1800")
	local s = { danger = 4, seen = 0, missing = 4, allies = 0, farSide = false }
	T.eq(R.FarmSkipWhy(s), "danger", "without the cover: skipped (game 084)")
	s.covered = true
	local why, kept = R.FarmSkipWhy(s)
	T.eq(why, nil, "under our tower: farmed")
	T.eq(kept, "own-tower", "kept by the tower")
	s.seen = 3
	T.eq(R.FarmSkipWhy(s), "danger-visible", "three seen enemies close it again")
	s.seen, s.allies = 3, 1
	T.eq(R.FarmSkipWhy(s), nil, "an ally there")
	s.allies, s.strictness = 0, 0
	T.eq(R.FarmSkipWhy(s), nil, "off")
	-- The bot itself stands 995 from mid T2; a tier 1 tower covers only 1100.
	T.eq(select(2, R.OwnTowerCover(G084_BOT.x, G084_BOT.y, { { x = -2999, y = -2752, tier = 1 } })), true, "995 < 1100")
	T.eq(select(2, R.OwnTowerCover(fx, fy, { { x = -2999, y = -2752, tier = 1 } })), false, "a T1 1355 away: no")
	T.eq(select(2, R.OwnTowerCover(fx, fy, {})), false, "no towers")
end)

T.test("danger map: skip hold - a skipped spot stays skipped 10s", function()
	local R = rules()
	local why, held = R.HoldSkip(nil, 100, "danger", false)
	T.eq(why, "danger", "skipped now")
	T.eq(held.untilT, 110, "held until")
	why, held = R.HoldSkip(held, 105, nil, false)
	T.eq(why, "danger", "not offered again at 105 (game 084: farm picked and dropped it every second)")
	why, held = R.HoldSkip(held, 110.5, nil, false)
	T.eq(why, nil, "free after 10s")
	T.eq(held, nil, "entry cleared")
	-- Skipped again: the hold runs from the last skip.
	why, held = R.HoldSkip(nil, 200, "danger", false)
	why, held = R.HoldSkip(held, 208, "danger", false)
	why = R.HoldSkip(held, 215, nil, false)
	T.eq(why, "danger", "10s from the last skip at 208")
	-- A wave skipped outside the cover that walks under our tower: free at once.
	why, held = R.HoldSkip(nil, 300, "danger", false)
	why = R.HoldSkip(held, 302, nil, true)
	T.eq(why, nil, "now under our tower")
	-- Skipped under the cover (3 seen): the hold stays under the cover too.
	why, held = R.HoldSkip(nil, 400, "danger-visible", true)
	why = R.HoldSkip(held, 402, nil, true)
	T.eq(why, "danger-visible", "held")
end)

T.test("danger map: no alternative - the safest wave by our towers", function()
	local R = rules()
	local best = R.SafestTowerWave({
		{ key = "lane1", seen = 1, ownTower = 900, dist = 3000 },
		{ key = "lane2", seen = 0, ownTower = 2400, dist = 500 },
		{ key = "lane3", seen = 0, ownTower = 1500, dist = 5000 },
	})
	T.eq(best and best.key, "lane3", "fewest seen, then nearest to the tower")
	best = R.SafestTowerWave({
		{ key = "lane1", seen = 3, ownTower = 500, dist = 100 },
		{ key = "lane2", seen = 0, ownTower = 3500, dist = 100 },
	})
	T.eq(best, nil, "3 seen, or too far from our towers")
	best = R.SafestTowerWave({
		{ key = "lane1", seen = 0, ownTower = 1000, dist = 4000 },
		{ key = "lane2", seen = 0, ownTower = 1000, dist = 2000 },
	})
	T.eq(best and best.key, "lane2", "tie: nearest to the bot")
	T.eq(R.SafestTowerWave({}), nil, "no lanes")
	-- Where to wait: at the edge of the cover, on the line from the tower to the front.
	local x, y = R.CoverPoint(G084_FRONT.x, G084_FRONT.y, -2999, -2752, R.COVER_DEEP)
	T.eq(x, G084_FRONT.x, "front inside the cover: the front")
	T.eq(y, G084_FRONT.y, "front y")
	x, y = R.CoverPoint(0, 0, -3000, 0, 1800)
	T.near(x, -1200, 0.01, "1800 from the tower toward the front")
	T.near(y, 0, 0.01, "on the line")
end)
