-- bots/lib/systems/last_hit_timing.lua (#71): the per-frame wind-up watch on a stub bot, and Fu.GetTurnTime.
local T = ...
local Stub = T.stub

local function setup(creepHp)
	Stub.reset({ hero = "npc_dota_hero_nevermore" })
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local Timing = require(GetScriptDirectory() .. "/lib/systems/last_hit_timing")
	local bot = GetBot()
	local creep = Stub.newUnit({
		name = "npc_dota_creep_goodguys_melee",
		hp = creepHp,
		maxHp = 550,
		loc = bot:GetLocation() + Vector(100, 0, 0),
	})
	local state = { activity = 0, lastAttack = -50, orders = {} }
	bot.GetActiveMode = function()
		return BOT_MODE_LANING
	end
	bot.GetAnimActivity = function()
		return state.activity
	end
	bot.GetAttackTarget = function()
		return state.activity == 1503 and creep or nil
	end
	bot.GetAttackPoint = function()
		return 0.5
	end
	bot.GetAttackSpeed = function()
		return 1
	end
	bot.GetLastAttackTime = function()
		return state.lastAttack
	end
	bot.Action_ClearActions = function()
		state.orders[#state.orders + 1] = "clear"
	end
	bot.Action_MoveToLocation = function()
		state.orders[#state.orders + 1] = "move"
	end
	bot.Action_AttackUnit = function()
		state.orders[#state.orders + 1] = "attack"
	end
	creep.GetActualIncomingDamage = function(_, damage)
		return damage
	end
	creep.GetHealthRegen = function()
		return 0
	end
	return Fu, Timing, bot, creep, state
end

-- Frames of 1/30s, re-armed by the "laning Think" every frame (the real one does it ~3 times a second).
local function frames(Timing, bot, creep, count, damage, allowEarly)
	for _ = 1, count do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = damage, allowEarly = allowEarly ~= false })
		Timing.Tick(bot)
	end
end
-- Frames until the first order (at most 30); returns how many ran.
local function untilOrder(Timing, bot, creep, state, damage)
	for count = 1, 30 do
		frames(Timing, bot, creep, 1, damage)
		if #state.orders > 0 then
			return count
		end
	end
	return 31
end

T.test("turn time: a hero facing away from the creep", function()
	local Fu, _, bot = setup(100)
	-- The stub faces 0 degrees (east). A creep due west is 180 degrees away; Shadow Fiend turns at 0.9.
	local west = Stub.newUnit({ name = "npc_dota_creep_badguys_melee", loc = bot:GetLocation() + Vector(-300, 0, 0) })
	T.near(Fu.GetTurnTime(bot, west), 0.03 * math.rad(180 - 11.5) / 0.9, 1e-6, "180 degrees at 0.9")
	local east = Stub.newUnit({ name = "npc_dota_creep_badguys_melee", loc = bot:GetLocation() + Vector(300, 0, 0) })
	T.eq(Fu.GetTurnTime(bot, east), 0, "already facing it")
	T.eq(Fu.GetTurnTime(west, bot), 0, "creeps: no turn time")
end)

T.test("wind-up: an early swing that would not kill is cancelled before the attack point", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 100
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	frames(Timing, bot, creep, 3, 45)
	T.eq(bot._lhTiming.phase, "windup", "watching the wind-up")
	T.eq(#state.orders, 0, "no order while there is time")
	local count = untilOrder(Timing, bot, creep, state, 45)
	T.ok(count < 15, "cancelled inside the 0.5s wind-up (frame " .. count .. ")")
	T.eq(state.orders[1], "clear", "cancelled")
	T.eq(bot._lhTiming.phase, "hold", "holding after the cancel")
	T.eq(bot._lhTiming.cancels, 1)
	-- The swing stops (no release by the attack point): the stop held. Still not one hit and no early restart
	-- allowed: it holds. The creep drops into one hit: attack again.
	state.activity = 0
	frames(Timing, bot, creep, 8, 45, false)
	T.eq(bot._lhtStopOk, 1, "stop counted as held")
	T.eq(#state.orders, 1, "holding, no new order")
	creep._hp = 30
	frames(Timing, bot, creep, 1, 45, false)
	T.eq(state.orders[#state.orders], "attack", "re-attack once the hit is sure")
	T.eq(bot._lhTiming.phase, "attack")
end)

T.test("wind-up: a swing that kills is released, never cancelled", function()
	local _, Timing, bot, creep, state = setup(40)
	Stub.time = 200
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	frames(Timing, bot, creep, 20, 45)
	T.eq(#state.orders, 0, "no cancel")
	T.eq(bot._lhTiming.phase, "decided", "release decided, kept until the release is seen")
	T.eq(bot._lhtStats.released, 1, "counted once, not again at every re-arm")
	T.ok(Timing.Holding(bot, creep), "the laning Think gives no order meanwhile")
	state.lastAttack = GameTime()
	frames(Timing, bot, creep, 1, 45)
	T.eq(bot._lhTiming.phase, "released", "release seen")
end)

T.test("wind-up: a swing that was sure when it started is never cancelled", function()
	local _, Timing, bot, creep, state = setup(40)
	Stub.time = 300
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	-- Sure at the start; a heal before the first look would make it short. Simulate by the classification at the
	-- start: the first look releases it at once ("kills"), so later HP changes do not matter.
	frames(Timing, bot, creep, 1, 45)
	creep._hp = 80
	frames(Timing, bot, creep, 20, 45)
	T.eq(#state.orders, 0, "no cancel")
end)

T.test("a stop that does not hold is counted (the attack released anyway)", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 400
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	untilOrder(Timing, bot, creep, state, 45)
	T.eq(state.orders[1], "clear", "cancelled")
	state.lastAttack = GameTime()
	frames(Timing, bot, creep, 1, 45)
	T.eq(bot._lhtStopFail, 1, "release after the stop: stopped=no")
	T.eq(bot._lhTiming.phase, "released")
end)

T.test("the laning Think dropping the hit clears the timing", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 500
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	Stub.time = Stub.time + 1 / 30
	Timing.BeginThink(bot)
	Timing.Tick(bot)
	T.eq(bot._lhTiming, nil, "a think without Arm drops it")
	T.ok(not Timing.IsTiming(bot))
end)

T.test("the previous attack's backswing (also activity 1503) does not start the wind-up clock", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 600
	-- Released 0.1s ago; seconds per attack 1.7 (stub), wind-up 0.5: the next swing can start 1.2s after the release.
	state.lastAttack = GameTime() - 0.1
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	frames(Timing, bot, creep, 20, 45)
	T.eq(bot._lhTiming.phase, "attack", "no wind-up clock in the backswing")
	T.eq(#state.orders, 0, "no cancel in the backswing")
	frames(Timing, bot, creep, 25, 45)
	T.ok(bot._lhTiming.phase == "windup" or bot._lhTiming.phase == "hold", "a real wind-up after the cooldown")
end)

T.test("early swings switch off for a bot whose stops never hold", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 700
	for round = 1, 4 do
		Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
		bot._lhTiming.phase = "attack"
		state.orders = {}
		state.activity = 1503
		untilOrder(Timing, bot, creep, state, 45)
		T.ok(state.orders[1] == "clear" or state.orders[1] == "move", "round " .. round .. " stopped")
		-- The attack releases anyway, then the backswing ends.
		state.lastAttack = GameTime()
		frames(Timing, bot, creep, 1, 45)
		state.activity = 0
		Stub.time = Stub.time + 2
	end
	T.eq(bot._lhtStopFail, 4)
	T.eq(state.orders[1], "move", "the last rounds used the move-order fallback")
	T.ok(not Timing.EarlyAllowed(bot), "early swings off")
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	T.eq(bot._lhTiming.allowEarly, false, "Arm drops early for this bot")
end)

-- A bot core next to the support, hitting creep (or not).
local function addCore(creep, props)
	local core = Stub.newUnit({
		name = "npc_dota_hero_juggernaut",
		team = GetBot():GetTeam(),
		hero = true,
		loc = creep:GetLocation() + Vector(-100, 0, 0),
	})
	core.GetAttackTarget = function()
		return props.attacking and creep or nil
	end
	core.GetAttackPoint = function()
		return 0.3
	end
	core.GetAttackSpeed = function()
		return 1
	end
	core.GetLastAttackTime = function()
		return -50
	end
	core.GetAttackDamage = function()
		return 50
	end
	core.IsBot = function()
		return true
	end
	core.GetActiveMode = function()
		return props.mode or BOT_MODE_LANING
	end
	return core
end

T.test("backup: the support leaves a creep the core's pending hit kills", function()
	local _, Timing, bot, creep, state = setup(40)
	Stub.time = 800
	local core = addCore(creep, { attacking = true })
	for _ = 1, 10 do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true, backupCore = core })
		Timing.Tick(bot)
	end
	T.eq(#state.orders, 0, "no attack: the core's hit lands first and kills it")
end)

T.test("backup: waits for a free core, takes it from a busy one", function()
	local _, Timing, bot, creep, state = setup(40)
	Stub.time = 900
	local props = { attacking = false }
	local core = addCore(creep, props)
	for _ = 1, 5 do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true, backupCore = core })
		Timing.Tick(bot)
	end
	T.eq(#state.orders, 0, "the free core is about to take it")
	props.mode = BOT_MODE_RETREAT
	Stub.time = Stub.time + 1 / 30
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true, backupCore = core })
	Timing.Tick(bot)
	T.eq(state.orders[1], "attack", "the core left: the support takes it")
end)

T.test("backup: a creep the core's hit leaves alive is taken after the core's hit", function()
	local _, Timing, bot, creep, state = setup(80)
	Stub.time = 1000
	local core = addCore(creep, { attacking = true })
	local facts = Timing.BackupFacts(bot, core, creep, 45)
	T.eq(facts.coreState, "attacking", "the core's hit is pending")
	T.ok(facts.myDelay >= facts.coreEta, "the support's hit lands later (wind-up 0.5s against 0.3s)")
	T.ok(facts.ourKills, "80 - 50 from the core leaves one support hit")
	Stub.time = Stub.time + 1 / 30
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true, backupCore = core })
	Timing.Tick(bot)
	T.eq(state.orders[1], "attack", "backup swing")
end)

T.test("backup: a core walking in or held by the overlay counts as attacking", function()
	local _, Timing, bot, creep = setup(60)
	Stub.time = 1050
	local core = addCore(creep, { attacking = false })
	-- Game 065: the core's own timing walking in on this creep (no attack target yet).
	core._lhTiming = { creep = creep, phase = "walk" }
	local facts = Timing.BackupFacts(bot, core, creep, 45)
	T.eq(facts.coreState, "attacking", "its walk-in on this creep")
	T.eq(facts.coreHold, "same")
	core._lhTiming = nil
	core._lhOwn = { unit = creep }
	facts = Timing.BackupFacts(bot, core, creep, 45)
	T.eq(facts.coreState, "attacking", "team roam's overlay holds this creep (any mode)")
	core.GetActiveMode = function()
		return BOT_MODE_TEAM_ROAM
	end
	T.eq(Timing.BackupFacts(bot, core, creep, 45).coreState, "attacking", "the overlay runs in team roam")
	core._lhOwn = { unit = Stub.newUnit({ name = "npc_dota_creep_goodguys_ranged", loc = creep:GetLocation() }) }
	T.eq(Timing.BackupFacts(bot, core, creep, 45).coreState, "elsewhere", "the overlay holds another creep")
	core._lhOwn = nil
	T.eq(Timing.BackupFacts(bot, core, creep, 45).coreState, "busy", "team roam without a hold")
end)

T.test("backup: a wind-up ahead of the core's hit is stopped (core-next)", function()
	local _, Timing, bot, creep, state = setup(40)
	Stub.time = 1080
	local core = addCore(creep, { attacking = false })
	core._lhTiming = { creep = creep, phase = "hold" }
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = false, backupCore = core })
	state.activity = 1503
	for _ = 1, 20 do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = false, backupCore = core })
		Timing.Tick(bot)
		if #state.orders > 0 then
			break
		end
	end
	T.eq(state.orders[1], "clear", "the core holds this creep and its hit kills it: our swing stops")
