-- bots/lib/systems/escape_rules.lua (#36): escape direction, Jaunt side check, lane Orb spare mana.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_puck" })
	return require(GetScriptDirectory() .. "/lib/systems/escape_rules")
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

T.test("escape rules: no TP while Roshan, a tower or creeps hit her, or with the exit Orb out (#191)", function()
	local R = load()
	T.eq(select(2, R.HoldTp(false, nil, { exitOrb = true, hp = 0.14 })), "exit-orb", "game 074 t=6323: exit Orb out")
	T.eq(select(2, R.HoldTp(false, nil, { roshan = true, hp = 0.09 })), "roshan", "game 073 t=2379: in the pit")
	T.eq(select(2, R.HoldTp(false, nil, { towerAge = 0.4, hp = 0.9 })), "tower", "a tower hit her, any HP")
	T.eq((R.HoldTp(false, nil, { towerAge = 2.0, hp = 0.9 })), false, "the tower hit is old")
	T.eq(select(2, R.HoldTp(false, nil, { unitAge = 0.7, hp = 0.14 })), "units", "game 074 t=6323: 4 creeps on her")
	T.eq((R.HoldTp(false, nil, { unitAge = 0.7, hp = 0.8 })), false, "creeps at 80% HP: TP is fine")
	T.eq((R.HoldTp(false, nil, { unitAge = 2.0, hp = 0.1 })), false, "out of the creeps for 2s")
	T.eq((R.HoldTp(false, nil, {})), false, "nothing on her")
	T.eq(select(2, R.HoldTp(false, 82, { exitOrb = true })), "hit-near", "a hero hitter comes first")
end)

T.test("escape rules: hit age without the Phase Shift's time (#191, games 073 / 074)", function()
	local R = load()
	T.eq(R.HitAge(10, nil, nil, nil), nil, "never hit")
	T.near(R.HitAge(10, 9, nil, nil), 1, 0.001, "no shift")
	-- Game 074: creeps on her, shift at 6319.0 for 3.25s, TP rule at 6323.
	T.near(R.HitAge(6323, 6318.9, 6319.0, 6322.25), 0.85, 0.001, "the shift's 3.25s do not count")
	T.near(R.HitAge(6321, 6318.9, 6319.0, 6322.25), 0.1, 0.001, "inside the shift")
	-- The hit stamped 0.5s into the shift (the damage read looks 0.5s back): the age starts at the shift end.
	T.near(R.HitAge(6323, 6319.5, 6319.0, 6322.25), 0.75, 0.001, "a stamp inside the shift")
	T.near(R.HitAge(6322, 6319.5, 6319.0, 6322.25), 0, 0.001, "still in the shift")
	-- A shift long after the hit: a plain age.
	T.near(R.HitAge(20, 10, 15, 17.5), 10, 0.001, "shift started 5s after the hit")
	-- A hit after an old shift: a plain age.
	T.near(R.HitAge(20, 19, 10, 12.5), 1, 0.001, "hit after the shift")
end)

T.test("puck: an enemy tower on her is found (#191: Fu.IsValid is false for buildings)", function()
	T.stub.reset({ hero = "npc_dota_hero_puck", slot = 2 })
	local ok, X = T.stub.load("bots/heroes/hero_puck")
	T.ok(ok, "hero_puck loads: " .. tostring(X))
	local bot = T.stub.bot
	local here = bot:GetLocation()
	local function tower(dx, target)
		local unit = T.stub.newUnit({
			name = "npc_dota_badguys_tower1_mid",
			team = TEAM_DIRE,
			loc = Vector(here.x + dx, here.y, 0),
			hero = false,
		})
		unit.IsBuilding = function()
			return true
		end
		unit.GetAttackRange = function()
			return 700
		end
		unit.GetAttackTarget = function()
			return target
		end
		return unit
	end
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local onHer = tower(400, bot)
	T.eq(Fu.IsValid(onHer), false, "Fu.IsValid rejects a building (the old check)")
	T.eq(Fu.IsValidBuilding(onHer), true, "Fu.IsValidBuilding takes it")
	bot.GetNearbyTowers = function(_, _, enemy)
		return enemy and { onHer } or {}
	end
	local found, dist, range = X.TowerOnHer()
	T.ok(found == onHer, "the tower targeting her is found")
	T.near(dist, 400, 1, "its distance")
	T.eq(range, 700, "its range")
	local far = tower(2000, bot)
	bot.GetNearbyTowers = function(_, _, enemy)
		return enemy and { far } or {}
	end
	local none, note = X.TowerOnHer()
	T.eq(none, nil, "a tower 2000 away is not on her")
	T.eq(note, "out", "note out")
	bot.GetNearbyTowers = function(_, _, enemy)
		return enemy and { tower(400, nil) } or {}
	end
	local _, noteOther = X.TowerOnHer()
	T.eq(noteOther, "other", "a tower in range on nobody")
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
	T.eq(R.ShiftJauntNow(0.3, 2.5, 0.5, 2.6, true), false, "0.3s in, a stun due, Orb flying: wait")
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

T.test("escape rules: the escape heads toward safety, bent away from threats (game 071, 34:06)", function()
	local R = load()
	local function homeDist(x, y, hx, hy)
		return math.sqrt((hx - x) * (hx - x) + (hy - y) * (hy - y))
	end
	-- Game 071 t=2046: Puck (Radiant) at about -1400,5880, Undying 106 away on the home side, our fountain about
	-- -6750,-6250 (home 13315). The old Direction sent the exit Orb to 165,5752: 547 farther from home.
	local bx, by, hx, hy = -1400, 5880, -6750, -6250
	local undying = { x = -1490, y = 5825 }
	local dx, dy, how = R.SafeDirection(bx, by, { undying }, hx, hy, 1600)
	local before = homeDist(bx, by, hx, hy)
	local after = homeDist(bx + dx * 1600, by + dy * 1600, hx, hy)
	T.ok(after < before, "1600 jump gets closer to home: " .. before .. " -> " .. after)
	T.eq(how, "bent", "bent off the home line around Undying")
	local ux, uy = undying.x - bx, undying.y - by
	T.ok(dx * ux + dy * uy <= 0, "does not move toward Undying")
	local oldX, oldY = R.Direction(bx, by, { undying }, hx, hy)
	T.ok(homeDist(bx + oldX * 1600, by + oldY * 1600, hx, hy) > before, "the old rule went farther from home")
	-- Nobody near: straight to safety.
	local sx, sy, sHow = R.SafeDirection(0, 0, {}, -1000, 0, 1000)
	T.near(sx, -1, 1e-6, "straight west")
	T.near(sy, 0, 1e-6, "no bend")
	T.eq(sHow, "safe", "safe")
	-- An enemy 300 ahead on the home line, far enough to go round: bent, still closer to home.
	local rx, ry, rHow = R.SafeDirection(0, 0, { { x = -600, y = 0 } }, -3000, 0, 1600)
	T.eq(rHow, "bent", "round the enemy on the home line")
	T.ok(rx < 0, "still toward home")
	-- Enemies on every side of the home cone: only then away.
	local ring = {}
	for deg = 0, 345, 15 do
		ring[#ring + 1] = { x = math.cos(math.rad(deg)) * 200, y = math.sin(math.rad(deg)) * 200 }
	end
	local _, _, ringHow = R.SafeDirection(0, 0, ring, -3000, 0, 1600)
	T.eq(ringHow, "fallback", "surrounded: the old rule")
end)

T.test("escape rules: escape Rift and moving out of a wave (game 071, 34:04-34:15)", function()
	local R = load()
	T.eq(R.EscapeRiftNow(0.14, false, 6, false), true, "game 071 t=2049: 14% HP, 6 units on her")
	T.eq(R.EscapeRiftNow(0.2, true, 0, false), true, "a hero on her")
	T.eq(R.EscapeRiftNow(0.2, true, 0, true), false, "a Jaunt out is ready")
	T.eq(R.EscapeRiftNow(0.6, true, 6, false), false, "healthy")
	T.eq(R.EscapeRiftNow(0.2, false, 1, false), false, "one creep")
	T.eq(R.MoveOutInsteadOfShift("low-hp-units", false, false, true), true, "game 071 t=2051: units only, Rift ready")
	T.eq(R.MoveOutInsteadOfShift("low-hp-units", true, false, true), false, "game 071 t=2044: hero hit too: shift")
	T.eq(R.MoveOutInsteadOfShift("low-hp-units", false, true, true), false, "a stun due: shift")
	T.eq(R.MoveOutInsteadOfShift("low-hp-units", false, false, false), false, "no way out: shift")
	T.eq(R.MoveOutInsteadOfShift("low-hp-hit", false, false, true), false, "low-hp-hit stays a shift")
end)

T.test("escape rules: out of an enemy tower's range, hop over it on the way home (game 072, 19:56-20:05)", function()
	local R = load()
	-- t=1196: the Dire mid T2 (attack range 700 from the handle) hit her alone at 320, HP 0.49, out = 700 + 150 - 320.
	T.eq(R.TowerEscape(true, 0.49, 0.05, 530, true, true, 350), "orb-jaunt", "530 to go: the Orb and a Jaunt")
	T.eq(R.TowerEscape(true, 0.49, 0.05, 530, false, true, 350), "walk", "Orb down, 530 past a 350 jump: walk")
	-- Game 087, t=740: the mid T1 on her at 395 (out 455), Rift jump 340, Orb down: a walk, no Rift that lands inside.
	T.eq(R.TowerEscape(true, 0.76, 0.14, 455, false, true, 340), "walk", "game 087: out 455 > jump 340")
	T.eq(R.TowerEscape(true, 0.76, 0.14, 330, false, true, 340), "rift", "out 330 <= jump 340: the Rift")
	T.eq(R.TowerEscape(true, 0.49, 0.05, 300, true, true, 350), "rift", "300 to go: the Rift gets her out")
	T.eq(R.TowerEscape(true, 0.49, 0.05, 150, true, true, 350), "walk", "at the edge: walk")
	T.eq(R.TowerEscape(true, 0.49, 0.05, 530, false, false, 350), "walk", "nothing ready: walk")
	T.eq(R.TowerEscape(true, 0.80, 0.12, 530, true, true, 350), "orb-jaunt", "healthy but falling fast")
	T.eq(R.TowerEscape(true, 0.80, 0.05, 530, true, true, 350), nil, "healthy, slow loss")
	T.eq(R.TowerEscape(false, 0.20, 0.30, 530, true, true, 350), nil, "the tower is not on her")
	-- Behind the tower on the way home (home -6619,-6336, the TP target in the log; tower 1300,700).
	T.eq(R.TowerHopWanted(11500, 10593, 15, 950, 700, true), true, "950 from the tower, the line home through it")
	T.eq(R.TowerHopWanted(11500, 10593, 15, 1487, 700, true), false, "still far: walk on first")
	T.eq(R.TowerHopWanted(9000, 10593, 15, 950, 700, true), false, "already past it")
	T.eq(R.TowerHopWanted(11500, 10593, 1200, 950, 700, true), false, "the way home misses its range")
	T.eq(R.TowerHopWanted(11500, 10593, 15, 950, 700, false), false, "not heading home")
	local dx, dy, hopAt = R.HopDirection(2003, 1339, 1300, 700, 700, -6619, -6336, 1950)
	T.ok(dx ~= nil and hopAt == 1800, "straight home, Jaunt 1800 along: " .. tostring(hopAt))
	T.ok(dx < 0 and dy < 0, "toward home")
	T.eq((R.HopDirection(3519, 2718, 1300, 700, 700, -6619, -6336, 1950)), nil, "3000 away: no line clears it")
end)

T.test("escape rules: no new order while her Rift or Orb is in its cast point (game 087, t=740-741)", function()
	local R = load()
	T.eq(R.CastPending(true, nil, 0.1, false), true, "in its ability phase (any caller's order)")
	T.eq(R.CastPending(false, 0.03, 0.1, false), true, "own order a think ago, not started yet")
	T.eq(R.CastPending(false, 0.25, 0.1, false), true, "within cast point + slack")
	T.eq(R.CastPending(false, 0.35, 0.1, false), false, "never started (held or dropped): the walk goes out")
	T.eq(R.CastPending(false, 0.1, 0.1, true), false, "on cooldown: the spell went out")
	T.eq(R.CastPending(false, nil, 0.1, false), false, "no order, not casting")
end)

T.test("puck: the escape helpers run on the stub", function()
	T.stub.reset({ hero = "npc_dota_hero_puck", slot = 2 })
	local ok, X = T.stub.load("bots/heroes/hero_puck")
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
		"SafePoint",
		"TowerOnHer",
		"TowerStanding",
		"TowerCastPending",
		"TowerEscape",
		"TowerHop",
		"TowerOrbJaunt",
		"HeroOnHer",
		"ExitJauntReady",
		"EscapeRiftWanted",
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
