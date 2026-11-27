-- #15: bots/lib/systems/ward.lua plant retry points and the maintainer's game 063 spots.
local T = ...

local function ward()
	T.stub.reset({ hero = "npc_dota_hero_zuus" })
	return require(GetScriptDirectory() .. "/lib/systems/ward")
end

T.test("ward: plant retry tries 8 directions at 50, then at 100", function()
	local Ward = ward()
	local center = { x = -4365, y = -1012 }
	local points = Ward.RetryPoints(center)
	T.eq(#points, 16, "16 points")
	for i, point in ipairs(points) do
		local dist = math.sqrt((point[1] - center.x) ^ 2 + (point[2] - center.y) ^ 2)
		T.near(dist, i <= 8 and 50 or 100, 1e-6, "distance of point " .. i)
	end
	T.near(points[1][1], -4315, 1e-6, "first point east")
	T.near(points[3][2], -962, 1e-6, "third point north")
	T.near(points[9][1], -4265, 1e-6, "ninth point east at 100")
end)

-- #15, game 080, 23:40: a lane observer at the rim of our top T2's range. The rule: at least the tower's attack
-- range plus the observer's vision (1600) from every living tower of ours.
T.test("ward: own-tower gap is the tower range plus observer vision 1600", function()
	local Ward = ward()
	T.eq(Ward.OwnTowerGap(700), 2300, "700 range")
	T.eq(Ward.OwnTowerGap(nil), 2300, "no range: 700")
	local nearest, margin = Ward.OwnTowerClearance(0, 0, {
		{ x = 1000, y = 0, range = 700 },
		{ x = 0, y = 3000, range = 700 },
	})
	T.near(nearest, 1000, 1e-6, "nearest tower")
	T.near(margin, -1300, 1e-6, "smallest margin")
	nearest, margin = Ward.OwnTowerClearance(0, 0, {})
	T.eq(nearest, nil, "no towers: no distance")
	T.eq(margin, nil, "no towers: no margin")
end)

-- Points every 300 along y = 0 from x = 300, our tower at x = 0 (range 700).
local function lanePoints(n, enemyFrom, baseFrom)
	local points = {}
	for i = 1, n do
		points[i] = {
			x = 300 * i,
			y = 0,
			enemyNear = enemyFrom ~= nil and i >= enemyFrom,
			inBase = baseFrom ~= nil and i >= baseFrom,
		}
	end
	return points
end
local OWN = { { x = 0, y = 0, range = 700 } }

T.test("ward: lane spot keeps the 900-ahead point when it is clear of our towers", function()
	local Ward = ward()
	T.eq(Ward.PickLaneSpot(lanePoints(10), 3, {}, 250), 3, "no towers of ours")
	local far = { { x = -5000, y = 0, range = 700 } }
	T.eq(Ward.PickLaneSpot(lanePoints(10), 3, far, 250), 3, "tower far behind")
end)

T.test("ward: lane spot moves forward until it is range + 1600 (+ margin) from our tower", function()
	local Ward = ward()
	-- 2300 + 250 = 2550: x = 2700 is point 9.
	local idx = Ward.PickLaneSpot(lanePoints(20), 3, OWN, 250)
	T.eq(idx, 9, "first point at or past 2550")
	T.eq(Ward.PickLaneSpot(lanePoints(20), 3, OWN, 0), 8, "no margin: x = 2400")
end)

T.test("ward: no lane spot when an enemy tower or a base comes before the gap", function()
	local Ward = ward()
	local idx, why = Ward.PickLaneSpot(lanePoints(20, 6), 3, OWN, 250)
	T.eq(idx, nil, "enemy tower range at x = 1800")
	T.eq(why, "enemy-tower", "why")
	idx, why = Ward.PickLaneSpot(lanePoints(20, nil, 5), 3, OWN, 250)
	T.eq(idx, nil, "base at x = 1500")
	T.eq(why, "base", "why base")
	idx, why = Ward.PickLaneSpot(lanePoints(5), 3, OWN, 250)
	T.eq(idx, nil, "lane ends before the gap")
	T.eq(why, "own-tower", "why own-tower")
end)

T.test("ward: preferred point under an enemy tower pulls back only to a point clear of our towers", function()
	local Ward = ward()
	-- No tower of ours near: the old pull-back (600, then 300 ahead).
	T.eq(Ward.PickLaneSpot(lanePoints(10, 3), 3, {}, 250), 2, "pull back to 600 ahead")
	-- Our tower near: the points behind are inside the gap, so none.
	T.eq(Ward.PickLaneSpot(lanePoints(10, 3), 3, OWN, 250), nil, "no pull-back into the tower's area")
end)

-- #15, game 087: the sentry list offered our own eye cliff while every T1 of ours stood, and the ward think planted
-- an observer there (Zuus 7:01, Largo 12:37).
T.test("ward: sentry list holds our own eye cliff back until a T1 of ours falls", function()
	local Ward = ward()
	local want, why = Ward.SentryWant("uber", true, false, false, true)
	T.eq(want, false, "own cliff, all T1s up: not wanted")
	T.eq(why, "home-too-early", "skip reason")
	want, why = Ward.SentryWant("uber", true, false, false, false)
	T.eq(want, true, "own cliff after a T1 fell")
	T.eq(why, nil, "no skip reason")
	T.eq((Ward.SentryWant("uber", false, false, false, false)), true, "enemy cliff")
	T.eq((Ward.SentryWant("contest", true, false, false, false)), true, "contest spot")
	T.eq((Ward.SentryWant("hunt", true, false, false, false)), false, "hunt spot before defending or pushing")
end)

T.test("ward: sentry list while defending or pushing keeps one side, home check aside", function()
	local Ward = ward()
	T.eq((Ward.SentryWant("uber", true, true, false, true)), true, "defending: our cliff")
	T.eq((Ward.SentryWant("uber", false, true, false, false)), false, "defending: not theirs")
	T.eq((Ward.SentryWant("hunt", false, false, true, false)), true, "pushing: their side")
	T.eq((Ward.SentryWant("uber", true, false, true, false)), false, "pushing: not ours")
end)