end)

T.test("a laning Think that gave another order drops the timing at the next frame's Tick", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 1100
	-- A walk-in armed by one Think; the next Think (a later frame) denies instead and does not re-arm it. The Tick
	-- after it must not attack the old creep over the deny.
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
	Stub.time = Stub.time + 0.3
	Timing.BeginThink(bot)
	Stub.time = Stub.time + 1 / 30
	creep._hp = 30
	Timing.Tick(bot)
	T.eq(bot._lhTiming, nil, "dropped")
	T.eq(#state.orders, 0, "no attack over the deny")
end)

T.test("timed hit and keep: a deny passed over keeps the wind-up armed", function()
	local _, Timing, bot, creep, state = setup(60)
	Stub.time = 1200
	Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
	state.activity = 1503
	frames(Timing, bot, creep, 2, 45)
	T.eq(Timing.TimedHit(bot), creep, "the wind-up is timed")
	Stub.time = Stub.time + 1 / 30
	Timing.BeginThink(bot)
	Timing.KeepTimed(bot)
	Timing.Tick(bot)
	T.ok(bot._lhTiming ~= nil, "still armed after a Think that only kept it")
end)

T.test("death estimate: our creeps and towers hitting the creep", function()
	local _, Timing, bot, creep = setup(100)
	local function hitter(target)
		local unit =
			Stub.newUnit({ name = "npc_dota_creep_goodguys_melee", loc = creep:GetLocation() + Vector(50, 0, 0) })
		unit.GetAttackTarget = function()
			return target
		end
		unit.GetAttackDamage = function()
			return 20
		end
		unit.GetSecondsPerAttack = function()
			return 1
		end
		return unit
	end
	local units = { hitter(creep), hitter(creep), hitter(bot) }
	bot.GetNearbyLaneCreeps = function()
		return units
	end
	bot.GetNearbyTowers = function()
		return {}
	end
	creep.GetIncomingTrackingProjectiles = function()
		return {}
	end
	local death, dps = Timing.DeathEta(bot, creep)
	T.near(dps, 40, 1e-9, "two creeps on it, one on something else")
	T.near(death, 100 / 40, 1e-9, "100 HP at 40 a second")
	units = {}
	T.eq((Timing.DeathEta(bot, creep)), math.huge, "nothing hits it")
end)

T.test("team roam's overlay owns a hit (#171 bot._lhOwn): no arm, no order, one skip line", function()
	local _, Timing, bot, creep, state = setup(30)
	Stub.time = 1300
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
	local other = Stub.newUnit({ name = "npc_dota_creep_badguys_melee", loc = bot:GetLocation() + Vector(80, 0, 0) })
	bot._lhOwn = { unit = other, t = GameTime() }
	-- The skip line is muted in OHA_MUTED (game 068); count it before the mute.
	local mutedPrint = print
	print = OHA_RAW_PRINT or print
	for _ = 1, 5 do
		Stub.time = Stub.time + 1 / 30
		T.eq(Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true }), nil, "not armed")
		T.eq(Timing.Tick(bot), false, "the overlay keeps the frame")
	end
	T.eq(#state.orders, 0, "no attack over the overlay's swing (the creep was a sure hit)")
	T.eq(bot._lhTiming, nil, "our timing dropped")
	print = mutedPrint
	local lines = 0
	for _, line in ipairs(Stub.printed) do
		if string.find(line, "skip why=overlay-owns", 1, true) then
			lines = lines + 1
		end
	end
	T.eq(lines, 1, "logged once per hold")
	-- The hold ends: the timing works again.
	bot._lhOwn = nil
	Stub.time = Stub.time + 1 / 30
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
	Timing.Tick(bot)
	T.eq(state.orders[1], "attack", "the sure walk-in attacks once the overlay let go")
end)

