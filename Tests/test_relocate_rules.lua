-- FuncLib/systems/relocate_rules.lua (#47): Io's Relocate save, the damage rate, the return decision, the ally hold.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_wisp" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/relocate_rules")
end

-- HP falling linearly from `from` to `to` over `seconds`, one sample per 0.1s; returns the samples.
local function falling(R, from, to, seconds)
	local samples = {}
	local steps = math.floor(seconds / 0.1 + 0.5)
	for i = 0, steps do
		R.AddSample(samples, i * 0.1, from + (to - from) * i / steps)
	end
	return samples
end

T.test("relocate: cast delay by level and the talent", function()
	local R = load()
	-- 7.42 npc_dota_hero_wisp.txt: cast_delay 3.5 3.25 3.0, special_bonus_unique_wisp_relocate_delay -2.0.
	T.eq(R.CastDelay(1, false), 3.5)
	T.eq(R.CastDelay(2, false), 3.25)
	T.eq(R.CastDelay(3, false), 3.0)
	T.eq(R.CastDelay(3, true), 1.0)
	T.eq(R.CastDelay(0, false), 3.5, "unlearned reads as level 1")
end)

T.test("relocate: loss rate over the last 1.25s", function()
	local R = load()
	local samples = falling(R, 0.8, 0.4, 2.0)
	T.near(R.LossRate(samples), 0.2, 0.01, "0.4 lost in 2s")
	T.eq(R.LossRate({}), 0, "no samples")
	T.eq(R.LossRate(falling(R, 0.8, 0.7, 0.3)), 0, "under 0.5s of history")
	-- A 3s gap (Io dead, no thinks): the old sample is not used.
	T.eq(R.LossRate({ { t = 0, hp = 0.9 }, { t = 3, hp = 0.3 } }), 0, "gap")
	-- Healing: no loss.
	T.eq(R.LossRate(falling(R, 0.4, 0.6, 1.5)), 0, "healing")
	-- Old samples are dropped after 2.5s.
	local long = falling(R, 1, 0, 5)
	T.ok(long[1].t >= 2.5 - 1e-6, "pruned")
end)

T.test("relocate: save needed (game 068 deaths)", function()
	local R = load()
	-- Undying t=1295: 0.55 -> 0.03 in 3.5s (0.149/s), 2 enemy heroes: ttd 3.7s. Fires at 0.55 at levels 1-2
	-- (delay + 0.5 = 4.0 / 3.75); at level 3 (3.5) a moment later, by 0.50.
	local dps = (0.55 - 0.03) / 3.5
	for level = 1, 2 do
		local needed, why = R.SaveNeeded(0.55, dps, R.CastDelay(level, false), 2)
		T.ok(needed, "t=1295 level " .. level)
		T.eq(why, "dps")
	end
	T.ok(not R.SaveNeeded(0.55, dps, R.CastDelay(3, false), 2), "t=1295 level 3 at 0.55")
	T.ok(R.SaveNeeded(0.5, dps, R.CastDelay(3, false), 2), "t=1295 level 3 at 0.50")
	-- Undying t=2202: 0.42 -> 0.05 (0.106/s), 2 enemies: ttd 3.97s.
	local needed, why = R.SaveNeeded(0.42, (0.42 - 0.05) / 3.5, 3.5, 2)
	T.ok(needed, "t=2202")
	T.eq(why, "dps")
	-- Undying t=559: 0.45 -> 0.14 (0.089/s, ttd 5.1s), 2 enemies: not by the rate, by the focus rule.
	needed, why = R.SaveNeeded(0.45, (0.45 - 0.14) / 3.5, 3.5, 2)
	T.ok(needed, "t=559")
	T.eq(why, "focus")
end)

T.test("relocate: no save when it is not needed", function()
	local R = load()
	T.ok(not R.SaveNeeded(0.3, 0.3, 3.5, 0), "no enemy hero near")
	-- One 20% nuke read as 16%/s at 80% HP: over the damage-rate cap.
	T.ok(not R.SaveNeeded(0.8, 0.16, 3.5, 1), "healthy, one nuke")
	T.ok(not R.SaveNeeded(0.6, 0.05, 3.5, 1), "slow loss, one enemy")
	T.ok(not R.SaveNeeded(0.4, 0, 3.5, 1), "40%, one enemy, not losing HP")
	local needed, why = R.SaveNeeded(0.18, 0, 3.5, 1)
	T.ok(needed, "under 20% with an enemy near (the old rule)")
	T.eq(why, "low")
end)

T.test("relocate: return keep or break", function()
	local R = load()
	local function decide(over)
		local o = { allyAlive = true, tetherUp = true, allyHp = 0.9, alliesAtOrigin = 1, enemiesAtOrigin = 2 }
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		return R.ReturnDecision(o)
	end
	T.eq(decide(), "keep", "healed, fight even")
	T.eq(decide({ allyHp = 0.5 }), "break", "not healed: the ally stays home")
	T.eq(decide({ alliesAtOrigin = 0, enemiesAtOrigin = 3 }), "break", "3 enemies against Io and the ally")
	T.eq(decide({ alliesAtOrigin = 0, enemiesAtOrigin = 2 }), "keep", "2 against 2")
	T.eq(decide({ tetherUp = false }), "none")
	T.eq(decide({ allyAlive = false }), "none")
end)

T.test("relocate: the ally holds at the fountain until the return", function()
	local R = load()
	local rec = { teleportAt = 10, returnAt = 22, released = false }
	local hold, move = R.AllyHold(rec, 9, 300, 200)
	T.ok(not hold, "before the teleport")
	hold, move = R.AllyHold(rec, 12, 300, 200)
	T.ok(hold and not move, "at the fountain next to Io")
	hold, move = R.AllyHold(rec, 15, 900, 800)
	T.ok(hold and move, "strayed past 700: walk back to Io")
	T.ok(not R.AllyHold(rec, 22, 300, 200), "the return")
	T.ok(not R.AllyHold(rec, 12, 4000, 200), "not at the fountain: it did not come along")
	rec.released = true
	T.ok(not R.AllyHold(rec, 15, 300, 200), "Io broke the tether: free to go")
	T.ok(not R.AllyHold(nil, 15, 300, 200), "no record")
end)

T.test("relocate: rescue a ganked ally", function()
	local R = load()
	local function check(over)
		local o = { hp = 0.6, dps = 0.05, delay = 3.5, damaged = true, enemies = 3, alliesThere = 0 }
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		return R.RescueCheck(o)
	end
	local ok, why, ttd = check()
	T.ok(ok, "3 on 1, 12s of HP left: go")
	T.eq(why, "go")
	T.near(ttd, 12, 0.01)
	T.eq(select(2, check({ damaged = false })), "no-gank", "not hit by a hero")
	T.eq(select(2, check({ enemies = 1 })), "no-gank", "one enemy")
	T.eq(select(2, check({ enemies = 2, alliesThere = 1 })), "no-gank", "2 on 2: not outnumbered")
	-- 0.3 HP at 0.08/s: 3.75s left, under the 3.5s delay + 1s.
	T.eq(select(2, check({ hp = 0.3, dps = 0.08 })), "too-late", "dies before Io lands")
	T.ok(check({ enemies = 5 }), "a 5-man gank is still a gank: the numbers are NumbersOk's call")
	T.ok(check({ dps = 0 }), "not losing HP yet")
end)

T.test("relocate: rescue partner", function()
	local R = load()
	local function score(over)
		local o = {
			hp = 0.9,
			dist = 900,
			ultReady = true,
			readySpells = 1,
			channeling = false,
			inFight = false,
			laneUnderTower = false,
		}
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		return R.PartnerScore(o)
	end
	T.ok(score() ~= nil, "healthy, ultimate ready")
	T.ok(score({ ultReady = false, readySpells = 2 }) ~= nil, "two spells ready")
	T.eq(score({ ultReady = false, readySpells = 1 }), nil, "one spell, no ultimate")
	T.eq(score({ hp = 0.6 }), nil, "under 70% HP")
	-- wisp_tether AbilityCastRange 1600.
	T.eq(score({ dist = 1700 }), nil, "out of tether cast range")
	T.eq(score({ channeling = true }), nil, "channeling")
	T.eq(score({ inFight = true }), nil, "in its own fight")
	T.eq(score({ laneUnderTower = true }), nil, "its lane is pushed under our tower")
	T.ok(score({ readySpells = 3 }) > score({ readySpells = 1 }), "more fight power ranks higher")
end)

T.test("relocate: numbers after the landing", function()
	local R = load()
	T.ok(not R.NumbersOk(2, 5), "2v5: skip")
	T.ok(not R.NumbersOk(2, 4), "2v4: skip")
	T.ok(R.NumbersOk(3, 4), "3v4: go")
	T.ok(R.NumbersOk(2, 3), "2v3: go")
	-- Io alone onto a 1v1 gank: Io + the ganked ally = 2 against 1.
	T.ok(R.NumbersOk(2, 1), "1v1 rescue: go")
	T.ok(R.NumbersOk(1, 2), "Io alone against 2: go (margin 1)")
end)
