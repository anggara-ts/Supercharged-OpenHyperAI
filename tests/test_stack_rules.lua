-- bots/lib/systems/stack_rules.lua: supports stacking a camp on the minute (#229).
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lion" })
	return require(GetScriptDirectory() .. "/lib/systems/stack_rules")
end

-- A pos 5 at 5:20 with nothing in the way.
local function facts(over)
	local f = {
		pos = 5,
		time = 5 * 60 + 20,
		lastStackAt = nil,
		hp = 1,
		partnerThreat = false,
		laneBehind = false,
		groupUp = false,
		enemyNear = false,
		otherMode = false,
		wardWanted = false,
	}
	for k, v in pairs(over or {}) do
		f[k] = v
	end
	return f
end

T.test("clock: second and minute", function()
	local R = rules()
	local sec, minute = R.Clock(5 * 60 + 53.5)
	T.near(sec, 53.5, 0.001)
	T.eq(minute, 5)
end)

T.test("start: pos 4/5 only, from 3:00 to 20:00, in the pick window", function()
	local R = rules()
	T.eq(R.CanStart(facts()), true)
	T.eq(select(2, R.CanStart(facts({ pos = 1 }))), "not-support")
	T.eq(select(2, R.CanStart(facts({ pos = 3 }))), "not-support")
	T.eq(R.CanStart(facts({ pos = 4 })), true)
	T.eq(select(2, R.CanStart(facts({ time = 2 * 60 + 20 }))), "too-early")
	T.eq(select(2, R.CanStart(facts({ time = 20 * 60 + 20 }))), "too-late")
	-- :10 is before the window, :45 after it (the bot could not reach a camp by :47).
	T.eq(select(2, R.CanStart(facts({ time = 5 * 60 + 10 }))), "not-pick-window")
	T.eq(select(2, R.CanStart(facts({ time = 5 * 60 + 45 }))), "not-pick-window")
end)

T.test("start: one stack per two minutes in the lane phase, every minute after 10:00", function()
	local R = rules()
	T.eq(select(2, R.CanStart(facts({ lastStackAt = 4 * 60 + 20 }))), "laning-gap")
	T.eq(R.CanStart(facts({ lastStackAt = 3 * 60 + 20 })), true)
	T.eq(R.CanStart(facts({ time = 12 * 60 + 20, lastStackAt = 11 * 60 + 20 })), true)
end)

T.test("start: not while the lane core is threatened (lane phase), the lane is behind, or unsafe", function()
	local R = rules()
	T.eq(select(2, R.CanStart(facts({ partnerThreat = true }))), "partner-threat")
	-- After the lane phase the partner is not tied to the support any more.
	T.eq(R.CanStart(facts({ time = 12 * 60 + 20, partnerThreat = true })), true)
	T.eq(select(2, R.CanStart(facts({ laneBehind = true }))), "lane-behind")
	T.eq(select(2, R.CanStart(facts({ hp = 0.5 }))), "low-hp")
	T.eq(select(2, R.CanStart(facts({ enemyNear = true }))), "enemy-near")
	T.eq(select(2, R.CanStart(facts({ groupUp = true }))), "group-up")
	T.eq(select(2, R.CanStart(facts({ otherMode = true }))), "other-mode")
	T.eq(select(2, R.CanStart(facts({ wardWanted = true }))), "ward")
end)

T.test("partner: 5 with 1, 4 with 3; threat when hit, low or facing two", function()
	local R = rules()
	T.eq(R.PartnerPosition(5), 1)
	T.eq(R.PartnerPosition(4), 3)
	T.eq(R.PartnerPosition(2), nil)
	T.eq(R.PartnerThreat(true, 0.9, false, 1), false)
	T.eq(R.PartnerThreat(true, 0.9, true, 0), true)
	T.eq(R.PartnerThreat(true, 0.4, false, 0), true)
	T.eq(R.PartnerThreat(true, 0.9, false, 2), true)
	-- A dead core: nothing to protect in lane.
	T.eq(R.PartnerThreat(false, 0, false, 3), false)
end)

local function camp(over)
	local c = {
		ourSide = true,
		type = "large",
		time = 5 * 60 + 35,
		dist = 2000,
		speed = 300,
		enemyNear = false,
		dangerous = false,
		claimed = false,
	}
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

T.test("camp: ours, arriving between :39 and :47, not claimed, no enemy; ancients only after 10:00", function()
	local R = rules()
	-- 2000 - 650 = 1350 at 300/s = 4.5s, x1.5 for the path = 6.75s: from :35 it arrives at :41.75.
	T.eq(R.CampOk(camp()), true)
	T.eq(select(2, R.CampOk(camp({ ourSide = false }))), "not-our-side")
	T.eq(select(2, R.CampOk(camp({ type = "ancient" }))), "ancient-early")
	T.eq(R.CampOk(camp({ type = "ancient", time = 11 * 60 + 35 })), true)
	T.eq(select(2, R.CampOk(camp({ dist = 4000 }))), "far")
	-- Leaving at :20 it would stand at the camp for half a minute: wait.
	T.eq(select(2, R.CampOk(camp({ time = 5 * 60 + 20 }))), "early")
	-- 3400: 13.75s, from :39 that is :52.75.
	T.eq(select(2, R.CampOk(camp({ time = 5 * 60 + 39, dist = 3400 }))), "late")
	T.eq(select(2, R.CampOk(camp({ claimed = true }))), "claimed")
	T.eq(select(2, R.CampOk(camp({ enemyNear = true }))), "enemy")
	T.eq(select(2, R.CampOk(camp({ dangerous = true }))), "enemy")
end)

T.test("pick: the nearest allowed camp, enemy checks only for allowed camps, each camp keeps its reason", function()
	local R = rules()
	local t = 5 * 60 + 38
	local far = camp({ time = t, dist = 2400 })
	local near = camp({ time = t, dist = 1200 })
	local enemySide = camp({ time = t, dist = 500, ourSide = false })
	T.eq(R.PickCamp({ far, enemySide, near }), near)
	T.eq(enemySide.why, "not-our-side")
	T.eq(far.why, "ok")
	-- The enemy check runs nearest first and stops at the first safe camp.
	local asked = {}
	local picked = R.PickCamp({ far, enemySide, near }, function(c)
		asked[#asked + 1] = c.dist
		return c == near
	end)
	T.eq(picked, far)
	T.eq(near.why, "enemy")
	T.eq(#asked, 2)
	T.eq(asked[1], 1200)
	T.eq(R.PickCamp({ enemySide }), nil)
	T.eq(R.PickCamp({}), nil)
end)

T.test("pick: a nearer camp that is still early wins over a farther one that could go now", function()
	local R = rules()
	local t = 5 * 60 + 30
	-- 1200: arrives :32.75 (early); 2500: arrives :39.25 (ok).
	local near = camp({ time = t, dist = 1200 })
	local far = camp({ time = t, dist = 2500 })
	T.eq(R.PickCamp({ near, far }), nil)
	T.eq(near.why, "early")
	T.eq(R.AnyEarly({ near, far }), true)
	T.eq(R.AnyEarly({ far }), false)
	-- Alone, the farther camp goes.
	T.eq(R.PickCamp({ camp({ time = t, dist = 2500 }) }) ~= nil, true)
end)

T.test("order second: the hit lands at the camp's pull second; a walk starts it earlier, never before :50", function()
	local R = rules()
	-- Ranged hero in range: order at the pull second.
	T.near(R.OrderSecond("large", 500, 600, 300), 54, 0.001)
	T.near(R.OrderSecond("small", 500, 600, 300), 55, 0.001)
	T.near(R.OrderSecond("ancient", 500, 600, 300), 53, 0.001)
	-- Melee 450 short at 300/s: 1.5s earlier.
	T.near(R.OrderSecond("medium", 600, 150, 300), 52.5, 0.001)
	-- Far away: clamped to :50.
	T.near(R.OrderSecond("large", 2000, 150, 300), 50, 0.001)
	-- Unknown type: the default.
	T.near(R.OrderSecond(nil, 100, 600, 300), R.PULL_SECOND_DEFAULT, 0.001)
end)

T.test("point from camp: on the line to the bot, at the distance", function()
	local R = rules()
	local x, y = R.PointFromCamp(0, 0, 300, 400, 1000)
	T.near(x, 600, 0.01)
	T.near(y, 800, 0.01)
	-- Bot on the camp centre: any direction, still at the distance.
	x, y = R.PointFromCamp(100, 100, 100, 100, 500)
	T.near(math.sqrt((x - 100) ^ 2 + (y - 100) ^ 2), 500, 0.01)
end)

T.test("result: more creeps after the spawn = stacked; unseen camp = unknown", function()
	local R = rules()
	T.eq(R.Result(3, 6, true), "yes")
	T.eq(R.Result(3, 3, true), "no")
	T.eq(R.Result(3, 2, true), "no")
	-- More creeps than before were seen, even with the camp centre out of sight: stacked.
	T.eq(R.Result(3, 6, false), "yes")
	-- Out of sight and not more than before: unknown, not "no".
	T.eq(R.Result(3, 0, false), "unknown")
	T.eq(R.Result(3, 3, false), "unknown")
	T.eq(R.Result(3, nil, true), "unknown")
	T.eq(R.Result(nil, 2, true), "yes")
end)

-- Game 087, 9:49: a camp with no creep in sight from the wait spot was called empty (visible=0).
T.test("wait, no creep: out of sight is stepped in on, not empty; in sight and empty only near the order", function()
	local R = rules()
	-- In sight, no creep: hold until :48, then empty.
	T.eq(R.NoCreepAction(true, 650, 45, false), "hold")
	T.eq(R.NoCreepAction(true, 650, 48, false), "empty")
	T.eq(R.NoCreepAction(true, 650, 2, true), "empty")
	-- Out of sight: step in, at any second before the latest hit.
	T.eq(R.NoCreepAction(false, 650, 42, false), "step")
	T.eq(R.NoCreepAction(false, 650, 52, false), "step")
	-- Stepped in to STEP_MIN and still out of sight: hold, then unknown (never "empty").
	T.eq(R.NoCreepAction(false, R.STEP_MIN, 45, false), "hold")
	T.eq(R.NoCreepAction(false, R.STEP_MIN, 49, false), "unseen")
	T.eq(R.NoCreepAction(false, 650, R.LATEST_HIT, false), "unseen")
	T.eq(R.NoCreepAction(false, 650, 3, true), "unseen")
end)

-- Game 087, 14:05 and 15:05: counted from the exit point (1300), the camp was out of sight: stacked=unknown.
T.test("check: exit point until :05, step in until the camp is in sight, count for a while, give up at :12", function()
	local R = rules()
	-- Before CHECK_SECOND: at the exit point.
	T.eq(R.CheckAction(2, false, nil, nil, 3, 1300), "exit")
	-- Out of sight after it: step in.
	T.eq(R.CheckAction(R.CHECK_SECOND, false, nil, 3, 3, 1300), "step")
	-- In sight: hold and keep counting for CHECK_LOOK, then done.
	T.eq(R.CheckAction(6, true, 6, 3, 3, 800), "hold")
	T.eq(R.CheckAction(6 + R.CHECK_LOOK, true, 6, 3, 3, 800), "done")
	-- More creeps than before: done at once (in sight or not).
	T.eq(R.CheckAction(6, false, nil, 5, 3, 1100), "done")
	-- At STEP_MIN and still out of sight: hold until CHECK_UNTIL, then done (the result is unknown).
	T.eq(R.CheckAction(9, false, nil, 0, 3, R.STEP_MIN), "hold")
	T.eq(R.CheckAction(R.CHECK_UNTIL, false, nil, 0, 3, R.STEP_MIN), "done")
	T.eq(R.Result(3, 0, false), "unknown")
end)
