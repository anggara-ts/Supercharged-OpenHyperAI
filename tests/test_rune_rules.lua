-- bots/lib/systems/rune_rules.lua (#32): the leftover-rune hold and the capped pick-up retries of mode_rune_generic.lua.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_clinkz" })
	return require(GetScriptDirectory() .. "/lib/systems/rune_rules")
end

T.test("rune rules: what counts as a leftover rune", function()
	local R = load()
	-- Game 063, 30:29: the bottom river spot read available, type -1, in vision, 29s into its cycle.
	T.eq(R.IsLeftover(true, -1, nil, true, 29), true, "available, no type, seen")
	T.eq(R.IsLeftover(true, 9, 9, true, 29), true, "RUNE_INVALID counts as no type")
	T.eq(R.IsLeftover(true, 5, nil, true, 29), false, "a typed rune (bounty) is a normal rune")
	T.eq(R.IsLeftover(false, -1, nil, true, 29), false, "missing")
	T.eq(R.IsLeftover(true, -1, nil, false, 29), false, "spot not in vision: the status is stale")
	-- Game 017: just after a spawn the type reads -1 before the rune shows.
	T.eq(R.IsLeftover(true, -1, nil, true, 3), false, "first 10s of the cycle")
end)

T.test("rune rules: passing grab leaves a rune to a closer ally only while it goes for it", function()
	local R = load()
	T.eq(R.PassingYield(false, false, false, 0), false, "no closer ally: take it")
	T.eq(R.PassingYield(true, true, false, 5), true, "a closer human always has it")
	T.eq(R.PassingYield(true, false, true, 5), true, "a closer bot in the rune mode has it")
	T.eq(R.PassingYield(true, false, false, 0.4), true, "a closer bot gets a second to switch to the rune mode")
	-- Game 066, 78:01: the closer allies kept chasing and nobody took the invisibility rune 357 away.
	T.eq(R.PassingYield(true, false, false, 1.2), false, "a closer bot still not in the rune mode after 1s gave it up")
end)

T.test("rune rules: leftover hold steps", function()
	local R = load()
	local hold = { t0 = 100 }
	T.eq(R.LeftoverStep(hold, 100.5, 80, true, false, false), "try", "the one pick-up order has its time")
	T.eq(R.LeftoverStep(hold, 102, 120, true, false, false), "walk", "then onto the spot")
	T.eq(R.LeftoverStep(hold, 102.5, 30, true, false, false), "hold", "on the spot")
	T.eq(R.HeldFor(hold, 104), 1.5, "held 1.5s")
	local phase, why = R.LeftoverStep(hold, 105.6, 30, true, false, false)
	T.eq(phase, "end", "3s on the spot ends it")
	T.eq(why, "held", "why=held")
	local _, gone = R.LeftoverStep({ t0 = 100 }, 101, 80, false, false, false)
	T.eq(gone, "taken", "the rune went (the order or the item mode took it)")
	local _, typed = R.LeftoverStep({ t0 = 100 }, 101, 80, true, true, false)
	T.eq(typed, "typed", "the type showed up: back to the normal pick-up")
	local _, fight = R.LeftoverStep({ t0 = 100 }, 101, 80, true, false, true)
	T.eq(fight, "fight", "enemy heroes at the spot")
	-- Never stuck: a bot that can't get onto the spot ends after GIVE_UP.
	local late, timeout = R.LeftoverStep({ t0 = 100 }, 100 + R.GIVE_UP + 0.1, 500, true, false, false)
	T.eq(late, "end", "timeout ends it")
	T.eq(timeout, "timeout", "why=timeout")
	-- Walking off the spot restarts the on-spot clock.
	local moved = { t0 = 100 }
	R.LeftoverStep(moved, 102, 30, true, false, false)
	R.LeftoverStep(moved, 103, 200, true, false, false)
	T.eq(moved.onSpotAt, nil, "off the spot: clock reset")
end)

T.test("rune rules: pick-up retries capped at 3, 1s apart", function()
	local R = load()
	local try = { n = 0 }
	local orders = 0
	-- Game 063: 19 orders in 3s at distance 0. Thinks every 0.1s for 5s.
	local failedAt
	for i = 0, 50 do
		local now = i * 0.1
		local step = R.PickupStep(try, now)
		if step == "order" then
			orders = orders + 1
			try.n = try.n + 1
			try.last = now
		elseif step == "fail" then
			failedAt = now
			break
		end
	end
	T.eq(orders, 3, "three orders")
	T.ok(
		failedAt ~= nil and failedAt >= 2.9 and failedAt <= 3.1,
		"fails 1s after the third order: " .. tostring(failedAt)
	)
end)

T.test("rune rules: the spawn hold window at a river spot", function()
	local R = load()
	-- Game 064, 2:00: Puck 475 from the top spot at the spawn.
	T.eq(R.SpawnHold(0.1, 475), true, "475 away at the spawn")
	T.eq(R.SpawnHold(-2, 590), true, "2s before the spawn, 590 away")
	T.eq(R.SpawnHold(-2.5, 300), false, "earlier: the normal walk desire")
	T.eq(R.SpawnHold(3, 500), true, "3s after the spawn")
	T.eq(R.SpawnHold(3.2, 500), false, "the hold ends 3s after the spawn")
	T.eq(R.SpawnHold(1, 700), false, "farther than 600")
	T.ok(R.SPAWN_HOLD_DESIRE > 0.56, "above laning's 0.54-0.56 in game 064")
end)

T.test("rune mode: a bot 475 from a river spot at the 2:00 spawn holds above laning (game 064)", function()
	T.stub.reset({ hero = "npc_dota_hero_puck" })
	local ok, err = T.stub.load("mode_rune_generic")
	T.ok(ok, tostring(err))
	local bot = GetBot()
	local spot = bot:GetLocation() + Vector(475, 0, 0)
	bot._waterWalk = { id = 0, loc = spot, t0 = 120 }
	T.stub.time = 120.1
	local desire = GetDesire()
	T.near(desire, 0.6, 1e-9, "spawn hold desire")
	local started, ended = nil, nil
	T.stub.time = 121
	bot._loc = spot + Vector(250, 0, 0)
	GetDesire()
	for _, line in ipairs(T.stub.printed) do
		started = started or (string.find(line, "river%-spawn%-hold spot=0 dist=475 since=0%.1") and line)
		ended = ended or (string.find(line, "river%-spawn%-hold%-end why=on%-spot spot=0 dist=250 held=0%.9") and line)
	end
	T.ok(started ~= nil, "start line")
	T.ok(ended ~= nil, "end line: the on-spot stay takes over")
end)

T.test("rune rules: the water-rune walk desire by distance to the spot (game 065)", function()
	local R = load()
	-- Game 065, t=112.7: Puck 2188 from the top spot, the team's closest hero, walked at 0.53 and laning (0.56) won.
	T.eq(R.RiverWalkDesire(2188, 1, 0.525), 0.6, "closest on the team: 0.6 at any distance")
	T.eq(R.RiverWalkDesire(1846, 2, 0.525), 0.6, "within 2000: 0.6 even with an ally closer")
	T.eq(R.RiverWalkDesire(2100, 2, 0.525), 0.525, "farther and not the closest: the old desire")
	T.eq(R.RiverWalkDesire(2211, 1, 0.35), 0.6, "after the spawn (t=120.3, 2211 away): 0.6 too")
	T.eq(R.RiverWalkDesire(500, 3, 0.75), 0.75, "never lowers a higher desire")
	T.ok(R.RIVER_WALK_DESIRE > 0.56, "above laning's 0.56 in game 065")
end)

T.test("rune mode: the water walk before the spawn beats laning near the spot (game 065)", function()
	T.stub.reset({ hero = "npc_dota_hero_puck" })
	local ok, err = T.stub.load("mode_rune_generic")
	T.ok(ok, tostring(err))
	local bot = GetBot()
	-- Every ally 1800-2000 from the spot (stub slots stand side by side): rank > 1, but within 2000.
	local spot = bot:GetLocation() + Vector(1900, 0, 0)
	bot._waterWalk = { id = 0, loc = spot, t0 = 120 }
	T.stub.time = 113
	T.near(GetDesire(), 0.6, 1e-9, "1900 away, 7s before the spawn")
	local line
	for _, printed in ipairs(T.stub.printed) do
		line = line or (string.find(printed, "river%-walk%-near spot=0 dist=1900 rank=%d des=0%.60") and printed)
	end
	T.ok(line ~= nil, "river-walk-near line")
	-- 2100 away with allies closer: the old pre-spawn desire.
	bot._waterWalk = { id = 0, loc = bot:GetLocation() + Vector(2100, 0, 0), t0 = 120 }
	T.ok(GetDesire() < 0.6, "2100 away, not the closest: below 0.6")
end)

T.test("rune rules: wisdom shrine trip and stand", function()
	local R = load()
	-- 7.42 game data: ability_xp_fountain radius 300; the shrine's RingRadius 100 stops a hero at ~140.
	T.ok(R.WISDOM_STAND < R.WISDOM_RADIUS and R.WISDOM_STAND > 140, "stand distance reachable and inside the radius")
	-- Game 068 t=428: Vengeful Spirit at dist=140, travel 0.4s, eta -8 read cant-arrive.
	-- Games 082-085: four bots reached the shrine at 139-140 as the window closed (`give-up why=window late=8`). On the
	-- shrine the window runs WISDOM_LATE_STAND longer, so the stand runs out.
	T.eq(R.WisdomTrip(140, 0.4, -8), "go", "on the shrine at the window end: stay for the stand")
	T.eq(R.WisdomTrip(140, 0.4, -5), "go", "on the shrine with 3s left: stay")
	T.eq(R.WisdomTrip(140, 0.4, -12), "go", "on the shrine 12s after the mark: still standing")
	T.eq(R.WisdomTrip(140, 0.4, -12.6), "window", "past the late stand: window")
	T.eq(R.WisdomTrip(300, 1, -8), "window", "not on the shrine at the window end: window")
	T.eq(R.WisdomStayAfter(140), R.WISDOM_STAY + R.WISDOM_LATE_STAND, "on the shrine: the longer window")
	T.eq(R.WisdomStayAfter(2000), R.WISDOM_STAY, "elsewhere: the 8s window")
	T.ok(R.WISDOM_LATE_STAND > R.WISDOM_COVER, "the late stand fits a whole stand")
	-- The mark a stand is for: the next one from 40s before it (games 083-085: `taken ... late=419` before the mark).
	T.eq(R.WisdomStandMark(836, 420), 840, "4s before the 14:00 mark: that mark")
	T.eq(R.WisdomStandMark(844, 420), 840, "after the mark: that mark")
	T.eq(R.WisdomStandMark(852, 420), 840, "12s after: still that mark")
	T.eq(R.WisdomStandMark(700, 420), 420, "far from the next mark: the last one")
	-- Phoenix, game 085: on the shrine from 835.5; the clock runs before the mark but nothing is done before it (the
	-- caller needs now >= mark), and at the mark it restarts.
	local mark = R.WisdomStandMark(835.5, 420)
	T.ok(835.5 < mark, "before the mark: the stand waits for it")
	T.eq(R.WisdomStandFrom(835.5, mark, 840.1), 840, "the mark passed: the stand counts from it")
	T.eq(R.WisdomTrip(7225, 24, 8), "cant-arrive", "24s walk with 16s left")
	T.eq(R.WisdomTrip(2000, 6, -7.5), "window", "under 1s left: the window, not the walk")
	T.eq(R.WisdomTrip(2679, 7, 12), "go", "7s walk with 20s left")
	-- The stand clock starts at the mark.
	T.eq(R.WisdomStandFrom(nil, 0, 412), 412, "first think on the shrine")
	T.eq(R.WisdomStandFrom(412, 0, 415), 412, "before the mark the clock keeps running")
	T.eq(R.WisdomStandFrom(412, 420, 420.1), 420, "the mark passed while standing: counts from the mark")
	T.eq(R.WisdomStandFrom(420, 420, 423), 420, "after the mark it stays")
end)

T.test("rune rules: a takeover claims the rune for the team", function()
	local R = load()
	-- Game 069 40:18-40:22: Vengeful Spirit, then Puck, then Zeus took the same rune over from each other.
	local claim = R.NextClaim(nil, "vengefulspirit", 2418, false)
	T.eq(R.ClaimedByOther(claim, "puck", 2419), true, "Puck leaves it to Vengeful Spirit")
	T.eq(R.ClaimedByOther(claim, "vengefulspirit", 2419), false, "not for the holder")
	claim = R.NextClaim(claim, "vengefulspirit", 2418.8, false)
	T.eq(claim.untilAt, 2418.8 + R.PASS_TAKE_FOR, "renewed within PASS_WAIT of the claim")
	claim = R.NextClaim(claim, "vengefulspirit", 2420, false)
	T.eq(claim.untilAt, 2418.8 + R.PASS_TAKE_FOR, "not in the rune mode after 1s: not renewed")
	T.eq(R.ClaimedByOther(claim, "zuus", 2422), false, "lapsed after 3s: Zeus may take it")
	claim = R.NextClaim(claim, "zuus", 2422, true)
	T.eq(claim.holder, "zuus", "a new holder once it lapsed")
	claim = R.NextClaim(claim, "zuus", 2424, true)
	T.eq(claim.untilAt, 2424 + R.PASS_TAKE_FOR, "renewed while in the rune mode")
end)

T.test("rune rules: XP gained from the XP still needed and the level", function()
	local R = load()
	local gain, leveled = R.XpGain(800, 10, 500, 10)
	T.eq(gain, 300, "same level: the drop")
	T.eq(leveled, false, "no level up")
	gain, leveled = R.XpGain(200, 10, 900, 11)
	T.eq(gain, 200, "level up: at least what was still needed")
	T.eq(leveled, true, "level up")
	T.eq((R.XpGain(500, 10, 500, 10)), 0, "nothing")
	T.eq((R.XpGain(nil, 10, 500, 10)), 0, "unknown start")
end)

T.test("rune rules: a shrine stand runs the countdown out", function()
	local R = load()
	-- Live game 2026-11-23: largo t=423 xp=+1 stood=0.3, winter_wyvern t=428 xp=+1 stood=1.2 left as "taken".
	T.eq(R.WisdomStandDone(0.3, 1, false), false, "0.3s with +1 XP: keep standing")
	T.eq(R.WisdomStandDone(1.2, 400, false), false, "a big gain before the 3s countdown is not the shrine's")
	local done, label = R.WisdomStandDone(3.6, 1, false)
	T.eq(done, true, "the countdown ran out")
	T.eq(label, "covered", "+1 XP: covered")
	done, label = R.WisdomStandDone(3.6, R.WISDOM_BIG_XP, false)
	T.eq(label, "taken", "a big gain: taken")
	done, label = R.WisdomStandDone(3.6, 20, true)
	T.eq(label, "taken", "a level up: taken")
end)

T.test("rune rules: the lotus stand ends a second after the lotus is taken", function()
	local R = load()
	local state = { base = 0 }
	T.eq(R.LotusTakeStep(state, 0, 180), "wait", "no lotus yet")
	T.eq(R.LotusTakeStep(state, 1, 181.5), "wait", "just taken: a second one may come 0.45s later")
	T.eq(R.LotusTakeStep(state, 2, 182), "wait", "a second one came")
	local step, after, gap = R.LotusTakeStep(state, 2, 183)
	T.eq(step, "leave", "nothing for 1s: leave")
	T.eq(after, 1.5, "1.5s after the first lotus")
	T.eq(gap, 1, "1s after the last one")
	-- Game 084 t=2706, Lone Druid's bear took five lotuses' worth in a row: after= counts from the first, gap= from the
	-- last.
	local bear = { base = 0 }
	local t = 2701.6
	for value = 1, 5 do
		T.eq(R.LotusTakeStep(bear, value, t), "wait", "lotus " .. value .. " taken: wait for another")
		t = t + 0.45
	end
	local bstep, bafter, bgap
	repeat
		t = t + 0.1
		bstep, bafter, bgap = R.LotusTakeStep(bear, 5, t)
	until bstep == "leave"
	T.ok(bafter > 2, "after= over 2 for five lotuses")
	T.ok(bgap < 1.2, "gap= about 1s")
	local eaten = { base = 2 }
	T.eq(R.LotusTakeStep(eaten, 1, 190), "wait", "one eaten while standing is no lotus taken")
	T.eq(eaten.base, 1, "the base follows it down")
end)

T.test("rune rules: lotus value counts the tiers, so a merging pickup still rises", function()
	local R = load()
	T.eq(R.LotusValue({}), 0, "no lotus")
	T.eq(R.LotusValue({ { name = "item_famango", charges = 2 } }), 2, "two Healing Lotuses")
	-- A third lotus merges three Healing Lotuses into one Great (the recipe consumes the charges): 2 -> 3, not 2 -> 1.
	T.eq(R.LotusValue({ { name = "item_great_famango", charges = 1 } }), 3, "one Great Healing Lotus")
	T.eq(
		R.LotusValue({ { name = "item_greater_famango", charges = 1 }, { name = "item_tango", charges = 3 } }),
		6,
		"other items don't count"
	)
end)

-- Runs a stand from 'from' to 'to' in 0.1s thinks at one distance; returns the first result that isn't "wait" (or
-- "wait"), the time it came, and stood / held.
local function standRun(R, stand, from, to, value, dist, contested)
	local t = from
	local result, stood, held = R.LotusStandStep(stand, t, value, dist, contested)
	while result == "wait" and t < to - 1e-6 do
		t = t + 0.1
		result, stood, held = R.LotusStandStep(stand, t, value, dist, contested)
	end
	return result, t, stood, held
