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
	local why, danger = DangerMap.FarmSkip(GetBot(), Vector(4700, 4800, 0), true)
	T.eq(why, "danger", "enemy camp with all five there")
	T.eq(danger, 5, "danger")
end)
