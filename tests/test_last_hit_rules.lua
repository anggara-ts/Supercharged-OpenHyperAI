-- bots/lib/systems/last_hit_rules.lua: last-hit timing rules (#71): turn time, creep value, early start, wind-up
-- release / cancel.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_nevermore" })
	return require(GetScriptDirectory() .. "/lib/systems/last_hit_rules")
end

T.test("turn time: 0.03 * radians / turn rate, after the 11.5 degree tolerance", function()
	local R = rules()
	-- Liquipedia "Turn Rate": 180 degrees at 0.6 is 0.03 * pi / 0.6 = 0.157s; less the 11.5 degree tolerance.
	T.near(R.TurnTime(180, 0.6), 0.03 * math.rad(168.5) / 0.6, 1e-9, "180 at 0.6")
	T.near(R.TurnTime(180, 0.6), 0.147, 0.001, "about 0.147s")
	T.eq(R.TurnTime(11.5, 0.6), 0, "inside the tolerance")
	T.eq(R.TurnTime(5, 0.9), 0, "facing it already")
	T.ok(R.TurnTime(90, 0.9) < R.TurnTime(90, 0.6), "a faster turner turns sooner")
	T.eq(R.TurnTime(90, 0), 0, "a bad turn rate gives no time, not inf")
end)

T.test("turn angle: facing degrees against the direction to the target", function()
	local R = rules()
	T.near(R.TurnAngle(0, 100, 0), 0, 1e-9, "facing east, target east")
	T.near(R.TurnAngle(0, -100, 0), 180, 1e-9, "target behind")
	T.near(R.TurnAngle(90, 100, 0), 90, 1e-9, "facing north, target east")
	T.near(R.TurnAngle(350, 100, 0), 10, 1e-9, "wraps around 360")
	T.near(R.TurnAngle(270, 0, 100), 180, 1e-9, "facing south, target north")
	T.eq(R.TurnAngle(45, 0, 0), 0, "on top of it")
end)

T.test("turn rates from the Valve datafeed, base 0.6", function()
	local R = rules()
	T.eq(R.TurnRate("npc_dota_hero_nevermore"), 0.9, "Shadow Fiend")
	T.eq(R.TurnRate("npc_dota_hero_kez"), 1.0, "Kez")
	T.eq(R.TurnRate("npc_dota_hero_weaver"), 0.6, "not listed: base")
	T.eq(R.TurnRate("npc_dota_hero_zuus"), 0.6, "Zeus base")
end)

T.test("creep kind and value: flagbearer > siege > ranged > melee", function()
	local R = rules()
	T.eq(R.CreepKind("npc_dota_creep_goodguys_flagbearer"), "flag")
	T.eq(R.CreepKind("npc_dota_goodguys_siege"), "siege", "game 063's siege name has no 'creep'")
	T.eq(R.CreepKind("npc_dota_creep_badguys_ranged"), "ranged")
	T.eq(R.CreepKind("npc_dota_creep_badguys_melee"), "melee")
	T.ok(R.KIND_VALUE.flag > R.KIND_VALUE.siege, "flag over siege")
	T.ok(R.KIND_VALUE.siege > R.KIND_VALUE.ranged, "siege over ranged")
	T.ok(R.KIND_VALUE.ranged > R.KIND_VALUE.melee, "ranged over melee")
end)

T.test("pick: sure beats early, value beats list order, a walk-in counts less", function()
	local R = rules()
	local nearMelee = R.PickScore("melee", true, false)
	local nearRanged = R.PickScore("ranged", true, false)
	local farFlag = R.PickScore("flag", true, true)
	local nearSiege = R.PickScore("siege", true, false)
	local earlyFlag = R.PickScore("flag", false, false)
	T.ok(nearRanged > nearMelee, "ranged over melee")
	T.ok(farFlag > nearRanged, "a far flagbearer over a near ranged creep")
	T.ok(nearSiege > farFlag, "a near siege creep over a far flagbearer")
	T.ok(nearMelee > earlyFlag, "a sure melee over an early flagbearer")
	T.ok(R.BetterPick(nearMelee, 0.5, nil, nil), "first candidate")
	T.ok(R.BetterPick(nearMelee, 0.3, nearMelee, 0.5), "tie: the hit that lands first")
	T.ok(not R.BetterPick(nearMelee, 0.6, nearMelee, 0.5), "tie: later hit loses")
end)

T.test("classify: sure / early (1.5 hits) / nil", function()
	local R = rules()
	T.eq(R.Classify(40, 45, false, true), "sure", "our hit kills")
	T.eq(R.Classify(45, 45, false, true), "early", "exactly our hit: Fu.WillKillTarget needs more than the HP")
	T.eq(R.Classify(60, 45, false, true), "early", "within 1.5 hits")
	T.eq(R.Classify(70, 45, false, true), nil, "beyond 1.5 hits")
	T.eq(R.Classify(60, 45, false, false), nil, "early not allowed (a support with a core near)")
	T.eq(R.Classify(10, 45, true, true), nil, "the others kill it first")
end)

T.test("wind-up: release a kill, wait while there is time, cancel an early miss at the last look", function()
	local R = rules()
	local function decide(over)
		local s = { predictedHp = 60, ourHit = 45, incomingKills = false, remaining = 0.05, frameGap = 0.033 }
		for k, v in pairs(over) do
			s[k] = v
		end
		return R.WindupDecision(s)
	end
	T.eq(decide({ predictedHp = 30, early = true }), "release", "our hit kills: release")
	T.eq(select(2, decide({ predictedHp = 30, early = true })), "kills")
	T.eq(decide({ incomingKills = true, early = true }), "release", "others kill it first: nothing to stop")
	T.eq(decide({ early = true, remaining = 0.2 }), "wait", "time for another look")
	local decision, why = decide({ early = true })
	T.eq(decision, "cancel", "early start, survives, last look")
	T.eq(why, "survives")
	decision, why = decide({ early = false })
	T.eq(decision, "release", "a sure start is never cancelled")
	T.eq(why, "sure")
	T.eq(decide({ early = true, remaining = -0.05 }), "cancel", "late look still tries to stop it")
end)

T.test("restart after a cancel: sure at once, early a few times, then hold", function()
	local R = rules()
	T.eq(R.RestartDecision("sure", 5), "sure")
	T.eq(R.RestartDecision("early", 0), "early")
	T.eq(R.RestartDecision("early", R.MAX_EARLY_RESTARTS), "hold", "early restarts capped")
	T.eq(R.RestartDecision(nil, 0), "hold")
end)

T.test("an early swing needs two looks inside the wind-up", function()
	local R = rules()
	T.ok(R.CanTimeWindup(0.21, 0.033), "Dark Willow's 0.21s wind-up at 30 looks a second")
	T.ok(not R.CanTimeWindup(0.21, 0.125), "at 8 looks a second it is too short")
end)

T.test("backup hit: lands after the core's, leaves the creep the core kills", function()
	local R = rules()
	local function decide(over)
		local b = {
			coreKillsFirst = false,
			coreState = "attacking",
			coreTooLate = false,
			coreCanKill = false,
			myDelay = 0.6,
			coreEta = 0.4,
			ourKills = true,
		}
		for k, v in pairs(over) do
			b[k] = v
		end
		return R.BackupDecision(b)
	end
	T.eq(decide({ coreKillsFirst = true }), "core", "the core's hit kills it first")
	T.eq(decide({ myDelay = 0.5 }), "wait", "ours would land under 0.15s after the core's")
	local decision, why = decide({})
	T.eq(decision, "go", "ours lands 0.2s after the core's and kills what is left")
	T.eq(why, "behind")
	T.eq(decide({ ourKills = false }), "wait", "still too healthy after the core's hit")
	T.eq(decide({ coreState = "free", coreCanKill = true }), "wait", "the core is free and its hit kills: it takes it")
	T.eq(decide({ coreState = "attacking", coreCanKill = true }), "wait", "the core holds it and its hit kills")
	-- Game 065 t=310 Dark Willow behind Clinkz: coreEta 0.93 against myEta 0.78, the creep taken first.
	T.eq(decide({ coreState = "free", myDelay = 0.78, coreEta = 0.93 }), "wait", "a free core walking in lands first")
	-- Game 065 t=634 Hoodwink behind Primal Beast (overlay hold): coreEta 0.59 against myEta 0.54.
	T.eq(decide({ myDelay = 0.54, coreEta = 0.59 }), "wait", "the core's hold counts as attacking")
	decision, why = decide({ coreState = "free", coreCanKill = true, coreTooLate = true, myDelay = 0.5, coreEta = 1.8 })
	T.eq(decision, "go", "the core's hit comes after the creep dies")
	T.eq(why, "late")
	for _, state in ipairs({ "busy", "far" }) do
		decision, why = decide({ coreState = state, coreCanKill = true, myDelay = 0.3, coreEta = 0.9 })
		T.eq(decision, "go", "the core cannot take it: " .. state)
		T.eq(why, state)
	end
	-- A core timing another creep: waits only when the core's hit kills this one too.
	T.eq(
		decide({ coreState = "elsewhere", coreCanKill = true, myDelay = 0.3, coreEta = 0.9 }),
		"wait",
		"it may take it"
	)
	decision, why = decide({ coreState = "elsewhere", coreCanKill = false, myDelay = 0.3, coreEta = 0.9 })
	T.eq(decision, "go", "its hit does not kill this one")
	T.eq(why, "elsewhere")
	decision, why = decide({ coreState = "elsewhere", coreCanKill = true, coreTooLate = true })
	T.eq(decision, "go", "too late for a core on another creep")
	T.eq(why, "late")
end)

T.test("backup: the core's hit is too late only clearly before it lands", function()
	local R = rules()
	T.ok(R.CoreTooLate(true, math.huge, 0.4), "hits already on their way kill it first")
	T.ok(R.CoreTooLate(false, 1.0, 1.8), "dies 0.8s before a walk-in lands")
	T.ok(not R.CoreTooLate(false, 0.35, 0.45), "within the margin: the core still gets the chance")
	T.ok(not R.CoreTooLate(false, math.huge, 3), "nothing hits it")
end)

T.test("backup swing: the core can still take it first", function()
	local R = rules()
	local b = { coreState = "attacking", coreTooLate = false, coreCanKill = true, myDelay = 0.54, coreEta = 0.59 }
	T.ok(R.BackupCoreNext(b), "game 065 t=634: Primal Beast's hit kills it, ours would land first")
	b.coreCanKill = false
	T.ok(not R.BackupCoreNext(b), "the core's hit does not kill it: ours goes")
	b.coreCanKill, b.coreState = true, "busy"
	T.ok(not R.BackupCoreNext(b), "a busy core does not take it")
	b.coreState = "elsewhere"
	T.ok(not R.BackupCoreNext(b), "a core timing another creep does not stop our swing")
	b.coreState, b.coreTooLate = "free", true
	T.ok(not R.BackupCoreNext(b), "too late for the core")
	local s = { predictedHp = 30, ourHit = 45, incomingKills = false, frameGap = 0.033, early = false, backup = true }
	s.coreNext, s.remaining = true, 0.3
	T.eq(R.WindupDecision(s), "wait", "another look first")
	s.remaining = 0.05
	local decision, why = R.WindupDecision(s)
	T.eq(decision, "cancel", "stopped for the core")
	T.eq(why, "core-next")
	s.coreNext = false
	T.eq(R.WindupDecision(s), "release", "the core cannot: ours kills it")
end)

T.test("backup swing: stopped when the core's hit kills first, at the last look", function()
	local R = rules()
	local s = { predictedHp = -5, ourHit = 45, incomingKills = true, frameGap = 0.033, early = false, backup = true }
	s.remaining = 0.3
	T.eq(R.WindupDecision(s), "wait", "time for another look")
	s.remaining = 0.05
	local decision, why = R.WindupDecision(s)
	T.eq(decision, "cancel", "the core's hit kills it")
	T.eq(why, "core")
	s.backup = false
	T.eq(R.WindupDecision(s), "release", "not a backup: nothing to stop")
end)

T.test("backup: no late go while the core's hit on its way kills (game 087 t=318)", function()
	local R = rules()
	-- Dark Willow behind Ringmaster: his projectile in the air, death=0.04 (it counted his projectile), coreEta 0.54
	-- (his next hit), myEta 0.42. Before: late, and she took his creep.
	T.ok(R.CoreTooLate(true, 0.04, 0.54, false), "without the hit on its way: too late (the old reading)")
	T.ok(not R.CoreTooLate(true, 0.04, 0.54, true), "the core's own hit on its way kills: never too late")
	T.ok(R.CoreOnWayKills(64, 48.8, false), "64 on a creep at 48.8 when it lands")
	T.ok(not R.CoreOnWayKills(30, 48.8, false), "a hit that leaves it alive")
	T.ok(not R.CoreOnWayKills(64, 48.8, true), "others kill it before the core's hit lands")
	T.ok(not R.CoreOnWayKills(nil, 48.8, false), "no hit on its way")
	local b = {
		coreKillsFirst = false,
		coreState = "attacking",
		coreOnWay = true,
		coreTooLate = R.CoreTooLate(true, 0.04, 0.54, true),
		coreCanKill = true,
		myDelay = 0.42,
		coreEta = 0.54,
		ourKills = true,
	}
	local decision, why = R.BackupDecision(b)
	T.eq(decision, "wait", "the support leaves it to the core's hit in the air")
	T.eq(why, "on-way")
	for _, state in ipairs({ "busy", "far", "free" }) do
		b.coreState = state
		T.eq(R.BackupDecision(b), "wait", "whatever the core does now: " .. state)
		T.eq(R.BackupNextWhy(b), "core-on-way", "a backup swing stops for it: " .. state)
	end
	b.coreKillsFirst = true
	T.eq(R.BackupDecision(b), "core", "it lands before ours: the core-first answer")
	b.coreKillsFirst, b.coreOnWay, b.coreTooLate = false, false, true
	decision, why = R.BackupDecision(b)
	T.eq(decision, "go", "no hit on its way and the creep dies before the core's next: late")
	T.eq(why, "late")
end)

T.test("backup: a core holding the creep after stopping its swing keeps it (games 081 / 083 / 085)", function()
	local R = rules()
	local b = {
		coreKillsFirst = false,
		coreState = "attacking",
		coreHolding = true,
		coreTooLate = false,
		coreCanKill = false,
		myDelay = 0.6,
		coreEta = 0.4,
		ourKills = true,
	}
	local decision, why = R.BackupDecision(b)
	T.eq(decision, "wait", "before: go behind (its hit alone does not kill); now it waits for the core's next swing")
	T.eq(why, "core-hold")
	T.eq(R.BackupNextWhy(b), "core-hold", "a released backup swing stops at its last look")
	T.ok(R.RECHECK_CANCEL["core-hold"] and R.RECHECK_CANCEL["core-on-way"], "a decided release may stop for both")
	b.coreTooLate = true
	decision, why = R.BackupDecision(b)
	T.eq(decision, "go", "the creep dies before the core's next hit: the backup takes it")
	T.eq(why, "late")
	T.eq(R.BackupNextWhy(b), nil, "and its swing is not stopped")
	b.coreHolding, b.coreTooLate = false, false
	T.eq(select(2, R.BackupDecision(b)), "behind", "no hold: the old behind rule")
	local s = { predictedHp = 30, ourHit = 45, incomingKills = false, frameGap = 0.033, early = false, backup = true }
	s.coreNext, s.coreNextWhy, s.remaining = true, "core-hold", 0.05
	decision, why = R.WindupDecision(s)
	T.eq(decision, "cancel")
	T.eq(why, "core-hold", "the cancel names it")
end)

T.test("walk-in too late: the hit lands after the creep's estimated death", function()
	local R = rules()
	-- Game 064 t=61 Abaddon: creep 53 HP, expect=2.47, took=0.93. Two melee creeps at ~19 a hit per second: 1.39s.
	T.near(R.DeathEta(53, 38), 53 / 38, 1e-9, "HP over damage per second")
	T.eq(R.DeathEta(0, 38), 0, "already dead")
	T.eq(R.DeathEta(53, 0), math.huge, "nothing hits it")
	T.ok(R.WalkTooLate(2.47, R.DeathEta(53, 38)), "Abaddon's walk-in is not opened")
	T.ok(not R.WalkTooLate(0.8, R.DeathEta(53, 38)), "a hit that lands first still goes")
	T.ok(not R.WalkTooLate(5, R.DeathEta(300, 0)), "a creep nothing hits waits for us")
end)

T.test("deny over a timed last hit: only a more valuable creep", function()
	local R = rules()
	T.ok(not R.DenyBeatsTimedHit("melee", "melee"), "same kind: keep the last hit (our gold)")
	T.ok(not R.DenyBeatsTimedHit("melee", "ranged"), "a melee deny does not stop a ranged last hit")
	T.ok(R.DenyBeatsTimedHit("flag", "melee"), "a flagbearer deny beats a melee last hit")
	T.ok(R.DenyBeatsTimedHit("siege", "ranged"), "a siege deny beats a ranged last hit")
end)

T.test("ally swing: time left to the attack point, none past it or in the backswing", function()
	local R = rules()
	-- Puck in the [SHy-LH] probe: attackPoint 0.5 at attack speed 1.18 (0.424s wind-up).
	T.near(R.SwingRemaining(0.5, 1.18, 0, nil, nil), 0.5 / 1.18, 1e-9, "a swing just started: the whole wind-up")
	T.near(R.SwingRemaining(0.5, 1.18, 0.2, 5, 1.441), 0.3 / 1.18, 1e-9, "the open part, as the bot's own swing")
	T.eq(R.SwingRemaining(0.5, 1.18, 0.5, 5, 1.441), nil, "at the attack point: the hit is out")
	T.eq(R.SwingRemaining(0.4, 1.15, 0.69, 5, 1.45), nil, "game 074 Leshrac cycle 0.69: the backswing")
	-- Released 0.1s ago: the backswing of that attack, whatever the cycle says.
	T.eq(R.SwingRemaining(0.5, 1.18, 0.3, 0.1, 1.441), nil, "just released: not a new wind-up")
	T.near(R.SwingRemaining(0.5, 1.18, 0.1, 1.2, 1.441), 0.4 / 1.18, 1e-9, "after the cooldown: a new wind-up")
	T.eq(R.SwingRemaining(0.5, 1.18, nil, 5, 1.441), nil, "no cycle: not counted")
end)

T.test("ally swing: only the swings landing before our hit count", function()
	local R = rules()
	local swings = { { eta = 0.3, damage = 50 }, { eta = 0.2, damage = 30 }, { eta = 0.6, damage = 40 } }
	local total, first = R.SwingDamage(swings, 0.5)
	T.eq(total, 80, "0.3 and 0.2 land before 0.5")
	T.eq(first.eta, 0.2, "the first to land")
	total, first = R.SwingDamage(swings, 0.2)
	T.eq(total, 0, "strictly before: a tie does not count (two swings never both yield)")
	T.eq(first, nil)
	T.eq((R.SwingDamage({}, 1)), 0, "no swings")
end)

T.test("ally swing: others kill it, and whether only with the allied swing", function()
	local R = rules()
	local kills, bySwing = R.OthersKill(41, 10, 50)
	T.ok(kills and bySwing, "40 HP: creeps 10 + the ally's 50")
	kills, bySwing = R.OthersKill(41, 45, 0)
	T.ok(kills and not bySwing, "the creeps alone kill it")
	kills, bySwing = R.OthersKill(41, 45, 50)
	T.ok(kills and not bySwing, "the creeps kill it anyway: not the ally's")
	kills, bySwing = R.OthersKill(100, 10, 50)
	T.ok(not kills and not bySwing, "alive after both")
end)

T.test("ally swing: yield reasons", function()
	local R = rules()
	T.eq(R.YieldReason({ class = nil, swingKill = true }), "ally-swing", "the ally's hit kills it first")
	local s = { class = "sure", swingKill = false, support = true, coreSwing = true, ownSwing = false }
	T.eq(R.YieldReason(s), "core-swing", "a support leaves the core's creep even when its own hit kills")
	s.support = false
	T.eq(R.YieldReason(s), nil, "a core does not yield to another core's swing that does not kill")
	s.support, s.ownSwing = true, true
	T.eq(R.YieldReason(s), nil, "our own swing already winding up: the wind-up watch decides")
	s.ownSwing, s.coreSwing = false, false
	T.eq(R.YieldReason(s), nil, "no core swinging")
	s.coreSwing, s.class = true, nil
	T.eq(R.YieldReason(s), nil, "not taken anyway: nothing to yield")
end)

T.test("wind-up yield: who stops for whom", function()
	local R = rules()
	T.eq(R.WindupYield(2, 1, true), "ally-swing", "position 2 for position 1, whose hit kills first")
	T.eq(R.WindupYield(1, 2, true), nil, "never for a higher position number: only one of the two stops")
	T.eq(R.WindupYield(2, 1, false), nil, "a core keeps its swing when the other core's hit does not kill")
	T.eq(R.WindupYield(5, 1, false), "core-swing", "a support never steals a core's creep")
	T.eq(R.WindupYield(5, 4, false), nil, "a support's swing that does not kill: no yield")
	T.eq(R.WindupYield(5, 4, true), "ally-swing", "the other support's hit kills first")
	T.eq(R.WindupYield(4, 5, true), nil)
	T.eq(R.WindupYield(3, 3, true), nil, "the same position (a human read as 2): nobody stops")
	T.eq(R.WindupYield(5, nil, true), nil)
end)

T.test("wind-up yield: wait to the last look, then stop; decided swings only for these reasons", function()
	local R = rules()
	local s = { predictedHp = 30, ourHit = 45, incomingKills = false, remaining = 0.3, frameGap = 0.033, early = false }
	T.eq((R.WindupDecision(s)), "release", "no yield: our hit kills, released")
	s.yield = "core-swing"
	T.eq((R.WindupDecision(s)), "wait", "an ally to yield to: keep looking")
	s.remaining = 0.05
	local decision, why = R.WindupDecision(s)
	T.eq(decision, "cancel")
	T.eq(why, "core-swing")
	-- A backup whose core kills it first: its own reason first.
	s.backup, s.incomingKills = true, true
	T.eq(select(2, R.WindupDecision(s)), "core")
	T.ok(
		R.LastLook(0.32, 0.2) and not R.LastLook(0.33, 0.2),
		"0.2s gap: the last look is 0.32s or less before the point"
	)
	T.ok(R.RECHECK_CANCEL["ally-swing"] and R.RECHECK_CANCEL["core-swing"] and R.RECHECK_CANCEL.core)
	T.ok(
		R.RECHECK_CANCEL["core-next"] and not R.RECHECK_CANCEL.survives,
		"a decided release is never stopped for survives"
	)
end)
