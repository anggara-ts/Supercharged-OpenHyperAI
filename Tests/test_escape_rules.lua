-- FuncLib/systems/escape_rules.lua (#36): escape direction, Jaunt side check, lane Orb spare mana.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_puck" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/escape_rules")
end

T.test("escape rules: away from the enemies, toward home", function()
	local R = load()
	-- No enemy: straight home.
	local x, y = R.Direction(0, 0, {}, -1000, 0)
	T.near(x, -1, 0.001, "home x")
	T.near(y, 0, 0.001, "home y")
	-- An enemy north of her, home west: the jump goes south-west, away from the enemy.
	x, y = R.Direction(0, 0, { { x = 0, y = 500 } }, -1000, 0)
	T.ok(y < 0, "away from the enemy (south)")
	T.ok(x < 0, "and toward home (west)")
	-- Game 064, 43:23: the enemy on the home side. The jump must not go into them.
	x = R.Direction(0, 0, { { x = -400, y = 0 } }, -5000, 0)
	T.ok(x > 0, "enemy between her and home: away from the enemy first")
	-- The nearest enemy counts most.
	x = R.Direction(0, 0, { { x = 300, y = 0 }, { x = -1500, y = 0 } }, 0, 5000)
	T.ok(x < 0, "away from the near one, not the far one")
end)

T.test("escape rules: a Jaunt only to an orb on the escape side", function()
	local R = load()
	T.eq(R.IsOnEscapeSide(0, 0, -800, 100, -1, 0), true, "orb ahead on the escape path")
	T.eq(R.IsOnEscapeSide(0, 0, 800, 100, -1, 0), false, "orb behind her (game 064, t=2600)")
end)

T.test("escape rules: lane Orb harass on spare mana", function()
	local R = load()
	-- Datafeed hero 13: Orb 90 mana, 12s cooldown at rank 1; Rift 100.
	T.eq(R.SpareManaOrb(380, 400, 1.5, 90, 100, 12), true, "nearly full")
	T.eq(R.SpareManaOrb(250, 400, 8, 90, 100, 12), true, "regen pays the orb back over its cooldown")
	T.eq(R.SpareManaOrb(250, 400, 1.5, 90, 100, 12), false, "neither")
	T.eq(R.SpareManaOrb(180, 190, 8, 90, 100, 12), false, "no Rift mana left after the orb")
	T.eq(R.SIPHON_BREAK, 750, "Spirit Siphon breaks at 500 + 250")
end)

T.test("escape rules: no lane Orb harass next to a hero or when hurt (game 067, 3:55)", function()
	local R = load()
	T.eq((R.OrbHarassSafe(0.72, 895)), false, "game 067: Death Prophet 895 away")
	T.eq(select(2, R.OrbHarassSafe(0.72, 895)), "threat", "why=threat")
	T.eq(select(2, R.OrbHarassSafe(0.65, nil)), "hp", "under 70% HP")
	T.eq((R.OrbHarassSafe(0.9, 950)), true, "the nearest hero past 900")
	T.eq((R.OrbHarassSafe(0.9, nil)), true, "no hero near")
end)

T.test("escape rules: no TP while siphoned or next to a hitter (game 067, 4:05)", function()
	local R = load()
	T.eq(select(2, R.HoldTp(true, nil)), "siphoned", "siphoned")
	T.eq(select(2, R.HoldTp(false, 82)), "hit-near", "game 067: Death Prophet 82 away hit her")
	T.eq((R.HoldTp(false, 760)), false, "past the break distance")
	T.eq((R.HoldTp(false, nil)), false, "nobody hit her")
end)

T.test("escape rules: Phase Shift at low HP while hit (game 067, 42:07; game 068)", function()
	local R = load()
	T.eq(R.LowHpPhase(0.05, 0, false, 3), "low-hp-units", "zombies attacking her")
	T.eq(R.LowHpPhase(0.05, 0, true, 0), "low-hp-units", "a creep hit")
	T.eq(R.LowHpPhase(0.18, 0.03, true, 1), "low-hp-units", "game 068 t=810")
	T.eq(R.LowHpPhase(0.10, 0.15, false, 0), "low-hp-hit", "game 068 t=2656: hero damage only")
	T.eq(R.LowHpPhase(0.12, 0.14, false, 0), "low-hp-hit", "game 068 t=2666")
	T.eq(R.LowHpPhase(0.12, 0, false, 0), nil, "low but nobody hits her")
	T.eq(R.LowHpPhase(0.3, 0.1, true, 4), nil, "over 20%")
	T.eq(R.IsLowHpWhy("low-hp-hit"), true, "low-hp-hit")
	T.eq(R.IsLowHpWhy("hero"), false, "hero")
end)

T.test("escape rules: the wait for the hold (game 068, t=3499)", function()
	local R = load()
	T.eq(R.PhaseMaxWait("dodge-linear", false), 0.2, "a dodge")
	T.eq(R.PhaseMaxWait("low-hp-units", true), 0.2, "game 068 t=810: retreat mode throughout")
	T.eq(R.PhaseMaxWait("low-hp-units", false), 0.4, "game 068 t=3499: defend mode, take the hold first")
	T.eq(R.PhaseMaxWait("low-hp-hit", false), 0.4, "low-hp-hit outside retreat")
	T.eq(R.PhaseMaxWait("hero", true), 0.4, "a hero shift")
	T.eq(R.PhaseMaxWait(nil, true), 0.4, "no why")
	T.eq(R.PhaseWantFresh(0.2, 0.4), true, "inside the wait")
	T.eq(R.PhaseWantFresh(0.65, 0.4), true, "the 0.3s grace")
	T.eq(R.PhaseWantFresh(3.77, 0.4), false, "game 068 t=2453: a 3.77s-old wait is not this dodge's")
	T.eq(R.PhaseWantFresh(nil, 0.4), false, "no wait")
	T.eq(R.PhaseWantFresh(0.45, nil), true, "no cap yet: 0.4")
end)

T.test("escape rules: escape shifts throw the Orb first and Jaunt out (game 068)", function()
	local R = load()
	T.eq(R.IsEscapeShift("hero", true, 0.69), true, "game 068 t=2326: from retreat mode")
	T.eq(R.IsEscapeShift("hero", false, 0.35), true, "game 068 t=2785: 35% HP")
	T.eq(R.IsEscapeShift("hero", false, 0.94), false, "a fight at 94% HP")
	T.eq(R.IsEscapeShift("dodge-linear", true, 0.2), false, "a dodge never waits for the Orb")
	T.eq(R.IsEscapeShift("low-hp-units", false, 0.05), true, "low HP")
	T.eq(R.IsEscapeShift("siphon", false, 0.8), true, "siphon")
	T.eq(R.PhaseOrbFirst(true, true, true, false, false), true, "all ready")
	T.eq(R.PhaseOrbFirst(true, true, true, true, false), false, "game 068 t=2074: rooted, Jaunt can't go")
	T.eq(R.PhaseOrbFirst(true, false, true, false, false), false, "Orb down")
	T.eq(R.PhaseOrbFirst(true, true, true, false, true), false, "an Orb is out already")
	T.eq(R.PhaseOrbFirst(false, true, true, false, false), false, "not an escape")
	-- Orb 1950 / 750 = 2.6s (datafeed hero 13); shift 2.5s at rank 3, 3.25s at rank 4.
	T.eq(R.ShiftJauntNow(1.0, 2.5, 1.2, 2.6, true), false, "mid-shift, a stun due, Orb flying")
	T.eq(R.ShiftJauntNow(0.6, 2.5, 0.8, 2.6, true), true, "after 0.5s: early even with something due")
	T.eq(select(2, R.ShiftJauntNow(0.2, 1.0, 0.35, 2.6, false)), "early", "nothing due: early from 0.15s")
	T.eq(R.ShiftJauntNow(0.1, 1.0, 0.25, 2.6, false), false, "too soon after the order")
	T.eq(select(2, R.ShiftJauntNow(2.3, 2.5, 2.5, 2.6, true)), "end", "the shift's last 0.2s")
	T.eq(select(2, R.ShiftJauntNow(2.2, 3.25, 2.35, 2.6, true)), "orb-end", "rank 4: before the Orb ends")
	T.eq(R.ShiftJauntNow(0.4, 3.25, nil, 2.6, true), false, "Orb time unknown, a stun due")
	T.eq(select(2, R.ShiftJauntNow(3.1, 3.25, nil, nil, true)), "end", "unknown Orb, shift ending")
end)

T.test(
	"escape rules: no offensive Rift when hurt, outnumbered or right after an escape shift (games 068-069)",
	function()
		local R = load()
		T.eq(R.OffensiveRiftBlocked(0.5, true, 0.58, 2, 2), true, "game 068 t=2329: after an escape shift")
		T.eq(select(2, R.OffensiveRiftBlocked(0.5, true, 0.58, 2, 2)), "after-shift", "why after-shift")
		T.eq(select(2, R.OffensiveRiftBlocked(0.2, false, 0.88, 2, 1)), "outnumbered", "game 068 t=2456: 2 vs her")
		T.eq(select(2, R.OffensiveRiftBlocked(nil, false, 0.26, 2, 3)), "hurt", "game 068 t=2788: 26% HP")
		T.eq(select(2, R.OffensiveRiftBlocked(nil, false, 0.6, 3, 2)), "outnumbered", "game 069: 60% HP into 3 heroes")
		T.eq((R.OffensiveRiftBlocked(nil, false, 0.9, 2, 3)), false, "healthy, not outnumbered")
		T.eq((R.OffensiveRiftBlocked(2.5, true, 0.8, 1, 2)), false, "the after-shift block is over")
		T.eq((R.OffensiveRiftBlocked(nil, false, 0.3, 0, 1)), false, "hurt but no enemy hero near")
	end
)

T.test("escape rules: the Orb stays for the escape, the exit Jaunt needs a real way out (game 069)", function()
	local R = load()
	T.eq(R.KeepOrbForEscape(0.45, 2), true, "under 50% with enemies near")
	T.eq(R.KeepOrbForEscape(0.45, 0), false, "no enemy hero near")
	T.eq(R.KeepOrbForEscape(0.7, 3), false, "healthy")
	-- Orb thrown with the shift: it leaves about 0.05s before the shift order, so at the shift's end it has flown
	-- 750 x (duration + 0.05) of path; ranks 3-4 hit the Orb's end first (2.6s, 1950). Datafeed hero 13.
	T.near(R.ExitJauntNeed(750 * 1.05), 590.6, 0.1, "rank 1 (1.0s): 787 of path, need 591, not 900")
	T.eq(R.ExitJauntNeed(750 * 1.8), 900, "rank 2 (1.75s): 1350 of path, capped at 900")
	T.eq(R.ExitJauntNeed(1950), 900, "ranks 3-4: the Orb's whole 1950")
	T.eq(R.ExitJauntNeed(200), 400, "just thrown: the 400 floor")
	T.eq(R.ExitJauntNeed(nil), 900, "Orb time unknown")
	local need1 = R.ExitJauntNeed(750 * 1.05)
	T.eq((R.ExitJauntOk(700, need1, true, 0, 2, 300, 1000, 150)), true, "rank 1: 700 away, 700 more from the enemy")
	T.eq((R.ExitJauntOk(700, 900, true, 0, 2, 300, 1000, 150)), false, "the old fixed 900 never passed at rank 1")
	T.eq(select(2, R.ExitJauntOk(532, 900, true, 1, 3, 320, 628, 550)), "near", "game 069 t=2547: 532 away")
	T.eq(select(2, R.ExitJauntOk(2054, 900, false, 0, 3)), "wrong-side", "game 069 t=922")
	T.eq(select(2, R.ExitJauntOk(1400, 900, true, 2, 2)), "crowded", "as many enemies at the Orb")
	T.eq(select(2, R.ExitJauntOk(1000, 900, true, 0, 2, 300, 600, 150)), "no-gain", "only 300 farther from the enemy")
	T.eq(select(3, R.ExitJauntOk(1000, 900, true, 0, 2, 300, 600, 150)), 300, "gain = 600 - 300")
	T.eq(select(2, R.ExitJauntOk(1000, 900, true, 0, 2, 100, 700, 600)), "in-range", "inside a ranged hero's 600 + 200")
	T.eq((R.ExitJauntOk(1400, 900, true, 0, 3, 300, 1500, 600)), true, "far, home side, clear, out of range")
	T.eq((R.ExitJauntOk(1400, 900, true, 0, 0)), true, "nobody near: distance only")
end)

T.test("escape rules: a dodge waits for the hold it asked for (game 069, t=761 / 830)", function()
	local R = load()
	T.eq(R.PhaseDodgeNow(0.30, false), false, "game 069 t=830: tti 0.30, hold not up: wait a think")
	T.eq(R.PhaseDodgeNow(0.30, true), true, "hold up: cast")
	T.eq(R.PhaseDodgeNow(0.20, false), true, "game 069 t=761: tti 0.20, no time left")
	T.eq(R.AskDodgeHold(true, nil), true, "Nyx casting Impale at her")
	T.eq(R.AskDodgeHold(false, 0.6), true, "a stun flying at her")
	T.eq(R.AskDodgeHold(false, 1.4), false, "far off")
	T.eq(R.AskDodgeHold(false, nil), false, "nothing")
end)

T.test("escape rules: a close dodge Phase Shift goes out at once (game 067, t=3039)", function()
	local R = load()
	T.eq(R.PhaseDodgeNow(0.15), true, "game 067: Impale close, no hold: cast")
	T.eq(R.PhaseDodgeNow(0.5, true), false, "time for the hold")
	T.eq(R.PhaseDodgeNow(nil), false, "unknown time: keep the wait")
	T.eq(R.PhaseDodgeResult(0.0, 0.20), "cast", "cast in the same think")
	T.eq(R.PhaseDodgeResult(0.21, 0.20), "late", "game 067: waited 0.2s, hit at 0.20")
	T.eq(R.PhaseDodgeResult(0.2, nil), "cast", "unknown time")
end)

T.test("puck: the escape helpers run on the stub", function()
	T.stub.reset({ hero = "npc_dota_hero_puck", slot = 2 })
	local ok, X = T.stub.load("BotsLib/hero_puck")
	T.ok(ok, "hero_puck loads: " .. tostring(X))
	for _, name in ipairs({
		"ConsiderSiphonEscape",
		"ShiftExit",
		"DangerJaunt",
		"ConsiderIllusoryOrb",
		"ConsiderPhaseShift",
		"HoldTpInDanger",
		"SampleHp",
		"HpLoss",
		"UnitAttackers",
		"TombstoneDistance",
		"PhaseDodgeThreat",
		"OrbFlightTime",
		"OffensiveRiftBlocked",
		"AskDodgeHold",
		"ExitOrbJaunt",
		"ConsiderIllusoryOrbRaw",
		"CastHoldTick",
		"SkillsComplement",
	}) do
		local okRun, err = pcall(X[name])
		T.ok(okRun, name .. ": " .. tostring(err))
	end
	local okWant, errWant = pcall(X.StartPhaseWant, 26)
	T.ok(okWant, "StartPhaseWant: " .. tostring(errWant))
	local okCheck, check = pcall(X.ExitJauntCheck, Vector(100, 100, 0))
	T.ok(okCheck and type(check) == "table" and check.need ~= nil, "ExitJauntCheck: " .. tostring(check))
	local okExit, errExit = pcall(X.EscapeShiftJaunt, 0, 2.4, 2.5)
	T.ok(okExit, "EscapeShiftJaunt: " .. tostring(errExit))
	local point = X.EscapePoint(1150)
	T.ok(point ~= nil and point.x ~= nil, "escape point")
	local okLog, errLog = pcall(X.LogEscapeAction, "blink", "test", point)
	T.ok(okLog, "LogEscapeAction: " .. tostring(errLog))
end)
