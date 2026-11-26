-- Last-hit timing every frame (#71, game 063: 105 got / 103 missed; 71 misses had no attack launched before the creep
-- died, 58 of them on a walk-in). The laning mode's Think runs only about 3 times a second (game 063 [SHy-PERF]: mode
-- GetDesire ~32 calls per 10s, ItemUsageThink 300), so its hit orders can be up to ~0.3s late. The laning Think still
-- picks the creep and walks in (Arm); this module, called every frame from ability_item_usage_generic.lua's
-- ItemUsageThink, then:
--   walk / hold  attacks on the frame the hit becomes sure (or early, see below) instead of at the next mode think;
--   wind-up      re-predicts the creep's HP at the moment our hit lands (attacks in flight, creeps and towers mid-swing,
--                our tower's next shot), lets the hit go when it kills, and cancels a hit that started early (the
--                creep was within 1.5 of our hits) and would not kill, just before the attack point; then holds and
--                attacks again at the right moment. Never cancels a hit that was sure when its wind-up started, a
--                deny or a harass hit (those never arm this), except to yield the creep to an ally winding up on it
--                (LastHitRules.WindupYield, [SHy-LH] yield ... at=windup) or, for a backup, to its core.
-- The pure decisions are in last_hit_rules.lua. Logs: [SHy-LH] release / cancel / cancel-result and the per-minute
-- [SHy-LH] minute summary. Other per-frame code (kiting #72, team roam's overlay #165) can ask X.IsTiming(bot) to keep
-- its hands off while a last hit is being timed.
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local Rules = require(GetScriptDirectory() .. "/lib/systems/last_hit_rules")

local X = {}

local ATTACK_ACTIVITY = 1503
-- A state not re-armed by the laning Think for this long is stale (the Think runs ~3 times a second).
local ARM_MAX_AGE = 1.0
local LOG_EVERY = 3

local function heroName(bot)
	return (string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""))
end

-- Seconds between frames of this bot's ItemUsageThink (smoothed), 0.02..0.4.
local function noteFrame(bot, now)
	local last = bot._lhtFrameAt
	bot._lhtFrameAt = now
	if last ~= nil and now > last and now - last < 1 then
		bot._lhtGap = (bot._lhtGap or 0.05) * 0.8 + (now - last) * 0.2
	end
end
function X.FrameGap(bot)
	return math.min(0.4, math.max(0.02, bot._lhtGap or 0.1))
end

local function isRangedAttacker(bot)
	return bot:GetAttackRange() > 320 or bot:GetUnitName() == "npc_dota_hero_templar_assassin"
end

-- Projectile flight from bot to creep (0 for melee), as Fu.GetAttackProDelayTime counts it.
function X.TravelTime(bot, creep)
	if not isRangedAttacker(bot) then
		return 0
	end
	local offset = bot:GetPrimaryAttribute() == ATTRIBUTE_INTELLECT and 59 or 39
	local distance = math.min(GetUnitToUnitDistance(bot, creep) - offset, bot:GetAttackRange())
	return math.max(0, distance) / math.max(1, bot:GetAttackProjectileSpeed())
end

