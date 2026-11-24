-- Difficulty levels (#232): bots/lib/systems/difficulty.lua (pure profiles and decisions) and
-- bots/lib/systems/difficulty_hooks.lua (the order wrappers). Unfair must be today's play: every hook passes the call
-- through unchanged, draws no random number and writes no state.
local T = ...
local Stub = T.stub

local function load(level)
	local bot = Stub.reset({ hero = "npc_dota_hero_lion", time = 600 })
	if level ~= nil then
		function bot:GetDifficulty()
			return level
		end
	end
	local D = require(GetScriptDirectory() .. "/lib/systems/difficulty")
	return bot, D
end

local function printed(what)
	local n = 0
	for _, line in ipairs(Stub.printed) do
		if string.find(line, what, 1, true) then
			n = n + 1
		end
	end
	return n
end

-- Records the calls that reach the original method; install before global_overrides wraps it.
local function recorder(class, method)
	local calls = {}
	class[method] = function(self, ...)
		calls[#calls + 1] = { self = self, n = select("#", ...), args = { ... } }
		return "orig-" .. method
	end
	return calls
end

local function countRandom()
	local count = { n = 0 }
	local real = math.random
	math.random = function(...)
		count.n = count.n + 1
		return real(...)
	end
	return count
end

T.test("difficulty: API values map to levels, anything else to unfair (default)", function()
	local _, D = load()
	local names = { [0] = "passive", "easy", "medium", "hard", "unfair" }
	for raw = 0, 4 do
		local level, name, profile, src = D.Resolve(raw)
		T.eq(level, raw, "level " .. raw)
		T.eq(name, names[raw], "name " .. raw)
		T.ok(profile == D.PROFILES[name], "profile " .. raw)
		T.eq(src, "api", "src " .. raw)
	end
	for _, raw in ipairs({ 5, 9, -1, "4" }) do
		local level, name, _, src = D.Resolve(raw)
		T.eq(level, 4, "level for " .. tostring(raw))
		T.eq(name, "unfair", "name for " .. tostring(raw))
		T.eq(src, "default", "src for " .. tostring(raw))
	end
	local _, name, _, src = D.Resolve(nil)
	T.eq(name, "unfair", "failed call")
	T.eq(src, "default", "failed call src")
end)

T.test("difficulty: only Unfair is neutral, lower levels only take away", function()
	local _, D = load()
	T.ok(D.PROFILES.unfair.neutral, "unfair neutral")
	local order = { "passive", "easy", "medium", "hard", "unfair" }
	local rank = { off = 0, careful = 1, on = 2 }
	for i, name in ipairs(order) do
		local p = D.PROFILES[name]
		if name ~= "unfair" then
			T.ok(not p.neutral, name .. " not neutral")
		end
		local nextP = D.PROFILES[order[i + 1]]
		if nextP ~= nil then
			T.ok(p.reactionDelay >= nextP.reactionDelay, name .. " reaction")
			T.ok(p.castSkipChance >= nextP.castSkipChance, name .. " skip")
			T.ok(p.lastHitError >= nextP.lastHitError, name .. " last hit")
			T.ok(p.dodgeChance <= nextP.dodgeChance, name .. " dodge")
			for _, gate in ipairs({ "hunt", "smoke", "dive" }) do
				T.ok(rank[p[gate]] <= rank[nextP[gate]], name .. " " .. gate)
			end
		end
	end
	T.eq(D.PROFILES.passive.fightHeroes, false, "passive does not fight")
end)

T.test("difficulty: cast hold waits the reaction delay per decision, a gap starts a new one", function()
	local _, D = load()
	local easy = D.PROFILES.easy
	local never = function()
		return 0.99
	end
	local state = {}
	local ok, why = D.CastStep(state, 10, easy, never)
	T.eq(ok, false, "held at first")
	T.eq(why, "reaction", "reaction")
	T.eq(D.CastStep(state, 10.3, easy, never), false, "0.3s")
	T.eq(D.CastStep(state, 10.6, easy, never), false, "0.6s")
	T.eq(D.CastStep(state, 10.8, easy, never), true, "0.8s: goes out")
	T.eq(D.CastStep(state, 11.0, easy, never), true, "same decision stays allowed")
	T.eq(D.CastStep(state, 12.0, easy, never), false, "1s gap: a new decision, held again")
	T.eq(D.CastStep({}, 0, D.PROFILES.unfair, never), true, "unfair: at once")
end)

T.test("difficulty: a skipped decision is held, then decided again", function()
	local _, D = load()
	local easy = D.PROFILES.easy
	local rolls = { 0.1, 0.9 }
	local i = 0
	local roll = function()
		i = i + 1
		return rolls[i]
	end
	local state = {}
	local ok, why = D.CastStep(state, 0, easy, roll)
	T.eq(ok, false, "skipped")
	T.eq(why, "skip", "skip")
	T.eq(D.CastStep(state, 0.5, easy, roll), false, "still skipped at 0.5")
	T.eq(D.CastStep(state, 1.0, easy, roll), false, "still skipped at 1.0")
	T.eq(D.CastStep(state, 1.5, easy, roll), false, "still skipped at 1.5")
	ok, why = D.CastStep(state, 1.8, easy, roll)
	T.eq(ok, false, "new decision at 1.8 (0.8 + 1.0)")
	T.eq(why, "reaction", "the re-roll passed, waits the reaction delay")
	T.eq(i, 2, "two rolls")
	T.eq(D.CastStep(state, 2.2, easy, roll), false, "2.2: waiting")
	T.eq(D.CastStep(state, 2.65, easy, roll), true, "goes out")
end)

T.test("difficulty: dodge share latched per window, last-hit wait once per creep", function()
	local _, D = load()
	local medium = D.PROFILES.medium
	local latch = {}
	T.eq(
		D.DodgeStep(latch, 0, medium, function()
			return 0.7
		end),
		false,
		"0.7 >= 0.5: no dodge"
	)
	T.eq(
		D.DodgeStep(latch, 1, medium, function()
			return 0.1
		end),
		false,
		"latched for the window"
	)
	T.eq(
		D.DodgeStep(latch, 2.1, medium, function()
			return 0.1
		end),
		true,
		"new window, new roll"
	)
	T.eq(D.DodgeStep({}, 0, D.PROFILES.easy, nil), false, "easy never")
	T.eq(D.DodgeStep({}, 0, D.PROFILES.hard, nil), true, "hard always")
	local state = {}
	local half = function()
		return 0.5
	end
	T.eq(D.LastHitStep(state, 0, D.PROFILES.easy, half, "creepA"), false, "waits 0.125")
	T.eq(D.LastHitStep(state, 0.1, D.PROFILES.easy, half, "creepA"), false, "0.1")
	T.eq(D.LastHitStep(state, 0.13, D.PROFILES.easy, half, "creepA"), true, "0.13")
	T.eq(D.LastHitStep(state, 0.13, D.PROFILES.easy, half, "creepB"), false, "a new creep waits again")
	T.eq(D.LastHitStep({}, 0, D.PROFILES.hard, nil, "c"), true, "hard: no error")
end)

T.test("difficulty: gank / help / smoke / dive gates", function()
	local _, D = load()
	local P = D.PROFILES
	T.eq(D.RoamFightKind("hunt-carry/hero"), "gank", "carry hunt")
	T.eq(D.RoamFightKind("hunt-support/hero"), "gank", "support hunt")
	T.eq(D.RoamFightKind("hunt-carry/lane"), nil, "creep hunt")
	T.eq(D.RoamFightKind("help-ally"), "help", "help")
	T.eq(D.RoamAllowed(P.easy, "gank", 1, 3, 1), false, "easy: no ganks")
	T.eq(D.RoamAllowed(P.easy, "help", 1, 1, 3), true, "easy: helps an ally")
	T.eq(D.RoamAllowed(P.passive, "help", 1, 3, 1), false, "passive: no help fights")
	T.eq(D.RoamAllowed(P.medium, "gank", 1, 2, 2), false, "medium: even numbers, healthy target")
	T.eq(D.RoamAllowed(P.medium, "gank", 1, 3, 2), true, "medium: more allies")
	T.eq(D.RoamAllowed(P.medium, "gank", 0.3, 1, 1), true, "medium: low target")
	T.eq(D.RoamAllowed(P.hard, "gank", 1, 1, 3), true, "hard: today's rule")
	T.eq(D.RoamAllowed(P.passive, nil, 1, 1, 1), true, "not a fight")
	T.eq(D.SmokeAllowed(P.easy, 5), false, "easy smoke")
	T.eq(D.SmokeAllowed(P.medium, 2), false, "medium smoke with 2")
	T.eq(D.SmokeAllowed(P.medium, 3), true, "medium smoke with 3")
	local dive = { underTower = true, chasingHero = true, pushing = false, towerOnUs = false, targetHp = 0.6 }
	T.eq(D.DiveRetreat(P.easy, dive), D.DIVE_RETREAT_DESIRE, "easy: out of the tower")
	T.eq(D.DiveRetreat(P.medium, dive), 0, "medium: tower not on us")
	dive.towerOnUs = true
	T.eq(D.DiveRetreat(P.medium, dive), D.DIVE_RETREAT_DESIRE, "medium: tower on us")
	dive.targetHp = 0.1
	T.eq(D.DiveRetreat(P.medium, dive), 0, "medium: target nearly dead")
	T.eq(D.DiveRetreat(P.unfair, dive), 0, "unfair: today's rules")
	dive.pushing = true
	T.eq(D.DiveRetreat(P.easy, dive), 0, "pushing the tower")
	T.ok(D.IsExemptAbility("ancient_apparition_ice_blast_release"), "release exempt")
	T.ok(D.IsExemptAbility("alchemist_unstable_concoction_throw"), "throw exempt")
	T.ok(not D.IsExemptAbility("lion_impale"), "a nuke is not")
end)

T.test("difficulty hooks: Unfair passes every order through unchanged, no roll, no state", function()
	local bot = load(4)
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnEntity")
	local noTargetCalls = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	local attackCalls = recorder(CDOTA_Bot_Script, "Action_AttackUnit")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local count = countRandom()
	local ability = bot:GetAbilityInSlot(0)
	local enemy = Stub.teams[TEAM_DIRE][1]
	local creep = Stub.newUnit({ name = "npc_dota_creep_badguys_melee", hp = 20 })
	bot._lhTiming = { creep = creep }
	T.eq(bot:Action_UseAbilityOnEntity(ability, enemy), "orig-Action_UseAbilityOnEntity", "cast return")
	T.eq(bot:Action_UseAbility(ability), "orig-Action_UseAbility", "no-target return")
	T.eq(bot:Action_AttackUnit(creep, true), "orig-Action_AttackUnit", "attack return")
	T.eq(bot:Action_AttackUnit(enemy, false), "orig-Action_AttackUnit", "hero attack return")
	T.eq(#castCalls, 1, "cast reached once")
	T.ok(castCalls[1].self == bot and castCalls[1].args[1] == ability and castCalls[1].args[2] == enemy, "cast args")
	T.eq(castCalls[1].n, 2, "cast arg count")
	T.eq(#noTargetCalls, 1, "no-target reached once")
	T.eq(noTargetCalls[1].n, 1, "no-target arg count")
	T.eq(#attackCalls, 2, "attacks reached")
	T.ok(attackCalls[1].args[1] == creep and attackCalls[1].args[2] == true, "attack args")
	T.eq(count.n, 0, "no random number drawn")
	T.eq(bot._ohaDiffCast, nil, "no cast state")
	T.eq(bot._ohaDiffLh, nil, "no last-hit state")
	T.eq(printed("held kind="), 0, "no held line")
	T.eq(printed("[SHy-DIFF] t=600 lion team=2 difficulty=4 name=unfair src=api raw=4"), 1, "start line once")
	local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	local desire, why = H.GateRoam(bot, 0.8, "hunt-carry/hero", enemy, 1, 3)
	T.eq(desire, 0.8, "roam desire unchanged")
	T.eq(why, "hunt-carry/hero", "roam why unchanged")
	T.eq(H.DiveRetreat(bot, enemy), 0, "no dive opinion")
	local smokeArgs = nil
	local smoke = H.WrapSmoke(bot, function(...)
		smokeArgs = select("#", ...)
		return 0.7, "t", "none", "r"
	end)
	local d, t, c, r = smoke("item")
	T.ok(d == 0.7 and t == "t" and c == "none" and r == "r" and smokeArgs == 1, "smoke rule passes through")
	T.eq(H.FightsHeroes(bot), true, "fights heroes")
	T.eq(count.n, 0, "still no random number")
end)

T.test("difficulty hooks: Unfair - all 15 wrapped order methods are transparent", function()
	local bot = load(4)
	local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	local methods = {}
	for _, kind in ipairs({ "", "OnLocation", "OnEntity", "OnTree" }) do
		for _, prefix in ipairs({ "Action_", "ActionPush_", "ActionQueue_" }) do
			methods[#methods + 1] = prefix .. "UseAbility" .. kind
		end
	end
	for _, prefix in ipairs({ "Action_", "ActionPush_", "ActionQueue_" }) do
		methods[#methods + 1] = prefix .. "AttackUnit"
	end
	T.eq(#methods, 15, "15 methods")
	local class, calls = {}, {}
	for _, method in ipairs(methods) do
		calls[method] = recorder(class, method)
	end
	H.InstallUnitHooks(class)
	local count = countRandom()
	local ability = bot:GetAbilityInSlot(0)
	local enemy = Stub.teams[TEAM_DIRE][1]
	bot._lhTiming = { creep = enemy }
	for _, method in ipairs(methods) do
		local r1, r2 = class[method](bot, ability, enemy, nil, "extra")
		T.eq(r1, "orig-" .. method, method .. " return")
		T.eq(r2, nil, method .. " one return value")
		local got = calls[method]
		T.eq(#got, 1, method .. " reached once")
		T.ok(got[1].self == bot, method .. " self")
		T.eq(got[1].n, 4, method .. " arg count (trailing nil kept)")
		T.ok(got[1].args[1] == ability and got[1].args[2] == enemy, method .. " args")
		T.ok(got[1].args[3] == nil and got[1].args[4] == "extra", method .. " extra args")
	end
	T.eq(count.n, 0, "no random number drawn")
	T.eq(bot._ohaDiffCast, nil, "no cast state")
	T.eq(printed("held kind="), 0, "no held line")
end)

T.test("difficulty hooks: a dodge item chosen this frame is not held (its window is shorter than the hold)", function()
	local bot = load(2)
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	math.random = function()
		return 0.9
	end
	local bkb = Stub.newAbility("item_black_king_bar", bot, false)
	bot._dodgeChosen = { t = 600, target = bot }
	bot:Action_UseAbility(bkb)
	T.eq(#castCalls, 1, "medium: the dodge goes out on the first call")
	bot._dodgeChosen = { t = 599, target = bot }
	Stub.time = 610
	bot:Action_UseAbility(bkb)
	T.eq(#castCalls, 2, "not chosen this frame: still at once (a no-target item is never held)")
	T.eq(printed("held kind=reaction"), 0, "no held line")
end)

T.test("difficulty hooks: items go out at once unless aimed at an enemy hero", function()
	local bot = load(1)
	local entityCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnEntity")
	local locationCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnLocation")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	math.random = function()
		return 0.9
	end
	-- One-shot orders (game 077: an eat after a swap): sent on the first call, even on Easy.
	local toadstool = Stub.newAbility("item_foragers_health", bot, false)
	bot:Action_UseAbilityOnEntity(toadstool, bot)
	T.eq(#entityCalls, 1, "a mushroom on self goes out at once")
	local tp = Stub.newAbility("item_tpscroll", bot, false)
	bot:Action_UseAbilityOnLocation(tp, Vector(5000, 5000, 0))
	T.eq(#locationCalls, 1, "a TP far from enemy heroes goes out at once")
	-- An item on an enemy hero keeps the reaction hold.
	local hex = Stub.newAbility("item_sheepstick", bot, false)
	local enemy = Stub.teams[TEAM_DIRE][1]
	bot:Action_UseAbilityOnEntity(hex, enemy)
	T.eq(#entityCalls, 1, "Hex on an enemy hero is held")
	T.eq(printed("held kind=reaction level=easy ability=item_sheepstick"), 1, "held line")
end)

T.test("difficulty hooks: Unfair projectile checks return exactly what they returned", function()
	load(4)
	local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	local fakeFu = {
		IsStunProjectileIncoming = function(unit, range)
			return range > 500, "extra"
		end,
		FindLinearProjectileIncoming = function()
			return { name = "mirana_arrow" }
		end,
	}
	local linear = fakeFu.FindLinearProjectileIncoming
	H.InstallFu(fakeFu)
	local a, b = fakeFu.IsStunProjectileIncoming(GetBot(), 1000)
	T.ok(a == true and b == "extra", "both values")
	T.eq(fakeFu.IsStunProjectileIncoming(GetBot(), 100), false, "false stays false")
	T.ok(
		fakeFu.FindLinearProjectileIncoming ~= linear and fakeFu.FindLinearProjectileIncoming().name == "mirana_arrow",
		"threat"
	)
end)

T.test("difficulty hooks: Easy holds a cast for the reaction delay and logs it", function()
	local bot = load(1)
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnEntity")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local ability = bot:GetAbilityInSlot(0)
	local enemy = Stub.teams[TEAM_DIRE][1]
	-- Stub's first random numbers are above 0.35 (no skip): 16807 / (2^31 - 1) is tiny, so force one above.
	math.random = function()
		return 0.9
	end
	T.eq(bot:Action_UseAbilityOnEntity(ability, enemy), nil, "held")
	T.eq(#castCalls, 0, "not sent")
	T.eq(printed("held kind=reaction level=easy ability=lion_ability_1"), 1, "held line")
	Stub.time = 600.4
	bot:Action_UseAbilityOnEntity(ability, enemy)
	T.eq(#castCalls, 0, "0.4s: still held")
	Stub.time = 600.85
	bot:Action_UseAbilityOnEntity(ability, enemy)
	T.eq(#castCalls, 1, "0.8s: sent")
	T.eq(printed("held kind=reaction"), 1, "throttled")
	local release = Stub.newAbility("ancient_apparition_ice_blast_release", bot, false)
	bot:Action_UseAbility(release)
	T.eq(printed("ice_blast_release"), 0, "a release is never held")
end)

T.test("difficulty hooks: Easy last hit goes out late, Passive never hits or targets a hero", function()
	local bot = load(1)
	local attackCalls = recorder(CDOTA_Bot_Script, "Action_AttackUnit")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	math.random = function()
		return 0.8
	end
	local creep = Stub.newUnit({ name = "npc_dota_creep_badguys_melee", hp = 20 })
	bot._lhTiming = { creep = creep }
	bot:Action_AttackUnit(creep, true)
	T.eq(#attackCalls, 0, "held 0.2s")
	T.eq(printed("held kind=lasthit level=easy late=0.20"), 1, "lasthit line")
	Stub.time = 600.1
	H.LastHitRetry(bot)
	T.eq(#attackCalls, 0, "0.1s: waiting")
	Stub.time = 600.21
	H.LastHitRetry(bot)
	T.eq(#attackCalls, 1, "sent on the frame the wait ends")
	T.ok(attackCalls[1].args[1] == creep and attackCalls[1].args[2] == true, "same order")
	local other = Stub.newUnit({ name = "npc_dota_creep_badguys_ranged", hp = 300 })
	bot:Action_AttackUnit(other, false)
	T.eq(#attackCalls, 2, "an attack that is not a timed last hit goes out")

	bot = load(0)
	attackCalls = recorder(CDOTA_Bot_Script, "Action_AttackUnit")
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnEntity")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	local enemy = Stub.teams[TEAM_DIRE][1]
	bot:Action_AttackUnit(enemy, false)
	T.eq(#attackCalls, 0, "no hero attack")
	T.eq(printed("held kind=gate level=passive what=hero-attack"), 1, "gate line")
	local ally = Stub.teams[TEAM_RADIANT][2]
	math.random = function()
		return 0.9
	end
	bot:Action_UseAbilityOnEntity(bot:GetAbilityInSlot(1), enemy)
	T.eq(printed("what=hero-cast"), 1, "no spell on a hero")
	Stub.time = 602
	bot:Action_UseAbilityOnEntity(bot:GetAbilityInSlot(1), ally)
	Stub.time = 602.5
	bot:Action_UseAbilityOnEntity(bot:GetAbilityInSlot(1), ally)
	Stub.time = 602.9
	bot:Action_UseAbilityOnEntity(bot:GetAbilityInSlot(1), ally)
	T.eq(#castCalls, 1, "a spell on an ally goes out (after the delay)")
	T.eq(H.FightsHeroes(bot), false, "no attack mode")
	local desire, why = H.GateRoam(bot, 0.6, "help-ally", ally, 3, 1)
	T.eq(desire, 0, "no help fight")
	T.eq(why, "diff-help-ally", "why")
end)
