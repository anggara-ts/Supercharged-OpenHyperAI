-- FuncLib/systems/charge_rules.lua (#47): Spirit Breaker's long Charge of Darkness - travel time, an ally's HP-loss
-- rate, when the save / teamfight charge is skipped, and the target score.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_spirit_breaker" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/charge_rules")
end

T.test("charge rules: travel time with the 1.5s windup and the speed cap", function()
	local R = rules()
	-- 300 move speed, level 1 bonus 275 (datafeed): starts at 368.75, capped at 550 after the windup
	T.near(R.ChargeEta(3000, 300, 275, 1.5, 25, 0.1, 550), 5.80, 0.01, "3000 away, capped")
	T.near(R.ChargeEta(3000, 300, 275, 1.5, 25, 0.1, nil), 5.59, 0.01, "3000 away, no cap: shorter")
	T.near(R.ChargeEta(300, 300, 275, 1.5, 25, 0.1, 550), 0.83, 0.01, "300 away lands inside the windup")
	T.ok(R.ChargeEta(3000, 300, 425) < R.ChargeEta(3000, 300, 275), "defaults: a higher level is faster")
end)

T.test("charge rules: HP-loss rate from a 0.5-1.5s old sample", function()
	local R = rules()
	local samples = {}
	R.PushSample(samples, 0, 1000)
	R.PushSample(samples, 0.5, 900)
	R.PushSample(samples, 1.0, 800)
	T.near(R.LossRate(samples, 1.2, 760), 200, 0.01, "1000 -> 760 over 1.2s")
	T.eq(R.LossRate({ { t = 1.0, hp = 800 } }, 1.2, 760), nil, "only a fresh sample: no rate")
	T.eq(R.LossRate(samples, 1.2, 1100), 0, "healing counts as no loss")
	for t = 1.5, 4, 0.5 do
		R.PushSample(samples, t, 800)
	end
	T.ok(samples[1].t >= 2, "samples older than 2s are dropped")
	T.eq(R.TimeToDie(400, 0), math.huge, "not losing HP")
	T.near(R.TimeToDie(400, 200), 2, 0.001, "400 HP at 200/s")
end)

local function save(over)
	local s = {
		kind = "save",
		selfHp = 0.8,
		retreating = false,
		busy = false,
		dist = 4000,
		eta = 6,
		allies = 1,
		enemies = 2,
		hitBy = 2,
		allyHp = 900,
		lossRate = 100,
		tower = false,
	}
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end

T.test("charge rules: the save charge", function()
	local R = rules()
	T.eq(R.ChargeSkipWhy(save()), nil, "1 ally hit by 2, lives 9s, charge lands in 6s: go (2 vs 2)")
	T.eq(R.ChargeSkipWhy(save({ enemies = 3, hitBy = 3 })), nil, "2 vs 3 after he lands: one down is fine")
	T.eq(R.ChargeSkipWhy(save({ enemies = 4, hitBy = 3 })), "outnumbered", "2 vs 4: no")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 200 })), "too-late", "dies in 4.5s, lands in 6s")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 150 })), "too-late", "dies at the moment he lands")
	T.eq(R.ChargeSkipWhy(save({ lossRate = nil })), "no-sample", "no HP history yet: no guess")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 0 })), nil, "hit but not losing HP: lives")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 1, enemies = 1 })), "no-gank", "a 1 v 1 is no gank")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 1, enemies = 2 })), nil, "hit by 1 while 2 enemies are on 1 ally: gank")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 0, enemies = 3 })), "no-gank", "enemies near but nobody hits it")
	T.eq(R.ChargeSkipWhy(save({ selfHp = 0.35 })), "low-hp", "Spirit Breaker under 40%")
	T.eq(R.ChargeSkipWhy(save({ retreating = true })), "retreat", "retreating")
	T.eq(R.ChargeSkipWhy(save({ busy = true })), "busy", "in his own fight")
	T.eq(R.ChargeSkipWhy(save({ dist = 1200 })), "near", "the near rules cover it")
	T.eq(R.ChargeSkipWhy(save({ tower = true })), "tower", "2 vs 2 under their tower")
	T.eq(R.ChargeSkipWhy(save({ tower = true, allies = 3, enemies = 2 })), nil, "already ours: tower is fine")
end)

T.test("charge rules: the teamfight charge", function()
	local R = rules()
	local fight = { kind = "fight", selfHp = 0.7, dist = 3500, eta = 5, allies = 3, enemies = 3, tower = false }
	T.eq(R.ChargeSkipWhy(fight), nil, "3 v 3, lands in 5s")
	fight.eta = 8
	T.eq(R.ChargeSkipWhy(fight), "too-far", "lands after 7s")
	fight.eta, fight.allies, fight.enemies = 5, 2, 5
	T.eq(R.ChargeSkipWhy(fight), "outnumbered", "3 vs 5 after he lands")
	fight.allies, fight.enemies, fight.tower = 3, 4, true
	T.eq(R.ChargeSkipWhy(fight), "tower", "4 vs 4 under their tower")
	fight.selfHp = 0.3
	T.eq(R.ChargeSkipWhy(fight), "low-hp", "low HP first")
end)

T.test("charge rules: target score", function()
	local R = rules()
	local hitter = R.TargetScore({ hp = 0.9, core = false, hitsAlly = true, distToSpot = 300 })
	local lowCore = R.TargetScore({ hp = 0.2, core = true, hitsAlly = false, distToSpot = 300 })
	T.ok(hitter > lowCore, "save: the hero hurting the ally first")
	local low = R.TargetScore({ hp = 0.3, core = false, distToSpot = 400 })
	local full = R.TargetScore({ hp = 1.0, core = false, distToSpot = 100 })
	T.ok(low > full, "fight: the lower one")
	local core = R.TargetScore({ hp = 0.6, core = true, distToSpot = 400 })
	local support = R.TargetScore({ hp = 0.6, core = false, distToSpot = 400 })
	T.ok(core > support, "fight: a core over a support at the same HP")
end)
