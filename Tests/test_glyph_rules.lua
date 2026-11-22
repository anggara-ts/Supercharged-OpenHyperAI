-- FuncLib/systems/glyph_rules.lua (#12): when the Glyph of Fortification saves a building or backs a fight.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_zuus" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/glyph_rules")
end

local function fight(over)
	local f = { tier = 2, enemies = 5, aliveEnemies = 5, allies = 3, hit = true, charges = 2, fortified = false }
	for k, v in pairs(over or {}) do
		f[k] = v
	end
	return f
end

T.test("glyph rules: save a dying building (old thresholds)", function()
	local R = load()
	T.eq(R.ShouldSave("tower", 0.30, true, false), true, "tower under 36% that an enemy attacks")
	T.eq(R.ShouldSave("tower", 0.40, true, false), false, "tower at 40%")
	T.eq(R.ShouldSave("tower", 0.30, false, false), false, "nobody attacks it")
	T.eq(R.ShouldSave("building", 0.45, true, false), true, "barracks / Ancient under 50%")
	T.eq(R.ShouldSave("building", 0.55, true, false), false, "barracks at 55%")
	T.eq(R.ShouldSave("tower", 0.30, true, true), false, "already fortified: don't spend the second charge")
end)

T.test("glyph rules: enemies needed", function()
	local R = load()
	T.eq(R.EnemiesNeeded(5), 3, "five alive: 3")
	T.eq(R.EnemiesNeeded(3), 3, "three alive: all 3")
	T.eq(R.EnemiesNeeded(2), 2, "two alive: both")
	T.eq(R.EnemiesNeeded(1), nil, "one alive: no fight Glyph")
	T.eq(R.EnemiesNeeded(0), nil, "none alive")
end)

T.test("glyph rules: fight under a tower", function()
	local R = load()
	-- Game 071, 31:10: all five Dire heroes in range of Radiant's mid T2 in a team fight.
	T.eq(R.ShouldFight(fight()), true, "5 enemies, 3 allies fighting, tower hit, 2 charges")
	T.eq(R.ShouldFight(fight({ enemies = 3 })), true, "3 of 5 is enough")
	local ok, why = R.ShouldFight(fight({ enemies = 2 }))
	T.eq(ok, false, "2 of 5 is not")
	T.eq(why, "few-enemies", "why=few-enemies")
	T.eq(R.ShouldFight(fight({ enemies = 2, aliveEnemies = 2 })), true, "both alive enemies")
	T.eq(R.ShouldFight(fight({ enemies = 1, aliveEnemies = 1 })), false, "one enemy")
	local _, noAllies = R.ShouldFight(fight({ allies = 0 }))
	T.eq(noAllies, "no-allies", "a dive with nobody of ours fighting there")
	local _, notHit = R.ShouldFight(fight({ hit = false }))
	T.eq(notHit, "not-hit", "the tower is not hit")
	local _, tier1 = R.ShouldFight(fight({ tier = 1 }))
	T.eq(tier1, "tier1", "T1 has no multishot")
	T.eq(R.ShouldFight(fight({ tier = 4 })), true, "T4")
	local _, reserve = R.ShouldFight(fight({ charges = 1 }))
	T.eq(reserve, "reserve", "the last charge stays for a save")
	local _, fortified = R.ShouldFight(fight({ fortified = true }))
	T.eq(fortified, "fortified", "already fortified")
end)

T.test("glyph rules: hp falling", function()
	local R = load()
	T.eq(R.HpFalling(nil, 1500), false, "no sample yet")
	T.eq(R.HpFalling(1600, 1500), true, "lost HP")
	T.eq(R.HpFalling(1500, 1500), false, "same HP")
end)

T.test("glyph rules: own charge count", function()
	local R = load()
	local s = R.NewCharges()
	T.eq(R.Tick(s, 100), 2, "two charges at the start")
	R.Spend(s, 100)
	T.eq(s.charges, 1, "one left")
	T.eq(s.nextAt, 100 + R.CHARGE_TIME, "replenish in 6 min")
	R.Spend(s, 200)
	T.eq(s.charges, 0, "none left")
	T.eq(s.nextAt, 100 + R.CHARGE_TIME, "the running replenish keeps its time")
	T.eq(R.Tick(s, 100 + R.CHARGE_TIME), 1, "first back")
	T.eq(s.nextAt, 100 + 2 * R.CHARGE_TIME, "second one 6 min later")
	T.eq(R.Tick(s, 100 + 2 * R.CHARGE_TIME + 5), 2, "both back")
	T.eq(s.nextAt, nil, "full: no replenish running")
end)