end

T.test("rune rules: the lotus stand reads taken or gone from the bot's own lotuses (game 074)", function()
	local R = load()
	-- Game 074, 6:00: Winter Wyvern in the pool (132) from 357.5, the lotus came at 361.4.
	local stand = R.NewLotusStand(360, 0)
	T.eq(R.LotusStandStep(stand, 357.5, 0, 132, false), "wait", "before the spawn")
	T.eq(standRun(R, stand, 360, 361.3, 0, 132, false), "wait", "1.3s stood, no lotus yet")
	local result, stood = R.LotusStandStep(stand, 361.4, 1, 132, false)
	T.eq(result, "taken", "a lotus came")
	T.ok(stood < R.LOTUS_STAND_WAIT, "taken before the wait ran out")
	T.eq(R.LotusStandStep(stand, 361.5, 0, 132, false), "taken", "the result stays (eaten right after)")

	-- Game 074, 3:00: in the pool from 176.9, someone else took the spawn. The stand now ends 2.5s after the mark
	-- instead of the 45s window (she stood and fought there until she died at 199).
	local gone = R.NewLotusStand(180, 0)
	R.LotusStandStep(gone, 176.9, 0, 132, false)
	local res, at = standRun(R, gone, 180, 190, 0, 132, false)
	T.eq(res, "gone", "no lotus: gone")
	T.near(at, 180 + R.LOTUS_STAND_WAIT, 0.15, "gone 2.5s after the spawn")
	local contested = R.NewLotusStand(180, 0)
	res, at = standRun(R, contested, 180, 190, 0, 132, true)
	T.eq(res, "gone", "contested: gone too")
	T.near(at, 180 + R.LOTUS_STAND_WAIT_CONTESTED, 0.15, "an enemy hero in the pool: 3.5s")
	-- An eaten lotus is no pickup.
	local eaten = R.NewLotusStand(180, 2)
	T.eq(R.LotusStandStep(eaten, 180, 1, 132, false), "wait", "ate one")
	T.eq(R.LotusStandStep(eaten, 180.1, 2, 132, false), "taken", "and picked one: taken")
end)

