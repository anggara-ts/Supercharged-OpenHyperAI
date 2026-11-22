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
		hit = false,
		away = false,
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
	T.eq(
		R.ChargeSkipWhy(save({ enemies = 3, hitBy = 3 })),
		"outnumbered",
		"2 vs 3 after he lands: CancelWhy would stop it"
	)
	T.eq(R.ChargeSkipWhy(save({ enemies = 4, hitBy = 3 })), "outnumbered", "2 vs 4: no")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 200 })), "too-late", "dies in 4.5s, lands in 6s")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 150 })), "too-late", "dies at the moment he lands")
	local noSample = save()
	noSample.lossRate = nil -- (an override table cannot carry a nil)
	T.eq(R.ChargeSkipWhy(noSample), "no-sample", "no HP history yet: no guess")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 0 })), "no-danger", "hit but not losing HP: no save needed")
	T.eq(R.ChargeSkipWhy(save({ lossRate = 0, allyHpRatio = 0.4 })), nil, "under 50% and hit: danger")
	-- game 072 t=863: a 14.5s charge for Largo at ttd=99 ran him into four heroes under Dire's tier 1
	T.eq(R.ChargeSkipWhy(save({ eta = 14.5, lossRate = 900 / 99, allyHpRatio = 0.7 })), "no-danger", "game 072")
	T.eq(R.ChargeSkipWhy(save({ eta = 6, lossRate = 900 / 12 })), "no-danger", "dies 6s after he lands: no")
	T.eq(R.ChargeSkipWhy(save({ eta = 6, lossRate = 900 / 10 })), nil, "dies 4s after he lands: go")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 1, enemies = 1 })), "no-gank", "a 1 v 1 is no gank")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 1, enemies = 2 })), nil, "hit by 1 while 2 enemies are on 1 ally: gank")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 0, enemies = 3 })), "no-gank", "enemies near but nobody hits it")
	T.eq(R.ChargeSkipWhy(save({ hitBy = 0, selfHp = 0.2 })), "no-gank", "no gank comes first (it is not logged)")
	T.eq(R.ChargeSkipWhy(save({ selfHp = 0.35 })), "low-hp", "Spirit Breaker under 40%")
	T.eq(R.ChargeSkipWhy(save({ retreating = true })), "retreat", "retreating")
	-- maintainer (#208): being hit is no reason to stay; under 40% / retreating only when it is also his escape
	T.eq(R.ChargeSkipWhy(save({ hit = true })), nil, "being hit does not block the save")
	T.eq(R.ChargeSkipWhy(save({ hit = true, selfHp = 0.3 })), "low-hp", "low and hit, charging into his attackers")
	T.eq(R.ChargeSkipWhy(save({ hit = true, away = true, selfHp = 0.3 })), nil, "low and hit, charging away: escape")
	T.eq(R.ChargeSkipWhy(save({ away = true, selfHp = 0.3 })), "low-hp", "low, not hit: no escape needed")
	T.eq(R.ChargeSkipWhy(save({ hit = true, away = true, retreating = true })), nil, "retreating, away: escape")
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
	fight.hit, fight.away, fight.tower = true, true, false
	T.eq(R.ChargeSkipWhy(fight), nil, "low HP but the charge is his escape")
end)

local function running(over)
	local c =
		{ kind = "save", distLeft = 4000, ours = 2, enemies = 2, tower = false, allyDead = false, allySafeFor = 0 }
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

T.test("charge rules: cancel a running long charge", function()
	local R = rules()
	T.eq(R.CancelWhy(running()), nil, "2 v 2, ally still in trouble: keep going")
	T.eq(R.CancelWhy(running({ allyDead = true })), "ally-dead", "the ally died")
	T.eq(R.CancelWhy(running({ allySafeFor = 0.5 })), nil, "safe for a moment only")
	T.eq(R.CancelWhy(running({ allySafeFor = 1.2 })), "ally-safe", "the ally got away")
	T.eq(R.CancelWhy(running({ allySafeFor = 5, kind = "fight" })), nil, "a fight charge has no ally to check")
	-- game 072 t=878: allies=0 enemies=4 at Dire's mid tier 1
	T.eq(R.CancelWhy(running({ ours = 1, enemies = 4 })), "outnumbered", "game 072: alone against four")
	T.eq(R.CancelWhy(running({ tower = true, towerDist = 2500 })), "tower", "2 v 2 under their tower")
	T.eq(R.CancelWhy(running({ tower = true, towerDist = 2500, ours = 4 })), nil, "4 v 2: the fight is ours")
	T.eq(R.CancelWhy(running({ tower = true, towerDist = 950, ours = 1, enemies = 4 })), nil, "inside range + 300")
	T.eq(R.CancelWhy(running({ tower = true, towerDist = 1010 })), "tower", "just outside range + 300")
	T.eq(R.CancelWhy(running({ distLeft = 500, ours = 1, enemies = 3 })), nil, "next to the target: committed")
end)

T.test("charge rules: when a ganked ally no longer needs the save", function()
	local R = rules()
	T.ok(R.AllySafe(0, false, true, 300, 0.2), "no enemy near it")
	T.ok(R.AllySafe(2, true, true, 300, 0.2), "back home")
	T.ok(R.AllySafe(2, false, false, 0, 0.6), "not hit, not losing HP, above half")
	T.ok(not R.AllySafe(2, false, false, 0, 0.3), "not hit but low with enemies near")
	T.ok(not R.AllySafe(2, false, true, 0, 0.9), "still being hit")
	T.ok(not R.AllySafe(2, false, false, nil, 0.9), "no HP sample: not safe")
end)

T.test("charge rules: away from the attackers", function()
	local R = rules()
	local me = { x = 0, y = 0 }
	local melee = { { x = 150, y = 0 } }
	T.ok(R.IsAway(me, { x = -3000, y = 0 }, melee), "melee attacker east, charge west")
	T.ok(not R.IsAway(me, { x = 3000, y = 0 }, melee), "charge through the attacker")
	T.ok(R.IsAway(me, { x = 0, y = 3000 }, melee), "sideways: the path never gets closer to it")
	T.ok(not R.IsAway(me, { x = 3000, y = 3000 }, melee), "diagonal past the attacker: gets closer first")
	local ranged = { { x = 600, y = 0 } }
	T.ok(not R.IsAway(me, { x = 3000, y = 200 }, ranged), "target beyond a ranged attacker")
	T.ok(not R.IsAway(me, { x = 3000, y = 1500 }, ranged), "path within 400 of a ranged attacker")
	T.ok(R.IsAway(me, { x = -2000, y = 3000 }, ranged), "away from a ranged attacker")
	T.ok(not R.IsAway(me, { x = -3000, y = 0 }, { { x = 150, y = 0 }, { x = -2000, y = 100 } }), "one attacker ahead")
	T.ok(not R.IsAway(me, { x = -3000, y = 0 }, {}), "no attacker seen: not an escape")
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
