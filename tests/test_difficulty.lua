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

-- math.random returns `values` in order (the last one repeats); count.n counts the draws.
local function scriptedRandom(values)
	local count = { n = 0 }
	math.random = function()
		count.n = count.n + 1
		return values[math.min(count.n, #values)]
	end
	return count
end

local function counter(values)
	local count = { n = 0 }
	return function()
		count.n = count.n + 1
		return values[math.min(count.n, #values)]
	end, count
end

T.test("difficulty: API values map to levels (NPX 9 = newplayer), anything else to unfair (default)", function()
	local _, D = load()
	local names = { [0] = "passive", "easy", "medium", "hard", "unfair" }
	for raw = 0, 4 do
		local level, name, profile, src = D.Resolve(raw)
		T.eq(level, raw, "level " .. raw)
		T.eq(name, names[raw], "name " .. raw)
		T.ok(profile == D.PROFILES[name], "profile " .. raw)
		T.eq(src, "api", "src " .. raw)
	end
	local npxLevel, npxName, npxProfile, npxSrc = D.Resolve(9)
	T.eq(npxLevel, 9, "level 9")
	T.eq(npxName, "newplayer", "name 9 (NPX, the lobby's New Player)")
	T.ok(npxProfile == D.PROFILES.newplayer and npxProfile.fightHeroes == true, "profile 9")
	T.eq(npxSrc, "api", "src 9")
	for _, raw in ipairs({ 5, 10, -1, "4" }) do
		local level, name, _, src = D.Resolve(raw)
		T.eq(level, 4, "level for " .. tostring(raw))
		T.eq(name, "unfair", "name for " .. tostring(raw))
		T.eq(src, "default", "src for " .. tostring(raw))
	end
	local _, name, _, src = D.Resolve(nil)
	T.eq(name, "unfair", "failed call")
	T.eq(src, "default", "failed call src")
end)

T.test("difficulty: only Unfair is neutral, lower levels only take away, the chances per level", function()
	local _, D = load()
	T.ok(D.PROFILES.unfair.neutral, "unfair neutral")
	local order = { "newplayer", "passive", "easy", "medium", "hard", "unfair" }
	-- Maintainer, 2026-11-27: reactive (escape, dodge, save, interrupt) and other casts, success chance per level.
	local reactive = { newplayer = 0.15, passive = 0.25, easy = 0.25, medium = 0.5, hard = 0.85, unfair = 1 }
	local other = { newplayer = 0.55, passive = 0.65, easy = 0.65, medium = 0.85, hard = 0.95, unfair = 1 }
	local rank = { off = 0, careful = 1, on = 2 }
	for i, name in ipairs(order) do
		local p = D.PROFILES[name]
		T.eq(p.reactiveChance, reactive[name], name .. " reactive chance")
		T.eq(p.castChance, other[name], name .. " cast chance")
		T.eq(p.reactionDelay, nil, name .. ": no reaction delay")
		if name ~= "unfair" then
			T.ok(not p.neutral, name .. " not neutral")
		end
		local nextP = D.PROFILES[order[i + 1]]
		if nextP ~= nil then
			T.ok(p.reactiveChance <= nextP.reactiveChance, name .. " reactive")
			T.ok(p.castChance <= nextP.castChance, name .. " cast")
			T.ok(p.lastHitError >= nextP.lastHitError, name .. " last hit")
			for _, gate in ipairs({ "hunt", "smoke", "dive" }) do
				T.ok(rank[p[gate]] <= rank[nextP[gate]], name .. " " .. gate)
			end
		end
	end
	T.eq(D.PROFILES.passive.fightHeroes, false, "passive does not fight")
end)

T.test("difficulty: a per-frame caller does not re-roll its cast decision", function()
	local _, D = load()
	local frame = 1 / 30
	for _, name in ipairs({ "hard", "medium", "easy", "newplayer" }) do
		local profile = D.PROFILES[name]
		local roll, count = counter({ 0.5 })
		local state = {}
		local sent = 0
		for i = 0, 89 do
			if D.CastStep(state, 50 + i * frame, profile, roll) then
				sent = sent + 1
			end
		end
		T.eq(count.n, 1, name .. ": one roll for 3s of orders")
		T.eq(sent, 90, name .. ": every order goes out from the first frame (no delay)")
		-- A pause over DECISION_GAP ends the decision: the next order is a new decision, a new roll.
		local _, rolled = D.CastStep(state, 50 + 89 * frame + D.DECISION_GAP + 0.05, profile, roll)
		T.eq(rolled, true, name .. ": new decision after a pause")
		T.eq(count.n, 2, name .. ": second roll")
	end
	local unfairRoll, unfairCount = counter({ 0.99 })
	T.eq(D.CastStep({}, 0, D.PROFILES.unfair, unfairRoll), true, "unfair: at once")
	T.eq(unfairCount.n, 0, "unfair: no roll")
end)

T.test("difficulty: a failed cast decision is held SKIP_HOLD, then rolled again", function()
	local _, D = load()
	local easy = D.PROFILES.easy
	local frame = 1 / 30
	-- Every frame: 0.9 >= 0.65 fails; held until SKIP_HOLD after the roll; the re-roll (0.1) passes.
	local roll, count = counter({ 0.9, 0.1 })
	local state = {}
	local firstAt = nil
	for i = 0, 45 do
		local now = i * frame
		if D.CastStep(state, now, easy, roll) and firstAt == nil then
			firstAt = now
		end
	end
	T.eq(count.n, 2, "two rolls")
	T.ok(firstAt ~= nil and firstAt >= D.SKIP_HOLD - 1e-9, "not before SKIP_HOLD " .. tostring(firstAt))
	T.ok(firstAt < D.SKIP_HOLD + frame + 1e-9, "on the first frame after it")
	-- One order a second (Largo's song toggle): the failed decision is held, the order 1s later rolls again.
	roll, count = counter({ 0.9, 0.1 })
	state = {}
	T.eq(D.CastStep(state, 100, easy, roll), false, "100: failed")
	T.eq(D.CastStep(state, 100.5, easy, roll), false, "100.5: still held, no re-roll")
	T.eq(count.n, 1, "one roll so far")
	T.eq(D.CastStep(state, 101, easy, roll), true, "101: rolled again, goes out")
	T.eq(count.n, 2, "two rolls")
	-- A slow caller (every 0.7s) does not re-roll a failed decision on each order.
	roll, count = counter({ 0.9 })
	state = {}
	D.CastStep(state, 200, easy, roll)
	D.CastStep(state, 200.7, easy, roll)
	T.eq(count.n, 1, "0.7s later: same failed decision")
	D.CastStep(state, 201.4, easy, roll)
	T.eq(count.n, 2, "1.4s: past SKIP_HOLD, a new roll")
end)

T.test("difficulty: one reactive roll covers every reactive spell of the episode", function()
	local _, D = load()
	local hard = D.PROFILES.hard
	local roll, count = counter({ 0.5 })
	local rs = {}
	local okOrb, episode, rolled = D.ReactiveStep(rs, 10, hard, roll, "puck_illusory_orb")
	T.eq(okOrb, true, "0.5 < 0.85: allowed")
	T.eq(rolled, true, "rolled")
	T.eq(episode.id, 1, "episode 1")
	local okRift, episodeRift, rolledRift = D.ReactiveStep(rs, 10, hard, roll, "puck_waning_rift")
	local okPhase = D.ReactiveStep(rs, 10.5, hard, roll, "puck_phase_shift")
	T.ok(okRift and okPhase, "the other spells share it")
	T.ok(episodeRift == episode and not rolledRift, "same episode, no roll")
	T.eq(count.n, 1, "one roll, not three")
end)

T.test("difficulty: a failed reactive roll stays failed until the episode ends, then rolls again", function()
	local _, D = load()
	local hard = D.PROFILES.hard
	local roll, count = counter({ 0.9, 0.2 })
	local rs = {}
	local danger = { alive = true, danger = true, hit = false }
	local safe = { alive = true, danger = false, hit = false }
	T.eq(D.ReactiveStep(rs, 0, hard, roll, "puck_illusory_orb"), false, "0.9 >= 0.85: failed")
	for t = 0.5, 1.5, 0.5 do
		T.eq(D.EpisodeTick(rs, t, danger), nil, "in danger at " .. t)
		T.eq(D.ReactiveStep(rs, t, hard, roll, "puck_waning_rift"), false, "still failed at " .. t)
		D.ReactiveStep(rs, t, hard, roll, "puck_phase_shift")
	end
	T.eq(count.n, 1, "no re-roll in the episode (re-rolling each second would make 0.85 about 0.98)")
	T.eq(rs.episode.fails, 3, "fails: three spells refused, each counted once")
	-- Out of retreat after 1.5; hero damage in the last 2s keeps it open.
	T.eq(D.EpisodeTick(rs, 3.4, safe), nil, "1.9s out of danger: open")
	T.eq(D.EpisodeTick(rs, 3.6, { alive = true, danger = false, hit = true }), nil, "hit within 2s: open")
	local why, ended = D.EpisodeTick(rs, 3.7, safe)
	T.eq(why, "safe", "2s out of danger: ends")
	T.eq(ended.fails, 3, "ended episode keeps its fails")
	T.eq(rs.episode, nil, "no episode")
	local ok, episode, rolled = D.ReactiveStep(rs, 6, hard, roll, "puck_phase_shift")
	T.eq(ok, true, "the next danger rolls again (0.2: allowed)")
	T.ok(rolled and episode.id == 2, "episode 2")
	T.eq(count.n, 2, "second roll")
end)

T.test(
	"difficulty: a reactive episode ends after EPISODE_CAP, at death, and lasts EPISODE_SAFE out of danger",
	function()
		local _, D = load()
		local medium = D.PROFILES.medium
		local roll = counter({ 0.9 })
		local danger = { alive = true, danger = true, hit = true }
		local rs = {}
		D.ReactiveStep(rs, 100, medium, roll, "x")
		T.eq(D.EpisodeTick(rs, 104.9, danger), nil, "4.9s in danger: open")
		T.eq(D.EpisodeTick(rs, 105, danger), "cap", "5s: cap")
		D.ReactiveStep(rs, 200, medium, roll, "x")
		T.eq(D.EpisodeTick(rs, 200.5, { alive = false, danger = false, hit = true }), "dead", "dead")
		-- A dodge or a save starts out of danger: it still lasts EPISODE_SAFE, not one frame.
		D.ReactiveStep(rs, 300, medium, roll, "x")
		local safe = { alive = true, danger = false, hit = false }
		T.eq(D.EpisodeTick(rs, 300 + 1 / 30, safe), nil, "next frame: open")
		T.eq(D.EpisodeTick(rs, 301.9, safe), nil, "1.9s: open")
		T.eq(D.EpisodeTick(rs, 302, safe), "safe", "2s: safe")
		-- Profiles at 0 and 1 draw nothing.
		local never, neverCount = counter({ 0 })
		T.eq(D.ReactiveStep({}, 0, { reactiveChance = 0 }, never, "x"), false, "chance 0: refused")
		T.eq(D.ReactiveStep({}, 0, { reactiveChance = 1 }, never, "x"), true, "chance 1: allowed")
		T.eq(neverCount.n, 0, "no roll at 0 or 1")
	end
)

T.test("difficulty: last-hit wait once per creep", function()
	local _, D = load()
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
	-- Retreat mode, a dodge check, a save on an ally, the per-frame tick: no roll, no state, no line.
	function bot:GetActiveMode()
		return BOT_MODE_RETREAT
	end
	H.Tick(bot)
	T.eq(H.DodgeAllowed(bot, "IsStunProjectileIncoming"), true, "dodge allowed")
	local ally = Stub.teams[TEAM_RADIANT][2]
	T.eq(bot:Action_UseAbilityOnEntity(ability, ally), "orig-Action_UseAbilityOnEntity", "save return")
	T.eq(#castCalls, 2, "save reached")
	T.eq(count.n, 0, "still no random number")
	T.eq(bot._ohaDiffReact, nil, "no episode state")
	T.eq(bot._ohaDiffRiskyAt, nil, "no retreat stamp")
	T.eq(bot._ohaDiffDodgeAt, nil, "no dodge stamp")
	T.eq(bot._ohaDiffRoll, nil, "no frame roll")
	T.eq(printed("roll kind="), 0, "no roll line")
	T.eq(printed("episode-end"), 0, "no episode line")
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

T.test("difficulty hooks: a dodge item chosen this frame goes out at once", function()
	local bot = load(2)
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local count = scriptedRandom({ 0.9 })
	local bkb = Stub.newAbility("item_black_king_bar", bot, false)
	bot._dodgeChosen = { t = 600, target = bot }
	bot:Action_UseAbility(bkb)
	T.eq(#castCalls, 1, "medium: the dodge goes out on the first call")
	bot._dodgeChosen = { t = 599, target = bot }
	Stub.time = 610
	bot:Action_UseAbility(bkb)
	T.eq(#castCalls, 2, "not chosen this frame: still at once (a no-target item is never rolled)")
	T.eq(count.n, 0, "no roll")
	T.eq(printed("roll kind="), 0, "no roll line")
end)

T.test("difficulty hooks: items go out at once unless aimed at an enemy hero, then they are rolled", function()
	local bot = load(1)
	local entityCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnEntity")
	local locationCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnLocation")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local count = scriptedRandom({ 0.9, 0.1 })
	-- One-shot orders (game 077: an eat after a swap): sent on the first call, even on Easy.
	local toadstool = Stub.newAbility("item_foragers_health", bot, false)
	bot:Action_UseAbilityOnEntity(toadstool, bot)
	T.eq(#entityCalls, 1, "a mushroom on self goes out at once")
	local tp = Stub.newAbility("item_tpscroll", bot, false)
	bot:Action_UseAbilityOnLocation(tp, Vector(5000, 5000, 0))
	T.eq(#locationCalls, 1, "a TP far from enemy heroes goes out at once")
	T.eq(count.n, 0, "items not on an enemy hero: no roll")
	-- An item on an enemy hero takes Easy's cast roll (0.65): 0.9 fails, held SKIP_HOLD, 0.1 passes.
	local hex = Stub.newAbility("item_sheepstick", bot, false)
	local enemy = Stub.teams[TEAM_DIRE][1]
	bot:Action_UseAbilityOnEntity(hex, enemy)
	T.eq(#entityCalls, 1, "Hex on an enemy hero: the roll failed")
	T.eq(printed("roll kind=cast result=fail p=0.65 ability=item_sheepstick episode=- level=easy n=1"), 1, "roll line")
	T.eq(printed("held kind=skip level=easy ability=item_sheepstick"), 1, "skip line")
	Stub.time = 600.5
	bot:Action_UseAbilityOnEntity(hex, enemy)
	T.eq(#entityCalls, 1, "0.5s: still held, no new roll")
	T.eq(count.n, 1, "one roll")
	Stub.time = 601
	bot:Action_UseAbilityOnEntity(hex, enemy)
	T.eq(#entityCalls, 2, "1s: rolled again, sent")
	T.eq(printed("held kind=reaction"), 0, "no reaction hold any more")
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

-- Game 087 8:32 (Hard): Puck switched between Orb, Rift and Phase Shift every think in retreat; the per-ability
-- reaction hold sent none of them and she died. Now one roll per danger episode covers all three.
T.test("difficulty hooks: Hard retreat - Orb, Rift and Phase Shift share one reactive roll per episode", function()
	local bot = load(3)
	local noTarget = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	local onLocation = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnLocation")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	local mode = BOT_MODE_RETREAT
	function bot:GetActiveMode()
		return mode
	end
	local count = scriptedRandom({ 0.9, 0.5 })
	local orb = Stub.newAbility("puck_illusory_orb", bot, false)
	local rift = Stub.newAbility("puck_waning_rift", bot, false)
	local phase = Stub.newAbility("puck_phase_shift", bot, false)
	local away = Vector(-5000, -5000, 0)
	local frame = 1 / 30
	-- Episode 1: 0.9 >= 0.85 fails; every order of every reactive spell is refused for the episode, no re-roll.
	for i = 0, 29 do
		Stub.time = 600 + i * frame
		H.Tick(bot)
		bot:Action_UseAbilityOnLocation(orb, away)
		bot:Action_UseAbilityOnLocation(rift, away)
		bot:Action_UseAbility(phase)
	end
	T.eq(count.n, 1, "one roll for three spells over 1s")
	T.eq(#noTarget + #onLocation, 0, "a failed episode sends none of them")
	T.eq(
		printed("roll kind=reactive result=fail p=0.85 ability=puck_illusory_orb episode=1 level=hard"),
		1,
		"roll line"
	)
	T.eq(printed("roll kind="), 1, "one roll line")
	T.eq(printed("held kind=reaction"), 0, "no reaction hold")
	-- Out of retreat at 601: the episode ends 2s later (why=safe), not before.
	mode = BOT_MODE_NONE
	local endedAt = nil
	for i = 0, 90 do
		Stub.time = 601 + i * frame
		H.Tick(bot)
		if endedAt == nil and printed("episode-end") > 0 then
			endedAt = Stub.time
		end
	end
	T.ok(endedAt ~= nil and endedAt >= 602.9 and endedAt <= 603.1, "ends 2s after the danger " .. tostring(endedAt))
	T.eq(printed("episode-end why=safe fails=3 episode=1 result=fail"), 1, "episode-end line")
	-- Episode 2: the next danger rolls again (0.5 passes); every reactive spell goes out on its first order.
	mode = BOT_MODE_RETREAT
	Stub.time = 610
	H.Tick(bot)
	bot:Action_UseAbility(phase)
	T.eq(#noTarget, 1, "Phase Shift goes out on the frame it is decided")
	bot:Action_UseAbilityOnLocation(orb, away)
	T.eq(#onLocation, 1, "the Orb in the same episode too")
	T.eq(count.n, 2, "second roll")
	T.eq(printed("roll kind=reactive result=ok p=0.85 ability=puck_phase_shift episode=2"), 1, "second roll line")
end)

-- Puck orders her escape shift from the outpost mode's cast hold, up to 0.4s after retreat mode (game 087
-- [SHy-PUCK] phase cast ... from-mode=4 mode=26).
T.test(
	"difficulty hooks: reactive = retreat or evasive (or just left), a dodge this frame, an ally, a channeller",
	function()
		local bot = load(2)
		local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
		local mode = BOT_MODE_EVASIVE_MANEUVERS
		function bot:GetActiveMode()
			return mode
		end
		local enemy = Stub.teams[TEAM_DIRE][1]
		local ally = Stub.teams[TEAM_RADIANT][2]
		T.eq(H.IsReactive(bot, "none", nil, 600), true, "evasive maneuvers")
		H.Tick(bot)
		mode = 26
		T.eq(H.IsReactive(bot, "none", nil, 600.4), true, "0.4s after retreat / evasive: still reactive")
		T.eq(H.IsReactive(bot, "none", nil, 601.1), false, "1.1s after: not")
		T.eq(H.IsReactive(bot, "entity", enemy, 601.1), false, "a nuke on an enemy hero: not")
		T.eq(H.IsReactive(bot, "entity", ally, 601.1), true, "a spell on an allied hero: a save")
		T.eq(H.IsReactive(bot, "entity", bot, 601.1), true, "on the bot itself: a save")
		function enemy:IsChanneling()
			return true
		end
		T.eq(H.IsReactive(bot, "entity", enemy, 601.1), true, "a channelling enemy hero: an interrupt")
		Stub.time = 602
		scriptedRandom({ 0.2 })
		T.eq(H.DodgeAllowed(bot, "IsStunProjectileIncoming"), true, "a dodge check: 0.2 < 0.5")
		T.eq(H.IsReactive(bot, "none", nil, 602), true, "a cast on the frame of a dodge check")
		T.eq(H.IsReactive(bot, "none", nil, 602 + 1 / 30), false, "not on the next frame")
	end
)

T.test("difficulty hooks: a dodge check and the dodge spell after it share the episode roll", function()
	local bot = load(3)
	local noTarget = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local H = require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks")
	local count = scriptedRandom({ 0.9, 0.1 })
	local phase = Stub.newAbility("puck_phase_shift", bot, false)
	local frame = 1 / 30
	-- Stifling Dagger seen for 1s (a check every frame): one roll, refused, and the shift on that frame too.
	for i = 0, 29 do
		Stub.time = 600 + i * frame
		H.Tick(bot)
		T.eq(H.DodgeAllowed(bot, "IsUnitTargetProjectileIncoming"), false, "refused at frame " .. i)
		bot:Action_UseAbility(phase)
	end
	T.eq(count.n, 1, "one roll")
	T.eq(#noTarget, 0, "no shift")
	T.eq(printed("roll kind=reactive result=fail p=0.85 ability=dodge:IsUnitTargetProjectileIncoming"), 1, "roll")
	T.eq(printed("held kind=dodge-off"), 1, "dodge-off line (throttled)")
	-- The threats keep the episode open: it ends 2s after the last one.
	local endedAt = nil
	for i = 0, 90 do
		Stub.time = 601 + i * frame
		H.Tick(bot)
		if endedAt == nil and printed("episode-end") > 0 then
			endedAt = Stub.time
		end
	end
	T.ok(
		endedAt ~= nil and endedAt >= 602.9 and endedAt <= 603.1,
		"ends 2s after the last threat " .. tostring(endedAt)
	)
	T.eq(printed("episode-end why=safe fails=2 episode=1 result=fail"), 1, "the check and the shift refused")
	Stub.time = 605
	T.eq(H.DodgeAllowed(bot, "IsUnitTargetProjectileIncoming"), true, "a new threat: a new roll (0.1)")
	bot:Action_UseAbility(phase)
	T.eq(#noTarget, 1, "the shift goes out on the same frame")
	T.eq(count.n, 2, "two rolls")
end)

T.test("difficulty hooks: a per-frame cast keeps one roll, and goes out on its first frame", function()
	local bot = load(2)
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbilityOnEntity")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	local count = scriptedRandom({ 0.5 })
	local ability = bot:GetAbilityInSlot(0)
	local enemy = Stub.teams[TEAM_DIRE][1]
	for i = 0, 29 do
		Stub.time = 600 + i / 30
		bot:Action_UseAbilityOnEntity(ability, enemy)
	end
	T.eq(#castCalls, 30, "sent on every frame, from the first")
	T.eq(count.n, 1, "one roll for the decision")
	T.eq(printed("roll kind=cast result=ok p=0.85 ability=lion_ability_1 episode=- level=medium n=1"), 1, "roll line")
	local release = Stub.newAbility("ancient_apparition_ice_blast_release", bot, false)
	bot:Action_UseAbility(release)
	T.eq(printed("ice_blast_release"), 0, "a release is never rolled")
	T.eq(count.n, 1, "still one roll")
end)

-- Game 080 (Hard): Largo ordered Amphibian Rhapsody once a second and the reaction hold never let it out.
T.test("difficulty hooks: Largo's once-a-second song toggle goes out (no hold left to break it)", function()
	local bot = load(3)
	local castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	scriptedRandom({ 0.9 })
	local song = Stub.newAbility("largo_amphibian_rhapsody", bot, false)
	bot:Action_UseAbility(song)
	T.eq(#castCalls, 1, "Hard: 0.9 < 0.95, the first order goes out")
	Stub.time = 601
	bot:Action_UseAbility(song)
	T.eq(#castCalls, 2, "1s later: a new decision, sent")

	bot = load(1)
	castCalls = recorder(CDOTA_Bot_Script, "Action_UseAbility")
	require(GetScriptDirectory() .. "/lib/systems/global_overrides")
	scriptedRandom({ 0.9, 0.1 })
	song = Stub.newAbility("largo_amphibian_rhapsody", bot, false)
	bot:Action_UseAbility(song)
	T.eq(#castCalls, 0, "Easy: 0.9 >= 0.65, the first decision fails")
	Stub.time = 601
	bot:Action_UseAbility(song)
	T.eq(#castCalls, 1, "the order 1s later rolls again and goes out")
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
		return 0.1
	end
	bot:Action_UseAbilityOnEntity(bot:GetAbilityInSlot(1), enemy)
	T.eq(printed("what=hero-cast"), 1, "no spell on a hero")
	Stub.time = 602
	bot:Action_UseAbilityOnEntity(bot:GetAbilityInSlot(1), ally)
	T.eq(#castCalls, 1, "a spell on an ally goes out at once (a save: Passive's reactive roll, 0.1 < 0.25)")
	T.eq(printed("roll kind=reactive result=ok p=0.25"), 1, "reactive roll line")
	T.eq(H.FightsHeroes(bot), false, "no attack mode")
	local desire, why = H.GateRoam(bot, 0.6, "help-ally", ally, 3, 1)
	T.eq(desire, 0, "no help fight")
	T.eq(why, "diff-help-ally", "why")
end)