-- An allied hero in the bot's team slots (GetTeamMember) winding up on creep (#71, maintainer 2026-11-23).
local function addSwinger(creep, props)
	local ally = GetTeamMember(2)
	ally._loc = creep:GetLocation() + Vector(-100, 0, 0)
	ally.GetAttackTarget = function()
		return props.attacking and creep or nil
	end
	ally.GetAnimActivity = function()
		return props.attacking and 1503 or 0
	end
	-- props.startAt: the swing started then and its cycle runs with the clock (attack speed 1).
	ally.GetAnimCycle = function()
		if props.startAt ~= nil then
			return GameTime() - props.startAt
		end
		return props.cycle or 0.1
	end
	ally.GetAttackPoint = function()
		return props.point or 0.3
	end
	ally.GetAttackSpeed = function()
		return 1
	end
	ally.GetLastAttackTime = function()
		return props.lastAttack or -50
	end
	ally.GetAttackDamage = function()
		return props.damage or 50
	end
	return ally
end

local function yieldLines(why)
	local lines = 0
	for _, line in ipairs(Stub.printed) do
		if string.find(line, "yield why=" .. why, 1, true) then
			lines = lines + 1
		end
	end
	return lines
end

T.test("ally swing: an ally's wind-up that kills the creep first is counted", function()
	local _, Timing, _, creep = setup(40)
	Stub.time = 1200
	local props = { attacking = true, cycle = 0.1 }
	addSwinger(creep, props)
	local predictedHp, _, incomingKills, swingKill = Timing.Predict(creep, 45, 0.5)
	T.ok(incomingKills, "40 HP, the ally's 50 lands in 0.2s, before our hit at 0.5s")
	T.ok(swingKill ~= nil and swingKill.ally == GetTeamMember(2), "the ally's swing made it")
	T.near(swingKill.eta, 0.2, 1e-9, "(0.3 - 0.1) / 1, melee: no flight")
	T.near(predictedHp, 40.8 - 50, 1e-9, "its hit is taken off the predicted HP")
	props.cycle = 0.35
	T.ok(not select(3, Timing.Predict(creep, 45, 0.5)), "past its attack point: the hit is out")
	props.cycle, props.lastAttack = 0.1, GameTime() - 0.1
	T.ok(not select(3, Timing.Predict(creep, 45, 0.5)), "its previous attack's backswing: no new wind-up")
	props.lastAttack, props.point = nil, 0.9
	T.ok(not select(3, Timing.Predict(creep, 45, 0.5)), "its hit lands after ours (0.8s): not counted")
	props.point = 0.3
	T.ok(not select(3, Timing.Predict(creep, 45, 0.5, 0, GetTeamMember(2))), "left out (exclude)")
	props.attacking = false
	T.ok(not select(3, Timing.Predict(creep, 45, 0.5)), "not attacking it")
end)

