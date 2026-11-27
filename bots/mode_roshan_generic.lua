-- Roshan mode.
local bot = GetBot()
local botName = bot:GetUnitName()
if
	bot == nil
	or bot:IsInvulnerable()
	or not bot:IsHero()
	or not bot:IsAlive()
	or not string.find(botName, "hero")
	or bot:IsIllusion()
then
	return
end
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local KillWindow = require(GetScriptDirectory() .. "/lib/systems/kill_window")
local ObjectiveTravel = require(GetScriptDirectory() .. "/lib/systems/objective_travel")
local HumanOrders = require(GetScriptDirectory() .. "/lib/systems/human_orders")
local CustomLoader = require(GetScriptDirectory() .. "/lib/systems/custom_loader")
local Push = require(GetScriptDirectory() .. "/lib/systems/push")
local PushRules = require(GetScriptDirectory() .. "/lib/systems/push_rules")
local RoshanRules = require(GetScriptDirectory() .. "/lib/systems/roshan_rules")
-- Roshan first (Push.RoshanFirstState, #12): read once per GetDesireHelper; the numbers rule and the call use it.
local aegisFirstNow = false
-- Roshan's HP ratio this think: seen now, or last seen within 10s (RoshanHpSeen); nil when unknown.
local roshRatioNow = nil
local isRoshanAlive = false
Fu.Utils.GameStates = Fu.Utils.GameStates or {}
Fu.Utils.GameStates.roshHandle = Fu.Utils.GameStates.roshHandle or nil
local roshanAliveSince = 0
local wasRoshanAlive = false
local hasEnoughDps = false
local roshan
local hasHumanInTeam = nil
local humanInviteStartTime = 0
local humanInviteCooldownUntil = 0
local humanInviteDuration = 15
local humanInviteCooldown = 3 * 60
local humanInviteCooldownTurbo = 2 * 60
local dipUntil = 0
local nextDipAllowedAt = 0
local dipDuration = 1.5
local dipCooldown = 8
local function AdjustDesireForHealth(desire)
	if botName ~= "npc_dota_hero_huskar" and Fu.ShouldLeaveRoshanFight(bot) then
		bot._roshDipActive = false
		return 0
	end
	-- Tank steps out (#12, game 048 29:07: Sniper stayed at 18% HP with Roshan on him and died to Roshan; under
	-- 50% Roshan HP nobody leaves). Roshan's next 3s would kill him, and Roshan isn't about to die: 3s out, so
	-- Roshan turns to someone else.
	if DotaTime() < (bot._roshStepOutUntil or -999) then
		return 0
	end
	if desire > 0 and Fu.Utils.IsValidUnit(roshan) and roshan:GetAttackTarget() == bot then
		-- Untested on Roshan: fall back to his attack damage over 3s if the estimate fails or reads 0.
		local okD, estimate = pcall(function()
			return roshan:GetEstimatedDamageToTarget(true, bot, 3.0, DAMAGE_TYPE_PHYSICAL)
		end)
		local roshDmg = okD and type(estimate) == "number" and estimate or 0
		if roshDmg <= 0 then
			local secondsPerAttack = roshan:GetSecondsPerAttack() or 1
			roshDmg = (roshan:GetAttackDamage() or 0) * 3 / math.max(0.5, secondsPerAttack)
		end
		if bot:GetHealth() <= roshDmg and Fu.GetHP(roshan) > 0.08 then
			bot._roshStepOutUntil = DotaTime() + 3
			pcall(
				print,
				string.format(
					"[SHy-ROSH] t=%.0f %s step-out hp=%d roshDmg3s=%d roshHp=%.2f",
					DotaTime(),
					(string.gsub(botName, "npc_dota_hero_", "")),
					bot:GetHealth(),
					math.floor(roshDmg),
					Fu.GetHP(roshan)
				)
			)
			return 0
		end
	end
	if desire <= 0 then
		return desire
	end
	if botName == "npc_dota_hero_huskar" then
		return desire
	end
	local hpRatio = Fu.GetHP(bot)
	local isRoshanHurt = Fu.Utils.IsValidUnit(roshan) and Fu.GetHP(roshan) < 0.9
	if bot:WasRecentlyDamagedByAnyHero(2.0) and hpRatio < 0.4 and not isRoshanHurt then
		return desire * RemapValClamped(hpRatio, 0.1, 0.4, 0.0, 0.5)
	end
	local isRoshanTargetingBot = Fu.Utils.IsValidUnit(roshan) and roshan:GetAttackTarget() == bot
	local isNearRoshan = Fu.Utils.IsValidUnit(roshan) and GetUnitToUnitDistance(bot, roshan) < 600
	if hpRatio < 0.5 and isRoshanTargetingBot and DotaTime() > nextDipAllowedAt then
		dipUntil = DotaTime() + dipDuration
		nextDipAllowedAt = DotaTime() + dipCooldown
	end
	bot._roshDipActive = DotaTime() < dipUntil
	if isRoshanHurt and (bot._roshDipActive or isNearRoshan) then
		return math.max(desire, BOT_MODE_DESIRE_HIGH)
	end
	return desire
end
local lastLogTime = 0
local function RoshLog(fmt, ...)
	pcall(
		print,
		string.format(
			"[SHy-ROSH] t=%.0f %s %s " .. fmt,
			DotaTime(),
			GetTeam() == TEAM_DIRE and "dire" or "radiant",
			(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
			...
		)
	)
end
-- One line when this bot's Roshan desire turns on or off, with the reason.
local function LogDesireChange(final)
	local on = final >= 0.3
	if on == (bot._roshOn == true) then
		return
	end
	bot._roshOn = on
	local roshanLocation = Fu.GetCurrentRoshanLocation()
	-- Game 036, 19:56-21:06: four bots stood ~65s at the pit and dropped as even(5v5); the log had
	-- no Roshan HP. roshHp=-1 means no valid handle; hitting = allies whose attack target is Roshan.
	local roshHp, hitting = -1, 0
	if Fu.Utils.IsValidUnit(roshan) then
		roshHp = roshan:GetHealth() / math.max(roshan:GetMaxHealth(), 1)
		for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
			if allyHero ~= nil and allyHero:IsAlive() and allyHero:GetAttackTarget() == roshan then
				hitting = hitting + 1
			end
		end
	end
	RoshLog(
		"%s desire=%.2f why=%s mode=%s dist=%d allies=%d enemies=%d held=%d fit=%s roshHp=%.2f hitting=%d",
		on and "call" or "drop",
		final,
		tostring(bot._roshWhy),
		tostring(bot:GetActiveMode()),
		roshanLocation ~= nil and math.floor(GetUnitToLocationDistance(bot, roshanLocation)) or -1,
		Fu.GetNumOfAliveHeroes(false),
		Fu.GetNumOfAliveHeroes(true),
		bot._roshHeld or 0,
		tostring(bot._roshFitWhy),
		roshHp,
		hitting
	)
end
function GetDesire()
	if ShouldSkipBotThink(GetBot()) then
		return 0
	end
	local rawDesire, gatherCall = GetDesireHelper()
	local final = AdjustDesireForHealth(rawDesire)
	-- A live gather has to beat farm and a one-kill push. VERYHIGH in this engine is ~0.6,
	-- so clamping the call there is why the rest of the team never leaves the lane.
	if type(gatherCall) == "number" then
		-- A human's Roshan order (#222): its own desire, cut as much as the health check above cut the raw one (0: leave).
		final = rawDesire > 0 and gatherCall * math.max(0, math.min(1, final / rawDesire)) or 0
	elseif gatherCall and final >= 0.9 then
		final = 0.96
	else
		final = Clamp(final, 0, BOT_MODE_DESIRE_VERYHIGH)
	end
	if DotaTime() > 3 * 60 and DotaTime() > lastLogTime + 15 then
		lastLogTime = DotaTime()
		log(
			string.format(
				"[ROSH] t=%.0f %s raw=%.2f final=%.2f alive=%s dps=%s kill=%s hg=%s eA=%d aA=%d",
				DotaTime(),
				string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""),
				rawDesire,
				final,
				tostring(Fu.IsRoshanAlive()),
				tostring(hasEnoughDps),
				tostring(isRoshanAlive),
				tostring(Fu.Utils.IsTeamPushingSecondTierOrHighGround(bot)),
				Fu.GetNumOfAliveHeroes(true),
				Fu.GetNumOfAliveHeroes(false)
			)
		)
	end
	LogDesireChange(final)
	-- Read by Push.GetPushDesire (bots/lib/systems/push.lua): a push stays under a live Roshan call (#12).
	bot._roshDesireNow = final
	bot._roshDesireAt = DotaTime()
	-- Do not shout here — desire alone is not a commit (caused "Let's Rosh" then nothing).
	return final
end
local function AllyActiveMode(hero)
	local ok, mode = pcall(function()
		return hero:GetActiveMode()
	end)
	if ok then
		return mode
	end
	return nil
end
-- A low hero (except Huskar) and anyone already defending the ancient are not part of the call.
local function AllyShouldJoin(ally)
	if ally == nil or not ally:IsAlive() or not ally:IsHero() or ally:IsIllusion() then
		return false
	end
	if ally:GetUnitName() ~= "npc_dota_hero_huskar" and Fu.GetHP(ally) < 0.45 then
		return false
	end
	local ancient = GetAncient(GetTeam())
	if ancient ~= nil and GetUnitToUnitDistance(ally, ancient) < 2500 then
		if Fu.Utils.CountEnemyHeroesNear(ancient:GetLocation(), 2500) >= 1 then
			return false
		end
	end
	return true
end
-- grouped: joiners already at the pit or the fountain-side rally.
-- pending: furthest joiner who acked (switched to Roshan) and is still outside that ring.
-- required: allies this call waits for: the ones there, the ones who acked, and, for the first
-- 4s of the call, everyone who could join (they need a think or two to switch).
-- declined: names of allies who did not switch after that, so the call does not wait for them
-- (a core busy defending or farming used to hold the whole group).
local ACK_GRACE = 4
-- ackSet: allies who acked inside the grace. A late joiner (decliner whose own mode ended) is
-- welcome but not waited for: it is neither required nor counted as still walking, so the group
-- that already gathered does not hold for it (it used to, up to the 40s cap).
local function RoshanGather(pit, callAge, ackSet)
	ackSet = ackSet or {}
	local grouped, pending, required = 0, 0, 0
	local declined = {}
	local coming = {}
	local players = GetTeamPlayers(GetTeam())
	for wasRoshanAlive = 1, #players do
		local ally = GetTeamMember(wasRoshanAlive)
		if AllyShouldJoin(ally) then
			local dist = GetUnitToLocationDistance(ally, pit)
			local acked = ally == bot or (ally:IsBot() and AllyActiveMode(ally) == BOT_MODE_ROSHAN)
			local inGrace = (callAge or 0) < ACK_GRACE
			local pid = ally:GetPlayerID()
			if inGrace and (acked or dist <= 1800) then
				ackSet[pid] = true
			end
			if dist <= 1800 then
				grouped = grouped + 1
				required = required + 1
				coming[#coming + 1] = ally
			elseif acked and (inGrace or ackSet[pid]) then
				required = required + 1
				coming[#coming + 1] = ally
				if ally ~= bot and dist > pending then
					pending = dist
				end
			elseif acked then
				-- Late joiner: on its way, not waited for.
				coming[#coming + 1] = ally
			elseif inGrace then
				required = required + 1
				coming[#coming + 1] = ally
			else
				declined[#declined + 1] = (string.gsub(ally:GetUnitName(), "npc_dota_hero_", ""))
			end
		end
	end
	return grouped, pending, required, declined, coming
end
local function GatherMinimum()
	if Fu.IsLateGame() then
		return 2
	elseif Fu.IsMidGame() then
		return 3
	end
	return 4
end
-- A teammate is on the call. That is what pulls the rest of the team. Any distance: it used
-- to count only allies within 2800 of the rally, so heroes further out never joined and the
-- gather sat at grouped=0/5 (game 014).
local function TeamRoshanCall(pit)
	local players = GetTeamPlayers(GetTeam())
	for wasRoshanAlive = 1, #players do
		local ally = GetTeamMember(wasRoshanAlive)
		if ally ~= nil and ally ~= bot and ally:IsAlive() and ally:IsHero() and not ally:IsIllusion() then
			if AllyActiveMode(ally) == BOT_MODE_ROSHAN then
				return true
			end
		end
	end
	return false
end
local function FindRoshan()
	local cachedRoshan = Fu.Utils.GameStates.roshHandle
	if Fu.Utils.IsValidUnit(cachedRoshan) then
		roshan = cachedRoshan
		return
	end
	local neutralCreeps = bot:GetNearbyNeutralCreeps(1600)
	for _, creep in pairs(neutralCreeps) do
		if creep:GetUnitName() == "npc_dota_roshan" then
			roshan = creep
			Fu.Utils.GameStates.roshHandle = creep
			return
		end
	end
end
-- Safe to start/continue Roshan: numbers + pit not contested.
-- finishing=true allows a looser gate when Roshan is already low and allies are in the pit.
-- Enemies that can reach the pit now. One who just respawned is still walking back
-- from the fountain, so the numbers a kill bought last a little past the respawn.
-- Enemies held at their base (user call, game 031, 70:00: Radiant's mega creeps were deep in Dire's
-- base and Radiant farmed the jungle instead of taking Roshan; with 4-5 Dire heroes alive the
-- numbers rule never allowed it). 4+ of our lane creeps within 3000 of the enemy ancient: an enemy
-- hero seen there (within 3500 of it) in the last 5s does not contest Roshan. Cached for 1s.
local heldAt, heldN = -999, 0
local function EnemiesHeldAtBase()
	local now = DotaTime()
	if now - heldAt < 1 then
		return heldN
	end
	heldAt, heldN = now, 0
	bot._roshHeld = 0
	local enemyAncient = GetAncient(GetOpposingTeam())
	if enemyAncient == nil then
		return 0
	end
	local creeps = 0
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS) or {}) do
		if
			unit ~= nil
			and not unit:IsNull()
			and unit:IsAlive()
			and GetUnitToUnitDistance(unit, enemyAncient) <= 3000
		then
			creeps = creeps + 1
		end
	end
	-- Or a lane our creeps press at their T3 or deeper (Push.CreepPressureLanes, #12: that wave pulls them home).
	if creeps < 4 and Push.CreepPressureLanes() < 1 then
		return 0
	end
	for _, pid in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(pid) then
			local info = GetHeroLastSeenInfo(pid)
			local lastSeen = info ~= nil and info[1] or nil
			if
				lastSeen ~= nil
				and lastSeen.time_since_seen <= 5
				and GetUnitToLocationDistance(enemyAncient, lastSeen.location) <= 3500
			then
				heldN = heldN + 1
			end
		end
	end
	bot._roshHeld = heldN
	return heldN
end
local function ContestingEnemies(roshanLocation)
	local alive = Fu.GetNumOfAliveHeroes(true)
	local grace = KillWindow.TransitGrace(roshanLocation)
	local transit = KillWindow.EnemiesInTransit(grace)
	return math.max(0, alive - transit - EnemiesHeldAtBase()), transit
end
-- Numbers rule for a fresh take. Returns ok, why.
local function FreshTakeNumbers(alliesAlive, enemiesAlive, missing)
	-- Roshan first (#12, maintainer 2026-11-22): every enemy alive, their base open and us ahead (or our creeps at their
	-- T3): the Aegis before the high ground, with 4+ of ours and at least their number alive. The pit check
	-- (contested) and the group's HP fit (RoshanRules.GroupFit) still apply.
	if aegisFirstNow and alliesAlive >= 4 and alliesAlive >= enemiesAlive then
		return true, "aegis-first"
	end
	if enemiesAlive >= alliesAlive then
		return false, string.format("even(%dv%d)", alliesAlive, enemiesAlive)
	end
	if enemiesAlive >= 4 and missing < 2 then
		return false, string.format("enemies4(missing=%d)", missing)
	end
	if enemiesAlive >= 3 and alliesAlive - enemiesAlive < 1 and missing < 2 then
		return false, string.format("enemies3(missing=%d)", missing)
	end
	return true, "ok"
end
-- Roshan window call (#12, bots/lib/systems/roshan_window.lua): in an even late game with all of ours alive the team
-- takes Roshan at equal numbers. Every numbers check (the safety check, the fit, the running call) goes through here.
do
	local RoshanWindow = require(GetScriptDirectory() .. "/lib/systems/roshan_window")
	local freshTakeNumbersBase = FreshTakeNumbers
	FreshTakeNumbers = function(alliesAlive, enemiesAlive, missing)
		if RoshanWindow.EvenTakeOk(alliesAlive, enemiesAlive) then
			return true, "rosh-window"
		end
		return freshTakeNumbersBase(alliesAlive, enemiesAlive, missing)
	end
end
-- One line when the clear-finish rule (RoshanRules.FinishClear) keeps a low Roshan going, at most every 5s per bot.
-- src=safe: the pit counted as safe with one ally and no foe; src=hitters / think: allies within 1600 counted as hitters.
local function LogFinishClear(src, allies, foes)
	local now = DotaTime()
	if now < (bot._roshFinishClearLogAt or -999) then
		return
	end
	bot._roshFinishClearLogAt = now + 5
	RoshLog("finish-clear src=%s allies=%d foes=%d roshHp=%.2f", src, allies or 0, foes or 0, roshRatioNow or -1)
end
-- Safe to start/continue Roshan: numbers + pit not contested. Returns ok, why.
local function IsRoshanEngageSafe(roshanLocation, finishing)
	if roshanLocation == nil then
		return false, "no-pit"
	end
	local alliesAlive = Fu.GetNumOfAliveHeroes(false)
	local enemiesAlive = ContestingEnemies(roshanLocation)
	local missing = Fu.Utils.CountMissingEnemyHeroes and Fu.Utils.CountMissingEnemyHeroes() or 0
	local alliesNear = Fu.GetAlliesNearLoc(roshanLocation, 1600) or {}
	local enemiesNear = Fu.GetLastSeenEnemiesNearLoc(roshanLocation, 1600) or {}
	local alliesInPit = #alliesNear
	local enemiesInPit = #enemiesNear
	-- Contested pit: enemies already there in force.
	if enemiesInPit >= 2 and enemiesInPit >= math.max(1, alliesInPit) then
		return false, string.format("contested(%d)", enemiesInPit)
	end
	if finishing then
		-- Finish only if we already own the pit / have numbers.
		if alliesInPit >= 2 and enemiesInPit <= 1 then
			return true, "ok"
		end
		-- Under 30% with at least their number alive and the pit not lost (#12, game 069 24:18: Dire dropped a 28%
		-- Roshan as their numbers flickered; Radiant took the Aegis).
		if
			roshRatioNow ~= nil
			and roshRatioNow < 0.3
			and alliesAlive >= enemiesAlive
			and alliesInPit >= 1
			and enemiesInPit <= alliesInPit
		then
			return true, "ok-low"
		end
		if alliesAlive >= enemiesAlive + 1 and enemiesInPit == 0 then
			return true, "ok"
		end
		-- Low Roshan and no enemy hero near the pit (RoshanRules.FinishClear, #12 game 088: t=1727 Dire 4v5 with Roshan
		-- at 19% and t=1352 Radiant at 35% dropped as finish-unsafe(pit=1 foes=0) and he regenerated): finish him.
		if alliesInPit >= 1 and RoshanRules.FinishClear(roshRatioNow, enemiesInPit) then
			LogFinishClear("safe", alliesInPit, enemiesInPit)
			return true, "ok-clear"
		end
		return false, string.format("finish-unsafe(pit=%d foes=%d)", alliesInPit, enemiesInPit)
	end
	-- Fresh take: need a real numbers edge or missing enemies — never full 5v5.
	return FreshTakeNumbers(alliesAlive, enemiesAlive, missing)
end
-- Roshan's damage per second on `ally`: his own estimate when he can be seen (learned for later), else the last
-- learned value, else RoshanRules.FALLBACK_DPS (measured from the step-out lines).
local function RoshanDpsOn(ally)
	local states = Fu.Utils.GameStates
	if Fu.Utils.IsValidUnit(roshan) and roshan:CanBeSeen() then
		local ok, estimate = pcall(function()
			return roshan:GetEstimatedDamageToTarget(true, ally, 3.0, DAMAGE_TYPE_PHYSICAL)
		end)
		if ok and type(estimate) == "number" and estimate > 0 then
			states.roshDpsSeen = estimate / 3
			return estimate / 3
		end
	end
	return states.roshDpsSeen or RoshanRules.FALLBACK_DPS
end
-- Time the group needs: the GatherMinimum-th closest joiner walks to the rally, then the
-- group kills Roshan. Everyone computes the same number, so the team goes or stays together.
local function TakeTimeNeeded(roshanLocation)
	local rally = Fu.AdjustLocationWithOffsetTowardsFountain(roshanLocation, 900)
	local etas = {}
	local dps = {}
	local players = GetTeamPlayers(GetTeam())
	for wasRoshanAlive = 1, #players do
		local ally = GetTeamMember(wasRoshanAlive)
		if AllyShouldJoin(ally) then
			-- Fastest way there: walk, TP to our tower nearest the pit, or a Twin Gate. Walking
			-- only made an ally across the map look too slow for every kill window.
			local eta = ObjectiveTravel.Eta(ally, rally)
			local secondsPerAttack = ally:GetSecondsPerAttack()
			local hit = (secondsPerAttack ~= nil and secondsPerAttack > 0) and ally:GetAttackDamage() / secondsPerAttack
				or 0
			etas[#etas + 1] = {
				eta = eta,
				dps = hit,
				hp = ally:GetHealth(),
				maxHp = ally:GetMaxHealth(),
				roshDps = RoshanDpsOn(ally),
			}
		end
	end
	if #etas == 0 then
		return 999, 999, 999, {}, 0, 1, 1
	end
	table.sort(etas, function(first, second)
		return first.eta < second.eta
	end)
	local gatherCount = math.min(#etas, GatherMinimum())
	-- Damage of everyone who is coming and arrives within 15s of the gather minimum, not only
	-- the first n. With only the first two, the estimate jumped as soon as the walk started and
	-- the closest heroes changed (game 014: called at need=31, dropped 5s later at need=55;
	-- 19 calls, 19 drops, no Roshan all game).
	local groupDps = 0
	local members = {}
	for wasRoshanAlive = 1, #etas do
		if wasRoshanAlive <= gatherCount or etas[wasRoshanAlive].eta <= etas[gatherCount].eta + 15 then
			groupDps = groupDps + etas[wasRoshanAlive].dps
			members[#members + 1] = etas[wasRoshanAlive]
		end
	end
	local roshHp = 6000 + 130 * math.max(0, DotaTime() / 60)
	local roshMax = roshHp
	if Fu.Utils.IsValidUnit(roshan) and roshan:CanBeSeen() then
		roshHp = roshan:GetHealth()
		roshMax = roshan:GetMaxHealth()
	end
	-- Roshan's armor takes roughly half of right-click damage.
	local killTime = math.max(8, math.min(60, roshHp / math.max(1, groupDps * 0.5)))
	return etas[gatherCount].eta + killTime, etas[gatherCount].eta, killTime, members, groupDps, roshHp, roshMax
end
-- The group coming can tank Roshan to half HP (RoshanRules.GroupFit, #12 game 068). Returns ok, why.
local function GroupFitsTake(roshanLocation)
	local _, _, _, members, groupDps, roshHp, roshMax = TakeTimeNeeded(roshanLocation)
	local ok, why = RoshanRules.GroupFit({ members = members, groupDps = groupDps, roshHp = roshHp, roshMax = roshMax })
	return ok, why, #members
end
-- The same fit with the allies who are at the pit (within 1800) at the commit (#12, game 069 20:17-21:14: the call fit
-- with five, the commit went with 3/5 and they left one by one, Roshan never under 56%). Returns ok, why, count.
local function GroupFitAt(roshanLocation)
	local members, groupDps, names = {}, 0, {}
	local players = GetTeamPlayers(GetTeam())
	for i = 1, #players do
		local ally = GetTeamMember(i)
		if AllyShouldJoin(ally) and GetUnitToLocationDistance(ally, roshanLocation) <= 1800 then
			local secondsPerAttack = ally:GetSecondsPerAttack()
			local hit = (secondsPerAttack ~= nil and secondsPerAttack > 0) and ally:GetAttackDamage() / secondsPerAttack
				or 0
			groupDps = groupDps + hit
			members[#members + 1] = { hp = ally:GetHealth(), maxHp = ally:GetMaxHealth(), roshDps = RoshanDpsOn(ally) }
			names[#names + 1] = string.format(
				"%s:%.2f",
				(string.gsub(ally:GetUnitName(), "npc_dota_hero_", "")),
				ally:GetHealth() / math.max(1, ally:GetMaxHealth())
			)
		end
	end
	local roshMax = 6000 + 130 * math.max(0, DotaTime() / 60)
	local roshHp = roshMax * (roshRatioNow or 1)
	if Fu.Utils.IsValidUnit(roshan) and roshan:CanBeSeen() then
		roshHp, roshMax = roshan:GetHealth(), roshan:GetMaxHealth()
	end
	local ok, why = RoshanRules.GroupFit({ members = members, groupDps = groupDps, roshHp = roshHp, roshMax = roshMax })
	return ok, why .. " members=" .. (#names > 0 and table.concat(names, ",") or "-"), #members
end
-- Roshan's HP ratio: seen now (remembered per team), or last seen within 10s while he is alive (#12, game 069 24:18:
-- every Dire bot stepped out at 28-36%, Roshan dropped out of sight, and the finishing check fell back to the
-- fresh-take numbers, `drop why=even(5v5) roshHp=-1.00`).
local function RoshanHpSeen()
	local states = Fu.Utils.GameStates
	states.roshSeenHp = states.roshSeenHp or {}
	if Fu.Utils.IsValidUnit(roshan) and roshan:CanBeSeen() then
		local ratio = roshan:GetHealth() / math.max(1, roshan:GetMaxHealth())
		states.roshSeenHp[GetTeam()] = { at = DotaTime(), ratio = ratio }
		return ratio
	end
	local seen = states.roshSeenHp[GetTeam()]
	if seen ~= nil and DotaTime() - seen.at <= 10 and Fu.IsRoshanAlive() then
		return seen.ratio
	end
	return nil
end
-- Allies deep in the enemy half in a fight (within 6000 of their Ancient, in attack mode or hit by a hero in the last
-- 3s): a Roshan call leaves them alone there (#12, game 069 22:48: Alchemist and Axe chased up to Dire's mid T3, the
-- other three went to Roshan on a kill-window call, both died). Returns the count and their names.
local function AlliesDeepInEnemyHalf()
	local enemyAncient = GetAncient(GetOpposingTeam())
	if enemyAncient == nil then
		return 0, "-"
	end
	local count, names = 0, {}
	for i = 1, #GetTeamPlayers(GetTeam()) do
		local ally = GetTeamMember(i)
		if
			ally ~= nil
			and ally:IsAlive()
			and GetUnitToUnitDistance(ally, enemyAncient) < 6000
			and (AllyActiveMode(ally) == BOT_MODE_ATTACK or ally:WasRecentlyDamagedByAnyHero(3.0))
		then
			count = count + 1
			names[#names + 1] = (string.gsub(ally:GetUnitName(), "npc_dota_hero_", ""))
		end
	end
	return count, #names > 0 and table.concat(names, ",") or "-"
end
-- A take that only works because of a kill must fit inside that kill's window.
-- Returns ok, why.
local function TakeFitsWindow(roshanLocation)
	local alliesAlive = Fu.GetNumOfAliveHeroes(false)
	local missing = Fu.Utils.CountMissingEnemyHeroes and Fu.Utils.CountMissingEnemyHeroes() or 0
	local killWindowState = KillWindow.Tick()
	-- Count enemies that respawn before the take could be done as alive already. Calling on the
	-- live count alone flipped to "window-short" a second later when two of them were back
	-- (15:12: called with 2 alive, 4 alive next think).
	local need0 = TakeTimeNeeded(roshanLocation)
	local back = KillWindow.RespawningWithin and KillWindow.RespawningWithin(need0) or 0
	local everyone = math.max(0, Fu.GetNumOfAliveHeroes(true) - EnemiesHeldAtBase())
		+ (killWindowState.fresh or 0)
		+ back
	local numbersOk, numbersWhy = FreshTakeNumbers(alliesAlive, everyone, missing)
	if numbersOk then
		local groupOk, groupWhy, coming = GroupFitsTake(roshanLocation)
		if not groupOk then
			return false, groupWhy
		end
		-- With every enemy alive the Aegis take goes with 4+ (not the 2-3 of a kill window).
		if numbersWhy == "aegis-first" and coming < 4 then
			return false, string.format("aegis-first-few(n=%d)", coming)
		end
		return true, (numbersWhy == "aegis-first" and "aegis-first+" or "no-window-needed+") .. groupWhy
	end
	local left = KillWindow.WindowLeft()
	if left == nil then
		-- Only the transit grace is left. Not enough to start a walk.
		return false, "window-closed"
	end
	local window = left + KillWindow.TransitGrace(roshanLocation)
	local need, eta, kill = TakeTimeNeeded(roshanLocation)
	if need + 3 > window then
		return false, string.format("window-short(need=%.0f eta=%.0f kill=%.0f left=%.0f)", need, eta, kill, window)
	end
	-- The group that comes has to tank Roshan to half HP, with 70%+ average HP (#12, game 068: kill-window calls
	-- right after fights; Roshan left at 60% and 78%).
	local groupOk, groupWhy = GroupFitsTake(roshanLocation)
	if not groupOk then
		return false, groupWhy
	end
	return true, string.format("window(need=%.0f left=%.0f)+%s", need, window, groupWhy)
end
-- Looser window check for a call that is already running (own call that passed the full check
-- in the last 20s, or a teammate's call): only drop when the window no longer covers the walk
-- plus 15s of hitting. Re-running the full check every think dropped every call within 1-8s.
local function RunningCallFits(roshanLocation)
	local alliesAlive = Fu.GetNumOfAliveHeroes(false)
	local missing = Fu.Utils.CountMissingEnemyHeroes and Fu.Utils.CountMissingEnemyHeroes() or 0
	local killWindowState = KillWindow.Tick()
	local need0, eta0 = TakeTimeNeeded(roshanLocation)
	local back = KillWindow.RespawningWithin and KillWindow.RespawningWithin(need0) or 0
	if
		FreshTakeNumbers(
			alliesAlive,
			math.max(0, Fu.GetNumOfAliveHeroes(true) - EnemiesHeldAtBase()) + (killWindowState.fresh or 0) + back,
			missing
		)
	then
		return true, "running-no-window-needed"
	end
	local left = KillWindow.WindowLeft()
	if left == nil then
		return false, "running-window-closed"
	end
	local window = left + KillWindow.TransitGrace(roshanLocation)
	if window < eta0 + 15 then
		return false, string.format("running-window-short(eta=%.0f left=%.0f)", eta0, window)
	end
	return true, string.format("running(eta=%.0f left=%.0f)", eta0, window)
end
-- Records why the desire came out as it did, for the [SHy-ROSH] call/abort lines.
local function Ret(desire, why, call)
	bot._roshWhy = why
	return desire, call
end
function GetDesireHelper()
	if
		bot:IsInvulnerable()
		or not bot:IsHero()
		or not bot:IsAlive()
		or not string.find(botName, "hero")
		or bot:IsIllusion()
	then
		return Ret(BOT_MODE_DESIRE_NONE, "invalid")
	end
	local ourAncient = GetAncient(GetTeam())
	if
		Fu.Utils.CountEnemyHeroesOnHighGround(GetTeam()) >= 2
		or ourAncient and Fu.Utils.CountEnemyHeroesNear(ourAncient:GetLocation(), 2500) >= 1
	then
		return Ret(BOT_MODE_DESIRE_NONE, "base-threat")
	end
	if not Fu.Utils.IsValidUnit(roshan) then
		FindRoshan()
	end
	-- Roshan first (#12, Push.RoshanFirstState): read before the numbers rule, which it relaxes.
	local okFirst, firstOn = pcall(Push.RoshanFirstState, bot)
	aegisFirstNow = okFirst and firstOn == true
	local roshanLocation = Fu.GetCurrentRoshanLocation()
	local alliesAlive = Fu.GetNumOfAliveHeroes(false)
	local contestingEnemies = ContestingEnemies(roshanLocation)
	local aliveAllies = {}
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
		if allyHero:IsAlive() then
			table.insert(aliveAllies, allyHero)
		end
	end
	isRoshanAlive = Fu.IsRoshanAlive()
	if isRoshanAlive and not wasRoshanAlive then
		roshanAliveSince = DotaTime()
		wasRoshanAlive = true
	elseif not isRoshanAlive then
		roshanAliveSince = 0
		wasRoshanAlive = false
	end
	-- Re-checked every think. A team that was strong enough once is not strong enough for the rest of the game.
	hasEnoughDps = Fu.HasEnoughDPSForRoshan(aliveAllies)
	if Fu.GetEnemiesAroundAncient(bot, 2000) > 2 or Fu.GetHP(GetAncient(bot:GetTeam())) < 0.6 then
		return Ret(BOT_MODE_DESIRE_NONE, "base-threat")
	end
	-- The human's Roshan call (#222, bots/lib/systems/human_orders.lua). A Roshan ping the team agreed with (the request
	-- checks - too early, outnumbered, too few alive - ran when it was made) still needs the damage and a safe pit, as
	-- before; an insisted ping or `!rosh` goes anyway. Before the early-game and window checks below.
	-- Its desire is the order's (HumanOrders.RoshCalled: a request 0.75, a forced call 0.97, above the team's own gather
	-- at 0.96; game 078), passed as the call so GetDesire does not clamp it to VERYHIGH (0.6), as it did to the 0.95
	-- this returned before.
	local roshCall, roshOrderDesire = false, nil
	-- A human call also counts while Roshan may be up (8-11 min after his death), not only after the 11 minutes
	-- Fu.IsRoshanAlive waits (game 082).
	if isRoshanAlive or HumanOrders.RoshanMaybeUp() then
		roshCall, roshOrderDesire = HumanOrders.RoshCalled(bot)
	end
	if roshCall == "order" or roshCall == "ping" and hasEnoughDps and IsRoshanEngageSafe(roshanLocation, false) then
		return Ret(0.95, roshCall, roshOrderDesire)
	end
	local alliesInPit = #(Fu.GetAlliesNearLoc(roshanLocation, 1600) or {})
	roshRatioNow = RoshanHpSeen()
	local roshLow = roshRatioNow ~= nil and roshRatioNow < 0.8
	-- Early game: no fresh pit. Only stay if Roshan is already low and allies are in it.
	if Fu.IsEarlyGame() and not (roshLow and alliesInPit >= 2 and IsRoshanEngageSafe(roshanLocation, true)) then
		return Ret(BOT_MODE_DESIRE_NONE, "early-game")
	end
	-- Nobody acked this bot's last call: off for 30s, finishing included (game 015, 57:00:
	-- Medusa stayed in a "finishing" Roshan alone and hit him solo while the rest pushed).
	if DotaTime() < (bot._roshNoAckUntil or -999) then
		return Ret(BOT_MODE_DESIRE_NONE, "nobody-acked")
	end
	if roshLow then
		local safeFinish, finishWhy = IsRoshanEngageSafe(roshanLocation, true)
		-- Finishing needs company in the pit, unless he can finish Roshan alone in about 5s.
		local secondsPerAttack = bot:GetSecondsPerAttack()
		local myDps = (secondsPerAttack ~= nil and secondsPerAttack > 0)
				and bot:GetAttackDamage() / secondsPerAttack * 0.5
			or 0
		local soloFinish = Fu.Utils.IsValidUnit(roshan) and roshan:GetHealth() <= myDps * 5
		-- Two hitters at least (#12, game 048 29:10: two allies TP'd out and Sniper and Ringmaster were left to
		-- finish it): allies next to Roshan, not only somewhere in the pit.
		local alliesAtRoshan = Fu.Utils.IsValidUnit(roshan) and #(Fu.GetAlliesNearLoc(roshan:GetLocation(), 900) or {})
			or alliesInPit
		-- Low Roshan and no enemy hero near the pit (RoshanRules.FinishClear, #12 game 088: t=1347 Radiant at 34% and
		-- t=1724 Dire at 18% dropped as few-hitters while the heroes he had hit stood 700-1400 away after a step-out):
		-- allies within 1600 of him count as hitters.
		if alliesAtRoshan < 2 and roshanLocation ~= nil and Fu.Utils.IsValidUnit(roshan) then
			local foesNear = #(Fu.GetLastSeenEnemiesNearLoc(roshanLocation, 1600) or {})
			if RoshanRules.FinishClear(roshRatioNow, foesNear) then
				local wide = #(Fu.GetAlliesNearLoc(roshan:GetLocation(), RoshanRules.FINISH_HITTER_RANGE) or {})
				if wide >= 2 then
					LogFinishClear("hitters", wide, foesNear)
					alliesAtRoshan = wide
				end
			end
		end
		if safeFinish and alliesAtRoshan < 2 and alliesInPit >= 2 and not soloFinish then
			return Ret(BOT_MODE_DESIRE_NONE, "few-hitters")
		end
		if safeFinish and (alliesInPit >= 2 or soloFinish) then
			return Ret(RemapValClamped(roshRatioNow, 0.8, 0.0, 0.9, 1.0), "finishing")
		end
		-- Contested / unsafe finish — do not suicide into the pit.
		return Ret(BOT_MODE_DESIRE_NONE, safeFinish and "finish-no-dps" or finishWhy)
	end
	-- A committed take with the group in the pit keeps going on pit control (the finishing check),
	-- not the fresh-take numbers: at 56:59 a committed 5-man take on full-HP Roshan was dropped
	-- by everyone at once as enemies4(missing=1).
	local committedNow = bot._roshCommitUntil ~= nil and DotaTime() < bot._roshCommitUntil
	-- The commit lasted 25s; after that a group already hitting Roshan in the pit fell back to the
	-- fresh-take numbers and left (game 036, 21:06, drop why=even(5v5) dist=69-299). Extend it
	-- while 3+ allies are in the pit, 2+ are hitting Roshan and no enemy hero is seen near it.
	if committedNow and alliesInPit >= 3 and Fu.Utils.IsValidUnit(roshan) then
		local hitting = 0
		for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES) or {}) do
			if allyHero ~= nil and allyHero:IsAlive() and allyHero:GetAttackTarget() == roshan then
				hitting = hitting + 1
			end
		end
		if
			hitting >= 2
			and #(Fu.GetEnemiesNearLoc(roshanLocation, 1600) or {}) == 0
			and bot._roshCommitUntil - DotaTime() < 8
		then
			bot._roshCommitUntil = DotaTime() + 10
			if DotaTime() >= (bot._roshExtendLogAt or -999) then
				bot._roshExtendLogAt = DotaTime() + 10
				RoshLog(
					"commit-extend hitting=%d inPit=%d roshHp=%.2f",
					hitting,
					alliesInPit,
					roshan:GetHealth() / math.max(roshan:GetMaxHealth(), 1)
				)
			end
		end
	end
	local safeTake, takeWhy = IsRoshanEngageSafe(roshanLocation, committedNow and alliesInPit >= 3)
	if not safeTake then
		return Ret(BOT_MODE_DESIRE_NONE, takeWhy)
	end
	if alliesAlive < contestingEnemies then
		return Ret(BOT_ACTION_DESIRE_NONE, "outnumbered")
	end
	-- A take that only works because of a kill has to fit in that kill's window. Once the
	-- group has committed at the rally, finish the walk in.
	local committed = bot._roshCommitUntil ~= nil and DotaTime() < bot._roshCommitUntil
	local teamCall = isRoshanAlive and hasEnoughDps and TeamRoshanCall(roshanLocation)
	if not committed then
		local running = teamCall or (bot._roshFitOkAt ~= nil and DotaTime() - bot._roshFitOkAt < 20)
		if running then
			local fits, fitWhy = RunningCallFits(roshanLocation)
			bot._roshFitWhy = fitWhy
			if not fits then
				bot._roshFitOkAt = nil
				bot._roshFitFailUntil = DotaTime() + 15
				return Ret(BOT_MODE_DESIRE_NONE, fitWhy)
			end
		else
			-- A take that just failed the window check is not re-called for 15s; the
			-- call-drop-call churn walked the team toward the pit and back several times.
			if DotaTime() < (bot._roshFitFailUntil or -999) then
				return Ret(BOT_MODE_DESIRE_NONE, "recent-window-fail")
			end
			-- No new call while allies fight deep in the enemy half (AlliesDeepInEnemyHalf, game 069 22:48).
			local deep, deepNames = AlliesDeepInEnemyHalf()
			if deep >= 1 then
				if isRoshanAlive and hasEnoughDps and DotaTime() >= (bot._roshDeepLogAt or -999) then
					bot._roshDeepLogAt = DotaTime() + 20
					RoshLog("hold why=allies-deep n=%d names=%s", deep, deepNames)
				end
				return Ret(BOT_MODE_DESIRE_NONE, "allies-deep")
			end
			local fits, fitWhy = TakeFitsWindow(roshanLocation)
			bot._roshFitWhy = fitWhy
			if not fits then
				bot._roshFitFailUntil = DotaTime() + 15
				return Ret(BOT_MODE_DESIRE_NONE, fitWhy)
			end
			bot._roshFitOkAt = DotaTime()
		end
	end
	if teamCall and not bot:WasRecentlyDamagedByAnyHero(2.0) then
		local enemiesHere = bot:GetNearbyHeroes(1000, true, BOT_MODE_NONE) or {}
		if #enemiesHere == 0 then
			return Ret(0.96, "team-call", true)
		end
	end
	local killWindowState = KillWindow.Tick()
	-- The kill window stays open until a respawned enemy could be back at the pit.
	local inTransit = KillWindow.EnemiesInTransit(KillWindow.TransitGrace(roshanLocation))
	local killRosh = (killWindowState.fresh >= 1 or inTransit >= 1)
		and isRoshanAlive
		and hasEnoughDps
		and not Fu.IsEarlyGame()
		and DotaTime() > 8 * 60
	-- Hold a kill-window call for 8s: the fresh-kill / in-transit counts flicker, and a call
	-- dropped as "too-early-no-kill" two seconds later was re-called five seconds after that.
	if killRosh then
		bot._roshKillLatchUntil = DotaTime() + 8
	elseif isRoshanAlive and hasEnoughDps and DotaTime() < (bot._roshKillLatchUntil or -999) then
		killRosh = true
	end
	if hasHumanInTeam == nil then
		hasHumanInTeam = Fu.Utils.IsHumanPlayerInTeam(GetTeam())
	end
	if hasHumanInTeam and not killRosh then
		if Fu.IsEarlyGame() then
			return Ret(BOT_ACTION_DESIRE_NONE, "early-game")
		end
		if DotaTime() < humanInviteCooldownUntil then
			return Ret(BOT_ACTION_DESIRE_NONE, "human-cooldown")
		end
		-- A Roshan ping the team agreed with, an insisted one or `!rosh` (#222, bots/lib/systems/human_orders.lua).
		local isPingAtRoshan = HumanOrders.RoshCalled(bot)
		if not isPingAtRoshan then
			-- Soft invite without shouting: quiet staging desire only while safe.
			-- Old behavior announced then dropped after 15s — looked like false invites.
			if Fu.IsRoshanAlive() and hasEnoughDps then
				if humanInviteStartTime == 0 then
					humanInviteStartTime = DotaTime()
				end
				local inviteAge = DotaTime() - humanInviteStartTime
				if inviteAge < humanInviteDuration then
					return Ret(BOT_MODE_DESIRE_LOW, "human-invite")
				else
					humanInviteStartTime = 0
					humanInviteCooldownUntil = DotaTime()
						+ (Fu.IsModeTurbo() and humanInviteCooldownTurbo or humanInviteCooldown)
					return Ret(BOT_MODE_DESIRE_NONE, "human-invite-expired")
				end
			else
				humanInviteStartTime = 0
			end
		else
			humanInviteStartTime = 0
			humanInviteCooldownUntil = 0
		end
	end
	if isRoshanAlive and hasEnoughDps then
		if DotaTime() < (Fu.IsModeTurbo() and 15 * 60 or 20 * 60) and not killRosh then
			return Ret(BOT_MODE_DESIRE_NONE, "too-early-no-kill")
		end
		local timeFactor = RemapValClamped(DotaTime(), roshanAliveSince, roshanAliveSince + 2.5 * 60, 1, 2)
		local desire = RemapValClamped(GetRoshanDesire() * timeFactor, 0, 1, 0, BOT_MODE_DESIRE_ABSOLUTE)
		local alliesNearPit = Fu.GetAlliesNearLoc(roshanLocation, 1600)
		if #alliesNearPit >= 4 then
			desire = 0.9
		end
		local isPushingHighGround = Fu.Utils.IsTeamPushingSecondTierOrHighGround(bot)
		if isPushingHighGround and #alliesNearPit < 3 then
			desire = desire * 0.6
		end
		local why = "timer"
		-- Creep pressure (#12, maintainer idea 2026-11-22): our waves at their T3 or deeper pull their heroes home;
		-- +0.1 per lane, at most +0.2, after every check above. The applied value is what the line prints (the
		-- non-call desire is clamped to VERYHIGH below and in GetDesire).
		local pressureLanes, pressureNames = Push.CreepPressureLanes()
		if pressureLanes >= 1 then
			local before = Clamp(desire, 0, BOT_MODE_DESIRE_VERYHIGH)
			desire = desire + PushRules.CreepPressureBonus(pressureLanes)
			local applied = Clamp(desire, 0, BOT_MODE_DESIRE_VERYHIGH) - before
			if
				(pressureLanes ~= bot._roshPressureLanes or DotaTime() >= (bot._roshPressureLogAt or -999))
				and not Fu.IsMeepoClone(bot)
			then
				bot._roshPressureLanes = pressureLanes
				bot._roshPressureLogAt = DotaTime() + 20
				RoshLog(
					"pressure lanes=%d which=%s bonus=%.2f desire=%.2f",
					pressureLanes,
					pressureNames,
					applied,
					desire
				)
			end
			why = "timer+pressure"
		else
			bot._roshPressureLanes = 0
		end
		-- Roshan first (#12, maintainer 2026-11-22): every enemy alive, their base open, Roshan up: a gather call (the
		-- same 0.92 as a kill-window take, so the push yields in push.lua), also while the team is on the high ground,
		-- which is what it replaces. The fit above already passed (numbers, group HP, tanking).
		if
			aegisFirstNow
			and not killRosh
			and DotaTime() - (bot._finishTowerAt or -999) > 2
			and not bot:WasRecentlyDamagedByAnyHero(2.0)
			and #(bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE) or {}) == 0
		then
			return Ret(0.92, "aegis-first", true)
		end
		if killRosh then
			local floor = BOT_MODE_DESIRE_VERYHIGH
			if desire < floor then
				KillWindow.LogRosh(bot, desire, floor, killWindowState)
				desire = floor
			end
			why = "kill-window"
			-- A take that fits the kill's window (checked above) is a call the team should answer (#12, game 067
			-- 32:11: the four callers sat at 0.60 under a 0.99 kill push and nobody walked; game 066: 7 calls dropped
			-- nobody-acked). Out of a fight it goes in as a gather call (0.96, above the 0.91 kill push; the push
			-- yields to it in push.lua). Not while the team pushes the T2 / high ground away from the pit, not with every
			-- enemy dead (#87's wipe push stays above Roshan: game 045, Dire left a 3-vs-0 push for Roshan), and not while
			-- this bot finishes a tower (push.lua sets _finishTowerAt).
			if
				not (isPushingHighGround and #alliesNearPit < 3)
				and Fu.GetNumOfAliveHeroes(true) > 0
				and DotaTime() - (bot._finishTowerAt or -999) > 2
				and not bot:WasRecentlyDamagedByAnyHero(2.0)
				and #(bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE) or {}) == 0
			then
				return Ret(0.92, why, true)
			end
		end
		return Ret(Clamp(desire, 0, BOT_MODE_DESIRE_VERYHIGH), why)
	end
	return Ret(BOT_ACTION_DESIRE_NONE, isRoshanAlive and "no-dps" or "rosh-dead")
end
local rallyOffset = 900
local pitAttackDistance = 300
function Think()
	if OhaCastGuard ~= nil and OhaCastGuard(GetBot()) then
		return
	end
	if not bot:IsAlive() or Fu.CanNotUseAction(bot) then
		return
	end
	if Fu.Item.TryPickupRoshanDrop(bot) then
		return
	end
	local roshanLocation = Fu.GetCurrentRoshanLocation()
	if roshanLocation == nil then
		return
	end
	if Fu.ShouldLeaveRoshanFight(bot) then
		local away = Fu.AdjustLocationWithOffsetTowardsFountain(roshanLocation, 1600)
		bot:Action_MoveToLocation(away)
		return
	end
	if bot._roshDipActive then
		local dipLocation = Fu.AdjustLocationWithOffsetTowardsFountain(roshanLocation, 300)
		bot:Action_MoveToLocation(dipLocation)
		return
	end
	if not Fu.Utils.IsValidUnit(roshan) then
		FindRoshan()
	end
	local distanceToPit = GetUnitToLocationDistance(bot, roshanLocation)
	local isInPit = distanceToPit <= pitAttackDistance
	local finishing = Fu.Utils.IsValidUnit(roshan) and Fu.GetHP(roshan) < 0.9
	local safe = IsRoshanEngageSafe(roshanLocation, finishing)
	local function MoveToPit()
		bot:Action_MoveToLocation(roshanLocation)
	end
	local function AttackRoshanOrMove()
		if isInPit and Fu.Utils.IsValidUnit(roshan) and Fu.CanBeAttacked(roshan) then
			bot:Action_AttackUnit(roshan, true)
		else
			MoveToPit()
		end
	end
	local rally = Fu.AdjustLocationWithOffsetTowardsFountain(roshanLocation, rallyOffset)
	local pitAllies = Fu.GetAlliesNearLoc(roshanLocation, 700) or {}
	local pitCount = 0
	for _, ally in pairs(pitAllies) do
		if Fu.IsValidHero(ally) and ally:IsAlive() and not ally:IsIllusion() then
			pitCount = pitCount + 1
		end
	end
	local now = DotaTime()
	-- After this bot's drop (nobody-acked, weak-group, commit-fit: bot._roshNoAckUntil), or while GetDesire's last answer
	-- was 0, decide nothing here and walk out (#12). The engine keeps the mode until another mode's desire is higher,
	-- and Think can run before GetDesire answers again: game 087 printed `drop why=weak-group` 47 times in 1147-1151;
	-- game 088 printed drops twice in a second (t=1178 abyssal_underlord commit-fit, t=1596 rubick and winter_wyvern,
	-- t=1727 dark_willow weak-group) and Sven committed 3/3 at t=1736, one second after all five Radiant bots dropped as
	-- base-threat. The old guard keyed on bot._roshWhy == "nobody-acked", which only GetDesire sets. A human's Roshan
	-- order still gets through: GetDesire answers it above 0 (bot._roshWhy is then "order" or "ping").
	local humanOrder = bot._roshWhy == "order" or bot._roshWhy == "ping"
	local dropped = now < (bot._roshNoAckUntil or -999)
	local answeredZero = now - (bot._roshFinalAt or -999) <= 2 and (bot._roshFinal or 0) <= 0
	if not humanOrder and (dropped or answeredZero) then
		bot._roshCommitUntil = nil
		if now >= (bot._roshHoldLogAt or -999) then
			bot._roshHoldLogAt = now + 10
			RoshLog(
				"think-hold why=%s last=%s left=%.0f",
				dropped and "dropped" or "desire0",
				tostring(bot._roshWhy),
				dropped and bot._roshNoAckUntil - now or 0
			)
		end
		bot:Action_MoveToLocation(Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 400))
		return
	end
	-- Low Roshan and no enemy hero near the pit (RoshanRules.FinishClear, #12 game 088): allies within 1600 of the pit
	-- count as the group, so the heroes he stepped out from do not turn the finish back into a gather (whose
	-- weak-group drop ended Dire's take at t=1727 with Roshan at 19%).
	if finishing and safe and pitCount < 2 then
		local foesNear = #(Fu.GetLastSeenEnemiesNearLoc(roshanLocation, 1600) or {})
		if RoshanRules.FinishClear(roshRatioNow, foesNear) then
			local wide = 0
			for _, ally in pairs(Fu.GetAlliesNearLoc(roshanLocation, RoshanRules.FINISH_HITTER_RANGE) or {}) do
				if Fu.IsValidHero(ally) and ally:IsAlive() and not ally:IsIllusion() then
					wide = wide + 1
				end
			end
			if wide >= 2 then
				LogFinishClear("think", wide, foesNear)
				pitCount = wide
			end
		end
	end
	-- Fight is already going with a group in the pit. Join it.
	if finishing and pitCount >= 2 and safe then
		AttackRoshanOrMove()
		return
	end
	-- A gank on the rally must not leave them idle. Fight if the local fight is ours,
	-- otherwise step toward the fountain instead of holding the spot.
	local function RallyThreat()
		local enemy = nil
		local enemyDist = 1200
		local near = Fu.GetEnemyList(bot, 1200) or {}
		for _, hero in pairs(near) do
			if Fu.IsValidHero(hero) then
				local dist = GetUnitToUnitDistance(bot, hero)
				if dist < enemyDist then
					enemy = hero
					enemyDist = dist
				end
			end
		end
		local seenLoc = nil
		local seenDist = 1400
		for _, pid in pairs(GetTeamPlayers(GetOpposingTeam())) do
			if IsHeroAlive(pid) then
				local info = GetHeroLastSeenInfo(pid)
				local spot = info and info[1]
				if spot ~= nil and spot.time_since_seen < 2.5 then
					local dist = GetUnitToLocationDistance(bot, spot.location)
					if dist < seenDist then
						seenLoc = spot.location
						seenDist = dist
					end
				end
			end
		end
		local hit = bot:WasRecentlyDamagedByAnyHero(2.0)
		if enemy == nil and seenLoc == nil and not hit then
			return false
		end
		local allies = #(Fu.GetAlliesNearLoc(bot:GetLocation(), 1200) or {})
		if allies < 1 then
			allies = 1
		end
		local threats = #near
		if seenLoc ~= nil then
			threats = math.max(threats, 1)
		end
		local run = threats > allies or not Fu.WeAreStronger(bot, 1200)
		bot._roshThinkAt = DotaTime() - 4
		if run then
			local away = Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 700)
			if enemy ~= nil then
				away = Fu.VectorAway(bot:GetLocation(), enemy:GetLocation(), 600)
				away = (away + Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 400)) / 2
			elseif seenLoc ~= nil then
				away = Fu.VectorAway(bot:GetLocation(), seenLoc, 600)
			end
			bot:Action_MoveToLocation(away)
			return true
		end
		if enemy ~= nil then
			if enemyDist <= bot:GetAttackRange() + 150 then
				bot:Action_AttackUnit(enemy, true)
			else
				bot:Action_MoveToLocation(enemy:GetLocation())
			end
			return true
		end
		if seenLoc ~= nil or hit then
			bot:Action_MoveToLocation(Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 400))
			return true
		end
		return false
	end
	if RallyThreat() then
		return
	end
	-- Hold the fountain side until the living team is in the ring, then go in together.
	-- Two at the rally used to count as ready, so the rest never had to arrive.
	-- A gap of more than 3s out of Roshan mode restarts the gather, but not during a commit: game
	-- 017, 41:42, Doom, Lich, Mirana and Medusa committed 4/4, Doom left the mode for a few
	-- seconds in the pit, the restart wiped his commit and acks, and 4s later he dropped the take
	-- as a weak group with Lich counted as declined (then Lich did the same to Doom and Mirana).
	local stillCommitted = bot._roshCommitUntil ~= nil and now < bot._roshCommitUntil
	if bot._roshGatherAt == nil or (now - (bot._roshThinkAt or 0) > 3 and not stillCommitted) then
		bot._roshGatherAt = now
		bot._roshCommitUntil = nil
		bot._roshAckSet = {}
	end
	bot._roshThinkAt = now
	bot._roshAckSet = bot._roshAckSet or {}
	-- (A drop of this bot holds Think above: the think-hold guard.)
	local grouped, pending, required, declined, coming =
		RoshanGather(roshanLocation, now - bot._roshGatherAt, bot._roshAckSet)
	local elapsed = now - bot._roshGatherAt
	-- Nobody else acked: drop the call (no solo Roshan) and do not re-call for 30s.
	if elapsed >= ACK_GRACE and required < 2 then
		if now >= (bot._roshNoAckUntil or -999) then
			RoshLog("drop why=nobody-acked declined=%s", #declined > 0 and table.concat(declined, ",") or "-")
		end
		bot._roshNoAckUntil = now + 30
		-- Stop hitting Roshan alone: the last order (attack) would keep running.
		bot:Action_MoveToLocation(Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 400))
		return
	end
	-- The allies who acked are not enough to kill Roshan (the desire check counts every living
	-- ally, decliners included): drop and do not re-call for 30s. Not once committed.
	if
		elapsed >= ACK_GRACE
		and not (bot._roshCommitUntil ~= nil and now < bot._roshCommitUntil)
		and not Fu.HasEnoughDPSForRoshan(coming)
	then
		bot._roshNoAckUntil = now + 30
		RoshLog(
			"drop why=weak-group coming=%d declined=%s",
			#coming,
			#declined > 0 and table.concat(declined, ",") or "-"
		)
		bot:Action_MoveToLocation(Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 400))
		return
	end
	local othersWalking = pending > 1800
	local minimum = math.min(GatherMinimum(), math.max(required, 1))
	-- Aegis first (every enemy alive): the take goes in with 4 there (or everyone who is coming), not the 2-3 of a kill
	-- window or the 40s cap.
	local minimumCap = 2
	if aegisFirstNow then
		minimum = math.max(minimum, math.min(4, math.max(required, 1)))
		minimumCap = minimum
	end
	local full = required > 0 and grouped >= required
	local committed = bot._roshCommitUntil ~= nil and now < bot._roshCommitUntil
	-- A short wait lets allies switch into the call. After that, the minimum group goes
	-- in as soon as nobody else is still walking. The old flat 22s wait was where kill
	-- windows ran out and the whole group walked away again.
	local arrived = not othersWalking and grouped >= minimum and elapsed >= 6
	-- Waiting for a straggler would outlast the kill window: go with who is here.
	local windowTight = false
	local left = KillWindow.WindowLeft()
	if othersWalking and grouped >= minimum and left ~= nil then
		local _, _, killTime = TakeTimeNeeded(roshanLocation)
		local window = left + KillWindow.TransitGrace(roshanLocation)
		windowTight = window < pending / 320 + killTime + 3
	end
	local capped = elapsed >= 40 and grouped >= math.min(minimumCap, math.max(required, 1))
	-- The group at the pit has to tank Roshan to half HP (GroupFitAt, #12 game 069 20:17-21:14). While others still
	-- walk in it waits for them; with nobody left to come (or the window or the 40s cap forcing it) the call drops.
	-- The fit's numbers go on the commit line (#12, game 087: 3 of 4 committed takes left Roshan at 61-92%), with each
	-- member's HP (members=name:hp): game 088's two commits set RoshanRules.HALF_CREDIT to 1.0, and the members list
	-- is the data a per-member model (who Roshan hits first, how long each lasts) would need.
	local commitFit = finishing and "finishing" or "-"
	if safe and not committed and not finishing and (full or arrived or windowTight or capped) then
		local fitOk, fitWhy, atPit = GroupFitAt(roshanLocation)
		commitFit = fitWhy
		if not fitOk then
			if othersWalking and not (windowTight or capped) then
				full, arrived = false, false
				if now >= (bot._roshCommitWaitLogAt or -999) then
					bot._roshCommitWaitLogAt = now + 5
					RoshLog("commit-wait why=%s atPit=%d grouped=%d/%d", fitWhy, atPit, grouped, required)
				end
			else
				RoshLog("drop why=commit-fit %s atPit=%d grouped=%d/%d", fitWhy, atPit, grouped, required)
				bot._roshNoAckUntil = now + 20
				bot:Action_MoveToLocation(Fu.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 400))
				return
			end
		end
	end
	if safe and (full or arrived or windowTight or capped) then
		local fresh = not committed
		bot._roshCommitUntil = now + 25
		committed = true
		if fresh then
			RoshLog(
				"commit grouped=%d/%d min=%d pending=%d elapsed=%.0f by=%s fit=%s",
				grouped,
				required,
				minimum,
				math.floor(pending),
				elapsed,
				full and "full" or (arrived and "arrived" or (windowTight and "window" or "cap")),
				tostring(commitFit)
			)
		end
	end
	local ready = safe and (committed or full or arrived or windowTight or capped)
	if not ready and now >= (bot._roshGatherLogAt or -999) then
		bot._roshGatherLogAt = now + 5
		local _, safeWhy = IsRoshanEngageSafe(roshanLocation, finishing)
		RoshLog(
			"gather grouped=%d/%d min=%d pending=%d elapsed=%.0f safe=%s window=%s declined=%s",
			grouped,
			required,
			minimum,
			math.floor(pending),
			elapsed,
			safe and "ok" or tostring(safeWhy),
			left ~= nil and string.format("%.0f", left) or "-",
			#declined > 0 and table.concat(declined, ",") or "-"
		)
	end
	if not ready then
		bot._roshCommitUntil = nil
		if GetUnitToLocationDistance(bot, rally) > 50 then
			if not ObjectiveTravel.Go(bot, rally, "roshan") then
				bot:Action_MoveToLocation(rally + RandomVector(80))
			end
		end
		if elapsed < 2 then
			local myId = bot:GetPlayerID()
			local caller = true
			local players = GetTeamPlayers(GetTeam())
			for wasRoshanAlive = 1, #players do
				local ally = GetTeamMember(wasRoshanAlive)
				if
					ally ~= nil
					and ally ~= bot
					and ally:IsAlive()
					and not ally:IsIllusion()
					and AllyActiveMode(ally) == BOT_MODE_ROSHAN
					and ally:GetPlayerID() < myId
				then
					caller = false
					break
				end
			end
			if caller then
				Fu.ModeAnnounce(bot, "say_roshan", 20, true)
			end
		end
		return
	end
	if not isInPit then
		MoveToPit()
		return
	end
	if Fu.Utils.IsValidUnit(roshan) and Fu.CanBeAttacked(roshan) then
		bot:Action_AttackUnit(roshan, true)
	else
		bot:Action_MoveToLocation(roshanLocation + RandomVector(50))
	end
end

-- [SHy-ERROR] trap (roshan). From ~11:20 every game an unwrapped entry point fails and the engine only
-- prints "Script Runtime Error: error in error handling" (its handler cannot run, typically a stack
-- overflow), then squelches it after 10 copies. Caught here and printed with its name, up to 3 times
-- per entry point per bot; the failing call still just stops, as before.
local OHA_TRAP_COUNT = {}
local function OHA_Trap(name, fn, fallback)
	if type(fn) ~= "function" then
		return fn
	end
	return function(...)
		local res = { pcall(fn, ...) }
		if res[1] then
			return unpack(res, 2)
		end
		local errorCount = (OHA_TRAP_COUNT[name] or 0) + 1
		OHA_TRAP_COUNT[name] = errorCount
		if errorCount <= 3 then
			local hero = "?"
			pcall(function()
				hero = GetBot():GetUnitName()
			end)
			pcall(print, string.format("[SHy-ERROR] t=%.1f %s %s: %s", DotaTime(), hero, name, tostring(res[2])))
		end
		return fallback
	end
end
GetDesire = OHA_Trap("ROSHAN_GetDesire", GetDesire, 0)
Think = OHA_Trap("ROSHAN_Run", Think, nil)
-- [SHy-PERF] timing (#52): bots/lib/systems/perf.lua
do
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	GetDesire = Perf.Wrap("roshan.GetDesire", GetDesire)
	Think = Perf.Wrap("roshan.Think", Think)
end
-- Strength push (#12, bots/lib/systems/strength_push.lua): while a strength push waits for the Aegis (Roshan first),
-- the Roshan desire of its bots is raised when the mode passed its safety checks but would not call the take itself.
-- Log [SHy-ROSH] strength-boost.
do
	local StrengthPush = require(GetScriptDirectory() .. "/lib/systems/strength_push")
	local roshanGetDesire = GetDesire
	GetDesire = function(...)
		return StrengthPush.RoshanDesire(bot, roshanGetDesire(...))
	end
end
-- Roshan window (#12, bots/lib/systems/roshan_window.lua): the pit peek in the respawn window (its own desire and
-- walk, before the gather logic) and the even late-game call raised to gather strength.
-- Logs [SHy-ROSH] rosh-peek, rosh-window.
do
	local RoshanWindow = require(GetScriptDirectory() .. "/lib/systems/roshan_window")
	local roshanGetDesire, roshanThink = GetDesire, Think
	GetDesire = function(...)
		return RoshanWindow.Desire(bot, roshanGetDesire(...))
	end
	Think = function(...)
		if RoshanWindow.Think(bot) then
			return
		end
		return roshanThink(...)
	end
end
-- The answer the engine gets (after the strength-push and Roshan-window raises above), read by Think's think-hold
-- guard: no commit or gather while the last answer was 0 (#12, game 088 t=1736).
do
	local roshanGetDesire = GetDesire
	GetDesire = function(...)
		local desire = roshanGetDesire(...)
		bot._roshFinal = type(desire) == "number" and desire or 0
		bot._roshFinalAt = DotaTime()
		return desire
	end
end
