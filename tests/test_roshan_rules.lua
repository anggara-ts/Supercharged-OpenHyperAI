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
		-- He died in 20s: 11330 HP in 20s needs 566 off his HP per second, about 2350 right-click through the model
		-- (the old 5 x 170 here was a guess; no model kills him in 20s with it).
		groupDps = 5 * 470,
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

T.test("time to half: right-click through armor 30, 70% of it lands, minus his regeneration", function()
	local R = rules()
	T.eq(R.HALF_CREDIT, 0.75, "credit (game 091 retune)")
	T.near(R.ArmorThrough(30), 1 / 2.8, 1e-9, "armor 30 lets 35.7% through")
	T.near(R.ArmorThrough(0), 1, 1e-9, "no armor")
	-- 1000 right-click: 1000 / 2.8 * 0.7 = 250 lands, 20 regenerates.
	T.near(R.HitDps(1000), 230, 1e-6, "1000 right-click")
	T.eq(R.HitDps(50), 0, "his regeneration outheals 50")
	T.near(R.HalfTime(10000, 10000, 1000), 5000 / 230, 1e-6, "full Roshan")
	T.eq(R.HalfTime(4000, 10000, 1000), 0, "already under half")
	T.near(R.HalfTime(10000, 10000, 0), 5000, 1e-9, "no damage: never")
end)

T.test("full-HP groups at 31:00: 5 carries' worth of right-click fit, 4 supports do not", function()
	local R = rules()
	local function group(n, maxHp, dps, minute)
		local members = {}
		for i = 1, n do
			members[i] = member(1.0, maxHp)
		end
		local roshHp = 6000 + 130 * minute
		return R.GroupFit({ members = members, groupDps = n * dps, roshHp = roshHp, roshMax = roshHp })
	end
	-- 5 x 2000 HP, 5 x 160 right-click: tank 5500 / 205 = 26.8s; half 5015 / (800 / 2.8 * 0.7 - 20) = 27.9s.
	local ok, why, numbers = group(5, 2000, 160, 31)
	T.ok(ok, "5 at 31:00 " .. why)
	T.near(numbers.tank, 5500 / 205, 1e-9, "tank")
	T.near(numbers.half, 5015 / (800 / 2.8 * 0.7 - 20), 1e-6, "half")
	T.ok(string.find(why, "dps=800,hit=180)", 1, true) ~= nil, "the line names the right-click and what lands: " .. why)
	-- 4 x 1500 HP, 4 x 130: tank 3300 / 198 = 16.7s; half 5015 / (520 / 2.8 * 0.7 - 20) = 45.6s.
	ok, why = group(4, 1500, 130, 31)
	T.ok(not ok, "4 at 31:00 " .. why)
	T.ok(string.find(why, "tank-short", 1, true) ~= nil, why)
end)

