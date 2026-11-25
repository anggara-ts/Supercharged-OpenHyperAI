-- bots/lib/systems/orb_path_rules.lua (#36): the Illusory Orb path probe's offset from the aimed line.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_puck" })
	return require(GetScriptDirectory() .. "/lib/systems/orb_path_rules")
end

T.test("orb path: signed offset from the aimed line", function()
	local R = load()
	-- Aim east from (100, 100): a point 300 ahead and 50 north is on the left.
	local lateral, along = R.Offset(100, 100, 1100, 100, 400, 150)
	T.near(lateral, 50, 0.001, "left of the aim is positive")
	T.near(along, 300, 0.001, "distance along the aim")
	lateral = R.Offset(100, 100, 1100, 100, 400, 30)
	T.near(lateral, -70, 0.001, "right of the aim is negative")
	-- A diagonal aim: a point on the line has no offset.
	lateral, along = R.Offset(0, 0, 1000, 1000, 500, 500)
	T.near(lateral, 0, 0.001, "on the diagonal")
	T.near(along, math.sqrt(2) * 500, 0.001, "along the diagonal")
	T.eq(R.Offset(5, 5, 5.5, 5, 100, 100), nil, "no direction when the aim is on the start")
end)

T.test("orb path: the record keeps the largest offset and the last one", function()
	local R = load()
	-- Aim north from the origin; an Orb that bends right, then partly back.
	local path = R.New(0, 0, 0, 1950)
	T.ok(R.Add(path, 0, 300), "straight at first")
	T.ok(R.Add(path, 120, 900), "bends right")
	T.ok(R.Add(path, 60, 1500), "comes back a little")
	T.eq(path.n, 3, "three samples")
	T.near(path.dev, -120, 0.001, "largest offset, right side negative")
	T.near(path.devAlong, 900, 0.001, "where the largest offset was")
	T.near(path.last, -60, 0.001, "last offset")
	T.near(path.lastAlong, 1500, 0.001, "last distance along")
	local flat = R.New(10, 10, 10, 10)
	T.eq(R.Add(flat, 50, 50), false, "no direction: not counted")
	T.eq(flat.n, 0, "still empty")
end)