T.test("rune rules: lotus stand time counts in the pluck ring only, keeps across a push-out, and has a cap", function()
	local R = load()
	-- Game 074 3:00: pushed out to 456 at t=186, back in the pool later.
	local stand = R.NewLotusStand(180, 0)
	standRun(R, stand, 180, 181, 0, 132, false) -- 1s in the ring
	standRun(R, stand, 181.1, 183, 0, 456, false) -- pushed out: not counted
	standRun(R, stand, 183.1, 184, 0, 250, false) -- fighting in the area but outside the ring: not counted
	local result, _, stood = standRun(R, stand, 184.1, 184.5, 0, 132, false)
	T.eq(result, "wait", "1.5s stood in the ring")
	T.near(stood, 1.5, 0.05, "time out of the ring doesn't count, the count keeps across it")
	-- A long gap (another mode won) adds nothing.
	local gap = R.NewLotusStand(180, 0)
	R.LotusStandStep(gap, 180, 0, 132, false)
	local _, _, gapStood, gapHeld = standRun(R, gap, 185, 185, 0, 132, false)
	T.eq(gapStood, 0, "a 5s gap (another mode, a retreat pause) is not standing")
	T.eq(gapHeld, 5, "held is wall time (the cap)")
	-- Never in the ring: the cap ends it after 10s of thinks within 800.
	local away = R.NewLotusStand(180, 0)
	T.eq(standRun(R, away, 185, 186, 0, 1300, false), "wait", "walking, not near yet")
	local capped, at, _, held = standRun(R, away, 186.1, 200, 0, 500, false)
	T.eq(capped, "cap", "10s near without standing in the ring: cap")
	T.near(at, 196.1, 0.15, "10s after it came within 800")
	T.ok(held <= R.LOTUS_HOLD_CAP + 0.15, "held= is the cap")
	-- Taken but never leaving (the take step missed it): the cap still ends it.
	local taken = R.NewLotusStand(180, 0)
	T.eq(R.LotusStandStep(taken, 180, 1, 132, false), "taken", "taken at once")
	local after, t = "taken", 180
	while after == "taken" and t < 195 do
		t = t + 0.1
		after = R.LotusStandStep(taken, t, 1, 320, false)
	end
	T.eq(after, "cap", "held 10s more after taken: cap")
	T.near(t, 190, 0.15, "10s after the stand began")
end)