T.test("ally swing: the bot does not walk in on a creep an ally's swing kills, logs it once", function()
	local _, Timing, bot, creep, state = setup(40)
	Stub.time = 1300
	local props = { attacking = true, cycle = 0.05 }
	addSwinger(creep, props)
	local mutedPrint = print
	print = OHA_RAW_PRINT or print
	for _ = 1, 5 do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
		Timing.Tick(bot)
	end
	print = mutedPrint
	T.eq(#state.orders, 0, "no attack: the ally takes it")
	T.eq(yieldLines("ally-swing"), 1, "one [SHy-LH] yield line for this creep")
	-- The ally cancels its swing: the bot may take it.
	props.attacking = false
	Stub.time = Stub.time + 1 / 30
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
	Timing.Tick(bot)
	T.eq(state.orders[1], "attack", "the ally stopped: the sure hit goes")
end)

T.test("ally swing: a support leaves the creep its core is swinging at (core-swing)", function()
	local Fu, Timing, bot, creep, state = setup(40)
	Stub.time = 1400
	local props = { attacking = true, cycle = 0.05, damage = 20 }
	local ally = addSwinger(creep, props)
	local getPosition = Fu.GetPosition
	Fu.GetPosition = function(hero)
		return hero == bot and 5 or hero == ally and 1 or getPosition(hero)
	end
	local mutedPrint = print
	print = OHA_RAW_PRINT or print
	for _ = 1, 5 do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
		Timing.Tick(bot)
	end
	print = mutedPrint
	T.eq(#state.orders, 0, "our hit would kill (40 - 20 < 45) but the core is swinging at it")
	T.eq(yieldLines("core-swing"), 1, "logged once")
	T.eq(yieldLines("ally-swing"), 0, "the core's 20 does not kill it alone")
	-- A core bot does not yield to another core's swing that does not kill.
	Fu.GetPosition = function(hero)
		return hero == bot and 2 or hero == ally and 1 or getPosition(hero)
	end
	Stub.time = Stub.time + 1 / 30
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true })
	Timing.Tick(bot)
	T.eq(state.orders[1], "attack", "a core takes it")
	Fu.GetPosition = getPosition
end)

