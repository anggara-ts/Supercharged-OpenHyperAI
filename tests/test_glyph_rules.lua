-- bots/lib/systems/glyph_rules.lua (#12): when the Glyph of Fortification saves a building or backs a fight.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_zuus" })
	return require(GetScriptDirectory() .. "/lib/systems/glyph_rules")
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
	local _, noCharge = R.ShouldFight(fight({ charges = 0 }))
	T.eq(noCharge, "no-charge", "none left: why=no-charge, not reserve")
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

-- A second save Glyph on the same fight (games 072, 081, 084, 085): only with one of our heroes there or walking in.
local function save(over)
	local s = { kind = "tower", charges = 2, sinceSame = nil, allies = 0, coming = 0 }
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end

T.test("glyph rules: second save Glyph needs help", function()
	local R = load()
	-- The first save with both charges: as before, no help needed.
	local ok, why, rule = R.ShouldSpendSave(save())
	T.eq(ok, true, "first save, two charges")
	T.eq(why, "save", "why=save")
	T.eq(rule, nil, "no rule asked for help")
	-- Game 084 t=942/950: Radiant's mid T1, five Dire heroes, nobody of ours; second Glyph 8s after the first.
	ok, why, rule = R.ShouldSpendSave(save({ charges = 1, sinceSame = 8 }))
	T.eq(ok, false, "8s after the first, nobody coming: keep the charge")
	T.eq(why, "no-help", "why=no-help")
	T.eq(rule, "repeat", "rule=repeat")
	-- Game 084 t=3052/3062: a fight Glyph, then a save on the same tower 10s later with nobody left there.
	T.eq(R.ShouldSpendSave(save({ charges = 1, sinceSame = 10 })), false, "fight Glyph then save, nobody there")
	-- Game 085 t=2760/2770: Shadow Fiend at the tower and four defenders walking in: the second Glyph is right.
	T.eq(R.ShouldSpendSave(save({ charges = 1, sinceSame = 10, allies = 1 })), true, "an ally fighting there")
	T.eq(R.ShouldSpendSave(save({ charges = 1, sinceSame = 10, coming = 2 })), true, "allies walking in")
	-- A repeat with both charges (one came back in between) still needs help.
	local _, _, both = R.ShouldSpendSave(save({ charges = 2, sinceSame = 12 }))
	T.eq(both, "repeat", "repeat with two charges")
	T.eq(R.SaveNeedsHelp("tower", 2, R.REPEAT_WINDOW), nil, "20s after: a new fight")
	-- The last charge on a tower nobody can defend.
	ok, why, rule = R.ShouldSpendSave(save({ charges = 1 }))
	T.eq(ok, false, "last charge, nobody coming")
	T.eq(rule, "last-charge", "rule=last-charge")
	T.eq(R.ShouldSpendSave(save({ charges = 1, coming = 1 })), true, "last charge with help on the way")
	T.eq(R.ShouldSpendSave(save({ kind = "barracks", charges = 1 })), false, "barracks: same rule")
	-- The Ancient: always (7s can bring a respawn or a buyback; nothing to keep the charge for).
	T.eq(R.ShouldSpendSave(save({ kind = "ancient", charges = 1, sinceSame = 8 })), true, "Ancient, repeat, alone")
end)

-- A save on a tier 1 tower keeps the last charge (#12, game 088 t=1327/1335; maintainer decision 2026-11-28).
T.test("glyph rules: a T1 save never spends the last charge", function()
	local R = load()
	-- Game 088 t=1327: the first save on the mid T1 with both charges, as before.
	local ok, why = R.ShouldSpendSave(save({ tier = 1 }))
	T.eq(ok, true, "T1, two charges: save")
	T.eq(why, "save", "why=save")
	-- Game 088 t=1335: the second save 8s later on the same T1 spent the last charge.
	ok, why = R.ShouldSpendSave(save({ tier = 1, charges = 1, sinceSame = 8 }))
	T.eq(ok, false, "T1 repeat on the last charge")
	T.eq(why, "t1-last-charge", "why=t1-last-charge")
	-- Allies fighting there or walking in do not change it on a T1.
	ok, why = R.ShouldSpendSave(save({ tier = 1, charges = 1, allies = 2, coming = 3 }))
	T.eq(ok, false, "T1, last charge, allies there and coming")
	T.eq(why, "t1-last-charge", "help does not unlock a T1's last charge")
	-- A repeat on the same T1 with both charges (one came back in between).
	ok, why = R.ShouldSpendSave(save({ tier = 1, charges = 2, sinceSame = 12, allies = 1 }))
	T.eq(ok, false, "T1 repeat with two charges")
	T.eq(why, "t1-repeat", "why=t1-repeat")
	T.eq(R.ShouldSpendSave(save({ tier = 1, sinceSame = R.REPEAT_WINDOW })), true, "T1, 20s after: a new fight")
	-- T2 and deeper keep the help rule (game 085 t=2760/2770, mid T3: the second Glyph with defenders walking in).
	T.eq(R.ShouldSpendSave(save({ tier = 2, charges = 1, coming = 1 })), true, "T2, last charge, help coming")
	T.eq(R.ShouldSpendSave(save({ tier = 3, charges = 1, sinceSame = 10, allies = 1 })), true, "T3 repeat, ally there")
	local _, t2why = R.ShouldSpendSave(save({ tier = 2, charges = 1 }))
	T.eq(t2why, "no-help", "T2, last charge, nobody: why=no-help as before")
	-- The barracks and the Ancient pass no tier.
	T.eq(R.ShouldSpendSave(save({ kind = "ancient", charges = 1, sinceSame = 8 })), true, "Ancient unchanged")
	-- No charge at all.
	ok, why = R.ShouldSpendSave(save({ tier = 2, charges = 0, allies = 1 }))
	T.eq(ok, false, "no charge")
	T.eq(why, "no-charge", "why=no-charge")
	T.eq(R.TierOneBlock(nil, 1, nil), nil, "no tier: no T1 rule")
	T.eq(R.TierOneBlock(1, 1, nil), "t1-last-charge", "T1 at one charge")
end)

T.test("glyph rules: charge count follows GetGlyphCooldown", function()
	local R = load()
	-- Game 085 (Dire): our count gave a charge back at t=1884, the API's cooldown said t=1980.
	local s = { charges = 1, nextAt = 2244 }
	T.eq(R.Sync(s, 1885, 95.4), 1, "cooldown above 7s: corrected, was 1")
	T.eq(s.charges, 0, "no charge left")
	T.near(s.nextAt, 1980.4, 0.01, "back when the API says")
	T.eq(R.Sync(s, 1887, 93.4), nil, "same reading 2s later: no change")
	T.eq(R.Tick(s, 1981), 1, "the charge comes back at the API's time")
	-- 2s after a cast with a charge left the API reads the 7s between uses (cd=5.0): not a restore time.
	local t = { charges = 1, nextAt = 1302 }
	T.eq(R.Sync(t, 944, 5.0), nil, "between-uses cooldown: no change")
	T.eq(t.charges, 1, "still one")
	-- Our count says none, the API says ready: one is there.
	local u = { charges = 0, nextAt = 2000 }
	T.eq(R.Sync(u, 1900, 0), 0, "ready while we counted none")
	T.eq(u.charges, 1, "one charge")
	T.eq(u.nextAt, 2000, "the second one's time stays")
	local full = R.NewCharges()
	T.eq(R.Sync(full, 100, 0), nil, "full and ready: no change")
end)
