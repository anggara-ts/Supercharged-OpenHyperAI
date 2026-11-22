-- Dark Willow: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/FuncLib/systems/ability_context")
local Minion = require(GetScriptDirectory() .. "/FuncLib/hero/minion")
local InterruptRules = require(GetScriptDirectory() .. "/FuncLib/systems/interrupt_rules")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 0, 10 }, ["t20"] = { 0, 10 }, ["t15"] = { 0, 10 }, ["t10"] = { 10, 0 } }
local tAllAbilityBuildList = { { 1, 2, 2, 3, 2, 4, 2, 1, 1, 1, 4, 3, 3, 3, 4 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 68,649 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_tranquil_boots",
	"item_cyclone",
	"item_blink",
	"item_aghanims_shard",
	"item_essence_distiller",
	"item_moon_shard",
	"item_wind_waker",
	"item_sheepstick",
	"item_aeon_disk",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 66,614 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_tranquil_boots",
	"item_cyclone",
	"item_blink",
	"item_aghanims_shard",
	"item_essence_distiller",
	"item_sheepstick",
	"item_moon_shard",
	"item_aeon_disk",
	"item_wind_waker",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 1,096 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_double_branches",
	"item_circlet",
	"item_magic_stick",
	"item_null_talisman",
	"item_magic_wand",
	"item_power_treads",
	"item_blink",
	"item_ultimate_scepter",
	"item_moon_shard",
	"item_ultimate_scepter_2",
	"item_witch_blade",
	"item_force_staff",
	"item_mask_of_madness",
	"item_monkey_king_bar",
	"item_hurricane_pike",
	"item_aghanims_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1 has 718 matches, built from pos 2 (5,844) (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_circlet",
	"item_mantle",
	"item_null_talisman",
	"item_magic_wand",
	"item_power_treads",
	"item_blink",
	"item_ultimate_scepter",
	"item_witch_blade",
	"item_moon_shard",
	"item_black_king_bar",
	"item_ultimate_scepter_2",
	"item_hydras_breath",
	"item_bloodthorn",
	"item_devastator",
	"item_aghanims_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 5,844 matches (Util/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_circlet",
	"item_mantle",
	"item_null_talisman",
	"item_magic_wand",
	"item_power_treads",
	"item_blink",
	"item_ultimate_scepter",
	"item_witch_blade",
	"item_moon_shard",
	"item_black_king_bar",
	"item_ultimate_scepter_2",
	"item_hydras_breath",
	"item_bloodthorn",
	"item_devastator",
	"item_aghanims_shard",
}
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_ultimate_scepter", "item_magic_wand" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_antimage" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
X["bDeafaultAbility"] = false
X["bDeafaultItem"] = false
function X.MinionThink(hMinionUnit)
	Minion.MinionThink(hMinionUnit)
end
local ShadowRealmRules = require(GetScriptDirectory() .. "/FuncLib/systems/shadow_realm_rules")
local brambleMazeAbility =
	SafeAbility(bot:GetAbilityByName("dark_willow_bramble_maze"), "dark_willow_bramble_maze", "dark_willow")
local shadowRealmAbility =
	SafeAbility(bot:GetAbilityByName("dark_willow_shadow_realm"), "dark_willow_shadow_realm", "dark_willow")
local cursedCrownAbility =
	SafeAbility(bot:GetAbilityByName("dark_willow_cursed_crown"), "dark_willow_cursed_crown", "dark_willow")
local bedlamAbility = SafeAbility(bot:GetAbilityByName("dark_willow_bedlam"), "dark_willow_bedlam", "dark_willow")
local terrorizeAbility =
	SafeAbility(bot:GetAbilityByName("dark_willow_terrorize"), "dark_willow_terrorize", "dark_willow")
local brambleMazeDesire, brambleMazeLocation
local shadowRealmDesire
local cursedCrownDesire, cursedCrownTarget
local bedlamDesire
local terrorizeDesire, terrorizeLocation
local lastBedlamTime = 0
local lastTerrorizeTime = 0
local botTarget
local isGoingOnSomeone
local isRetreating
local hpRatio
local isInTeamFight
-- Shadow Realm hold (#48): runs inside the realm, even when the item think counts her as invulnerable
-- (bThinkWhileInvulnerable lets only this tick run then).
X["bThinkWhileInvulnerable"] = true
function X.SkillsComplement()
	local okRealm, realmOrder = pcall(X.ShadowRealmTick)
	if not okRealm then
		X.LogRealmError(realmOrder)
	end
	if okRealm and realmOrder or bot:IsInvulnerable() then
		return
	end
	local context = AbilityContext.Build(bot)
	isGoingOnSomeone = context.isEngaging
	isRetreating = context.isRetreating
	hpRatio = context.hp
	isInTeamFight = context.isTeamFight
	X.TrackEnemyTeleports()
	if Fu.CanNotUseAbility(bot) then
		return
	end
	brambleMazeDesire, brambleMazeLocation = X.ConsiderBrambleMaze()
	if brambleMazeDesire > 0 then
		bot:Action_UseAbilityOnLocation(brambleMazeAbility, brambleMazeLocation)
		return
	end
	-- Terrorize is considered before Bedlam: casting one puts the other on cooldown (shared levels
	-- and cooldown), and Bedlam fired on any enemy near Dark Willow in a fight, so the fear was
	-- almost never cast.
	terrorizeDesire, terrorizeLocation = X.ConsiderTerrorize()
	if terrorizeDesire > 0 then
		bot:Action_UseAbilityOnLocation(terrorizeAbility, terrorizeLocation)
		lastTerrorizeTime = DotaTime()
		return
	end
	bedlamDesire = X.ConsiderBedlam()
	if bedlamDesire > 0 then
		bot:Action_UseAbility(bedlamAbility)
		lastBedlamTime = DotaTime()
		return
	end
	local shadowRealmWhy, shadowRealmTarget
	shadowRealmDesire, shadowRealmWhy, shadowRealmTarget = X.ConsiderShadowRealm()
	if shadowRealmDesire > 0 then
		X.StartShadowRealm(shadowRealmWhy, shadowRealmTarget)
		bot:Action_UseAbility(shadowRealmAbility)
		-- return: without it the Cursed Crown order below replaced Shadow Realm in the same frame.
		return
	end
	cursedCrownDesire, cursedCrownTarget = X.ConsiderCurseCrown()
	if cursedCrownDesire > 0 then
		bot:Action_UseAbilityOnEntity(cursedCrownAbility, cursedCrownTarget)
		return
	end
end
-- Interrupt probes (#48): after an interrupt cast, look at the target once the effect should have landed and log
-- whether the teleport/channel stopped. [OHA-DARK_WILLOW] interrupt-result spell= target= seen= moved= rooted=
-- feared= tp= channel=. tp=false alone is ambiguous (a finished TP reads false too): moved= is the distance from
-- where the target stood at the cast (a completed TP moves it far), seen=false means it is out of vision.
local interruptProbes = {}
function X.StartInterruptProbe(spell, target, delay)
	interruptProbes[spell] = {
		target = target,
		name = target:GetUnitName(),
		from = target:GetLocation(),
		checkAt = DotaTime() + delay,
	}
end
function X.CheckInterruptProbes()
	for spell, probe in pairs(interruptProbes) do
		if DotaTime() >= probe.checkAt then
			interruptProbes[spell] = nil
			local target = probe.target
			local seen = target ~= nil and not target:IsNull() and target:IsAlive() and target:CanBeSeen()
			local moved, rooted, feared, tp, channel = -1, "-", "-", "-", "-"
			if seen then
				moved = Fu.GetLocationToLocationDistance(probe.from, target:GetLocation())
				rooted = tostring(target:HasModifier("modifier_dark_willow_bramble_maze"))
				feared = tostring(target:HasModifier("modifier_dark_willow_debuff_fear"))
				tp = tostring(target:HasModifier("modifier_teleporting"))
				channel = tostring(target:IsChanneling())
			end
			pcall(
				print,
				string.format(
					"[OHA-DARK_WILLOW] t=%.0f interrupt-result spell=%s target=%s seen=%s moved=%d rooted=%s feared=%s tp=%s channel=%s",
					DotaTime(),
					spell,
					probe.name,
					tostring(seen),
					math.floor(moved),
					rooted,
					feared,
					tp,
					channel
				)
			)
		end
	end
end
-- Time left of an enemy's TP (InterruptRules.TrackTeleport): the modifier read, checked once per TP against the
-- clock. [OHA-DARK_WILLOW] tp-left target= first= second= dt= real=yes|no, once per TP. TP channel 3.0, or 2.0
-- with Boots of Travel 2 (7.42 items.txt: item_tpscroll AbilityChannelTime 3.0, item_travel_boots_2 tp_channel_time 2).
local teleportMemory = {}
function X.TeleportLeft(enemy)
	local modLeft = Fu.GetModifierTime(enemy, "modifier_teleporting")
	local channelTime = 3.0
	local ok, hasBoots2 = pcall(Fu.HasItem, enemy, "item_travel_boots_2")
	if ok and hasBoots2 then
		channelTime = 2.0
	end
	local left, entry, decided =
		InterruptRules.TrackTeleport(teleportMemory, enemy:GetUnitName(), modLeft, DotaTime(), channelTime)
	if decided then
		local real = "no"
		if entry.real then
			real = "yes"
		end
		pcall(
			print,
			string.format(
				"[OHA-DARK_WILLOW] t=%.0f tp-left target=%s first=%.2f second=%.2f dt=%.2f real=%s channel=%.1f",
				DotaTime(),
				enemy:GetUnitName(),
				entry.firstLeft,
				entry.secondLeft,
				entry.dt,
				real,
				channelTime
			)
		)
	end
	return left
end
-- Every think: follow the TPs of enemy heroes near her, so the first read is taken when the TP starts, not when
-- one of her spells comes off cooldown.
function X.TrackEnemyTeleports()
	for _, enemy in pairs(Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)) do
		if Fu.IsValidHero(enemy) and enemy:HasModifier("modifier_teleporting") then
			X.TeleportLeft(enemy)
		end
	end
end
-- Time left of an enemy's channel: the TP modifier's remaining time, else the channelled ability's channel time
-- counted from the first think this bot saw it (an upper bound if she saw it late). src: tp|channel|unknown.
-- Third value: the enemy's active ability name ("-" when the API gives none), for the log (#48, game 065: the
-- t=3155 interrupt on Primal Beast said src=channel but not which channel).
local channelMemory = {}
function X.EnemyChannelLeft(enemy)
	local active = enemy:GetCurrentActiveAbility()
	local name = "-"
	if active ~= nil and not active:IsNull() then
		name = active:GetName() or "-"
	end
	if enemy:HasModifier("modifier_teleporting") then
		return X.TeleportLeft(enemy), "tp", name ~= "-" and name or "item_tpscroll"
	end
	if active == nil or active:IsNull() then
		return 0, "unknown", name
	end
	local channelTime = active:GetChannelTime() or 0
	if channelTime <= 0 then
		return 0, "unknown", name
	end
	return InterruptRules.TrackChannel(channelMemory, enemy:GetUnitName(), name, channelTime, DotaTime()),
		"channel",
		name
end
-- A channel or cast phase a root cancels (InterruptRules.ROOT_CANCELS, from the game files): time left, the
-- ability name and src tp|channel|cast; src "none" when the enemy is doing nothing a root cancels.
function X.EnemyRootCancelLeft(enemy)
	local active = enemy:GetCurrentActiveAbility()
	local name = nil
	if active ~= nil and not active:IsNull() then
		name = active:GetName()
	end
	if enemy:HasModifier("modifier_teleporting") then
		return X.TeleportLeft(enemy), name or "item_tpscroll", "tp"
	end
	local entry = name ~= nil and InterruptRules.ROOT_CANCELS[name] or nil
	if entry == nil then
		return 0, name, "none"
	end
	local total = 0
	if entry.kind == "channel" and enemy:IsChanneling() then
		total = active:GetChannelTime() or 0
	elseif entry.kind == "cast" and active:IsInAbilityPhase() then
		total = active:GetCastPoint() or 0
	end
	if total <= 0 then
		return 0, name, "none"
	end
	return InterruptRules.TrackChannel(channelMemory, enemy:GetUnitName(), name, total, DotaTime()), name, entry.kind
end
-- [OHA-DARK_WILLOW] bramble why=... lines, each why at most once per 3s.
local brambleLogAt = {}
function X.LogBramble(why, fmt, ...)
	if DotaTime() < (brambleLogAt[why] or -999) then
		return
	end
	brambleLogAt[why] = DotaTime() + 3
	pcall(print, string.format("[OHA-DARK_WILLOW] t=%.0f " .. fmt, DotaTime(), ...))
end
-- Bramble Maze (#48, maintainer 2026-11-21: "team fight, engaging, cancelling channeling (that can be cancelled
-- with roots)"). Datafeed (hero 119): cast range 1000-1300, cast point 0.3, 8 brambles in a 500 area that grow
-- after 0.3s; an enemy within 90 of one is rooted 1-2.5s; "Does not interrupt channeling spells upon rooting".
-- Single targets: cast so the first (east) inner bramble grows on the hero (InterruptRules.BrambleAim), an
-- instant root 0.7s after the order. Fights: the zone over the most enemies that are free to move.
function X.ConsiderBrambleMaze()
	X.CheckInterruptProbes()
	if not brambleMazeAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = brambleMazeAbility:GetCastRange()
	local castPoint = brambleMazeAbility:GetCastPoint()
	local growDelay = brambleMazeAbility:GetSpecialValueFloat("initial_creation_delay")
	local latchDelay = brambleMazeAbility:GetSpecialValueFloat("latch_creation_delay")
	local interval = brambleMazeAbility:GetSpecialValueFloat("latch_creation_interval")
	local zoneRadius = brambleMazeAbility:GetSpecialValueInt("placement_range")
	if zoneRadius <= 0 then
		zoneRadius = 500
	end
	local botLocation = bot:GetLocation()
	-- Where to cast so a bramble grows on `location`; nil when no cardinal spot is in range.
	local function Aim(location)
		local x, y, aim, index =
			InterruptRules.BrambleAim(location.x, location.y, botLocation.x, botLocation.y, castRange)
		if x == nil then
			return nil
		end
		return Vector(x, y, location.z),
			aim,
			InterruptRules.BrambleRootTime(castPoint, growDelay, latchDelay, interval, index)
	end
	-- An inner bramble sits 200 from the cast point, so a target up to 200 past cast range can still be aimed at.
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange + 200, true, BOT_MODE_NONE)
	botTarget = Fu.GetProperTarget(bot)
	-- Cancel what a root cancels, if the root lands first (cast point + grow + latch delay + spawn order).
	for _, enemy in pairs(nearbyEnemies) do
		if
			Fu.IsValidHero(enemy)
			and (enemy:IsChanneling() or enemy:IsCastingAbility() or enemy:HasModifier("modifier_teleporting"))
			and Fu.CanCastOnNonMagicImmune(enemy)
			and not Fu.IsSuspiciousIllusion(enemy)
			and not enemy:IsRooted()
		then
			local left, channel, src = X.EnemyRootCancelLeft(enemy)
			if src ~= "none" then
				local location, aim, arrive = Aim(enemy:GetLocation())
				if location ~= nil then
					if InterruptRules.LandsBeforeChannelEnds(arrive, left) then
						X.LogBramble(
							"interrupt",
							"bramble why=interrupt target=%s channel=%s aim=%s arrive=%.2f left=%.2f margin=%.2f src=%s",
							enemy:GetUnitName(),
							channel,
							aim,
							arrive,
							left,
							left - arrive,
							src
						)
						X.StartInterruptProbe("bramble", enemy, arrive + 0.5)
						return BOT_ACTION_DESIRE_HIGH, location
					end
					X.LogBramble(
						"too-late",
						"bramble-skip why=too-late target=%s channel=%s arrive=%.2f left=%.2f margin=%.2f src=%s",
						enemy:GetUnitName(),
						channel,
						arrive,
						left,
						left - arrive,
						src
					)
				end
			end
		end
	end
	-- Team fight: the zone where it catches the most enemy heroes that are free to move (predicted to where they
	-- will be when the brambles grow), 2 or more.
	if not isRetreating and (isInTeamFight or #nearbyEnemies >= 2) then
		local aoe = bot:FindAoELocation(true, true, botLocation, castRange, zoneRadius, castPoint + growDelay, 0)
		if aoe ~= nil and aoe.count ~= nil and aoe.count >= 2 then
			local free = 0
			for _, enemy in pairs(Fu.GetEnemiesNearLoc(aoe.targetloc, zoneRadius)) do
				if
					Fu.IsValidHero(enemy)
					and not Fu.IsSuspiciousIllusion(enemy)
					and Fu.CanCastOnNonMagicImmune(enemy)
					and not Fu.IsDisabled(enemy)
					and not enemy:IsRooted()
				then
					free = free + 1
				end
			end
			if free >= 2 then
				X.LogBramble("teamfight", "bramble why=teamfight n=%d aim=zone", free)
				return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
			end
		end
	end
	-- Engage: put the first bramble where the target will stand when it grows (still targets: where it is).
	if isGoingOnSomeone then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange + 200)
			and not Fu.IsDisabled(botTarget)
			and not botTarget:IsRooted()
			and not Fu.IsSuspiciousIllusion(botTarget)
		then
			local lead = InterruptRules.BrambleRootTime(castPoint, growDelay, latchDelay, 0, 0)
			local predicted = botTarget:GetLocation()
			if Fu.IsMoving(botTarget) then
				predicted = botTarget:GetExtrapolatedLocation(lead)
			end
			local location, aim = Aim(predicted)
			if location ~= nil then
				X.LogBramble(
					"engage",
					"bramble why=engage target=%s lead=%.2f aim=%s moving=%s",
					botTarget:GetUnitName(),
					lead,
					aim,
					tostring(Fu.IsMoving(botTarget))
				)
				return BOT_ACTION_DESIRE_HIGH, location
			end
		end
	end
	if
		isRetreating
		and Fu.IsValid(nearbyEnemies[1])
		and Fu.IsInRange(bot, nearbyEnemies[1], castRange)
		and Fu.CanCastOnNonMagicImmune(nearbyEnemies[1])
		and not Fu.IsDisabled(nearbyEnemies[1])
		and not Fu.IsRealInvisible(bot)
		and not Fu.IsSuspiciousIllusion(nearbyEnemies[1])
	then
		X.LogBramble("retreat", "bramble why=retreat target=%s aim=zone", nearbyEnemies[1]:GetUnitName())
		return BOT_ACTION_DESIRE_HIGH, nearbyEnemies[1]:GetLocation()
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
function X.ConsiderShadowRealm()
	if not shadowRealmAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end
	local attackRangeBonus = shadowRealmAbility:GetSpecialValueInt("attack_range_bonus")
	if attackRangeBonus <= 0 then
		attackRangeBonus = 600
	end
	local attackRange = bot:GetAttackRange()
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, attackRange + attackRangeBonus, true, BOT_MODE_NONE)
	botTarget = Fu.GetProperTarget(bot)
	if isGoingOnSomeone then
		-- Dodge: hurt in a fight against 2+ (the old rule, kept). The hit after it still ends the realm.
		if
			hpRatio < 0.5
			and Fu.IsValidHero(botTarget)
			and Fu.CanCastOnMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, bot:GetAttackRange())
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not botTarget:HasModifier("modifier_abaddon_borrowed_time")
			and not Fu.IsRealInvisible(bot)
			and nearbyEnemies ~= nil
			and #nearbyEnemies >= 2
		then
			return BOT_ACTION_DESIRE_HIGH, "dodge", botTarget
		end
		-- Attack (#48, maintainer game 067 4:50): go on the target within attack range + 600, hold the hit up to 3s
		-- for the full bonus (X.ShadowRealmTick). Only in the attack mode, the one whose attack order the hold
		-- replaces (override_generic/mode_attack_generic.lua); another mode's attack would end the realm at once.
		-- The bonus is magic damage: not on a magic-immune target. Mana for Cursed Crown stays.
		local crownCost = cursedCrownAbility:IsTrained() and cursedCrownAbility:GetManaCost() or 0
		if
			bot:GetActiveMode() == BOT_MODE_ATTACK
			and Fu.IsValidHero(botTarget)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and not botTarget:IsAttackImmune()
			and not botTarget:HasModifier("modifier_abaddon_borrowed_time")
			and not botTarget:HasModifier("modifier_dazzle_shallow_grave")
			and GetUnitToUnitDistance(bot, botTarget) <= attackRange + attackRangeBonus
			and not Fu.IsRealInvisible(bot)
			and bot:GetMana() - shadowRealmAbility:GetManaCost() >= crownCost
			and botTarget:GetHealth()
				> botTarget:GetActualIncomingDamage(bot:GetAttackDamage() * 2, DAMAGE_TYPE_PHYSICAL)
		then
			return BOT_ACTION_DESIRE_HIGH, "attack", botTarget
		end
	end
	if
		(isRetreating or isRetreating and hpRatio < 0.6 and bot:WasRecentlyDamagedByAnyHero(2))
		and not Fu.IsRealInvisible(bot)
		and nearbyEnemies ~= nil
		and #nearbyEnemies >= 1
	then
		if Fu.DidEnemyCastAbility() or hpRatio < 0.5 or Fu.IsStunProjectileIncoming(bot, 800) then
			return BOT_ACTION_DESIRE_HIGH, "retreat", nil
		end
		return BOT_ACTION_DESIRE_MODERATE, "retreat", nil
	end
	return BOT_ACTION_DESIRE_NONE
end
-- The realm she is in (bot._dwRealm): why (attack | dodge | retreat), the cast time, the target, her attack range
-- at the cast (GetAttackRange may already add the +600 inside the realm) and the bonus values from the ability.
function X.StartShadowRealm(why, target)
	local bonusRange = shadowRealmAbility:GetSpecialValueInt("attack_range_bonus")
	if bonusRange <= 0 then
		bonusRange = 600
	end
	local maxTime = shadowRealmAbility:GetSpecialValueFloat("max_damage_duration")
	if maxTime <= 0 then
		maxTime = ShadowRealmRules.MAX_DAMAGE_TIME
	end
	local duration = shadowRealmAbility:GetSpecialValueFloat("duration")
	if duration <= 0 then
		duration = ShadowRealmRules.DURATION
	end
	bot._dwRealm = {
		why = why or "retreat",
		at = DotaTime(),
		target = target,
		baseRange = bot:GetAttackRange(),
		bonusRange = bonusRange,
		maxDamage = shadowRealmAbility:GetSpecialValueInt("damage"),
		maxTime = maxTime,
		duration = duration,
		tp = "-",
		-- Deaths at the cast: a higher count later means she died in or right after the realm (#48).
		deaths = GetHeroDeaths(bot:GetPlayerID()) or 0,
	}
	pcall(
		print,
		string.format(
			"[OHA-DW] t=%.0f dark_willow shadow-realm-cast why=%s target=%s dist=%d hp=%.2f mode=%d",
			DotaTime(),
			tostring(why),
			target ~= nil and (string.gsub(target:GetUnitName(), "npc_dota_hero_", "")) or "-",
			target ~= nil and GetUnitToUnitDistance(bot, target) or -1,
			Fu.GetHP(bot),
			bot:GetActiveMode()
		)
	)
end
-- [OHA-DW] t= dark_willow shadow-realm why=attack|dodge|retreat held= ended= release= tp= dist= mod= invuln=, one
-- line per realm when it ends. held: seconds from the cast to the release order (attack) or to the end; ended: when
-- the realm was seen to end (the hit landed; about 5.2 when it ran out, or when the modifier was never seen).
-- release=died: she died in the realm or the tick stopped (her think doesn't run while dead); t=, held= and ended=
-- are then from the last tick she was alive (game 068: the lines printed at respawn, 18-51s late, held=51.10).
-- endedAt: that time (default now).
function X.EndShadowRealm(realm, since, endedAt)
	bot._dwRealm = nil
	local target = realm.target
	local dist = -1
	if target ~= nil and not target:IsNull() and target:IsAlive() and target:CanBeSeen() then
		dist = GetUnitToUnitDistance(bot, target)
	end
	pcall(
		print,
		string.format(
			"[OHA-DW] t=%.0f dark_willow shadow-realm why=%s held=%.2f ended=%.2f release=%s tp=%s target=%s dist=%d mod=%s invuln=%s",
			endedAt or DotaTime(),
			realm.why,
			realm.releasedAt or since,
			since,
			tostring(realm.released or "-"),
			tostring(realm.tp),
			target ~= nil and not target:IsNull() and (string.gsub(target:GetUnitName(), "npc_dota_hero_", "")) or "-",
			dist,
			realm.modSeen ~= nil and string.format("%.2f", realm.modSeen) or "no",
			tostring(realm.invuln == true)
		)
	)
end
-- Another allied hero within 1500 in the attack mode (the TP rule's attackingAllies, without herself).
function X.AllyFighting()
	for _, ally in pairs(Fu.GetNearbyHeroes(bot, 1500, false, BOT_MODE_ATTACK) or {}) do
		if Fu.IsValidHero(ally) and ally ~= bot and not ally:IsIllusion() then
			return true
		end
	end
	return false
end
-- Her TP: the TP slot (15) or Boots of Travel in the main slots, ready.
function X.TeleportItem()
	for _, name in ipairs({ "item_tpscroll", "item_travel_boots", "item_travel_boots_2" }) do
		local slot = bot:FindItemSlot(name)
		if slot == 15 or slot >= 0 and slot <= 5 then
			local item = bot:GetItemInSlot(slot)
			if item ~= nil and not item:IsNull() and item:IsFullyCastable() then
				return item
			end
		end
	end
	return nil
end
-- An escape realm: TP home at once, so the 3s channel ends inside the 5s untargetable time (#48, game 067 17:06:
-- realm, then a walk, a TP 4s later, dead after the realm ended). The generic TP rule waits out an enemy tower
-- within 888 (she was 320 from one); towers can't target her in the realm. HP under 0.45 and over 4900 from the
-- fountain, hit by a hero in the last 6s, no ally fighting within 1500: the gates of the TP rule's own retreat TP
-- (ability_item_usage_generic.lua 撤退:2: HP under 15% + 24% per enemy hero within 1600, at most 45%), and its
-- channel gates that still apply (Usage.TpGatesClosed: rooted, already teleporting, Nethertoxin, Macropyre) plus a
-- hero script's own TP hold (bot._noTpUntil). tp=ordered until the channel shows; up to 3 orders while it fits
-- (a TP scroll can't start rooted: items_all.txt ROOT_DISABLES), then tp=now, or tp=failed.
function X.ShadowRealmTeleport(realm, since, castDone)
	if not castDone or realm.tp ~= "-" and realm.tp ~= "ordered" then
		return false
	end
	if realm.tp == "ordered" and since - realm.tpAt < 0.4 then
		return false
	end
	local fits = ShadowRealmRules.TpFits(since, realm.duration, ShadowRealmRules.TP_CHANNEL, 0.3)
	if realm.tp == "ordered" then
		if not fits or realm.tpTries >= 3 then
			realm.tp = "failed"
			return false
		end
	else
		local enemyCount = #Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
		local hpLine = math.min(0.15 + 0.24 * enemyCount, 0.45)
		local tp = X.TeleportItem()
		if tp == nil then
			realm.tp = "none"
		elseif not fits then
			realm.tp = "late"
		elseif Fu.GetHP(bot) >= hpLine then
			realm.tp = "skip-hp"
		elseif bot:DistanceFromFountain() <= 4900 then
			realm.tp = "skip-near"
		elseif not bot:WasRecentlyDamagedByAnyHero(6.0) then
			realm.tp = "skip-safe"
		elseif X.AllyFighting() then
			realm.tp = "skip-allies"
		elseif
			bot:IsRooted()
			or bot:HasModifier("modifier_teleporting")
			or bot:HasModifier("modifier_viper_nethertoxin")
			or bot:HasModifier("modifier_jakiro_macropyre_burn")
			or DotaTime() < (bot._noTpUntil or -999)
		then
			realm.tp = "skip-gate"
		end
		if realm.tp ~= "-" then
			return false
		end
		realm.tpTries = 0
	end
	local tp = X.TeleportItem()
	if tp == nil then
		realm.tp = realm.tp == "ordered" and "failed" or "none"
		return false
	end
	realm.tp = "ordered"
	realm.tpAt = since
	realm.tpTries = realm.tpTries + 1
	bot:Action_UseAbilityOnLocation(tp, Fu.GetTeamFountain())
	return true
end
-- Every think while she is in a realm. Attack realm: keep within attack range + 600 of the target and hold the hit
-- until the bonus is full (ShadowRealmRules.HoldStep), then one attack. Retreat realm: the TP. Returns true when it
-- gave an order the spells below must not replace (the hit, the TP); hold moves return false so a spell can still go
-- out. Also called by the attack mode's Think (bot._attackHold), in place of its attack order.
function X.ShadowRealmTick()
	local realm = bot._dwRealm
	if realm == nil then
		return false
	end
	local since = DotaTime() - realm.at
	-- Dead, a death since the cast, or the realm older than its duration + 1s (the tick missed its end: her think
	-- does not run while dead): end it at the last tick she was alive, release=died (release=stale when no death
	-- was counted, e.g. the think stopped for another reason).
	local deaths = GetHeroDeaths(bot:GetPlayerID()) or 0
	local died = not bot:IsAlive() or deaths > (realm.deaths or deaths)
	if died or since > realm.duration + 1 then
		local last = realm.lastTick or 0
		realm.released, realm.releasedAt = died and "died" or "stale", realm.releasedAt or last
		X.EndShadowRealm(realm, last, realm.at + last)
		return false
	end
	realm.lastTick = since
	local inRealm = bot:HasModifier("modifier_dark_willow_shadow_realm_buff")
	if inRealm and realm.modSeen == nil then
		realm.modSeen = since
		realm.invuln = bot:IsInvulnerable()
	end
	-- The cast went out: the modifier is on, or the ability went on cooldown (in case the modifier name is wrong).
	local castDone = inRealm or shadowRealmAbility:GetCooldownTimeRemaining() > 0
	if since > 0.5 and not castDone then
		realm.released = realm.released or "no-cast"
		X.EndShadowRealm(realm, since)
		return false
	end
	if since > realm.duration + 0.2 or realm.modSeen ~= nil and not inRealm then
		X.EndShadowRealm(realm, since)
		return false
	end
	if realm.tp == "ordered" and bot:IsChanneling() then
		realm.tp = "now"
	end
	if bot:IsChanneling() or bot:IsCastingAbility() or Fu.CanNotUseAction(bot) then
		return false
	end
	if realm.why == "retreat" then
		return X.ShadowRealmTeleport(realm, since, castDone)
	end
	if realm.why ~= "attack" or realm.released ~= nil or not castDone then
		return false
	end
	local target = realm.target
	if not Fu.IsValidHero(target) or not target:CanBeSeen() then
		realm.released, realm.releasedAt = "target-gone", since
		return false
	end
	if bot:GetActiveMode() ~= BOT_MODE_ATTACK then
		realm.released, realm.releasedAt = "mode", since
		return false
	end
	local holdRange = realm.baseRange + realm.bonusRange
	local dist = GetUnitToUnitDistance(bot, target)
	local bonusNow = ShadowRealmRules.BonusDamage(realm.maxDamage, since, realm.maxTime)
	local hitNow = target:GetActualIncomingDamage(bonusNow, DAMAGE_TYPE_MAGICAL)
		+ target:GetActualIncomingDamage(bot:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
	local killNow = target:GetHealth() <= hitNow
	local allyNeeds = false
	for _, ally in pairs(Fu.GetNearbyHeroes(target, 900, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(ally) and ally ~= bot and not ally:IsIllusion() then
			-- An ally next to a nearly dead target finishes it anyway.
			if Fu.GetHP(target) < 0.15 and GetUnitToUnitDistance(ally, target) <= 700 then
				killNow = true
			end
			if
				Fu.GetHP(ally) < 0.35
				and (target:GetAttackTarget() == ally or ally:WasRecentlyDamagedByHero(target, 1.0))
			then
				allyNeeds = true
			end
		end
	end
	local action, why = ShadowRealmRules.HoldStep({
		since = since,
		maxTime = realm.maxTime,
		dist = dist,
		holdRange = holdRange,
		predictedDist = GetUnitToLocationDistance(bot, target:GetExtrapolatedLocation(0.5)),
		canFollow = bot:GetCurrentMovementSpeed() > target:GetCurrentMovementSpeed() + 10,
		killNow = killNow,
		allyNeeds = allyNeeds,
	})
	if action == "attack" then
		realm.released, realm.releasedAt = why, since
		bot:Action_AttackUnit(target, true)
		return true
	end
	-- A move order every think, so she never stands idle (an idle unit's own attack would end the realm early).
	local targetLocation = target:GetLocation()
	local point
	if action == "close" then
		point = target:GetExtrapolatedLocation(0.5)
	else
		-- Hold: step 25 degrees around the target at her distance, the way that ends nearer our fountain, so she
		-- settles on the target's home side (not behind it or under its tower) when the hit makes her targetable.
		local here = bot:GetLocation()
		local dx, dy = here.x - targetLocation.x, here.y - targetLocation.y
		local fountain = Fu.GetTeamFountain()
		local best, bestDist = nil, nil
		for _, sign in ipairs({ 1, -1 }) do
			local angle = math.rad(25) * sign
			local candidate = Vector(
				targetLocation.x + dx * math.cos(angle) - dy * math.sin(angle),
				targetLocation.y + dx * math.sin(angle) + dy * math.cos(angle),
				here.z
			)
			local toFountain = Fu.GetLocationToLocationDistance(candidate, fountain)
			if bestDist == nil or toFountain < bestDist then
				best, bestDist = candidate, toFountain
			end
		end
		point = best
	end
	bot:Action_MoveToLocation(point)
	return false
end
-- The attack mode asks this before its own attack order (override_generic/mode_attack_generic.lua): true when the
-- realm gave the order (the hold move or the hit), or the realm cast is still going out (an attack order would
-- replace it).
bot._attackHold = function()
	local realm = bot._dwRealm
	if realm == nil or realm.why ~= "attack" or realm.released ~= nil then
		return false
	end
	local ok, order = pcall(X.ShadowRealmTick)
	if not ok then
		X.LogRealmError(order)
		return false
	end
	if order then
		return true
	end
	realm = bot._dwRealm
	return realm ~= nil and realm.released == nil
end
-- A Lua error in the realm tick (both callers pcall it): [OHA-ERROR] once per distinct message, at most 3, and the
-- realm state is dropped so a broken hold never keeps her from attacking.
local realmErrors = {}
function X.LogRealmError(err)
	bot._dwRealm = nil
	local key = tostring(err)
	if realmErrors[key] or #realmErrors >= 3 then
		return
	end
	realmErrors[key] = true
	realmErrors[#realmErrors + 1] = key
	pcall(print, string.format("[OHA-ERROR] t=%.1f dark_willow ShadowRealmTick: %s", DotaTime(), key))
end
function X.ConsiderCurseCrown()
	if not cursedCrownAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, cursedCrownAbility:GetCastRange())
	local mpRatio = bot:GetMana() / bot:GetMaxMana()
	local enemiesInRange = Fu.GetNearbyHeroes(bot, castRange + 50, true, BOT_MODE_NONE)
	local enemiesInWideRange = Fu.GetNearbyHeroes(bot, castRange + 150, true, BOT_MODE_NONE)
	local weakestEnemy = Fu.GetWeakestUnit(enemiesInRange)
	local weakestWideEnemy = Fu.GetWeakestUnit(enemiesInWideRange)
	local nearbyEnemyTowers = bot:GetNearbyTowers(900, true)
	if isInTeamFight then
		local strongestEnemy = nil
		local maxDamage = 0
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange + 100, true, BOT_MODE_NONE)
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and Fu.CanCastOnTargetAdvanced(enemy)
				and not Fu.IsDisabled(enemy)
			then
				local estimatedDamage = enemy:GetEstimatedDamageToTarget(false, bot, 3.5, DAMAGE_TYPE_ALL)
				if estimatedDamage > maxDamage then
					maxDamage = estimatedDamage
					strongestEnemy = enemy
				end
			end
		end
		if strongestEnemy ~= nil then
			return BOT_ACTION_DESIRE_HIGH, strongestEnemy
		end
	end
	if isGoingOnSomeone then
		botTarget = Fu.GetProperTarget(bot)
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.CanCastOnTargetAdvanced(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and not Fu.IsDisabled(botTarget)
			and not Fu.IsSuspiciousIllusion(botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end
	if isRetreating then
		for _, enemy in pairs(enemiesInRange) do
			if
				Fu.IsValidHero(enemy)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and Fu.CanCastOnTargetAdvanced(enemy)
				and Fu.IsInRange(bot, enemy, castRange)
				and bot:WasRecentlyDamagedByHero(enemy, 3.5)
				and bot:IsFacingLocation(enemy:GetLocation(), 45)
				and not Fu.IsDisabled(enemy)
				and not Fu.IsSuspiciousIllusion(enemy)
			then
				return BOT_ACTION_DESIRE_HIGH, enemy
			end
		end
	end
	if bot:WasRecentlyDamagedByAnyHero(2) and enemiesInRange[1] ~= nil and #enemiesInRange >= 1 then
		for _, enemy in pairs(enemiesInRange) do
			if
				Fu.IsValidHero(enemy)
				and Fu.CanCastOnNonMagicImmune(enemy)
				and Fu.CanCastOnTargetAdvanced(enemy)
				and bot:IsFacingLocation(enemy:GetLocation(), 30)
				and not Fu.IsDisabled(enemy)
				and not Fu.IsSuspiciousIllusion(enemy)
			then
				return BOT_ACTION_DESIRE_HIGH, enemy
			end
		end
	end
	if Fu.IsLaning(bot) and #nearbyEnemyTowers == 0 or DotaTime() > 12 * 60 then
		if mpRatio > 0.7 then
			if Fu.IsValidHero(weakestEnemy) and not Fu.IsDisabled(weakestEnemy) then
				return BOT_ACTION_DESIRE_HIGH, weakestEnemy
			end
		end
		if mpRatio > 0.88 then
			local nearbyEnemyCreeps = bot:GetNearbyCreeps(1200, true)
			if
				Fu.IsValidHero(weakestWideEnemy)
				and hpRatio > 0.6
				and #nearbyEnemyTowers == 0
				and (#nearbyEnemyCreeps + #enemiesInWideRange <= 5 or DotaTime() > 12 * 60)
				and not Fu.IsDisabled(weakestWideEnemy)
			then
				return BOT_ACTION_DESIRE_HIGH, weakestWideEnemy
			end
		end
		if Fu.IsValidHero(weakestEnemy) and Fu.GetHP(weakestEnemy) < 0.4 then
			return BOT_ACTION_DESIRE_HIGH, weakestEnemy
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderBedlam()
	if not bedlamAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	if terrorizeAbility:IsTrained() then
		local fearDuration = bedlamAbility:GetSpecialValueInt("destination_status_duration")
		if DotaTime() - lastTerrorizeTime <= fearDuration then
			return BOT_ACTION_DESIRE_NONE, nil
		end
	end
	-- Bedlam has no cast range: the wisp circles 200 around her and hits within 300 (datafeed
	-- roaming_radius, attack_radius). GetProperCastRange(0) gave attack range + 200, so it was cast
	-- on heroes the wisp could not reach.
	local castRange = bedlamAbility:GetSpecialValueInt("roaming_radius")
		+ bedlamAbility:GetSpecialValueInt("attack_radius")
	if castRange <= 0 then
		castRange = 500
	end
	botTarget = Fu.GetProperTarget(bot)
	local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
	if isInTeamFight then
		if #nearbyEnemies >= 1 then
			return BOT_ACTION_DESIRE_HIGH, bot
		end
	end
	if isGoingOnSomeone then
		if Fu.IsInRange(bot, botTarget, castRange) and Fu.IsValidTarget(botTarget) then
			return BOT_ACTION_DESIRE_HIGH, bot -- was the undefined global allyTarget; Bedlam is no-target
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderTerrorize()
	if not terrorizeAbility:IsFullyCastable() or DotaTime() - lastBedlamTime <= 5 then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	local castRange = Fu.GetProperCastRange(false, bot, terrorizeAbility:GetCastRange())
	local radius = terrorizeAbility:GetSpecialValueInt("destination_radius")
	local enemiesInWideRange = Fu.GetNearbyHeroes(bot, castRange + 150, true, BOT_MODE_NONE)
	if isInTeamFight then
		local teamFightLocation = Fu.GetTeamFightLocation(bot)
		local nearbyAllies = Fu.GetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)
		local disabledAllyCount = 0
		local arenaEnemyCount = 0
		local hasChronoAlly = false
		local chronoAlly = nil
		if teamFightLocation ~= nil then
			nearbyAllies = Fu.GetAlliesNearLoc(teamFightLocation, radius)
		end
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)
		for _, enemy in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemy)
				and not Fu.IsSuspiciousIllusion(enemy)
				and enemy:HasModifier("modifier_mars_arena_of_blood")
			then
				arenaEnemyCount = arenaEnemyCount + 1
			end
		end
		if arenaEnemyCount >= 2 then
			local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
			if aoe.count >= 2 then
				return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
			end
		end
		for _, ally in pairs(nearbyAllies) do
			if Fu.IsValidHero(ally) and Fu.IsDisabled(ally) and not ally:IsIllusion() then
				disabledAllyCount = disabledAllyCount + 1
			end
			if
				Fu.IsValidHero(ally)
				and Fu.IsCore(ally)
				and ally:HasModifier("modifier_faceless_void_chronosphere_freeze")
			then
				local enemiesNearAlly = Fu.GetNearbyHeroes(ally, 400, true, BOT_MODE_NONE)
				if enemiesNearAlly ~= nil and #enemiesNearAlly >= 1 then
					hasChronoAlly = true
					chronoAlly = ally
					break
				end
			end
		end
		if chronoAlly ~= nil and hasChronoAlly then
			-- was ChronodAlly (an undefined global), a runtime error every time this case matched
			return BOT_ACTION_DESIRE_HIGH, chronoAlly:GetLocation()
		end
		if disabledAllyCount >= 2 then
			local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
			if aoe.count >= 2 then
				return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
			end
		end
		-- Plain team fight: fear 3+ enemies standing in one Terrorize area (1s cast point, so
		-- predict 1s ahead). Without this the fear only went out for disabled allies, Chrono or
		-- Arena, and Bedlam took the shared cooldown first.
		local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius * 0.8, 1.0, 0)
		if aoe ~= nil and aoe.count ~= nil and aoe.count >= 3 then
			local realFeared = Fu.GetEnemiesNearLoc(aoe.targetloc, radius * 0.8)
			if realFeared ~= nil and #realFeared >= 3 then
				if DotaTime() >= (bot._terrorizeLogAt or -999) then
					bot._terrorizeLogAt = DotaTime() + 5
					pcall(
						print,
						string.format("[OHA-DARK_WILLOW] t=%.0f terrorize fight heroes=%d", DotaTime(), #realFeared)
					)
				end
				return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
			end
		end
	end
	if isRetreating then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
		if bot:WasRecentlyDamagedByAnyHero(2.0) and #nearbyEnemies >= 2 then
			local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
			if aoe.count >= 2 then
				return BOT_ACTION_DESIRE_MODERATE, aoe.targetloc
			end
		end
	end
	-- A teleporting or channelling enemy (#48): only when the fear lands before the channel ends. Datafeed (hero
	-- 119): cast point 1.0, the wisp flies from her to the point at destination_travel_speed 2000, no other delay.
	-- TP scroll channel 3.0s (7.42 items.txt). The old branch also aimed at a 2-hero spot that need not hold
	-- the teleporter, and took enemies 150 past cast range.
	local castPoint = terrorizeAbility:GetCastPoint()
	local travelSpeed = terrorizeAbility:GetSpecialValueInt("destination_travel_speed")
	for _, enemy in pairs(enemiesInWideRange) do
		if
			Fu.IsValidHero(enemy)
			and not Fu.IsSuspiciousIllusion(enemy)
			and (enemy:IsChanneling() or enemy:HasModifier("modifier_teleporting"))
			and Fu.CanCastOnNonMagicImmune(enemy)
			and Fu.CanCastOnTargetAdvanced(enemy)
		then
			local location = enemy:GetLocation()
			local aoe = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius * 0.8, 0, 0)
			if
				aoe ~= nil
				and aoe.count ~= nil
				and aoe.count >= 2
				and Fu.GetLocationToLocationDistance(aoe.targetloc, location) <= radius * 0.8
			then
				location = aoe.targetloc
			end
			local distance = GetUnitToLocationDistance(bot, location)
			if distance <= castRange then
				local left, src, channel = X.EnemyChannelLeft(enemy)
				local arrive = InterruptRules.ArrivalTime(castPoint, distance, travelSpeed, 0)
				if InterruptRules.LandsBeforeChannelEnds(arrive, left) then
					X.LogTerrorize("interrupt", enemy, arrive, left, src, channel)
					-- arrive has no turning time; the fear lasts 2.8s+, so look 0.5s after the landing.
					X.StartInterruptProbe("terrorize", enemy, arrive + 0.5)
					return BOT_ACTION_DESIRE_HIGH, location
				end
				-- src=unknown: the channel time could not be read from the enemy's ability (bot API check).
				X.LogTerrorize(src == "unknown" and "unreadable" or "too-late", enemy, arrive, left, src, channel)
			end
		end
	end
	local nearbyAllies = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
	for _, ally in pairs(nearbyAllies) do
		-- was "valid and retreating OR retreating and hurt and core and hit": the first half alone matched, so
		-- any retreating ally (even at full HP) drew the fear. Now a hurt core that is being hit (#48).
		if
			Fu.IsValidHero(ally)
			and not ally:IsIllusion()
			and Fu.IsRetreating(ally)
			and Fu.GetHP(ally) < 0.4
			and Fu.IsCore(ally)
			and ally:WasRecentlyDamagedByAnyHero(2)
		then
			local aoe = bot:FindAoELocation(true, true, ally:GetLocation(), castRange, radius, 0, 0)
			if aoe.count >= 2 and GetUnitToLocationDistance(bot, aoe.targetloc) <= castRange then
				X.LogTerrorize("save-ally", ally, 0, Fu.GetHP(ally), "ally")
				return BOT_ACTION_DESIRE_HIGH, aoe.targetloc
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
-- [OHA-DARK_WILLOW] terrorize why=interrupt ... / terrorize-skip why=too-late|unreadable ... / terrorize why=save-ally,
-- each at most once per 3s. arrive: seconds until the fear lands; left: channel time left; margin = left - arrive.
local terrorizeLogAt = {}
function X.LogTerrorize(why, unit, arrive, left, src, channel)
	if DotaTime() < (terrorizeLogAt[why] or -999) then
		return
	end
	terrorizeLogAt[why] = DotaTime() + 3
	if why == "save-ally" then
		pcall(
			print,
			string.format(
				"[OHA-DARK_WILLOW] t=%.0f terrorize why=save-ally ally=%s hp=%.2f",
				DotaTime(),
				unit:GetUnitName(),
				left
			)
		)
		return
	end
	local what = "terrorize"
	if why ~= "interrupt" then
		what = "terrorize-skip"
	end
	pcall(
		print,
		string.format(
			"[OHA-DARK_WILLOW] t=%.0f %s why=%s target=%s channel=%s arrive=%.2f left=%.2f margin=%.2f src=%s",
			DotaTime(),
			what,
			why,
			unit:GetUnitName(),
			tostring(channel or "-"),
			arrive,
			left,
			left - arrive,
			src
		)
	)
end
return X