T.test("ally swing: a backup behind a core in a team slot counts its pending hit once", function()
	local Fu, Timing, bot, creep, state = setup(80)
	Stub.time = 1500
	-- The core in slot 2 (seen by AllySwings) winding up: hit 50, 0.25s left (cycle 0.05 of 0.3).
	local props = { attacking = true, cycle = 0.05, damage = 50 }
	local core = addSwinger(creep, props)
	core.IsBot = function()
		return true
	end
	core.GetActiveMode = function()
		return BOT_MODE_LANING
	end
	local getPosition = Fu.GetPosition
	Fu.GetPosition = function(hero)
		return hero == bot and 5 or hero == core and 1 or getPosition(hero)
	end
	local facts = Timing.BackupFacts(bot, core, creep, 45)
	-- 80 HP + 0.8: the core's 50 once leaves 30.8 (twice would be -19.2).
	T.near(facts.predictedHp, 80.8 - 50, 1e-9, "the core's pending hit taken off once")
	T.eq(facts.coreState, "attacking")
	T.ok(not facts.coreKillsFirst, "its hit alone does not kill 80")
	local mutedPrint = print
	print = OHA_RAW_PRINT or print
	for _ = 1, 5 do
		Stub.time = Stub.time + 1 / 30
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true, backupCore = core })
		Timing.Tick(bot)
	end
	print = mutedPrint
	T.eq(#state.orders, 0, "no backup swing while the core winds up")
	T.eq(yieldLines("core-swing"), 1, "one core-swing line")
	-- The core's hit is out (past its attack point): the backup may go.
	props.cycle = 0.35
	Stub.time = Stub.time + 1 / 30
	Timing.Arm(bot, creep, { damage = 45, allowEarly = false, walk = true, backupCore = core })
	Timing.Tick(bot)
	T.eq(state.orders[1], "attack", "the backup swing after the core's hit")
	Fu.GetPosition = getPosition
end)

