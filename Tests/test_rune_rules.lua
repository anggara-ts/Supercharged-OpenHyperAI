-- FuncLib/systems/rune_rules.lua (#32): the leftover-rune hold and the capped pick-up retries of mode_rune_generic.lua.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_clinkz" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/rune_rules")
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
	T.eq(R.WisdomTrip(140, 0.4, -8), "window", "on the shrine at the window end: window, not cant-arrive")
	T.eq(R.WisdomTrip(140, 0.4, -5), "go", "on the shrine with 3s left: stay")
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
	local step, after = R.LotusTakeStep(state, 2, 183)
	T.eq(step, "leave", "nothing for 1s: leave")
	T.eq(after, 1.5, "1.5s after the first lotus")
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
	T.eq(gapStood, 0, "a 5s gap is not standing")
	T.eq(gapHeld, 0, "nor holding")
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