-- Every committed take with recorded fit numbers (#12). { name, game second, tank, half }: tank / half are the
-- group(tank=,half=) seconds of the log, from the old model (half = Roshan's HP above half / half the right-click).
-- Games 088-091 print them on the commit line; older games only on the call lines before it (the call counts everyone
-- coming, often a minute or more before the commit), so those are an approximation. The logs round to whole seconds.
-- Logged(...) rebuilds the GroupFit input: Roshan's HP at that minute (6000 + 130 per minute, full), the right-click that
-- gave the logged half (roshMax / half), and five full-HP members whose pool gives the logged tank.
local function Logged(R, take)
	local minute, tank, half = take[2] / 60, take[3], take[4]
	local roshMax = 6000 + 130 * minute
	local pool = tank * (170 + R.SLAM_DPS * 5)
	local members = {}
	for i = 1, 5 do
		members[i] = member(1.0, pool / 5 / (1 - R.LEAVE_HP))
	end
	return R.GroupFit({ members = members, groupDps = roshMax / half, roshHp = roshMax, roshMax = roshMax })
end
-- Commits that passed the old check and failed (games 088-091: every commit line with fit=; 091's two lines are one
-- take, so six takes), then older failed takes from call-line fits.
local FAILED = {
	{ "091 dire 5/5 (Roshan 76% after 16s, four left under 45%, Radiant took him)", 1885, 21, 14 },
	{ "091 dire 4/5 (the same take, the first commit line)", 1885, 17, 17 },
	{ "088 radiant 4/4 (left Roshan at 34%)", 1297, 16, 19 },
	{ "088 dire 4/4 (left him at 18%)", 1681, 14, 18 },
	{ "089 dire 5/5 (left at 82% after 19s)", 1594, 17, 17 },
	{ "089 dire 5/5 (left at 94% after 15s)", 2069, 18, 14 },
	{ "089 dire 4/5 (left at 75% after 20s)", 2199, 18, 17 },
	{ "087 radiant 4/4 (left at 90%)", 1048, 11, 12 },
	{ "083 dire 4/5 (left at 51%)", 1963, 13, 16 },
	{ "083 dire 4/4 (left at 51%)", 2034, 12, 16 },
	{ "081 dire 5/5 (left at 83%)", 1572, 13, 15 },
	{ "069 radiant 3/5 (left at 66%)", 1116, 14, 16 },
	{ "069 dire 3/4 (left at 28%)", 1403, 14, 15 },
}
-- Kills (games 074-087, call-line fits) that still pass: a fast group.
local KILLED = {
	{ "074 dire (died t=4252)", 4216, 37, 10 },
	{ "083 radiant (Aegis t=3275)", 3246, 34, 8 },
	{ "084 radiant (died t=3793)", 3742, 38, 8 },
	{ "085 dire (Aegis t=2001)", 1963, 24, 10 },
	{ "085 dire (Aegis t=2677)", 2637, 30, 9 },
	{ "085 dire (Aegis t=3569)", 3488, 24, 12 },
	{ "087 dire (died t=1647; a human on the team took the Aegis)", 1622, 17, 10 },
}
-- Kills that the new check drops (the cost of the retune; a slower group, call-line fits only).
local KILLED_DROPPED = {
	{ "074 radiant (died t=2486)", 2455, 26, 16 },
	{ "078 radiant (died t=1497)", 1457, 17, 13 },
	{ "081 dire (died t=2011)", 1981, 14, 11 },
	{ "082 radiant (died t=851)", 809, 18, 16 },
	{ "082 radiant (died t=1952; a human took the Aegis)", 1917, 12, 12 },
	{ "085 radiant (died t=1261)", 1240, 14, 14 },
}
-- Takes that failed with the check passing: the cause was not the tank model (enemies came, the group split).
local FAILED_BUT_FIT = {
	{ "087 radiant 3/5 by=window (left at 60%)", 1337, 22, 10 },
	{ "087 dire 4/4 (left at 48%; the next take killed him)", 1535, 17, 10 },
}

T.test("recorded takes: every failed commit of games 088-091 drops, the fast kills still pass", function()
	local R = rules()
	for _, take in ipairs(FAILED) do
		local ok, why, numbers = Logged(R, take)
		T.near(numbers.tank, take[3], 1e-6, "rebuilt tank: " .. take[1])
		T.ok(not ok, "failed, dropped now: " .. take[1] .. " " .. why)
	end
	for _, take in ipairs(KILLED) do
		local ok, why = Logged(R, take)
		T.ok(ok, "killed, still passes: " .. take[1] .. " " .. why)
	end
	for _, take in ipairs(KILLED_DROPPED) do
		local ok, why = Logged(R, take)
		T.ok(not ok, "killed, dropped now: " .. take[1] .. " " .. why)
	end
	for _, take in ipairs(FAILED_BUT_FIT) do
		local ok, why = Logged(R, take)
		T.ok(ok, "still passes (not a tank-model failure): " .. take[1] .. " " .. why)
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
	T.ok(string.find(why, "low=1,", 1, true) ~= nil, why)
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
