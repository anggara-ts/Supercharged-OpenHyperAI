-- bots/lib/systems/roshan_rules.lua: can the group that comes tank Roshan to half HP (#12, game 068: 3 of 4 committed
-- tries failed; the kill time ignored Roshan's damage on the group).
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/lib/systems/roshan_rules")
end

-- HP ratios from the game 068 log at the call; max HP and right-click damage per second are rough values for the
-- heroes' levels (not in the log).
local function member(ratio, maxHp)
	return { hp = ratio * maxHp, maxHp = maxHp, roshDps = 170 }
end

T.test("game 068 Dire 41:24 (5/5, killed in 20s): fits", function()
	local R = rules()
	local ok, why = R.GroupFit({
		members = {
			member(0.64, 2000), -- clinkz
			member(0.52, 2400), -- nyx_assassin
			member(1.00, 2000), -- wisp
			member(1.00, 1800), -- dark_willow
			member(0.90, 2800), -- undying
		},
		groupDps = 5 * 170,
		roshHp = 6000 + 130 * 41,
		roshMax = 6000 + 130 * 41,
	})
	T.ok(ok, why)
end)

T.test("game 068 Radiant 25:51 (left Roshan at 60%): tank-short", function()
	local R = rules()
	-- At the call all five were 6000-6300 from the pit at 0.68-0.92 HP (average 0.78), so all five count.
	local ok, why = R.GroupFit({
		members = {
			member(0.68, 1500), -- alchemist
			member(0.74, 1100), -- puck
			member(0.70, 1200), -- vengefulspirit
			member(0.86, 1400), -- ember_spirit
			member(0.92, 1000), -- zuus
		},
		groupDps = 5 * 110,
		roshHp = 6000 + 130 * 26,
		roshMax = 6000 + 130 * 26,
	})
	T.ok(not ok, "two heroes can't tank Roshan to half")
	T.ok(string.find(why, "tank-short", 1, true) ~= nil, why)
end)

T.test("game 068 Radiant 37:08 (2/3, left at 78%): tank-short", function()
	local R = rules()
	local ok, why = R.GroupFit({
		members = {
			member(1.00, 2000), -- alchemist
			member(0.92, 1400), -- puck
			member(0.60, 1700), -- ember_spirit
		},
		groupDps = 3 * 150,
		roshHp = 6000 + 130 * 37,
		roshMax = 6000 + 130 * 37,
	})
	T.ok(not ok, why)
end)

T.test("a hurt group is not sent (average under 70%)", function()
	local R = rules()
	local ok, why, numbers = R.GroupFit({
		members = { member(0.5, 2000), member(0.6, 2000), member(0.9, 2000), member(0.55, 2000) },
		groupDps = 2000,
		roshHp = 5000,
		roshMax = 10000,
	})
	T.ok(not ok, "hurt")
	T.ok(string.find(why, "group-hurt", 1, true) ~= nil, why)
	T.near(numbers.avg, 0.6375, 1e-9, "average")
	-- Roshan already at half: nothing to tank, a healthy group goes.
	T.ok(
		R.GroupFit({
			members = { member(0.9, 2000), member(0.9, 2000) },
			groupDps = 300,
			roshHp = 5000,
			roshMax = 10000,
		}),
		"Roshan at half"
	)
	T.ok(not R.GroupFit({ members = {} }), "nobody coming")
end)

T.test("full-HP groups at HALF_CREDIT 1.0: 5 at 20:00 fit; 4 at 25:00, 3 at 40:00 and 2 at 45:00 do not", function()
	local R = rules()
	T.eq(R.HALF_CREDIT, 1.0, "credit (game 088 retune)")
	local function group(n, maxHp, dps, minute)
		local members = {}
		for i = 1, n do
			members[i] = member(1.0, maxHp)
		end
		local roshHp = 6000 + 130 * minute
		return R.GroupFit({ members = members, groupDps = n * dps, roshHp = roshHp, roshMax = roshHp })
	end
	-- 5 x 1300 HP: pool 5 * 715 = 3575, drain 170 + 7 * 5 = 205 -> tank 17.4s; half 4300 / 250 = 17.2s.
	local ok, why, numbers = group(5, 1300, 100, 20)
	T.ok(ok, "5 at 20:00 " .. why)
	T.near(numbers.tank, 3575 / 205, 1e-9, "tank")
	T.near(numbers.half, 4300 / 250, 1e-9, "half")
	-- 4 x 1500 HP (game 088 Radiant's shape, 4/4 at 21:37, left Roshan at 34%): tank 3300 / 198 = 16.7s, half
	-- 4625 / 260 = 17.8s. It passed at the old 0.75.
	ok, why = group(4, 1500, 130, 25)
	T.ok(not ok, "4 at 25:00 " .. why)
	T.ok(string.find(why, "tank-short", 1, true) ~= nil, why)
	-- 3 x 2200 HP: tank 3630 / 191 = 19.0s, half 5600 / 255 = 22.0s.
	ok, why = group(3, 2200, 170, 40)
	T.ok(not ok, "3 at 40:00 " .. why)
	ok, why = group(2, 2400, 200, 45)
	T.ok(not ok, "2 at 45:00 " .. why)
end)

-- Every committed take with recorded fit numbers (#12, retune after game 088, maintainer decision D7 2026-11-27).
-- tank / half are the group(tank=,half=) seconds of the log: the commit line's fit= for game 088 (the first game that
-- printed it), else the last call line's fit before the commit (the call counts everyone coming, the commit only the
-- heroes at the pit, so those are an approximation). The logs round to whole seconds.
local KILLED = {
	{ "074 t=2455 radiant (Roshan died t=2486)", 26, 16 },
	{ "074 t=4216 dire (died t=4252)", 37, 10 },
	{ "078 t=1457 radiant (died t=1497)", 17, 13 },
	{ "081 t=1981 dire (died t=2011)", 14, 11 },
	{ "082 t=809 radiant (died t=851)", 18, 16 },
	{ "082 t=1917 radiant (died t=1952)", 12, 12 },
	{ "083 t=3246 radiant (Aegis t=3275)", 34, 8 },
	{ "084 t=3742 radiant (died t=3793)", 38, 8 },
	{ "085 t=1963 dire (Aegis t=2001)", 24, 10 },
	{ "085 t=2637 dire (Aegis t=2677)", 30, 9 },
	{ "085 t=3488 dire (Aegis t=3569)", 24, 12 },
}
-- Takes that failed and that the tank check now drops (they passed at 0.75).
local DROPPED_NOW = {
	{ "088 t=1297 radiant commit 4/4 (left Roshan at 34%)", 16, 19 },
	{ "088 t=1681 dire commit 4/4 (left Roshan at 18%)", 14, 18 },
	{ "087 t=1048 radiant 4/4 (left at 90%)", 11, 12 },
	{ "083 t=1963 dire 4/5 (left at 51%)", 13, 16 },
	{ "083 t=2034 dire 4/4 (left at 51%)", 12, 16 },
	{ "081 t=1572 dire 5/5 (left at 83%)", 13, 15 },
	{ "069 t=1116 radiant 3/5 (left at 66%)", 14, 16 },
	{ "069 t=1403 dire 3/4 (left at 28%)", 14, 15 },
}
-- Takes that failed with the tank check passing: the cause was not the tank model (enemies came, the group split, or
-- the finish dropped), so no credit drops them without dropping the kills above (082 t=1917 sits at 12/12).
local FAILED_BUT_FIT = {
	{ "087 t=1337 radiant 3/5 by=window (left at 60%)", 22, 10 },
	{ "087 t=1535 dire 4/4 (left at 48%; the next take killed him)", 17, 10 },
}

T.test("recorded takes: the kills still pass the tank check, game 088's two commits drop", function()
	local R = rules()
	for _, take in ipairs(KILLED) do
		T.ok(R.TankCovers(take[2], take[3]), "killed: " .. take[1])
	end
	for _, take in ipairs(DROPPED_NOW) do
		T.ok(not R.TankCovers(take[2], take[3]), "dropped now: " .. take[1])
		local old = take[2] >= take[3] * 0.75
		T.ok(old, "passed at the old 0.75: " .. take[1])
	end
	for _, take in ipairs(FAILED_BUT_FIT) do
		T.ok(R.TankCovers(take[2], take[3]), "still passes (not a tank-model failure): " .. take[1])
	end
end)

T.test("the fit line names the weakest member's seconds to the leave line (low=)", function()
	local R = rules()
	-- The 95% hero (2000 HP): 1900 - 900 = 1000 above the 45% line, 1000 / (170 + 7) = 5.6s;
	-- the 50% hero: margin 100, 100 / 177 = 0.6s.
	local ok, why, numbers = R.GroupFit({
		members = { member(0.95, 2000), member(0.5, 2000), member(1.0, 2000) },
		groupDps = 600,
		roshHp = 5000,
		roshMax = 10000,
	})
	T.ok(ok, why)
	T.near(numbers.low, 100 / 177, 1e-9, "low")
	T.ok(string.find(why, "low=1)", 1, true) ~= nil, why)
end)

T.test("finish clear: under 36% with no foe near the pit", function()
	local R = rules()
	T.ok(R.FinishClear(0.18, 0), "game 088 Dire t=1724 (18%, foes=0)")
	T.ok(R.FinishClear(0.34, 0), "game 088 Radiant t=1347 (34%, foes=0)")
	T.ok(R.FinishClear(0.355, 0), "game 088 Radiant t=1352 (printed 0.35)")
	T.ok(not R.FinishClear(0.18, 1), "a foe near the pit")
	T.ok(not R.FinishClear(0.5, 0), "Roshan at half")
	T.ok(not R.FinishClear(nil, 0), "Roshan's HP unknown")
	-- The stepped-out heroes stood 1618-2014 from the pit in game 088.
	T.ok(R.FINISH_HITTER_RANGE >= 2014, "hitter range covers them")
end)