T.test("rune rules: the lotus hold gives way when retreat asks (game 074)", function()
	local R = load()
	-- Game 074 retreat desires while Leshrac hit Winter Wyvern at the pool: 0.30 (t=184), 0.34, 0.40 (t=193), 0.61.
	T.eq(R.LotusHoldYields(0.297), true, "0.30 as printed: yield")
	T.eq(R.LotusHoldYields(0.34), true, "0.34: yield")
	T.eq(R.LotusHoldYields(0.40), true, "0.40: yield")
	T.eq(R.LotusHoldYields(0.61), true, "0.61: yield")
	T.eq(R.LotusHoldYields(0.18), false, "a healthy bot with an enemy near: hold")
	T.eq(R.LotusHoldYields(nil), false, "no fresh retreat desire: hold")
end)

T.test("rune rules: the lotus hold pauses for retreat and resumes while the spawn is open (game 074)", function()
	local R = load()
	-- Game 074, Winter Wyvern at the bottom pool: retreat 0.30 at t=184, 0.34, then (assumed) back under the line,
	-- 0.40 at t=193 and 0.61 at t=196.
	local state = {}
	T.eq(R.LotusYieldStep(state, 0.297, true, false), "yield-start", "t=184 retreat 0.30: pause the hold")
	T.eq(R.LotusYieldStep(state, 0.34, true, false), "yield", "0.34: still paused")
	T.eq(R.LotusYieldStep(state, 0.18, true, false), "resume", "retreat back under the line: hold again")
	T.eq(R.LotusYieldStep(state, 0.18, true, false), "hold", "holding")
	T.eq(R.LotusYieldStep(state, 0.40, true, false), "yield-start", "t=193 retreat 0.40: pause again")
	T.eq(R.LotusYieldStep(state, 0.61, true, false), "yield", "t=196 retreat 0.61: paused")
	T.eq(R.LotusYieldStep(state, 0.61, true, true), "drop", "the cap ran out while paused: the spawn is dropped")
	local window = { yielding = true }
	T.eq(R.LotusYieldStep(window, 0.5, false, false), "drop", "the window closed while paused: dropped")
	T.eq(R.LotusYieldStep({}, 0.18, true, true), "hold", "cap while holding: the stand's own cap result ends it")
	T.eq(R.LotusYieldStep({}, nil, true, false), "hold", "no fresh retreat desire: hold")
	-- Game 083 t=180-199, Zeus: yield, resume from 463 / 1074 away, and the cap only at held=18.4. A resumed hold is
	-- dropped on the cap, the window end or beyond LOTUS_RESUME_DIST, like a paused one.
	local zeus = {}
	T.eq(R.LotusYieldStep(zeus, 0.36, true, false, false), "yield-start", "t=180 retreat 0.36")
	T.eq(R.LotusYieldStep(zeus, 0.21, true, false, false), "resume", "t=180.8 back under the line")
	T.eq(R.LotusYieldStep(zeus, 0.21, true, false, false), "hold", "resumed: holding")
	T.eq(R.LotusYieldStep(zeus, 0.21, true, true, false), "drop", "the cap ran out after the resume: dropped")
	T.eq(zeus.resumed, false, "the state is cleared")
	local resumedClosed = { resumed = true }
	T.eq(R.LotusYieldStep(resumedClosed, 0.1, false, false, false), "drop", "the window closed after a resume")
	local pugna = { yielding = true }
	T.eq(R.LotusYieldStep(pugna, 0, true, false, true), "drop", "game 084 t=395: 10562 away, no resume")
	T.eq(R.LotusYieldStep({}, 0.1, true, false, true), "hold", "never paused: far doesn't matter (beside is 800)")
	-- A pause belongs to its spawn: game 083 Winter Wyvern resumed at 182 and read gone at 188; at the next spawn the
	-- old state must not read resumed (a far bot would drop the new spawn as end=far).
	local old = { mark = 180, resumed = true }
	T.eq(R.LotusYieldFor(old, 360), nil, "the next spawn: no pause state")
	T.eq(R.LotusYieldFor(old, 180), old, "the same spawn: kept")
	T.eq(R.LotusYieldFor(nil, 360), nil, "none")

	-- The ring clock pauses while yielding: 1s stood, a pause 181-184, back in the ring at 184: gone at 1.5s more.
	local stand = R.NewLotusStand(180, 0)
	standRun(R, stand, 180, 181, 0, 132, false)
	stand.lastAt = nil -- the pause (map_objectives sets this on yield)
	local res, at, stood, held = standRun(R, stand, 184, 190, 0, 132, false)
	T.eq(res, "gone", "no lotus after the pause either: gone")
	T.near(at, 185.5, 0.15, "the pause didn't count as standing")
	T.near(stood, R.LOTUS_STAND_WAIT, 0.15, "stood= is ring time only")
	T.near(held, 5.5, 0.15, "held= counts the pause (wall time for the cap)")
end)