-- The wind-up yield (#71, game 077 t=38 and games 083-085): the bot's own swing is stopped for an ally.
local function rangedBot(bot)
	-- Ranged, slow projectile: the creep at 100 (less the 39 offset) takes 61 / 250 = 0.244s to reach.
	bot.GetAttackRange = function()
		return 600
	end
	bot.GetAttackProjectileSpeed = function()
		return 250
	end
end

local function withPositions(Fu, bot, myPos, ally, allyPos, fn)
	local getPosition = Fu.GetPosition
	Fu.GetPosition = function(hero)
		return hero == bot and myPos or hero == ally and allyPos or getPosition(hero)
	end
	local mutedPrint = print
	print = OHA_RAW_PRINT or print
	local ok, err = pcall(fn)
	print = mutedPrint
	Fu.GetPosition = getPosition
	if not ok then
		error(err, 0)
	end
end

local function windupYieldLines(why)
	local lines = 0
	for _, line in ipairs(Stub.printed) do
		if string.find(line, "yield why=" .. why .. " at=windup", 1, true) then
			lines = lines + 1
		end
	end
	return lines
end

T.test("wind-up yield: a core stops its swing for a lower-position core's swing that kills first", function()
	local Fu, Timing, bot, creep, state = setup(40)
	Stub.time = 1600
	rangedBot(bot)
	-- Game 077 t=38: Io (position 2) and Phantom Assassin (position 1) swung at one creep together.
	local props = { attacking = true, point = 0.5, damage = 50, startAt = GameTime() }
	local ally = addSwinger(creep, props)
	withPositions(Fu, bot, 2, ally, 1, function()
		Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
		state.activity = 1503
		frames(Timing, bot, creep, 3, 45)
		T.eq(bot._lhTiming.phase, "windup", "our hit would kill, but the ally's lands first: waiting, not released")
		local count = untilOrder(Timing, bot, creep, state, 45)
		T.ok(count < 15, "stopped inside the 0.5s wind-up (frame " .. count .. ")")
		T.eq(state.orders[1], "clear", "our swing stopped")
		T.eq(bot._lhTiming.phase, "hold", "holding after the stop")
		T.eq(windupYieldLines("ally-swing"), 1, "[SHy-LH] yield why=ally-swing at=windup")
	end)
end)

T.test("wind-up yield: never for a higher position number (one of two heroes yields, never both)", function()
	local Fu, Timing, bot, creep, state = setup(40)
	Stub.time = 1650
	rangedBot(bot)
	local props = { attacking = true, point = 0.5, damage = 50, startAt = GameTime() }
	local ally = addSwinger(creep, props)
	withPositions(Fu, bot, 1, ally, 2, function()
		Timing.Arm(bot, creep, { damage = 45, allowEarly = true })
		state.activity = 1503
		frames(Timing, bot, creep, 20, 45)
		T.eq(#state.orders, 0, "position 1 keeps its swing")
		T.eq(bot._lhTiming.phase, "decided", "released (others): as before")
		T.eq(windupYieldLines("ally-swing"), 0)
	end)
end)

T.test("wind-up yield: a decided support swing stops at the last look for a core's new swing", function()
	local Fu, Timing, bot, creep, state = setup(40)
	Stub.time = 1700
	rangedBot(bot)
	-- Games 083-085: the support released at its first look, then the core (cancelled, holding) swung again.
	local props = { attacking = false, point = 0.6, damage = 20 }
	local ally = addSwinger(creep, props)
	withPositions(Fu, bot, 5, ally, 1, function()
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false })
		state.activity = 1503
		frames(Timing, bot, creep, 1, 45, false)
		T.eq(bot._lhTiming.phase, "decided", "our hit kills: release decided at the first look")
		props.attacking, props.startAt = true, GameTime()
		frames(Timing, bot, creep, 5, 45, false)
		T.eq(#state.orders, 0, "not before the last look")
		local count = untilOrder(Timing, bot, creep, state, 45)
		T.ok(count < 15, "stopped before our attack point (frame " .. count .. ")")
		T.eq(state.orders[1], "clear", "the decided swing stopped")
		T.eq(windupYieldLines("core-swing"), 1, "[SHy-LH] yield why=core-swing at=windup (the core's 20 does not kill)")
	end)
end)

T.test("wind-up yield: a decided swing is not stopped when no ally swings (release stays a release)", function()
	local Fu, Timing, bot, creep, state = setup(40)
	Stub.time = 1750
	rangedBot(bot)
	local props = { attacking = false, point = 0.6, damage = 20 }
	local ally = addSwinger(creep, props)
	withPositions(Fu, bot, 5, ally, 1, function()
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false })
		state.activity = 1503
		frames(Timing, bot, creep, 1, 45, false)
		T.eq(bot._lhTiming.phase, "decided")
		-- The creep heals out of one hit: a "survives" at the last look does not stop a decided release.
		creep._hp = 80
		frames(Timing, bot, creep, 20, 45, false)
		T.eq(#state.orders, 0, "no stop")
	end)
end)

T.test("wind-up yield: looks 0.2s apart still stop the swing before the attack point", function()
	local Fu, Timing, bot, creep, state = setup(40)
	Stub.time = 1800
	rangedBot(bot)
	bot._lhtGap = 0.2
	bot._lhtFrameAt = Stub.time
	local props = { attacking = false, point = 0.6, damage = 20 }
	local ally = addSwinger(creep, props)
	local function look()
		Stub.time = Stub.time + 0.2
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false })
		Timing.Tick(bot)
	end
	withPositions(Fu, bot, 5, ally, 1, function()
		Timing.Arm(bot, creep, { damage = 45, allowEarly = false })
		state.activity = 1503
		look()
		T.eq(bot._lhTiming.phase, "decided", "first look 0.1s into the 0.5s wind-up: released")
		props.attacking, props.startAt = true, GameTime()
		look()
		T.eq(state.orders[1], "clear", "the next look (0.2s left, last look at a 0.2s gap) stops it")
		T.ok(GameTime() < bot._lhTiming.cancelPointAt, "before the attack point")
	end)
end)
