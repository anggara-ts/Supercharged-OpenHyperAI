-- #111: the interaction probe's pure rules (bots/lib/systems/interact_probe.lua).
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_lion" })
	return require(GetScriptDirectory() .. "/lib/systems/interact_probe")
end

local function kinds(watcher, gate, outpost)
	return { watcher = watcher, gate = gate, outpost = outpost }
end

T.test("interact probe: the probe bot (pos 5, else 3, else 4; never the swap probe's bot)", function()
	local P = load()
	local all = {
		{ pos = 1, isBot = true },
		{ pos = 2, isBot = true },
		{ pos = 3, isBot = true },
		{ pos = 4, isBot = true },
		{ pos = 5, isBot = true },
	}
	T.eq(P.PickProbe(all, nil), 5, "pos 5")
	-- On Radiant with the swap probe on, the swap probe takes the highest position (pos 5).
	local swapSlot = P.SwapProbeSlot(all)
	T.eq(swapSlot, 5, "swap probe takes pos 5")
	T.eq(P.PickProbe(all, swapSlot), 3, "pos 3 when pos 5 is the swap probe's")
	local humanFive = {
		{ pos = 1, isBot = true },
		{ pos = 2, isBot = true },
		{ pos = 3, isBot = true },
		{ pos = 4, isBot = true },
		{ pos = 5, isBot = false },
	}
	T.eq(P.PickProbe(humanFive, nil), 3, "pos 3 when pos 5 is human")
	T.eq(P.SwapProbeSlot(humanFive), 4, "the swap probe skips humans")
	T.eq(P.PickProbe(humanFive, 4), 3, "pos 3 again")
	local onlyCores = {
		{ pos = 1, isBot = true },
		{ pos = 2, isBot = true },
		{ pos = 3, isBot = false },
		{ pos = 4, isBot = true },
		{ pos = 5, isBot = false },
	}
	T.eq(P.PickProbe(onlyCores, nil), 4, "pos 4 last")
	T.eq(P.PickProbe(onlyCores, 4), nil, "no core is picked")
	-- A tie in position: the later slot (#219's >=).
	T.eq(P.SwapProbeSlot({ { pos = 5, isBot = true }, { pos = 5, isBot = true } }), 2, "tie: later slot")
end)

T.test("interact probe: danger and windows", function()
	local P = load()
	T.eq(P.Danger(true, 1, 0), nil, "safe")
	T.eq(P.Danger(false, 1, 0), "dead", "dead")
	T.eq(P.Danger(true, 0.59, 0), "hp", "low HP")
	T.eq(P.Danger(true, 0.6, 0), nil, "60% is fine")
	T.eq(P.Danger(true, 0.9, 1), "enemy", "an enemy hero near")
	T.eq(P.InWindow("watcher", -1), false, "not before the horn")
	T.eq(P.InWindow("watcher", 0), true, "from the horn")
	T.eq(P.InWindow("gate", 239), true, "until 4:00")
	T.eq(P.InWindow("gate", 300), false, "not 4:00-10:00")
	T.eq(P.InWindow("gate", 700), true, "again from 10:00")
	T.eq(P.InWindow("outpost", 100), false, "outpost not before 10:00")
	T.eq(P.InWindow("outpost", 2400), true, "outpost late")
end)

T.test("interact probe: which kind runs next, and when the test is done", function()
	local P = load()
	local open = { tries = 0 }
	T.eq(P.NextKind(kinds({ tries = 0 }, { tries = 0 }, { tries = 0 }), 10), "watcher", "watcher first")
	T.eq(P.NextKind(kinds({ tries = 1, result = "no" }, { tries = 0 }, { tries = 0 }), 10), "gate", "then the gate")
	T.eq(P.NextKind(kinds({ tries = 3 }, { tries = 1, result = "yes" }, open), 10), nil, "outpost waits for 10:00")
	T.eq(P.NextKind(kinds({ tries = 3 }, { tries = 1, result = "yes" }, open), 650), "outpost", "outpost after 10:00")
	T.eq(P.NextKind(kinds({ tries = 1 }, { tries = 0 }, open), 650), "watcher", "an open watcher retries at 10:00")
	T.eq(P.Closed("watcher", { tries = 3 }, 100), true, "tries used")
	T.eq(P.Closed("watcher", { tries = 1 }, 1500), true, "window over")
	T.eq(P.Closed("watcher", { tries = 1 }, 1000), false, "still open")
	T.eq(P.Closed("outpost", { tries = 0 }, 3599), false, "outpost open until 60:00")
	local line = P.ChatLine(kinds({ tries = 1, result = "yes" }, { tries = 3 }, { tries = 0 }), 300)
	T.eq(line, "Interaction test done: watcher=yes gate=untested outpost=waiting(enemy tier-2)", "first chat")
	line = P.ChatLine(
		kinds({ tries = 1, result = "yes" }, { tries = 1, result = "no" }, { tries = 1, result = "ability" }),
		3000
	)
	T.eq(line, "Interaction test done: watcher=yes gate=no outpost=ability", "final chat")
end)

T.test("interact probe: the capture try needs the ability and an outpost of the other team", function()
	local P = load()
	local outposts = {
		{ team = 2, invulnerable = false },
		{ team = 3, invulnerable = true },
	}
	T.eq(P.CanCapture(true, outposts, 2, false), nil, "theirs still invulnerable (or unseen): no try")
	local index, fallback = P.CanCapture(true, outposts, 2, true)
	T.eq(index, 2, "the invulnerable one as the allowed fallback")
	T.eq(fallback, true, "marked as the fallback")
	T.eq(P.CanCapture(true, { { team = 2, invulnerable = false } }, 2, true), nil, "only ours")
	T.eq(P.CanCapture(false, { { team = 3, invulnerable = false } }, 2, true), nil, "no ability")
	outposts[3] = { team = 3, invulnerable = false }
	index, fallback = P.CanCapture(true, outposts, 2, true)
	T.eq(index, 3, "one without the invulnerability first")
	T.eq(fallback, false, "a normal try")
end)

T.test("interact probe: approach steps and points", function()
	local P = load()
	T.eq(P.FirstStep(5000), 1, "far: from 1500")
	T.eq(P.FirstStep(1000), 3, "1000 away: 1500 and 1200 are behind")
	T.eq(P.FirstStep(10), #P.STEPS, "at the spot: the last step")
	T.eq(P.Dwell(400), 4, "long stand at 400")
	T.eq(P.Dwell(900), P.DWELL, "short stand")
	local x, y = P.ApproachPoint(0, 0, 3000, 0, 500)
	T.near(x, 500, 0.01, "x on the line")
	T.near(y, 0, 0.01, "y on the line")
	x, y = P.ApproachPoint(100, 100, 100, 100, 200)
	T.near(x, 300, 0.01, "at the target: offset in x")
	T.near(y, 100, 0.01, "at the target: y kept")
	x, y = P.RingPoint(0, 0, 1)
	T.near(x, P.RING_RADIUS, 0.01, "ring point 1")
	T.near(y, 0, 0.01, "ring point 1 y")
	T.eq(P.Nearest(P.WATCHER_SPOTS, 1000, -4000), 1, "the south watcher")
	T.eq(P.Nearest(P.WATCHER_SPOTS, 3000, 0), 2, "the east watcher")
end)

T.test("interact probe: ability list lines", function()
	local P = load()
	T.eq(P.SlotEntry(20, "ability_lamp_use", true, true, 1), "20:ability_lamp_use:h=true:c=true:l=1", "entry")
	local entries = {}
	for i = 1, 25 do
		entries[i] = "e" .. i
	end
	local parts = P.Parts(entries)
	T.eq(#parts, 3, "25 entries in 3 lines")
	T.ok(string.find(parts[1], "part=1/3 n=25 list=e1,", 1, true) ~= nil, "first part")
	T.ok(string.find(parts[3], "list=e25$") ~= nil, "last part")
	T.eq(P.Parts({})[1], "part=1/1 n=0 list=", "empty list still prints one line")
end)

T.test("interact probe: off and silent without the setting", function()
	local P = load()
	T.stub.time = 10
	T.eq(P.Desire(GetBot()), nil, "no desire")
	T.eq(P.Think(GetBot()), false, "no orders")
end)