T.test("rune rules: the team's own river spot first", function()
	local R = load()
	-- Game 078, 0:00: both mids went to the top spot; Radiant tries top first, Dire bottom first.
	local top, bottom = 0, 1
	T.eq(R.RiverSpotOrder(false, top, bottom)[1], top, "Radiant: top first")
	T.eq(R.RiverSpotOrder(false, top, bottom)[2], bottom, "Radiant: then bottom")
	T.eq(R.RiverSpotOrder(true, top, bottom)[1], bottom, "Dire: bottom first")
	T.eq(R.RiverSpotOrder(true, top, bottom)[2], top, "Dire: then top")
end)

T.test("rune rules: a failed river pick-up lets go of the spot (game 080)", function()
	local R = load()
	-- Game 080, 0:01.7: Winter Wyvern on the bottom spot (dist 0), `river-pickup-try id=1 worked=no`, rune still up.
	T.eq(R.ReleaseStarts("no", 0, true), true, "worked=no on the spot with the rune up")
	T.eq(R.ReleaseStarts("unsure", 0, true), false, "unsure: the water stay holds")
	T.eq(R.ReleaseStarts("yes", 0, false), false, "worked")
	T.eq(R.ReleaseStarts("no", 0, false), false, "already gone")
	T.eq(R.ReleaseStarts("no", R.RELEASE_RADIUS + 1, true), false, "not on the spot")
	T.eq(R.ReleaseStarts("no", nil, true), false, "no distance")
	local release = { t0 = 1.7 }
	T.eq(R.ReleaseStep(release, 2.0, true), "hold", "lets go while the rune is up")
	local step, taken = R.ReleaseStep(release, 3.0, false)
	T.eq(step, "end", "the rune went")
	T.eq(taken, true, "taken=yes")
	step, taken = R.ReleaseStep(release, 1.7 + R.RELEASE_FOR, true)
	T.eq(step, "end", "ends after RELEASE_FOR")
	T.eq(taken, false, "taken=no")
end)

