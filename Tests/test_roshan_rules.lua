-- FuncLib/systems/roshan_rules.lua: can the group that comes tank Roshan to half HP (#12, game 068: 3 of 4 committed
-- tries failed; the kill time ignored Roshan's damage on the group).
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/roshan_rules")
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

T.test("healthy groups fit: 5 at 20:00, 4 at 25:00, 3 at 40:00", function()
	local R = rules()
	local function group(n, maxHp, dps, minute)
		local members = {}
		for i = 1, n do
			members[i] = member(1.0, maxHp)
		end
		local roshHp = 6000 + 130 * minute
		return R.GroupFit({ members = members, groupDps = n * dps, roshHp = roshHp, roshMax = roshHp })
	end
	local ok, why = group(5, 1300, 100, 20)
	T.ok(ok, "5 at 20:00 " .. why)
	ok, why = group(4, 1500, 130, 25)
	T.ok(ok, "4 at 25:00 " .. why)
	ok, why = group(3, 2200, 170, 40)
	T.ok(ok, "3 at 40:00 " .. why)
	-- Two heroes late are not enough to tank him to half.
	ok, why = group(2, 2400, 200, 45)
	T.ok(not ok, "2 at 45:00 " .. why)
end)