-- Our tower's next shot on a creep (#71, game 045): when an allied tower is attacking this creep and its next shot
-- lands before our hit (hitDelay seconds from now), the damage it deals, else 0.
function X.TowerShotBefore(bot, creep, hitDelay)
	-- An unreachable hit (delay inf, game 046: a melee bot far from the creep) has no timing to plan.
	if hitDelay == nil or hitDelay ~= hitDelay or hitDelay > 3 then
		return 0
	end
	for _, tower in pairs(bot:GetNearbyTowers(1000, false) or {}) do
		if Fu.IsValidBuilding(tower) and tower:GetAttackTarget() == creep then
			local nextShot = tower:GetLastAttackTime() + tower:GetSecondsPerAttack()
			local travel = GetUnitToUnitDistance(tower, creep) / math.max(1, tower:GetAttackProjectileSpeed())
			if nextShot + travel < GameTime() + hitDelay then
				return creep:GetActualIncomingDamage(tower:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
			end
		end
	end
	return 0
end

-- Allied heroes (bot or human; not bot, not exclude) winding up on creep now (#71, maintainer 2026-11-23,
-- LastHitRules.SwingRemaining): a list of { ally, eta (seconds until the hit lands: rest of the wind-up + flight),
-- damage (GetAttackDamage, the average, after armour: crits and Quelling Blade not counted), cycle, since }. Team
-- slots 1-5 cover humans; illusions are not team members. Game 074's [SHy-HUMAN] state lines read GetAttackTarget,
-- GetAnimActivity and GetAnimCycle on a human hero; GetLastAttackTime on one is unverified (a non-number or wrong
-- value only drops the backswing test).
function X.AllySwings(bot, creep, exclude)
	local list = {}
	local now = GameTime()
	for slot = 1, 5 do
		local ally = GetTeamMember(slot)
		if
			ally ~= nil
			and ally ~= bot
			and ally ~= exclude
			and Fu.IsValidHero(ally)
			and ally:GetAttackTarget() == creep
			and ally:GetAnimActivity() == ATTACK_ACTIVITY
			and GetUnitToUnitDistance(ally, creep) <= Rules.ALLY_SWING_RANGE
		then
			local lastAttack = ally:GetLastAttackTime()
			local since = type(lastAttack) == "number" and now - lastAttack or nil
			local cycle = ally:GetAnimCycle()
			local remaining = Rules.SwingRemaining(
				ally:GetAttackPoint(),
				ally:GetAttackSpeed(),
				cycle,
				since,
				ally:GetSecondsPerAttack()
			)
			if remaining ~= nil then
				list[#list + 1] = {
					ally = ally,
					eta = remaining + X.TravelTime(ally, creep),
					damage = creep:GetActualIncomingDamage(ally:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL),
					cycle = cycle,
					since = since,
				}
			end
		end
	end
	return list
end

-- The creep's HP when our hit lands in delay seconds: predictedHp, ourHit (our damage on it after armour),
-- incomingKills (the other hits alone kill it first), swingKill (the allied swing that made incomingKills true, or
-- nil), swings (X.AllySwings: every allied hero winding up on it, also those landing after ours). Same sums as
-- Fu.WillKillTarget, with the tower shot as a hit that lands first and the allied heroes' swings landing before ours
-- (exclude: a hero left out, e.g. the core whose own hit BackupFacts adds).
function X.Predict(creep, damage, delay, towerShot, exclude)
	towerShot = towerShot or 0
	local effectiveHealth = creep:GetHealth() + creep:GetHealthRegen() * delay + 0.8
	local incoming = Fu.GetTotalAttackWillRealDamage(creep, delay)
	local ourHit = creep:GetActualIncomingDamage(damage, DAMAGE_TYPE_PHYSICAL)
	local swings = X.AllySwings(GetBot(), creep, exclude)
	local swingDamage, firstSwing = Rules.SwingDamage(swings, delay)
	local othersKill, bySwing = Rules.OthersKill(effectiveHealth, incoming, swingDamage)
	local towerKills = towerShot > 0 and towerShot >= creep:GetHealth()
	local swingKill = bySwing and not towerKills and firstSwing or nil
	return effectiveHealth - incoming - swingDamage - towerShot, ourHit, othersKill or towerKills, swingKill, swings
end

-- [SHy-LH] yield: once per creep, reason and stage (at = "pick": no swing of ours started; "windup": our swing is
-- stopped for the ally), at most every second per bot and stage.
local function logYield(bot, creep, why, swing, myDelay, at)
	at = at or "pick"
	bot._lhtYieldSeen = bot._lhtYieldSeen or {}
	bot._lhtYieldLogAt = bot._lhtYieldLogAt or {}
	local seen = bot._lhtYieldSeen[at]
	if seen ~= nil and seen.creep == creep and seen.why == why then
		return
	end
	if DotaTime() < (bot._lhtYieldLogAt[at] or -99) then
		return
	end
	bot._lhtYieldSeen[at] = { creep = creep, why = why }
	bot._lhtYieldLogAt[at] = DotaTime() + 1
	local ally = swing.ally
	pcall(
		print,
		string.format(
			"[SHy-LH] t=%.0f %s yield why=%s at=%s ally=%s human=%d pos=%d creep-hp=%d allyHit=%.0f allyEta=%.2f myEta=%.2f cycle=%.2f since=%.2f",
			DotaTime(),
			heroName(bot),
			why,
			at,
			heroName(ally),
			ally:IsBot() and 0 or 1,
			Fu.GetPosition(ally),
			creep:GetHealth(),
			swing.damage,
			swing.eta,
			myDelay,
			swing.cycle,
			swing.since ~= nil and math.min(99, swing.since) or -1
		)
	)
end

-- Our own swing on creep is winding up or its release is decided (the wind-up watch owns it then).
local function ownSwing(bot, creep)
	local st = bot._lhTiming
	return st ~= nil and st.creep == creep and (st.phase == "windup" or st.phase == "decided")
end

-- An allied core (position 1-3, bot or human) winding up on creep: the swing, else nil.
local function coreSwing(bot, creep)
	for _, swing in ipairs(X.AllySwings(bot, creep)) do
		if Fu.GetPosition(swing.ally) <= 3 then
			return swing
		end
	end
	return nil
end

-- Yield a creep to an ally's swing (LastHitRules.YieldReason): returns class, or nil when the bot leaves the creep to
-- the ally (logged [SHy-LH] yield why=ally-swing / core-swing). class: Classify's result for our hit; swingKill:
-- X.Predict's 4th value; myDelay: when our hit would land. Re-checked at every pick and frame: a human may cancel.
function X.Yield(bot, creep, class, swingKill, myDelay)
	local support = Fu.GetPosition(bot) >= 4
	local own = ownSwing(bot, creep)
	-- The ally scan only where it can decide something.
	local core = swingKill == nil and class ~= nil and support and not own and coreSwing(bot, creep) or nil
	local why = Rules.YieldReason({
		class = class,
		swingKill = swingKill ~= nil,
		support = support,
		coreSwing = core ~= nil,
		ownSwing = own,
	})
	if why == nil then
		return class
	end
	logYield(bot, creep, why, swingKill or core, myDelay)
	return nil
end

-- Our own swing winds up on creep (or its release is decided) while allied heroes wind up on it too (swings:
-- X.Predict's 5th value; swingKill its 4th; myDelay: when our hit lands): the ally the bot stops its swing for
-- (LastHitRules.WindupYield: a lower position number only), and why, else nil. No scan of its own: the swings are the
-- ones the prediction read.
local function windupYield(bot, swings, swingKill, myDelay)
	if swings == nil or #swings == 0 then
		return nil, nil
	end
	local myPos = Fu.GetPosition(bot)
	local why, yieldTo = nil, nil
	for _, swing in ipairs(swings) do
		local reason = Rules.WindupYield(myPos, Fu.GetPosition(swing.ally), swingKill ~= nil and swing.eta < myDelay)
		if reason == "ally-swing" then
			return reason, swing
		end
		if reason ~= nil and why == nil then
			why, yieldTo = reason, swing
		end
	end
	return why, yieldTo
end

-- A backup hit (the support behind its core): the core-swing yield before BackupDecision may say go. True when the
-- bot leaves the creep now (logged).
function X.YieldBackup(bot, creep, myDelay)
	return X.Yield(bot, creep, "backup", nil, myDelay) == nil
end

-- Seconds until an enemy lane creep dies to our lane creeps and towers hitting it, our own hit not counted
-- (LastHitRules.DeathEta), and that damage per second. Heroes are left out: their hits on lane creeps come and go (a
-- support's backup hit, a core's last hit), the creeps and towers keep swinging.
function X.DeathEta(bot, creep)
	local dps = 0
	local function add(unit)
		if Fu.IsValid(unit) and unit:GetAttackTarget() == creep then
			local hit = creep:GetActualIncomingDamage(unit:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
			dps = dps + hit / math.max(0.1, unit:GetSecondsPerAttack())
		end
	end
	for _, unit in pairs(bot:GetNearbyLaneCreeps(1600, false) or {}) do
		add(unit)
	end
	for _, tower in pairs(bot:GetNearbyTowers(1600, false) or {}) do
		add(tower)
	end
	local hp = creep:GetHealth() - Fu.GetCreepAttackProjectileWillRealDamage(creep, 1.0)
	return Rules.DeathEta(hp, dps), dps
end

-- The core's hit on creep: pending (attacking it and not in the previous attack's backswing / cooldown, so a hit is
-- still to come) and cooling (in the backswing / cooldown: its last hit already went out).
local function coreHitState(core, creep)
	local point = core:GetAttackPoint() / math.max(0.1, core:GetAttackSpeed())
	local cooling = GameTime() - core:GetLastAttackTime() < core:GetSecondsPerAttack() - point - 0.05
	return core:GetAttackTarget() == creep and not cooling, cooling
end

-- The core's own hold on a unit: team roam's overlay (core._lhOwn, #171) or its last-hit timing (core._lhTiming: a
-- walk-in, an attack it ordered, a wind-up, a hold after a cancel, a decided release). "same" when it is this creep,
-- "other" when another unit, nil when none (a human core has neither). The overlay clears _lhTiming while it owns a
-- hit, so both are read.
local CORE_HOLD_PHASES = { walk = true, attack = true, windup = true, hold = true, decided = true }
local function coreHold(core, creep)
	local own = core._lhOwn
	if own ~= nil and own.unit ~= nil then
		return own.unit == creep and "same" or "other"
	end
	local st = core._lhTiming
	if st ~= nil and CORE_HOLD_PHASES[st.phase] and st.creep ~= nil then
		return st.creep == creep and "same" or "other"
	end
	return nil
end

-- The core's hit already on its way to creep (#71, game 087 t=318): its attack projectile in flight, or its swing
-- winding up on it (LastHitRules.SwingRemaining, plus the flight). Seconds until the first of them lands, or nil. A
-- projectile's eta is distance / speed, the window Fu.GetCreepAttackProjectileWillRealDamage does not count it in yet
-- (it needs speed * window * 0.95 > distance * 1.02), so X.Predict at that eta leaves the core's own hit out.
local function coreHitOnWay(core, creep)
	local eta = nil
	local speed = math.max(1, core:GetAttackProjectileSpeed())
	for _, projectile in pairs(creep:GetIncomingTrackingProjectiles() or {}) do
		if projectile.is_attack and projectile.caster == core and projectile.location ~= nil then
			local flight = GetUnitToLocationDistance(creep, projectile.location) / speed
			if eta == nil or flight < eta then
				eta = flight
			end
		end
	end
	if core:GetAttackTarget() == creep and core:GetAnimActivity() == ATTACK_ACTIVITY then
		local lastAttack = core:GetLastAttackTime()
		local remaining = Rules.SwingRemaining(
			core:GetAttackPoint(),
			core:GetAttackSpeed(),
			core:GetAnimCycle(),
			type(lastAttack) == "number" and GameTime() - lastAttack or nil,
			core:GetSecondsPerAttack()
		)
		if remaining ~= nil then
			local swingEta = remaining + X.TravelTime(core, creep)
			if eta == nil or swingEta < eta then
				eta = swingEta
			end
		end
	end
	return eta
end

-- A support's backup hit behind its core (#71, games 064 / 065). Returns the facts for LastHitRules.BackupDecision /
-- BackupCoreNext, with coreEta / myDelay / deathEta for the log. myDelay: our hit's landing (default: an attack
-- started now; the wind-up passes the rest of the swing). The core's pending hit counts as landing first when it
-- lands before ours; its projectile in flight is already in Fu.GetTotalAttackWillRealDamage. coreEta
-- (Fu.GetAttackProDelayTime) counts the core's walk, turn and attack cooldown. The core is left out of X.Predict's
-- allied swings (exclude) in both predictions: its pending hit is the term below, and its own hit is not "others".
function X.BackupFacts(bot, core, creep, damage, myDelay)
	myDelay = myDelay or Fu.GetAttackProDelayTime(bot, creep)
	local coreEta = Fu.GetAttackProDelayTime(core, creep)
	local pending = coreHitState(core, creep)
	local predictedHp, ourHit, incomingKills =
		X.Predict(creep, damage, myDelay, X.TowerShotBefore(bot, creep, myDelay), core)
	if pending and coreEta < myDelay then
		predictedHp = predictedHp - creep:GetActualIncomingDamage(core:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
		incomingKills = incomingKills or predictedHp <= 0
	end
	-- Game 065: a core walking in, holding after a cancel or held by the overlay read as "not attacking", and the
	-- support went first. Its hold counts as attacking now (before the mode check: the overlay runs in team roam).
	local hold = coreHold(core, creep)
	local coreTarget = core:GetAttackTarget()
	local coreState
	if pending or hold == "same" then
		coreState = "attacking"
	elseif hold == "other" then
		coreState = "elsewhere"
	elseif
		core:IsBot() and core:GetActiveMode() ~= BOT_MODE_LANING
		or coreTarget ~= nil and not coreTarget:IsNull() and coreTarget:IsHero()
	then
		coreState = "busy"
	elseif GetUnitToUnitDistance(core, creep) > Rules.BACKUP_CORE_NEAR then
		coreState = "far"
	else
		coreState = "free"
	end
	local corePredicted, coreHit, coreOthersKill =
		X.Predict(creep, core:GetAttackDamage(), coreEta, X.TowerShotBefore(bot, creep, coreEta), core)
	-- The core's hit already on its way (game 087 t=318): when it kills, the support waits for it, whatever the
	-- death estimate says (that estimate counted the core's own projectile).
	local onWayEta = coreHitOnWay(core, creep)
	local coreOnWay = false
	if onWayEta ~= nil then
		local wayPredicted, wayHit, wayOthersKill =
			X.Predict(creep, core:GetAttackDamage(), onWayEta, X.TowerShotBefore(bot, creep, onWayEta), core)
		coreOnWay = Rules.CoreOnWayKills(wayHit, wayPredicted, wayOthersKill)
	end
	-- The core (a bot) stopped its swing on this creep and holds to swing again (games 081 / 083 / 085).
	local coreTiming = core._lhTiming
	local coreHolding = core._lhOwn == nil
		and coreTiming ~= nil
		and coreTiming.phase == "hold"
		and coreTiming.creep == creep
	-- The death estimate (two unit scans) only where it decides something: a core that can take the creep.
	local deathEta = not coreOnWay and Rules.CORE_MAY_TAKE[coreState] and X.DeathEta(bot, creep) or math.huge
	return {
		coreKillsFirst = incomingKills,
		coreState = coreState,
		coreHold = hold or "-",
		coreOnWay = coreOnWay,
		coreOnWayEta = onWayEta,
		coreHolding = coreHolding,
		coreTooLate = Rules.CoreTooLate(coreOthersKill, deathEta, coreEta, coreOnWay),
		coreCanKill = coreOnWay or not coreOthersKill and coreHit > corePredicted,
		myDelay = myDelay,
		coreEta = coreEta,
		deathEta = deathEta,
		predictedHp = predictedHp,
		ourHit = ourHit,
		ourKills = not incomingKills and ourHit > predictedHp,
	}
end

local function backupCoreOf(st)
	local core = st.backupCore
	if core == nil or core:IsNull() or not core:IsAlive() then
		return nil
	end
	return core
end

-- Classify the hit if the bot attacked now (fresh attack: turn, walk, wind-up, flight).
local function classifyNow(bot, st)
	local delay = Fu.GetAttackProDelayTime(bot, st.creep)
	local predictedHp, ourHit, incomingKills, swingKill =
		X.Predict(st.creep, st.damage, delay, X.TowerShotBefore(bot, st.creep, delay))
	local class =
		X.Yield(bot, st.creep, Rules.Classify(predictedHp, ourHit, incomingKills, st.allowEarly), swingKill, delay)
	return class, predictedHp, ourHit
end

-- Per-minute counts for the [SHy-LH] minute summary.
function X.Stats(bot)
	local stats = bot._lhtStats
	if stats == nil then
		stats = {
			since = DotaTime(),
			got = 0,
			missed = 0,
			late = 0,
			early = 0,
			cancelled = 0,
			cancelLost = 0,
			released = 0,
			sureShort = 0,
			stopOk = 0,
			stopFail = 0,
			backup = 0,
			backupGot = 0,
			backupCore = 0,
			walkSkip = 0,
			walkSkipped = {},
		}
		bot._lhtStats = stats
	end
	return stats
end

-- From the laning mode's attempt tracker when an attempt ends. backupResult: nil (not a backup), "took" (the support
-- got it), "core-took" (the core got it: not a miss for the support) or "lost".
function X.NoteResult(bot, got, launch, early, cancels, backupResult)
	local stats = X.Stats(bot)
	if backupResult ~= nil then
		stats.backup = stats.backup + 1
		if backupResult == "took" then
			stats.backupGot = stats.backupGot + 1
		elseif backupResult == "core-took" then
			stats.backupCore = stats.backupCore + 1
			return
		end
	end
	if got then
		stats.got = stats.got + 1
	else
		stats.missed = stats.missed + 1
		if launch < 0 then
			stats.late = stats.late + 1
		end
		if (cancels or 0) > 0 then
			stats.cancelLost = stats.cancelLost + 1
		end
	end
	if early then
		stats.early = stats.early + 1
	end
end

-- One line per bot per minute with any attempt.
function X.LogMinute(bot)
	local stats = bot._lhtStats
	if stats == nil or DotaTime() - stats.since < 60 then
		return
	end
	bot._lhtStats = nil
	if stats.got + stats.missed + stats.cancelled + stats.backup + stats.walkSkip == 0 then
		return
	end
	pcall(
		print,
		string.format(
			"[SHy-LH] t=%.0f %s minute got=%d missed=%d late=%d early=%d cancelled=%d cancel-lost=%d released=%d sure-short=%d stop-ok=%d stop-fail=%d backup=%d backupGot=%d backupCore=%d walk-skip=%d",
			DotaTime(),
			heroName(bot),
			stats.got,
			stats.missed,
			stats.late,
			stats.early,
			stats.cancelled,
			stats.cancelLost,
			stats.released,
			stats.sureShort,
			stats.stopOk,
			stats.stopFail,
			stats.backup,
			stats.backupGot,
			stats.backupCore,
			stats.walkSkip
		)
	)
end

-- A walk-in left out because it lands after the creep's death (counted once per creep per minute), with a throttled
-- [SHy-LH] walk-skip line.
function X.NoteWalkSkip(bot, creep, expect, death, dps, backup)
	local stats = X.Stats(bot)
	if not stats.walkSkipped[creep] then
		stats.walkSkipped[creep] = true
		stats.walkSkip = stats.walkSkip + 1
	end
	bot._lhtLogAt = bot._lhtLogAt or {}
	if DotaTime() < (bot._lhtLogAt.walkSkip or -99) then
		return
	end
	bot._lhtLogAt.walkSkip = DotaTime() + LOG_EVERY
	pcall(
		print,
		string.format(
			"[SHy-LH] t=%.0f %s walk-skip why=too-late creep-hp=%d expect=%.2f death=%.2f dps=%.0f dist=%d backup=%d",
			DotaTime(),
			heroName(bot),
			creep:GetHealth(),
			expect,
			death,
			dps,
			GetUnitToUnitDistance(bot, creep),
			backup and 1 or 0
		)
	)
end

local function throttledLog(bot, key, fmt, ...)
	bot._lhtLogAt = bot._lhtLogAt or {}
	if DotaTime() < (bot._lhtLogAt[key] or -99) then
		return
	end
	bot._lhtLogAt[key] = DotaTime() + LOG_EVERY
	pcall(print, string.format(fmt, ...))
end

-- The core's hit on its way (seconds until it lands), or "-".
local function onWayText(facts)
	return facts.coreOnWayEta ~= nil and string.format("%.2f", facts.coreOnWayEta) or "-"
end

-- [SHy-LH] backup go: why the support attacks behind its core now (BackupDecision's why, the core's state, lead =
-- myEta - coreEta: 0.15 or more when it waited behind the core; onway= the core's hit on its way that does not kill,
-- or -). Throttled per bot.
local function logBackupGo(bot, facts, why, from)
	throttledLog(
		bot,
		"backupgo",
		"[SHy-LH] t=%.0f %s backup go why=%s state=%s hold=%s from=%s coreEta=%.2f myEta=%.2f lead=%.2f death=%.2f onway=%s",
		DotaTime(),
		heroName(bot),
		why,
		facts.coreState,
		facts.coreHold,
		from,
		facts.coreEta,
		facts.myDelay,
		facts.myDelay - facts.coreEta,
		math.min(99, facts.deathEta),
		onWayText(facts)
	)
end

-- [SHy-LH] backup wait: the support waits for its core's hit on its way (why=on-way, onway= when it lands) or for a
-- core holding the creep after stopping its swing (why=core-hold). Other waits are not logged. Throttled per bot.
local function logBackupWait(bot, creep, facts, why, from)
	if why ~= "on-way" and why ~= "core-hold" then
		return
	end
	throttledLog(
		bot,
		"backupwait",
		"[SHy-LH] t=%.0f %s backup wait why=%s from=%s state=%s creep-hp=%d onway=%s coreEta=%.2f myEta=%.2f",
		DotaTime(),
		heroName(bot),
		why,
		from,
		facts.coreState,
		creep:GetHealth(),
		onWayText(facts),
		facts.coreEta,
		facts.myDelay
	)
end

-- The laning Think starts: a state it does not re-arm in this think is dropped by the next Tick.
function X.BeginThink(bot)
	local st = bot._lhTiming
	if st ~= nil then
		st.thinkAt = GameTime()
	end
end

-- Team roam's last-hit overlay (#171, bots/lib/systems/last_hit_overlay.lua, not on main yet) owns a hit while
-- bot._lhOwn is set: from its attack order until the attack is released, the unit dies or 1s passes. It runs after
-- this module in ItemUsageThink, so an order from here would replace its swing. While it owns one: no arm, no order;
-- on the same creep the overlay times it. A plain field read, so this works with or without #171.
-- [SHy-LH] skip why=overlay-owns once per hold (and at most every 3s).
local function overlayOwns(bot)
	local own = bot._lhOwn
	if own == nil then
		bot._lhtOverlaySeen = nil
		return false
	end
	if bot._lhtOverlaySeen ~= own then
		bot._lhtOverlaySeen = own
		local st = bot._lhTiming
		local unit = own.unit
		throttledLog(
			bot,
			"overlay",
			"[SHy-LH] t=%.0f %s skip why=overlay-owns ours=%s same=%s phase=%s",
			DotaTime(),
			heroName(bot),
			st ~= nil and "yes" or "no",
			(st ~= nil and st.creep == unit) and "yes" or "no",
			st ~= nil and st.phase or "-"
		)
	end
	bot._lhTiming = nil
	return true
end
X.OverlayOwns = overlayOwns

-- The laning Think orders (or keeps) a last hit on creep. info = { damage, allowEarly, walk }. Returns the state.
function X.Arm(bot, creep, info)
	if overlayOwns(bot) then
		return nil
	end
	local now = GameTime()
	local st = bot._lhTiming
	if st == nil or st.creep ~= creep then
		st = { creep = creep, cancels = 0, lastAttackSeen = bot:GetLastAttackTime() }
		bot._lhTiming = st
	end
	st.armedAt = now
	st.damage = info.damage
	st.allowEarly = info.allowEarly and X.EarlyAllowed(bot)
	st.backupCore = info.backupCore
	-- "decided": the release is decided and the swing still plays; it stays until the release is seen.
	if
		st.phase == "hold"
		or st.phase == "windup"
		or st.phase == "decided"
		or st.phase == "attack" and not info.walk
	then
		return st
	end
	st.phase = info.walk and "walk" or "attack"
	return st
end

-- True while the frame code owns this creep's hit (wind-up being watched, holding after a cancel, or an attack it
-- ordered): the laning Think then re-arms and issues no order of its own.
function X.Holding(bot, creep)
	local st = bot._lhTiming
	if st == nil or st.creep ~= creep then
		return false
	end
	-- An attack order counts only while the engine still has it (another order may have replaced it).
	return st.phase == "hold"
		or st.phase == "windup"
		or st.phase == "decided"
		or st.phase == "attack" and bot:GetAttackTarget() == creep
end

-- Early swings for this bot: off after the stop orders failed again and again (every early swing would then land
-- on a creep that survives).
local EARLY_OFF_AFTER = 4
function X.EarlyAllowed(bot)
	return not bot._lhtNoEarly
end

-- For other per-frame code: a last hit is being timed now (do not move or re-target the bot).
function X.IsTiming(bot)
	local st = bot._lhTiming
	return st ~= nil and (st.phase == "hold" or st.phase == "windup" or st.phase == "decided")
end

-- The creep (and backup core) of the hit being timed now (X.IsTiming), else nil.
function X.TimedHit(bot)
	if not X.IsTiming(bot) then
		return nil, nil
	end
	local st = bot._lhTiming
	return st.creep, st.backupCore
end

-- The laning Think keeps the hit being timed this think without changing it (a deny passed over for it).
function X.KeepTimed(bot)
	local st = bot._lhTiming
	if st ~= nil then
		st.armedAt = GameTime()
	end
end

function X.Clear(bot)
	bot._lhTiming = nil
end

local function cancelSwing(bot, st, now, pointAt, predictedHp, ourHit, remaining, why)
	-- Which order stops a wind-up is not documented for the bot API: Action_ClearActions(true) first; after two stops
	-- that did not hold (the attack released anyway) and none that did, a move order to where the bot stands.
	local method = "clear"
	if (bot._lhtStopFail or 0) >= 2 and (bot._lhtStopOk or 0) == 0 then
		method = "move"
		bot:Action_MoveToLocation(bot:GetLocation())
	else
		bot:Action_ClearActions(true)
	end
	st.cancels = st.cancels + 1
	st.phase = "hold"
	st.cancelAt = now
	st.cancelPointAt = pointAt
	st.stopPending = method
	st.windupAt = nil
	local stats = X.Stats(bot)
	stats.cancelled = stats.cancelled + 1
	local attempt = bot._lhAttempt
	if attempt ~= nil and attempt.creep == st.creep then
		attempt.cancels = (attempt.cancels or 0) + 1
	end
	throttledLog(
		bot,
		"cancel",
		"[SHy-LH] t=%.0f %s cancel creep-hp=%d predicted=%.0f hit=%.0f remaining=%.2f cycle=%.3f since=%.2f n=%d method=%s why=%s",
		DotaTime(),
		heroName(bot),
		st.creep:GetHealth(),
		predictedHp,
		ourHit,
		remaining,
		bot:GetAnimCycle(),
		now - bot:GetLastAttackTime(),
		st.cancels,
		method,
		why
	)
end

-- recheck: the release was decided at an earlier look ("decided"); this look may only stop it (RECHECK_CANCEL).
local function watchWindup(bot, st, now, recheck)
	local pointTime = bot:GetAttackPoint() / math.max(0.1, bot:GetAttackSpeed())
	if st.windupAt == nil then
		-- Seen this frame, so it started at most one frame ago.
		st.windupAt = now - X.FrameGap(bot) * 0.5
		st.early = nil
	end
	local remaining = st.windupAt + pointTime - now
	local delay = math.max(0, remaining) + X.TravelTime(bot, st.creep)
	local predictedHp, ourHit, incomingKills, swingKill, swings =
		X.Predict(st.creep, st.damage, delay, X.TowerShotBefore(bot, st.creep, delay))
	-- An ally winding up on it that the bot leaves it to (#71, LastHitRules.WindupYield): stopped at the last look.
	local yieldWhy, yieldTo = windupYield(bot, swings, swingKill, delay)
	local core = backupCoreOf(st)
	local facts, nextWhy = nil, nil
	if core ~= nil then
		-- A backup swing: the core's hit still to come and landing before ours counts too, and a core that can still
		-- take it first (its hold, walking in, free next to it) stops ours (LastHitRules.BackupCoreNext).
		facts = X.BackupFacts(bot, core, st.creep, st.damage, delay)
		predictedHp, ourHit, incomingKills = facts.predictedHp, facts.ourHit, facts.coreKillsFirst
		nextWhy = Rules.BackupNextWhy(facts)
	end
	if st.early == nil then
		-- Sure when the swing started: never cancelled.
		st.early = Rules.Classify(predictedHp, ourHit, incomingKills, false) ~= "sure"
	end
	local decision, why = Rules.WindupDecision({
		predictedHp = predictedHp,
		ourHit = ourHit,
		incomingKills = incomingKills,
		remaining = remaining,
		frameGap = X.FrameGap(bot),
		early = st.early,
		backup = core ~= nil,
		coreNext = nextWhy ~= nil,
		coreNextWhy = nextWhy,
		yield = yieldWhy,
	})
	if recheck and not (decision == "cancel" and Rules.RECHECK_CANCEL[why]) then
		return
	end
	if decision == "cancel" and yieldTo ~= nil and why == yieldWhy then
		logYield(bot, st.creep, why, yieldTo, delay, "windup")
	end
	if facts ~= nil and (decision == "cancel" or decision == "release") then
		-- state= the core's state, hold= its own hold (same creep, other unit, -), late= its hit too late (1), coreKill= its
		-- hit kills when it lands (1), onway= its hit on its way (seconds, or -). Releases and cancels are throttled apart:
		-- a cancel at the last look often comes 0.3s after the release line.
		throttledLog(
			bot,
			decision == "cancel" and "backupcancel" or "backup",
			"[SHy-LH] t=%.0f %s backup creep-hp=%d coreEta=%.2f myEta=%.2f lead=%.2f result=%s why=%s state=%s hold=%s late=%d coreKill=%d onway=%s",
			DotaTime(),
			heroName(bot),
			st.creep:GetHealth(),
			facts.coreEta,
			delay,
			delay - facts.coreEta,
			decision,
			why,
			facts.coreState,
			facts.coreHold,
			facts.coreTooLate and 1 or 0,
			facts.coreCanKill and 1 or 0,
			onWayText(facts)
		)
	end
	if decision == "cancel" then
		cancelSwing(bot, st, now, st.windupAt + pointTime, predictedHp, ourHit, remaining, why)
		return
	end
	if decision == "release" then
		st.phase = "decided"
		local stats = X.Stats(bot)
		stats.released = stats.released + 1
		if why == "sure" then
			stats.sureShort = stats.sureShort + 1
		end
		throttledLog(
			bot,
			"release",
			"[SHy-LH] t=%.0f %s release creep-hp=%d predicted=%.0f hit=%.0f remaining=%.2f elapsed=%.2f cycle=%.3f early=%s why=%s",
			DotaTime(),
			heroName(bot),
			st.creep:GetHealth(),
			predictedHp,
			ourHit,
			remaining,
			now - st.windupAt,
			bot:GetAnimCycle(),
			st.early and "yes" or "no",
			why
		)
	end
end

-- After a cancel: did the stop hold, then attack again at the right moment.
local function watchHold(bot, st, now)
	if st.stopPending ~= nil then
		if now <= st.cancelPointAt + 0.1 then
			return
		end
		-- The attack point passed without a release (a release moves the state to "released" in Tick).
		bot._lhtStopOk = (bot._lhtStopOk or 0) + 1
		local stats = X.Stats(bot)
		stats.stopOk = stats.stopOk + 1
		throttledLog(
			bot,
			"stop",
			"[SHy-LH] t=%.0f %s cancel-result stopped=yes method=%s",
			DotaTime(),
			heroName(bot),
			st.stopPending
		)
		st.stopPending = nil
	end
	local core = backupCoreOf(st)
	local restart
	if core ~= nil then
		local facts = X.BackupFacts(bot, core, st.creep, st.damage)
		local decision, why = Rules.BackupDecision(facts)
		-- An allied core winding up on it (core-swing): wait until its hit is out (#71, maintainer 2026-11-23).
		if decision == "go" and X.YieldBackup(bot, st.creep, facts.myDelay) then
			decision = "wait"
		end
		restart = decision == "go" and "sure" or "hold"
		if decision == "go" then
			logBackupGo(bot, facts, why, "hold")
		else
			logBackupWait(bot, st.creep, facts, why, "hold")
		end
	else
		restart = Rules.RestartDecision(classifyNow(bot, st), st.cancels)
	end
	if restart ~= "hold" then
		bot:Action_AttackUnit(st.creep, true)
		st.phase = "attack"
		return
	end
	-- Standing idle, the engine may auto-attack another unit: stop it.
	local target = bot:GetAttackTarget()
	if target ~= nil and target ~= st.creep and bot:GetAnimActivity() == ATTACK_ACTIVITY then
		bot:Action_ClearActions(true)
	end
end

-- Walking in: attack on the frame the hit becomes sure, or early once in range.
local function watchWalk(bot, st)
	local core = backupCoreOf(st)
	if core ~= nil then
		-- A backup hit: only once the core's hit is due to land first (or the core cannot take it).
		local facts = X.BackupFacts(bot, core, st.creep, st.damage)
		local decision, why = Rules.BackupDecision(facts)
		if decision == "go" and not X.YieldBackup(bot, st.creep, facts.myDelay) then
			logBackupGo(bot, facts, why, "walk")
			bot:Action_AttackUnit(st.creep, true)
			st.phase = "attack"
			return true
		end
		logBackupWait(bot, st.creep, facts, why, "walk")
		return false
	end
	local kind = classifyNow(bot, st)
	if kind == "sure" then
		bot:Action_AttackUnit(st.creep, true)
		st.phase = "attack"
		return true
	end
	if
		kind == "early"
		and GetUnitToUnitDistance(bot, st.creep) <= bot:GetAttackRange() + st.creep:GetBoundingRadius()
		and Rules.CanTimeWindup(bot:GetAttackPoint() / math.max(0.1, bot:GetAttackSpeed()), X.FrameGap(bot))
	then
		bot:Action_AttackUnit(st.creep, true)
		st.phase = "attack"
		return true
	end
	return false
end

-- Every frame (ItemUsageThink). Returns true while it owns the bot's order this frame (the caller then issues none).
function X.Tick(bot)
	local now = GameTime()
	noteFrame(bot, now)
	if overlayOwns(bot) then
		return false
	end
	local st = bot._lhTiming
	if st == nil then
		return false
	end
	local creep = st.creep
	if
		bot:GetActiveMode() ~= BOT_MODE_LANING
		-- An enemy tower on us: the tower-aggro step after this hook comes first.
		or bot:WasRecentlyDamagedByTower(1.0)
		-- The last laning Think did not re-arm it (it gave another order: a deny, a harass hit). Before: only when that
		-- Think ran in this same frame, so a Think that ran after the frame's Tick left the walk / attack armed for up to
		-- ARM_MAX_AGE, and the next Tick could replace the Think's deny with the old last-hit attack.
		or (st.thinkAt ~= nil and st.thinkAt > (st.armedAt or -99))
		or now - (st.armedAt or -99) > ARM_MAX_AGE
		or creep == nil
		or creep:IsNull()
		or not creep:IsAlive()
	then
		bot._lhTiming = nil
		return false
	end
	-- Our attack released (GetLastAttackTime moves at the release: game 063's probe read 5-200s since the last attack
	-- while the swing was winding up).
	local lastAttack = bot:GetLastAttackTime()
	if lastAttack > (st.lastAttackSeen or -99) then
		st.lastAttackSeen = lastAttack
		if st.stopPending ~= nil then
			bot._lhtStopFail = (bot._lhtStopFail or 0) + 1
			local stats = X.Stats(bot)
			stats.stopFail = stats.stopFail + 1
			throttledLog(
				bot,
				"stop",
				"[SHy-LH] t=%.0f %s cancel-result stopped=no method=%s",
				DotaTime(),
				heroName(bot),
				st.stopPending
			)
			st.stopPending = nil
			if bot._lhtStopFail >= EARLY_OFF_AFTER and (bot._lhtStopOk or 0) == 0 and not bot._lhtNoEarly then
				bot._lhtNoEarly = true
				pcall(
					print,
					string.format(
						"[SHy-LH] t=%.0f %s early-off stop-fail=%d stop-ok=0",
						DotaTime(),
						heroName(bot),
						bot._lhtStopFail
					)
				)
			end
		end
		st.phase = "released"
		st.windupAt = nil
		return false
	end
	local phase = st.phase
	local swinging = bot:GetAnimActivity() == ATTACK_ACTIVITY and bot:GetAttackTarget() == creep
	if phase == "decided" then
		if swinging then
			-- Looked at again only at the last look before the attack point: an ally or the backup's core may have
			-- started a swing since the release was decided (games 083-085).
			local pointTime = bot:GetAttackPoint() / math.max(0.1, bot:GetAttackSpeed())
			local remaining = st.windupAt ~= nil and st.windupAt + pointTime - now or -1
			if remaining > -X.FrameGap(bot) and Rules.LastLook(remaining, X.FrameGap(bot)) then
				watchWindup(bot, st, now, true)
			end
			return true
		end
		-- The swing stopped before the release (another order, a disable): wait for the next one.
		st.phase = "attack"
		return false
	end
	if phase == "attack" or phase == "windup" then
		-- A new wind-up only once the previous attack's backswing is over: activity 1503 also covers the backswing
		-- (GetLastAttackTime is the release; the next swing can start at release + seconds per attack - wind-up).
		local pointTime = bot:GetAttackPoint() / math.max(0.1, bot:GetAttackSpeed())
		local cooledDown = now - lastAttack >= bot:GetSecondsPerAttack() - pointTime - 0.05
		if swinging and (phase == "windup" or cooledDown) then
			st.phase = "windup"
			watchWindup(bot, st, now)
			return st.phase == "windup" or st.phase == "hold" or st.phase == "decided"
		end
		if phase == "windup" then
			-- The swing stopped without a release (another order, a disable): wait for the next one.
			st.phase = "attack"
			st.windupAt = nil
		end
		return false
	end
	if phase == "hold" then
		watchHold(bot, st, now)
		return true
	end
	if phase == "walk" then
		return watchWalk(bot, st)
	end
	return false
end

return X
