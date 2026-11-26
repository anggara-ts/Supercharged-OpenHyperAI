-- bots/lib/systems/berserk_potion_rules.lua (#184): Alchemist's Berserk Potion (Aghanim's Shard) target rules.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_alchemist" })
	return require(GetScriptDirectory() .. "/lib/systems/berserk_potion_rules")
end

T.test("berserk potion: dispel, save and fight, each only in its situation", function()
	local R = load()
	-- A Rod of Atos root (severity 5, basic-dispellable in bots/lib/systems/dispel.lua) next to an enemy hero.
	T.eq(R.Why({ basicScore = 5, threatened = true, hp = 0.9 }), "dispel", "listed basic debuff")
	T.eq(R.Why({ rootSilence = true, threatened = true, hp = 0.9 }), "dispel", "rooted or silenced")
	T.eq(R.Why({ basicScore = 5, threatened = false, hp = 0.9 }), nil, "no enemy near: keep it")
	T.eq(R.Why({ basicScore = 2, threatened = true, hp = 0.9 }), nil, "a goo alone is not worth it")
	T.eq(R.Why({ hp = 0.3, chasers = 1, recentlyHit = true }), "save", "hurt and chased")
	T.eq(R.Why({ hp = 0.5, chasers = 2, recentlyHit = true }), nil, "not hurt enough")
	T.eq(R.Why({ hp = 0.3, chasers = 0, recentlyHit = true }), nil, "no enemy hero close")
	T.eq(R.Why({ hp = 0.3, chasers = 1, recentlyHit = false }), nil, "not being hit")
	T.eq(R.Why({ hp = 0.9, core = true, fighting = true }), "fight", "core hitting a hero")
	T.eq(R.Why({ hp = 0.9, core = false, fighting = true }), nil, "support hitting a hero")
	T.eq(R.Why({ hp = 0.9, core = true, fighting = false }), nil, "core not fighting")
	T.eq(R.Why({ buffed = true, basicScore = 9, threatened = true, hp = 0.1 }), nil, "already has the potion")
end)

T.test("berserk potion: the dispel beats the save beats the fight, then the lowest HP", function()
	local R = load()
	local fight = { hp = 0.9, core = true, fighting = true }
	local save = { hp = 0.3, chasers = 1, recentlyHit = true }
	local dispel = { hp = 0.8, rootSilence = true, threatened = true }
	local idx, why = R.Pick({ fight, save, dispel })
	T.eq(idx, 3, "dispel first")
	T.eq(why, "dispel", "why dispel")
	idx, why = R.Pick({ fight, save })
	T.eq(idx, 2, "save before fight")
	T.eq(why, "save", "why save")
	idx = R.Pick({ { hp = 0.35, chasers = 1, recentlyHit = true }, { hp = 0.2, chasers = 1, recentlyHit = true } })
	T.eq(idx, 2, "two saves: the lower HP")
	idx, why = R.Pick({ { hp = 1 }, { hp = 0.5 } })
	T.eq(idx, nil, "nobody qualifies")
	T.eq(why, nil, "no reason")
end)

T.test("berserk potion: the Alchemist rule runs on the stub", function()
	Stub.reset({ hero = "npc_dota_hero_alchemist", slot = 1 })
	local ok, X = Stub.load("bots/heroes/hero_alchemist")
	T.ok(ok, "hero file loads: " .. tostring(X))
	local okC, desire = pcall(X.ConsiderBerserkPotion)
	T.ok(okC, "ConsiderBerserkPotion: " .. tostring(desire))
	T.eq(desire, BOT_ACTION_DESIRE_NONE, "no cast without the Shard")
	-- The Shard granted it, he has the mana, he is rooted, and an enemy hero
	-- stands next to him.
	local bot = Stub.bot
	local potion = bot:GetAbilityByName("alchemist_berserk_potion")
	T.ok(potion ~= nil, "the stub hero has the ability")
	potion.IsTrained = function()
		return true
	end
	potion.IsFullyCastable = function()
		return true
	end
	potion.GetCastRange = function()
		return 800
	end
	potion.GetManaCost = function()
		return 75
	end
	bot.GetMana = function()
		return 500
	end
	bot.IsRooted = function()
		return true
	end
	local enemyHero = Stub.teams[bot:GetTeam() == 2 and 3 or 2][1]
	enemyHero._loc = bot:GetLocation()
	-- A new think (the first call above logged a skip).
	Stub.time = (Stub.time or 0) + 5
	local okR, desireR, target = pcall(X.ConsiderBerserkPotion)
	T.ok(okR, "ConsiderBerserkPotion when castable: " .. tostring(desireR))
	T.eq(desireR, BOT_ACTION_DESIRE_HIGH, "thrown")
	T.ok(target == bot, "at himself (self-cast allowed: no target flags in the game data)")
	T.eq(bot._potionOrder and bot._potionOrder.name, "alchemist", "the order is remembered for the refused check")
	-- Ordered every think for 3 s in range and never thrown (the stub's cooldown stays ready): refused, held out.
	for _ = 1, 7 do
		Stub.time = Stub.time + 0.5
		desireR = X.ConsiderBerserkPotion()
	end
	T.eq(desireR, BOT_ACTION_DESIRE_NONE, "refused: no more orders at himself")
	T.ok((bot._potionRefused or {}).alchemist ~= nil, "himself held out")
	-- While brewing a concoction, the seconds do not count.
	bot._potionRefused, bot._potionOrder = nil, nil
	bot.HasModifier = function(_, name)
		return name == "modifier_alchemist_unstable_concoction"
	end
	for _ = 1, 8 do
		Stub.time = Stub.time + 0.5
		desireR = X.ConsiderBerserkPotion()
	end
	T.eq(desireR, BOT_ACTION_DESIRE_HIGH, "still wanted while brewing")
	T.eq(bot._potionRefused, nil, "not counted as refused while brewing")
end)

T.test("berserk potion: a refused order needs 3 s of orders in range with no throw", function()
	local R = load()
	local order, refused = R.OrderStep(nil, "alchemist", 100, true, true)
	T.eq(refused, false, "first order")
	for t = 100.5, 102.5, 0.5 do
		order, refused = R.OrderStep(order, "alchemist", t, true, true)
		T.eq(refused, false, "still waiting at " .. t)
	end
	order, refused = R.OrderStep(order, "alchemist", 103, true, true)
	T.eq(refused, true, "3 s in range, cooldown never started: refused")
	T.eq(order, nil, "record cleared")
end)

T.test("berserk potion: death, a lapse, a new target or walking in range start the count again", function()
	local R = load()
	-- Thrown at t=100, died at 101, back after the cooldown: the first new order is not a refusal.
	local order = R.OrderStep(nil, "alchemist", 100, true, true)
	local refused
	order, refused = R.OrderStep(order, "alchemist", 230, true, true)
	T.eq(refused, false, "after a long gap")
	T.eq(order.inRangeAt, 230, "count restarted")
	-- The reason lapsed for 2 s between orders.
	order = R.OrderStep(nil, "puck", 300, true, true)
	order, refused = R.OrderStep(order, "puck", 304, true, true)
	T.eq(refused, false, "gap of 4 s")
	-- Another target.
	order = R.OrderStep(nil, "puck", 400, true, true)
	order, refused = R.OrderStep(order, "zuus", 403.5, true, true)
	T.eq(refused, false, "new target")
	-- Walking toward the target out of range does not count.
	order = R.OrderStep(nil, "puck", 500, false, true)
	for t = 500.5, 503, 0.5 do
		order, refused = R.OrderStep(order, "puck", t, false, true)
		T.eq(refused, false, "out of range at " .. t)
	end
	order, refused = R.OrderStep(order, "puck", 503.5, true, true)
	T.eq(refused, false, "just came in range")
	-- The throw happened (cooldown started): never a refusal.
	order = R.OrderStep(nil, "puck", 600, true, true)
	order, refused = R.OrderStep(order, "puck", 600.5, true, false)
	order, refused = R.OrderStep(order, "puck", 603.5, true, false)
	T.eq(refused, false, "on cooldown")
	T.ok(order ~= nil, "record kept")
end)
