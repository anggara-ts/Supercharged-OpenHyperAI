-- bots/lib/systems/shadow_realm_rules.lua (#48): Dark Willow's Shadow Realm hold, bonus damage and the escape TP.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_dark_willow" })
	return require(GetScriptDirectory() .. "/lib/systems/shadow_realm_rules")
end

T.test("shadow realm: the bonus grows to its maximum at 3s", function()
	local R = load()
	-- Datafeed hero 119: damage 120/200/280/360, max_damage_duration 3.
	T.eq(R.BonusDamage(360, 0, 3), 0, "at the cast")
	T.near(R.BonusDamage(360, 1.5, 3), 180, 0.01, "half way")
	T.eq(R.BonusDamage(360, 3, 3), 360, "full at 3s")
	T.eq(R.BonusDamage(360, 4.5, 3), 360, "no more after 3s")
end)

T.test("shadow realm: hold, close in or hit", function()
	local R = load()
	local base = {
		since = 1,
		maxTime = 3,
		dist = 700,
		holdRange = 1100,
		predictedDist = 720,
		canFollow = true,
		killNow = false,
		allyNeeds = false,
	}
	local function step(over)
		local o = {}
		for k, v in pairs(base) do
			o[k] = v
		end
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		return R.HoldStep(o)
	end
	T.eq(step(), "hold", "in range, 1s in: wait for the damage")
	T.eq(select(2, step({ since = 3 })), "max", "full bonus: hit")
	T.eq(select(2, step({ since = 4.5, maxTime = 6 })), "end", "the realm is about to end (a longer max time)")
	T.eq(select(2, step({ killNow = true })), "kill", "the hit kills now")
	T.eq(select(2, step({ allyNeeds = true })), "ally", "an ally needs the damage")
	T.eq(step({ dist = 1050, predictedDist = 1060 }), "close", "near the edge, she can follow: step after it")
	T.eq(
		select(2, step({ dist = 1050, predictedDist = 1150, canFollow = false })),
		"leave",
		"walking out of range faster than her: hit now"
	)
	T.eq(step({ dist = 1300, predictedDist = 1320 }), "close", "out of range: close in")
end)

T.test("shadow realm: the escape TP fits inside the realm (game 067, 17:06)", function()
	local R = load()
	-- 5s realm, 3s TP channel (7.42 items_all.txt).
	T.eq(R.TpFits(0.1, 5, 3, 0.3), true, "right after the cast")
	T.eq(R.TpFits(1.7, 5, 3, 0.3), true, "1.7s in: ends at 4.7s")
	T.eq(R.TpFits(4, 5, 3, 0.3), false, "game 067: 4s in, the channel outlasts the realm")
end)

T.test("dark willow: the realm helpers run on the stub", function()
	T.stub.reset({ hero = "npc_dota_hero_dark_willow", slot = 4 })
	local ok, X = T.stub.load("bots/heroes/hero_dark_willow")
	T.ok(ok, "hero_dark_willow loads: " .. tostring(X))
	local okC, err = pcall(X.ConsiderShadowRealm)
	T.ok(okC, "ConsiderShadowRealm: " .. tostring(err))
	for _, why in ipairs({ "attack", "retreat" }) do
		local okS, errS = pcall(X.StartShadowRealm, why, nil)
		T.ok(okS, "StartShadowRealm " .. why .. ": " .. tostring(errS))
		local okT, errT = pcall(X.ShadowRealmTick)
		T.ok(okT, "ShadowRealmTick " .. why .. ": " .. tostring(errT))
	end
	local okSk, errSk = pcall(X.SkillsComplement)
	T.ok(okSk, "SkillsComplement: " .. tostring(errSk))
end)

-- Drives the realm tick through the hold, the full-bonus hit and the escape TP (the stub alone stops at "no cast").
local function realmBot()
	local bot = T.stub.reset({ hero = "npc_dota_hero_dark_willow", slot = 4, time = 100 })
	local ok, X = T.stub.load("bots/heroes/hero_dark_willow")
	T.ok(ok, "hero_dark_willow loads: " .. tostring(X))
	local realm = bot:GetAbilityByName("dark_willow_shadow_realm")
	realm.GetCooldownTimeRemaining = function()
		return 15
	end
	local orders = {}
	bot.Action_MoveToLocation = function()
		orders[#orders + 1] = "move"
	end
	bot.Action_AttackUnit = function()
		orders[#orders + 1] = "attack"
	end
	bot.Action_UseAbilityOnLocation = function(_, ability)
		orders[#orders + 1] = "use:" .. ability:GetName()
	end
	return bot, X, orders
end

T.test("dark willow: an attack realm holds, then hits at 3s", function()
	local bot, X, orders = realmBot()
	bot.GetActiveMode = function()
		return BOT_MODE_ATTACK
	end
	bot.GetAttackRange = function()
		return 475
	end
	local target = T.stub.teams[TEAM_DIRE][1]
	target._loc = bot._loc + Vector(700, 0, 0)
	X.StartShadowRealm("attack", target)
	T.stub.time = 101
	T.eq(X.ShadowRealmTick(), false, "1s in: a hold move, spells may still go out")
	T.eq(orders[#orders], "move", "she moves, she does not attack")
	T.eq(bot._attackHold(), true, "the attack mode is held")
	T.stub.time = 103.05
	T.eq(X.ShadowRealmTick(), true, "3s in: the hit")
	T.eq(orders[#orders], "attack", "attack order")
	T.eq(bot._dwRealm.released, "max", "release=max")
	T.eq(bot._attackHold(), false, "the attack mode attacks again")
	T.stub.time = 105.5
	X.ShadowRealmTick()
	T.eq(bot._dwRealm, nil, "the realm is over")
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "shadow-realm why=attack held=3.05", 1, true) ~= nil, line)
	T.ok(string.find(line, "release=max", 1, true) ~= nil, line)
end)

T.test("dark willow: an escape realm starts the TP at once (game 067, 17:06)", function()
	local bot, X, orders = realmBot()
	-- 10% HP, alone (the stub's ally list ignores the mode filter: move the allies away).
	bot._hp = 100
	for _, ally in ipairs(T.stub.teams[bot._team]) do
		if ally ~= bot then
			ally._loc = Vector(0, 0, 0)
		end
	end
	bot.DistanceFromFountain = function()
		return 9000
	end
	bot.WasRecentlyDamagedByAnyHero = function()
		return true
	end
	local scroll = T.stub.newAbility("item_tpscroll", bot, false)
	scroll.IsFullyCastable = function()
		return true
	end
	bot._items[15] = scroll
	bot.FindItemSlot = function(_, name)
		return name == "item_tpscroll" and 15 or -1
	end
	X.StartShadowRealm("retreat", nil)
	T.stub.time = 100.1
	T.eq(X.ShadowRealmTick(), true, "the TP order: " .. tostring(bot._dwRealm and bot._dwRealm.tp))
	T.eq(orders[#orders], "use:item_tpscroll", "TP scroll used")
	T.eq(bot._dwRealm.tp, "ordered", "ordered")
	bot.IsChanneling = function()
		return true
	end
	T.stub.time = 100.3
	X.ShadowRealmTick()
	T.eq(bot._dwRealm.tp, "now", "the channel started")
	T.stub.time = 105.3
	X.ShadowRealmTick()
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "why=retreat", 1, true) ~= nil and string.find(line, "tp=now", 1, true) ~= nil, line)
end)

-- Game 068: she died in a retreat realm and the end line printed at respawn with stale values (t=2274 held=51.10,
-- died 2225). Now it ends as release=died at the last tick she was alive.
T.test("dark willow: a realm she dies in ends as release=died at her last tick", function()
	local bot, X = realmBot()
	X.StartShadowRealm("retreat", nil)
	T.stub.time = 101
	X.ShadowRealmTick()
	T.ok(bot._dwRealm ~= nil, "1s in: still in the realm")
	-- Dead: no tick runs until she respawns 49s later.
	T.stub.time = 151
	X.ShadowRealmTick()
	T.eq(bot._dwRealm, nil, "the realm is over")
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "t=101 dark_willow shadow-realm why=retreat held=1.00 ended=1.00", 1, true) ~= nil, line)
	T.ok(string.find(line, "release=stale", 1, true) ~= nil, "no death counted: stale " .. line)
	-- A tick while she is dead (the realm was cast at 151).
	X.StartShadowRealm("retreat", nil)
	T.stub.time = 152
	X.ShadowRealmTick()
	bot._alive = false
	T.stub.time = 153
	X.ShadowRealmTick()
	bot._alive = true
	T.eq(bot._dwRealm, nil, "ended when dead")
	line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "t=152 dark_willow shadow-realm why=retreat held=1.00", 1, true) ~= nil, line)
	T.ok(string.find(line, "release=died", 1, true) ~= nil, line)
end)

T.test("shadow realm: when to cast (game 069, #48)", function()
	local R = load()
	-- Attack realm: under 60% HP or more enemy heroes within 1200 than our heroes (her included).
	T.eq(R.AttackSkip(0.9, 1, 1), nil, "1v1 at 90%")
	T.eq(R.AttackSkip(0.9, 2, 2), nil, "2v2")
	T.eq(R.AttackSkip(0.45, 1, 3), "low-hp", "14:01: cast at 45% HP")
	T.eq(R.AttackSkip(0.99, 3, 2), "outnumbered", "12:55: 3 enemies, she and 1 ally")
	T.eq(R.AttackSkip(0.66, 4, 2), "outnumbered", "44:59: 4 enemies, she and 1 ally")
	-- Escape realm.
	local function escape(retreating, engaging, hp, hit)
		return R.Escape({ retreating = retreating, engaging = engaging, hp = hp, hit = hit })
	end
	T.eq(escape(true, false, 0.5, false), "retreat", "retreating at 50%")
	T.eq(escape(true, false, 1.0, true), "retreat", "retreating at full HP, hit by a hero")
	T.eq(select(2, escape(true, false, 1.0, false)), "full-hp", "9:39: retreating at full HP, not hit")
	T.eq(escape(true, false, 0.85, false), nil, "retreating at 85%, not hit: no realm")
	T.eq(escape(false, false, 0.5, true), "hit", "24:43: pushing at 50%, hit by a hero")
	T.eq(escape(false, false, 0.5, false), nil, "pushing at 50%, not hit")
	T.eq(escape(false, false, 0.7, true), nil, "pushing at 70%, hit")
	T.eq(escape(false, true, 0.5, true), nil, "in a fight mode the attack and dodge rules decide")
	T.eq(escape(true, true, 0.3, true), "retreat", "cornered (retreating and engaging): escape")
	-- Release reasons, the early drop.
	T.eq(R.JoinRelease(nil, "died"), "died", "only died")
	T.eq(R.JoinRelease("mode", "died"), "mode+died", "44:59: both kept")
	T.eq(R.JoinRelease("died", "died"), "died", "no repeat")
	T.eq(R.EarlyDrop(nil, 0.67, 5), true, "5:03: gone after 0.67s, nothing released it")
	T.eq(R.EarlyDrop("max", 3.3, 5), false, "the hit ended it")
	T.eq(R.EarlyDrop(nil, 4.9, 5), false, "ran out")
end)

-- Everything but Shadow Realm out of reach, one enemy hero 400 away, the other heroes far.
local function castBot(mode, hpRatio, hit)
	local bot = T.stub.reset({ hero = "npc_dota_hero_dark_willow", slot = 4, time = 600 })
	local ok, X = T.stub.load("bots/heroes/hero_dark_willow")
	T.ok(ok, "hero_dark_willow loads: " .. tostring(X))
	local realm = bot:GetAbilityByName("dark_willow_shadow_realm")
	realm.IsFullyCastable = function()
		return true
	end
	local enemy = nil
	for _, hero in ipairs(T.stub.heroes) do
		if hero ~= bot then
			hero._loc = bot._loc + Vector(5000, 5000, 0)
			if enemy == nil and hero._team ~= bot._team then
				enemy = hero
			end
		end
	end
	enemy._loc = bot._loc + Vector(400, 0, 0)
	bot._hp = bot._maxHp * hpRatio
	bot.GetActiveMode = function()
		return mode
	end
	bot.GetActiveModeDesire = function()
		return 0.8
	end
	bot.DistanceFromFountain = function()
		return 6000
	end
	bot.WasRecentlyDamagedByAnyHero = function()
		return hit
	end
	local used = {}
	bot.Action_UseAbility = function(_, ability)
		used[#used + 1] = ability:GetName()
	end
	return bot, X, used
end

local function printedWith(text)
	for _, line in ipairs(T.stub.printed) do
		if string.find(line, text, 1, true) then
			return line
		end
	end
	return nil
end

T.test("dark willow: an escape realm when hit under 60% HP while pushing (game 069, 24:43)", function()
	local _, X, used = castBot(BOT_MODE_PUSH_TOWER_MID, 0.5, true)
	X.SkillsComplement()
	T.eq(used[#used], "dark_willow_shadow_realm", "Shadow Realm cast")
	local line = printedWith("shadow-realm-cast why=retreat")
	T.ok(line ~= nil and string.find(line, "rule=hit", 1, true) ~= nil, tostring(line))
end)

T.test("dark willow: no retreat realm at full HP when no hero hit her (game 069, 9:39)", function()
	local _, X, used = castBot(BOT_MODE_RETREAT, 1.0, false)
	X.SkillsComplement()
	T.eq(#used, 0, "no realm")
	T.ok(printedWith("shadow-realm-skip kind=retreat why=full-hp") ~= nil, "the skip is logged")
end)

-- Game 069, 44:59: "release=died" lost the first reason.
T.test("dark willow: a release before her death keeps both reasons", function()
	local bot, X = realmBot()
	bot.GetActiveMode = function()
		return BOT_MODE_RETREAT
	end
	local target = T.stub.teams[TEAM_DIRE][1]
	target._loc = bot._loc + Vector(600, 0, 0)
	X.StartShadowRealm("attack", target)
	T.stub.time = 100.5
	X.ShadowRealmTick()
	T.eq(bot._dwRealm.released, "mode", "the mode left attack")
	bot._alive = false
	T.stub.time = 101
	X.ShadowRealmTick()
	bot._alive = true
	T.eq(bot._dwRealm, nil, "ended")
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "release=mode+died", 1, true) ~= nil, line)
end)

-- Game 069, 5:03 9:40 45:55: realms gone after 0.67-1.17s with release=-.
T.test("dark willow: an early realm drop says what she was doing", function()
	local bot, X = realmBot()
	local inRealm = true
	bot.HasModifier = function(_, name)
		return inRealm and name == "modifier_dark_willow_shadow_realm_buff"
	end
	bot.GetActiveMode = function()
		return BOT_MODE_RETREAT
	end
	X.StartShadowRealm("retreat", nil)
	T.stub.time = 100.4
	X.ShadowRealmTick()
	T.ok(bot._dwRealm ~= nil and bot._dwRealm.modSeen ~= nil, "in the realm")
	inRealm = false
	bot.GetLastAttackTime = function()
		return 100.8
	end
	T.stub.time = 101
	X.ShadowRealmTick()
	T.eq(bot._dwRealm, nil, "ended")
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "release=-", 1, true) ~= nil, line)
	T.ok(string.find(line, "drop-mode=" .. BOT_MODE_RETREAT .. ">" .. BOT_MODE_RETREAT, 1, true) ~= nil, line)
	T.ok(string.find(line, "attacked=yes", 1, true) ~= nil, line)
end)

T.test("shadow realm: one cast order, a spaced re-send, then give up (#203, game 079 t=356)", function()
	local R = load()
	T.eq(R.CastStep(0.03, 0.03, 1), "wait", "the next think: no new order")
	T.eq(R.CastStep(0.31, 0.31, 1), "resend", "not taken after 0.3s: one more")
	T.eq(R.CastStep(0.5, 0.19, 2), "wait", "the re-send is spaced")
	T.eq(R.CastStep(0.95, 0.35, 3), "wait", "at most 3 orders")
	T.eq(R.CastStep(1.0, 0.4, 3), "give-up", "1s: give up")
end)

-- Game 079 t=356: the cast line and the order 14 times in one second (the realm record restarted every think, so
-- the no-cast check never fired), then release=stale.
T.test("dark willow: a pending realm cast is ordered once and logged once", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_dark_willow", slot = 4, time = 100 })
	local ok, X = T.stub.load("bots/heroes/hero_dark_willow")
	T.ok(ok, "hero_dark_willow loads: " .. tostring(X))
	local realm = bot:GetAbilityByName("dark_willow_shadow_realm")
	local cooldown = 0
	realm.GetCooldownTimeRemaining = function()
		return cooldown
	end
	realm.IsFullyCastable = function()
		return cooldown <= 0
	end
	local uses = 0
	bot.Action_UseAbility = function()
		uses = uses + 1
	end
	bot.Action_MoveToLocation = function() end
	local function castLines()
		local count = 0
		for _, line in ipairs(T.stub.printed) do
			if string.find(line, "shadow-realm-cast", 1, true) then
				count = count + 1
			end
		end
		return count
	end
	X.StartShadowRealm("attack", nil, "attack")
	local at = bot._dwRealm.at
	T.ok(bot._castHoldUntil ~= nil and bot._castHoldUntil > 100, "the cast hold is up while the cast is pending")
	for _, t in ipairs({ 100.03, 100.06, 100.1 }) do
		T.stub.time = t
		X.SkillsComplement()
	end
	T.eq(bot._dwRealm.at, at, "the same realm record (not restarted every think)")
	T.eq(castLines(), 1, "one cast line")
	T.eq(uses, 0, "no new order in the first 0.3s")
	T.stub.time = 100.35
	X.SkillsComplement()
	T.eq(uses, 1, "one re-send after 0.3s")
	T.eq(bot._dwRealm.orders, 2, "orders=2")
	cooldown = 15
	T.stub.time = 100.4
	X.ShadowRealmTick()
	T.near(bot._dwRealm.tookAt, 0.4, 0.001, "took at 0.4")
	T.eq(bot._castHoldUntil, nil, "the cast hold ends once it took")
	-- A cast that never takes ends as release=no-cast with what blocked it.
	cooldown = 0
	bot._dwRealm = nil
	X.StartShadowRealm("attack", nil, "attack")
	for _, t in ipairs({ 100.5, 100.85, 101.2, 101.55 }) do
		T.stub.time = t
		X.ShadowRealmTick()
	end
	T.eq(bot._dwRealm, nil, "given up")
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "release=no-cast", 1, true) ~= nil, line)
	T.ok(string.find(line, "orders=3 took=no", 1, true) ~= nil, line)
	T.ok(string.find(line, "block=", 1, true) ~= nil, line)
	T.eq(bot._castHoldUntil, nil, "no hold left")
end)

-- Game 073: 4 rule=hit realms in push / defend ended by her own attack (drop-act=4 attacked=yes).
T.test("dark willow: an escape realm holds the modes and walks her home (#203 item 1)", function()
	local bot, X, orders = realmBot()
	bot.GetActiveMode = function()
		return BOT_MODE_PUSH_TOWER_MID
	end
	bot.HasModifier = function(_, name)
		return name == "modifier_dark_willow_shadow_realm_buff"
	end
	X.StartShadowRealm("retreat", nil, "hit")
	T.ok(bot._dwEscapeHoldUntil ~= nil and bot._dwEscapeHoldUntil > 105, "outpost hold until the realm ends")
	T.ok(bot._castHoldUntil ~= nil and bot._castHoldUntil > 105, "item-think hold until the realm ends")
	T.eq(type(X.CastHoldTick), "function", "the item think's hold tick")
	T.stub.time = 101
	T.eq(X.ShadowRealmTick(), false, "a move, spells may still go out")
	T.eq(orders[#orders], "move", "move-only")
	T.stub.time = 103
	local before = #orders
	X.CastHoldTick()
	T.eq(orders[before + 1], "move", "still walking home")
	T.stub.time = 105.5
	X.ShadowRealmTick()
	T.eq(bot._dwRealm, nil, "the realm is over")
	T.eq(bot._dwEscapeHoldUntil, nil, "outpost hold cleared")
	T.eq(bot._castHoldUntil, nil, "item-think hold cleared")
	local line = T.stub.printed[#T.stub.printed] or ""
	T.ok(string.find(line, "hold=yes", 1, true) ~= nil, line)
end)

T.test("dark willow: the outpost mode takes her during an escape realm (#203 item 1)", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_dark_willow", slot = 4, time = 300 })
	local ok, err = T.stub.load("mode_outpost_generic")
	T.ok(ok, tostring(err))
	bot._dwEscapeHoldUntil = 305
	local okD, desire = pcall(GetDesire)
	T.ok(okD, "GetDesire: " .. tostring(desire))
	T.near(desire, BOT_DESIRE_OVERRIDE * 1.5, 1e-9, "the hold desire, above retreat")
	T.ok(bot._outpostHoldUntil ~= nil and bot._outpostHoldUntil > 300, "Think gives no order")
	bot._dwEscapeHoldUntil = nil
	bot._outpostHoldUntil = nil
	local okN, after = pcall(GetDesire)
	T.ok(okN and after < BOT_DESIRE_OVERRIDE * 1.5, "no hold without a realm: " .. tostring(after))
end)

T.test("shadow realm: the cornered realm (#203, game 083 47:06)", function()
	local R = load()
	local function cornered(over)
		local o = { enemiesNear = 0, alliesNear = 0, enemies = 0, ourHeroes = 1, jump = false }
		for k, v in pairs(over) do
			o[k] = v
		end
		return R.Cornered(o)
	end
	T.eq(cornered({ enemiesNear = 3, enemies = 3 }), "crowd", "47:07: 3 enemies within 900, no ally")
	T.eq(cornered({ enemiesNear = 3, enemies = 3, alliesNear = 1, ourHeroes = 2 }), nil, "an ally near: no")
	T.eq(cornered({ enemiesNear = 2, enemies = 3 }), nil, "only 2 within 900")
	T.eq(cornered({ charge = 900 }), "charge", "the charge on her, Spirit Breaker 900 away")
	T.eq(cornered({ charge = 2000 }), nil, "the charge from far: it would land after the realm")
	T.eq(cornered({ jump = true, enemies = 2 }), "jump", "a jump-in with a second enemy near")
	T.eq(cornered({ jump = true, enemies = 1 }), nil, "a lone jump-in: the hit rule decides")
	T.eq(cornered({ jump = true, enemies = 2, ourHeroes = 3 }), nil, "a jump-in into more of ours")
	-- The jump-in.
	T.eq(R.Jump(1162, 0.1, 200, 0.1), "jump", "Templar Assassin's blink from 1162")
	T.eq(R.Jump(nil, nil, 300, 0.1), "appear", "out of the fog next to her")
	T.eq(R.Jump(700, 0.1, 400, 0.1), nil, "walked 300 closer")
	T.eq(R.Jump(1300, 0.1, 600, 0.1), nil, "landed 600 away: not next to her")
	T.eq(R.Jump(nil, nil, 300, 2.0), nil, "her own think had a gap: no read")
	T.eq(R.Jump(nil, nil, 300, nil), nil, "her first sample")
	T.eq(R.Jump(1300, 1.0, 300, 0.1), "appear", "last seen 1s ago")
end)

T.test("dark willow: a cornered realm at full HP, before Bramble Maze (game 083 47:06)", function()
	local bot, X, used = castBot(BOT_MODE_DEFEND_TOWER_MID, 0.98, false)
	local maze = bot:GetAbilityByName("dark_willow_bramble_maze")
	maze.IsFullyCastable = function()
		return true
	end
	local n = 0
	for _, hero in ipairs(T.stub.heroes) do
		if hero._team ~= bot._team and n < 3 then
			n = n + 1
			hero._loc = bot._loc + Vector(300 * n - 100, 100, 0)
		end
	end
	X.SkillsComplement()
	T.eq(used[1], "dark_willow_shadow_realm", "the realm, not the maze")
	local line = printedWith("shadow-realm-cast why=retreat")
	T.ok(line ~= nil and string.find(line, "rule=cornered", 1, true) ~= nil, tostring(line))
	line = printedWith("realm-cornered trigger=crowd")
	T.ok(line ~= nil and string.find(line, "near=3 allies=0", 1, true) ~= nil, tostring(line))
	T.eq(bot._dwRealm ~= nil and bot._dwRealm.hold, true, "an escape realm: the hold walks her home")
end)

T.test("dark willow: a jump-in with a second enemy near casts the realm", function()
	local bot, X, used = castBot(BOT_MODE_PUSH_TOWER_MID, 0.9, false)
	local enemies = {}
	for _, hero in ipairs(T.stub.heroes) do
		if hero._team ~= bot._team then
			enemies[#enemies + 1] = hero
		end
	end
	enemies[1]._loc = bot._loc + Vector(800, 0, 0)
	enemies[2]._loc = bot._loc + Vector(0, 1300, 0)
	X.SkillsComplement()
	T.eq(#used, 0, "no realm: nobody jumped yet")
	T.stub.time = T.stub.time + 0.1
	enemies[2]._loc = bot._loc + Vector(0, 250, 0)
	X.SkillsComplement()
	T.eq(used[1], "dark_willow_shadow_realm", "the realm after the blink")
	local line = printedWith("realm-cornered trigger=jump")
	T.ok(line ~= nil and string.find(line, "kind=jump from=1300 to=250", 1, true) ~= nil, tostring(line))
end)