T.test("rune rules: no pick-up order where it never worked; let go at once (games 075-085)", function()
	local R = load()
	local top, bottom, bounty, water = 0, 1, 5, 7
	-- `river-pickup-try`: water at the top spot worked (yes 9, unsure 2); nothing at the bottom spot (no 14 of 14);
	-- bounties and type -1 never.
	T.eq(R.RiverOrderWorks(top, water, top, water), true, "water rune, top spot: the order works")
	T.eq(R.RiverOrderWorks(bottom, water, top, water), false, "water rune, bottom spot: never worked")
	T.eq(R.RiverOrderWorks(top, bounty, top, water), false, "river bounty: never worked")
	T.eq(R.RiverOrderWorks(top, -1, top, water), false, "unknown type: never worked")
	T.eq(R.RiverOrderWorks(top, water, top, nil), false, "no RUNE_WATER in the API: no order")
	-- The plan on a spot with the rune up.
	T.eq(R.RiverTryPlan(true, false, false), "order", "top water rune: the order")
	T.eq(R.RiverTryPlan(false, false, false), "yield", "horn bounty: let go at once")
	T.eq(R.RiverTryPlan(false, false, true), "order", "let go and still up: the order once, then the old release")
	T.eq(R.RiverTryPlan(true, true, false), "yield", "the order failed for this type before: let go instead")
	T.eq(R.RiverTryPlan(true, true, true), "none", "stopped and already let go: the old stay")
	-- The no-order release is short; the old one keeps RELEASE_FOR.
	local yield = { t0 = 0.2, duration = R.YIELD_FOR }
	T.eq(R.ReleaseStep(yield, 0.6, true, 0), "hold", "0.4s in")
	local step, taken = R.ReleaseStep(yield, 0.2 + R.YIELD_FOR, true, 0)
	T.eq(step, "end", "ends after YIELD_FOR")
	T.eq(taken, false, "not taken")
	T.ok(R.YIELD_FOR < R.RELEASE_FOR, "shorter than the release after a failed order")
	-- Games 081-084: releases that began 167-287 off the spot never got the rune. A release off the spot steps back
	-- onto it first; its let-go clock starts there.
	local tusk = { t0 = 1.8, step = true }
	T.eq(R.ReleaseStep(tusk, 1.8, true, 196), "step", "084 Tusk at 196: walk back onto the spot")
	T.eq(R.ReleaseStep(tusk, 2.3, true, 60), "hold", "on the spot: let go")
	T.near(tusk.t0, 2.3, 0.001, "the let-go clock starts on the spot")
	T.near(tusk.stepped, 0.5, 0.001, "stepped= the walk back")
	T.eq(R.ReleaseStep(tusk, 2.3 + R.RELEASE_FOR - 0.1, true, 0), "hold", "the full release from there")
	local blocked = { t0 = 0, step = true }
	T.eq(R.ReleaseStep(blocked, 0, true, 250), "step", "can't get closer yet")
	T.eq(R.ReleaseStep(blocked, R.RELEASE_STEP_FOR, true, 250), "hold", "after RELEASE_STEP_FOR it lets go anyway")
	local gone = { t0 = 0, step = true }
	local gstep, gtaken = R.ReleaseStep(gone, 0.5, false, 250)
	T.eq(gstep, "end", "taken while stepping back")
	T.eq(gtaken, true, "taken=yes")
	T.ok(R.RELEASE_STEP_DESIRE < 0.90, "the step stays under Valve's item mode (0.90)")
end)
