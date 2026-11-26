-- Hero-specific helper: rubick.
local X = {}
local bot = GetBot()
local Abaddon = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/abaddon")
local AbyssalUnderlord = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/abyssal_underlord")
local Alchemist = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/alchemist")
local AncientApparition = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/ancient_apparition")
local Antimage = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/antimage")
local ArcWarden = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/arc_warden")
local Axe = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/axe")
local Bane = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bane")
local Batrider = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/batrider")
local Beastmaster = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/beastmaster")
local Bloodseeker = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bloodseeker")
local BountyHunter = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bounty_hunter")
local Brewmaster = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/brewmaster")
local Bristleback = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/bristleback")
local Broodmother = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/broodmother")
local Centaur = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/centaur")
local ChaosKnight = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/chaos_knight")
local Chen = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/chen")
local Clinkz = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/clinkz")
local CrystalMaiden = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/crystal_maiden")
local Rattletrap = require(GetScriptDirectory() .. "/lib/hero/rubick_hero/rattletrap")
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local botTarget = nil
-- What a rubick_hero handler's ConsiderStolenSpell(ability) returns (#271):
--   "cast", target   it gave the order (target: the unit or location, nil for a no-target spell);
--   true             the spell is its own and it holds it for now: nothing else casts it this think;
--   nil              not its spell (or the bot cannot act).
-- SmartCast runs only for a spell no handler owns (heroes without a rubick_hero file). tests/test_rubick.lua checks
-- that every spell name a handler tests for returns "cast" or true, so a branch that forgets its `return true`
-- fails there instead of handing the spell to SmartCast.
local CAST = "cast"
local stolenSpellHandlers = {
	Abaddon,
	AbyssalUnderlord,
	Alchemist,
	AncientApparition,
	Antimage,
	ArcWarden,
	Axe,
	Bane,
	Batrider,
	Beastmaster,
	Bloodseeker,
	BountyHunter,
	Brewmaster,
	Bristleback,
	Broodmother,
	Centaur,
	ChaosKnight,
	Chen,
	Clinkz,
	CrystalMaiden,
	Rattletrap,
}
if DOTA_ABILITY_BEHAVIOR_UNIT_TARGET == nil then
	DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8
end
if DOTA_ABILITY_BEHAVIOR_NO_TARGET == nil then
	DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
end
if DOTA_ABILITY_BEHAVIOR_POINT == nil then
	DOTA_ABILITY_BEHAVIOR_POINT = 16
end
if DOTA_ABILITY_BEHAVIOR_AOE == nil then
	DOTA_ABILITY_BEHAVIOR_AOE = 32
end
if DOTA_UNIT_TARGET_HERO == nil then
	DOTA_UNIT_TARGET_HERO = 1
end
if DOTA_UNIT_TARGET_TEAM_FRIENDLY == nil then
	DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
end
if DOTA_UNIT_TARGET_TEAM_ENEMY == nil then
	DOTA_UNIT_TARGET_TEAM_ENEMY = 2
end
if DOTA_UNIT_TARGET_TEAM_BOTH == nil then
	DOTA_UNIT_TARGET_TEAM_BOTH = 3
end
-- [SHy-RUBICK] stolen-cast: at most one line per spell every STOLEN_LOG_GAP seconds.
local STOLEN_LOG_GAP = 3
-- A cast target is a location or a unit. A Vector is userdata in the game (bots/lib/systems/global_overrides.lua
-- refuses any other location type) and in the test stub; what type a unit handle has is not documented, so neither
-- test asks for a Lua type: a location has a number x, a unit answers GetUnitName.
local function IsLocation(target)
	if target == nil or type(target) == "number" then
		return false
	end
	local ok, x = pcall(function()
		return target.x
	end)
	return ok and type(x) == "number"
end
local function IsUnit(target)
	if target == nil or type(target) == "number" or IsLocation(target) then
		return false
	end
	local ok, name = pcall(function()
		return target:GetUnitName()
	end)
	return ok and type(name) == "string"
end
-- A unit's name and HP, or a location's x,y, for the log.
local function DescribeTarget(target)
	if IsLocation(target) then
		return string.format("%.0f,%.0f", target.x, target.y or 0), nil
	end
	if IsUnit(target) then
		return (string.gsub(target:GetUnitName(), "npc_dota_hero_", "")), target:GetHealth()
	end
	return "none", nil
end
-- event: stolen-cast (a stolen spell) or own-cast (Rubick's own spell, hero_rubick.lua). path: custom (a rubick_hero
-- file), smart (SmartCast) or own. why: what made it cast (rule, last-will, toggle-on, toggle-off). radius: the radius
-- SmartCast used.
function X.LogCast(event, spellName, path, target, why, radius)
	local now = DotaTime()
	X._stolenLogAt = X._stolenLogAt or {}
	if now < (X._stolenLogAt[spellName] or -math.huge) then
		return
	end
	X._stolenLogAt[spellName] = now + STOLEN_LOG_GAP
	local targetName, targetHp = DescribeTarget(target)
	local heroName = string.gsub(GetBot():GetUnitName() or "rubick", "npc_dota_hero_", "")
	pcall(
		print,
		string.format(
			"[SHy-RUBICK] t=%.0f %s %s spell=%s path=%s why=%s target=%s hp=%s radius=%s",
			now,
			heroName,
			event,
			spellName,
			path,
			why or "rule",
			targetName,
			type(targetHp) == "number" and string.format("%.0f", targetHp) or "-",
			type(radius) == "number" and string.format("%.0f", radius) or "-"
		)
			.. (
				why == "last-will"
					and string.format(" self_hp=%.0f incoming=%.0f", X.lastWill.health or 0, X.lastWill.incoming or 0)
				or ""
			)
	)
end
function X.LogStolenCast(spellName, path, target, why, radius)
	X.LogCast("stolen-cast", spellName, path, target, why, radius)
end
-- Last will: a stolen spell is lost when Rubick dies (Valve datafeed hero_id=86, Spell Steal: "as his own for several
-- minutes or until he dies"), so one he is about to die with is cast at whoever is in reach.
-- About to die: under LAST_WILL_HP of his HP, hit by a hero within the last second, and the enemy heroes within 1200
-- would deal at least his HP within LAST_WILL_WINDOW seconds (GetEstimatedDamageToTarget, as the retreat mode uses
-- it). A cast costs him a moment he could walk away in, so it waits until walking away would not save him.
-- What GetEstimatedDamageToTarget counts is not documented, so the last-will line prints Rubick's HP and the sum
-- (self_hp=, incoming=): a game shows whether the gate is too loose. nearbyEnemies: optional, asked only past the HP
-- test.
local LAST_WILL_HP = 0.25
local LAST_WILL_WINDOW = 2.0
X.lastWill = { health = 0, incoming = 0 }
function X.IsAboutToDie(unit, nearbyEnemies)
	if not Fu.IsValidHero(unit) or Fu.GetHP(unit) > LAST_WILL_HP or not unit:WasRecentlyDamagedByAnyHero(1.0) then
		return false
	end
	nearbyEnemies = nearbyEnemies or Fu.GetNearbyHeroes(unit, 1200, true, BOT_MODE_NONE)
	local incoming = 0
	for _, enemyHero in pairs(nearbyEnemies or {}) do
		if Fu.IsValidHero(enemyHero) and Fu.IsInRange(unit, enemyHero, 1200) then
			incoming = incoming
				+ (enemyHero:GetEstimatedDamageToTarget(true, unit, LAST_WILL_WINDOW, DAMAGE_TYPE_ALL) or 0)
		end
	end
	X.lastWill.health, X.lastWill.incoming = unit:GetHealth(), incoming
	return incoming >= unit:GetHealth()
end
-- The enemy hero in `enemies` within `range` that a unit-target spell can hit and that has the least HP, or nil.
function X.WeakestCastableEnemy(enemies, range)
	local weakest, lowestHealth = nil, math.huge
	for _, enemyHero in pairs(enemies) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.IsInRange(bot, enemyHero, range)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanCastOnTargetAdvanced(enemyHero)
			and enemyHero:GetHealth() < lowestHealth
		then
			weakest, lowestHealth = enemyHero, enemyHero:GetHealth()
		end
	end
	return weakest
end
-- What a stolen spell does as Rubick's last will: an enemy spell at the weakest enemy in reach, a spell with no team
-- around him when an enemy is within its radius, a no-target ally spell. A point spell with no team (a blink, a
-- leap) is left to the other rules: it is no attack. Toggles never get here.
function X.ConsiderLastWill(abilityInfo, nearbyEnemies, castRange, radius)
	if abilityInfo.targetsEnemy then
		if abilityInfo.isUnitTarget or abilityInfo.isPointTarget or abilityInfo.isAOE then
			local enemyHero = X.WeakestCastableEnemy(nearbyEnemies, castRange)
			if enemyHero ~= nil then
				if abilityInfo.isUnitTarget then
					return BOT_ACTION_DESIRE_VERYHIGH, enemyHero
				end
				return BOT_ACTION_DESIRE_VERYHIGH, enemyHero:GetLocation()
			end
		elseif abilityInfo.isNoTarget and X.CountEnemiesInRange(nearbyEnemies, radius) > 0 then
			return BOT_ACTION_DESIRE_VERYHIGH, nil
		end
		return BOT_ACTION_DESIRE_NONE
	end
	-- A unit-target ally spell already goes on himself under 35% HP (the ally rule below); a no-target one (a team
	-- heal, a save around him) otherwise waits for a team fight.
	if abilityInfo.targetsAlly then
		if abilityInfo.isNoTarget then
			return BOT_ACTION_DESIRE_VERYHIGH, nil
		end
		return BOT_ACTION_DESIRE_NONE
	end
	if abilityInfo.isNoTarget and X.CountEnemiesInRange(nearbyEnemies, radius) > 0 then
		return BOT_ACTION_DESIRE_VERYHIGH, nil
	end
	return BOT_ACTION_DESIRE_NONE
end
-- The order for a SmartCast answer. False when the answer has no usable target (a unit-target spell without a
-- unit, a point spell without a location): then nothing is ordered and nothing is logged.
local function IssueSmartCast(ability, abilityInfo, castTarget)
	if abilityInfo.isNoTarget or abilityInfo.isToggle then
		Fu.SetQueuePtToINT(bot, true)
		bot:ActionQueue_UseAbility(ability)
		return true
	end
	local isUnit = IsUnit(castTarget)
	if abilityInfo.isUnitTarget and isUnit then
		Fu.SetQueuePtToINT(bot, true)
		bot:ActionQueue_UseAbilityOnEntity(ability, castTarget)
		return true
	end
	if (abilityInfo.isPointTarget or abilityInfo.isAOE) and (isUnit or IsLocation(castTarget)) then
		Fu.SetQueuePtToINT(bot, true)
		bot:ActionQueue_UseAbilityOnLocation(ability, isUnit and castTarget:GetLocation() or castTarget)
		return true
	end
	return false
end
-- Returns true when an order went out. The caller (bots/heroes/hero_rubick.lua) then ends its think, so a later
-- Action_* (Spell Steal, Telekinesis, Fade Bolt) cannot clear the queued cast.
function X.ConsiderStolenSpell(ability)
	if ability == nil or ability:IsNull() then
		return false
	end
	local spellName = ability:GetName()
	if spellName == "rubick_empty1" or spellName == "rubick_empty2" or not ability:IsFullyCastable() then
		return false
	end
	if ability:IsPassive() then
		return false
	end
	bot = GetBot()
	if Fu.CanNotUseAbility(bot) then
		return false
	end
	botTarget = Fu.GetProperTarget(bot)
	for _, handler in ipairs(stolenSpellHandlers) do
		local owned, castTarget = handler.ConsiderStolenSpell(ability)
		if owned == CAST then
			X.LogStolenCast(spellName, "custom", castTarget, "rule", nil)
			return true
		end
		if owned then
			return false
		end
	end
	local abilityInfo = X.ClassifyAbility(ability)
	local castDesire, castTarget, why = X.SmartCast(ability, abilityInfo)
	if castDesire <= 0 or not IssueSmartCast(ability, abilityInfo, castTarget) then
		return false
	end
	X.LogStolenCast(spellName, "smart", castTarget, why, X.SpellRadius(abilityInfo))
	return true
end
function X.ClassifyAbility(ability)
	local behavior = ability:GetBehavior()
	local targetTeam = ability:GetTargetTeam()
	local targetType = ability:GetTargetType()
	return {
		name = ability:GetName(),
		castRange = ability:GetCastRange(),
		manaCost = ability:GetManaCost(),
		damage = ability:GetAbilityDamage(),
		aoeRadius = ability:GetAOERadius() or 0,
		isUltimate = ability:IsUltimate(),
		isNoTarget = bit.band(DOTA_ABILITY_BEHAVIOR_NO_TARGET, behavior) ~= 0,
		isUnitTarget = bit.band(DOTA_ABILITY_BEHAVIOR_UNIT_TARGET, behavior) ~= 0,
		isPointTarget = bit.band(DOTA_ABILITY_BEHAVIOR_POINT, behavior) ~= 0,
		isAOE = bit.band(DOTA_ABILITY_BEHAVIOR_AOE, behavior) ~= 0,
		isToggle = ability:IsToggle(),
		targetsEnemy = bit.band(DOTA_UNIT_TARGET_TEAM_ENEMY, targetTeam) ~= 0,
		targetsAlly = bit.band(DOTA_UNIT_TARGET_TEAM_FRIENDLY, targetTeam) ~= 0,
		targetsHero = bit.band(DOTA_UNIT_TARGET_HERO, targetType) ~= 0,
	}
end
-- The radius SmartCast assumes around a no-target or area spell: the ability's AoE radius, else 300. What
-- GetAOERadius() returns for a no-target spell is unverified, so the stolen-cast line prints it (radius=).
function X.SpellRadius(abilityInfo)
	return abilityInfo.aoeRadius > 0 and abilityInfo.aoeRadius or 300
end
-- Valid enemy heroes from `enemies` within `range` of Rubick.
function X.CountEnemiesInRange(enemies, range)
	local count = 0
	for _, enemyHero in pairs(enemies) do
		if Fu.IsValidHero(enemyHero) and Fu.IsInRange(bot, enemyHero, range) then
			count = count + 1
		end
	end
	return count
end
-- The nearest valid enemy hero from `enemies` within `range`, or nil. The list order of GetNearbyHeroes is not
-- documented, so [1] is not taken to be the nearest.
function X.NearestEnemyInRange(enemies, range)
	local nearest, nearestDistance = nil, math.huge
	for _, enemyHero in pairs(enemies) do
		if Fu.IsValidHero(enemyHero) then
			local distance = GetUnitToUnitDistance(bot, enemyHero)
			if distance <= range and distance < nearestDistance then
				nearest, nearestDistance = enemyHero, distance
			end
		end
	end
	return nearest
end
-- Stolen toggles a copy never flips: Morphling's attribute shifts move Rubick's own Strength and Agility (datafeed
-- hero_id=10, behavior 516). Agility shift takes HP away, and no fight rule here can weigh that.
local NO_TOGGLE = { morphling_morph_agi = true, morphling_morph_str = true }
-- After a toggle order, none for this long: a toggle can still read as before right after the order (Pudge's Rot
-- in game 020 flickered 10 times a second, bots/heroes/hero_pudge.lua).
local TOGGLE_LOCK = 1.5
-- Stolen toggles (Rot, Pulse Nova, Voodoo Restoration, Split Shot, ...) have no custom file. On: into a fight with an
-- enemy in reach, not while retreating. Off: while retreating (Rot burns Rubick, Pulse Nova his mana), or once no
-- enemy is within 1600.
function X.ConsiderToggle(
	ability,
	abilityInfo,
	nearbyEnemies,
	castRange,
	radius,
	isInTeamFight,
	isGoingOnSomeone,
	isRetreating
)
	local name = abilityInfo.name
	if NO_TOGGLE[name] then
		return BOT_ACTION_DESIRE_NONE
	end
	X._toggleAt = X._toggleAt or {}
	if DotaTime() < (X._toggleAt[name] or -math.huge) then
		return BOT_ACTION_DESIRE_NONE
	end
	local toggledOn = ability:GetToggleState() == true
	local why = nil
	if
		not toggledOn
		and not isRetreating
		and (isInTeamFight or isGoingOnSomeone)
		and X.CountEnemiesInRange(nearbyEnemies, math.max(castRange, radius)) > 0
	then
		why = "toggle-on"
	elseif toggledOn and (isRetreating or X.CountEnemiesInRange(nearbyEnemies, 1600) == 0) then
		why = "toggle-off"
	end
	if why == nil then
		return BOT_ACTION_DESIRE_NONE
	end
	X._toggleAt[name] = DotaTime() + TOGGLE_LOCK
	return why == "toggle-on" and BOT_ACTION_DESIRE_HIGH or BOT_ACTION_DESIRE_MODERATE, nil, why
end
function X.SmartCast(ability, abilityInfo)
	local castRange = abilityInfo.castRange + 200
	local radius = X.SpellRadius(abilityInfo)
	local nearbyEnemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE) or {}
	local nearbyAllies = bot:GetNearbyHeroes(1200, false, BOT_MODE_NONE) or {}
	local hpRatio = Fu.GetHP(bot)
	local isInTeamFight = Fu.IsInTeamFight(bot, 1200)
	local isGoingOnSomeone = Fu.IsGoingOnSomeone(bot)
	local isRetreating = Fu.IsRetreating(bot)
	if abilityInfo.isToggle then
		return X.ConsiderToggle(
			ability,
			abilityInfo,
			nearbyEnemies,
			castRange,
			radius,
			isInTeamFight,
			isGoingOnSomeone,
			isRetreating
		)
	end
	if X.IsAboutToDie(bot, nearbyEnemies) then
		local lastWillDesire, lastWillTarget = X.ConsiderLastWill(abilityInfo, nearbyEnemies, castRange, radius)
		if lastWillDesire > 0 then
			return lastWillDesire, lastWillTarget, "last-will"
		end
	end
	-- Ultimates first: the ultimate rule asks for a team fight or two enemies, and a safe fight. A no-target ultimate
	-- with no team (Ravage, Reverse Polarity, Echo Slam, Requiem: datafeed behavior 4, target team 0) must not reach
	-- the rule below, which would throw it at one enemy.
	if abilityInfo.isUltimate then
		return X.ConsiderUltimate(ability, abilityInfo, nearbyEnemies, nearbyAllies, castRange, radius, isInTeamFight)
	end
	-- A no-target spell with no team matched neither the enemy branch nor the ally branch, so it never cast. Lone
	-- Druid's Savage Roar is one (datafeed hero_id=80, behavior 4, target team 0). It acts around Rubick, so an enemy
	-- must be within its radius.
	if abilityInfo.isNoTarget and not abilityInfo.targetsEnemy and not abilityInfo.targetsAlly then
		if (isInTeamFight or isGoingOnSomeone or isRetreating) and X.CountEnemiesInRange(nearbyEnemies, radius) > 0 then
			return BOT_ACTION_DESIRE_MODERATE, nil
		end
		return BOT_ACTION_DESIRE_NONE
	end
	if abilityInfo.targetsEnemy or not abilityInfo.targetsAlly and not abilityInfo.isNoTarget then
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and enemyHero:IsChanneling()
				and Fu.IsInRange(bot, enemyHero, castRange)
				and not enemyHero:IsMagicImmune()
			then
				if abilityInfo.isUnitTarget then
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				elseif abilityInfo.isPointTarget or abilityInfo.isAOE then
					return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
				elseif abilityInfo.isNoTarget and Fu.IsInRange(bot, enemyHero, radius) then
					return BOT_ACTION_DESIRE_HIGH, nil
				end
			end
		end
		local tpTarget = Fu.GetTPTarget(bot, castRange)
		if tpTarget and not tpTarget:IsMagicImmune() then
			if abilityInfo.isUnitTarget then
				return BOT_ACTION_DESIRE_HIGH, tpTarget
			elseif abilityInfo.isPointTarget or abilityInfo.isAOE then
				return BOT_ACTION_DESIRE_HIGH, tpTarget:GetLocation()
			end
		end
		if abilityInfo.damage > 0 then
			for _, enemyHero in pairs(nearbyEnemies) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.IsInRange(bot, enemyHero, castRange)
					and not enemyHero:IsMagicImmune()
					and enemyHero:GetHealth() < abilityInfo.damage * 0.8
				then
					if abilityInfo.isUnitTarget then
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					elseif abilityInfo.isPointTarget then
						return BOT_ACTION_DESIRE_HIGH, enemyHero:GetExtrapolatedLocation(0.3)
					end
				end
			end
		end
		if isInTeamFight and #nearbyEnemies >= 2 then
			if abilityInfo.isAOE or abilityInfo.isPointTarget then
				local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
				if aoeLocation.count >= 2 then
					return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
				end
			end
			if abilityInfo.isNoTarget and X.CountEnemiesInRange(nearbyEnemies, radius) >= 2 then
				return BOT_ACTION_DESIRE_HIGH, nil
			end
		end
		if
			isGoingOnSomeone
			and Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and Fu.CanBeAttacked(botTarget)
			and not botTarget:IsMagicImmune()
		then
			if abilityInfo.isUnitTarget then
				return BOT_ACTION_DESIRE_MODERATE, botTarget
			elseif abilityInfo.isPointTarget then
				return BOT_ACTION_DESIRE_MODERATE, botTarget:GetExtrapolatedLocation(0.3)
			elseif abilityInfo.isNoTarget then
				return BOT_ACTION_DESIRE_MODERATE, nil
			end
		end
		if isRetreating and hpRatio < 0.5 then
			local nearestEnemy = X.NearestEnemyInRange(nearbyEnemies, castRange)
			if nearestEnemy ~= nil then
				if abilityInfo.isUnitTarget then
					return BOT_ACTION_DESIRE_HIGH, nearestEnemy
				elseif abilityInfo.isPointTarget then
					return BOT_ACTION_DESIRE_HIGH, nearestEnemy:GetLocation()
				elseif abilityInfo.isNoTarget then
					return BOT_ACTION_DESIRE_HIGH, nil
				end
			end
		end
	end
	if abilityInfo.targetsAlly and abilityInfo.isUnitTarget then
		for _, allyHero in pairs(nearbyAllies) do
			if Fu.IsValidHero(allyHero) and allyHero ~= bot and Fu.IsInRange(bot, allyHero, castRange) then
				local allyHpRatio = Fu.GetHP(allyHero)
				if allyHpRatio < 0.3 and allyHero:WasRecentlyDamagedByAnyHero(2.0) then
					return BOT_ACTION_DESIRE_HIGH, allyHero
				end
				if allyHpRatio < 0.5 and isInTeamFight then
					return BOT_ACTION_DESIRE_MODERATE, allyHero
				end
			end
		end
		if hpRatio < 0.35 and bot:WasRecentlyDamagedByAnyHero(2.0) then
			return BOT_ACTION_DESIRE_HIGH, bot
		end
	end
	if abilityInfo.isNoTarget and abilityInfo.targetsAlly and isInTeamFight then
		return BOT_ACTION_DESIRE_MODERATE, nil
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderUltimate(ability, abilityInfo, nearbyEnemies, nearbyAllies, castRange, radius, isInTeamFight)
	if not isInTeamFight and #nearbyEnemies < 2 then
		if
			abilityInfo.damage > 0
			and Fu.IsValidHero(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and botTarget:GetHealth() < abilityInfo.damage * 0.8
			and not botTarget:IsMagicImmune()
		then
			if abilityInfo.isUnitTarget then
				return BOT_ACTION_DESIRE_HIGH, botTarget
			elseif abilityInfo.isPointTarget then
				return BOT_ACTION_DESIRE_HIGH, botTarget:GetExtrapolatedLocation(0.3)
			end
		end
		return BOT_ACTION_DESIRE_NONE
	end
	if not Fu.IsSafeToUseUltimate(bot, bot:GetLocation(), 1200) then
		return BOT_ACTION_DESIRE_NONE
	end
	if abilityInfo.isAOE or abilityInfo.isPointTarget then
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), castRange, radius, 0, 0)
		if aoeLocation.count >= 2 then
			return BOT_ACTION_DESIRE_HIGH, aoeLocation.targetloc
		end
	end
	if abilityInfo.isUnitTarget then
		local weakestEnemy = nil
		local lowestHpRatio = 1
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsInRange(bot, enemyHero, castRange)
				and not enemyHero:IsMagicImmune()
				and Fu.CanBeAttacked(enemyHero)
				and Fu.GetHP(enemyHero) < lowestHpRatio
			then
				lowestHpRatio = Fu.GetHP(enemyHero)
				weakestEnemy = enemyHero
			end
		end
		if weakestEnemy then
			return BOT_ACTION_DESIRE_HIGH, weakestEnemy
		end
	end
	-- A no-target ultimate acts around Rubick: two enemies within its radius, not anywhere within 1600.
	if abilityInfo.isNoTarget and X.CountEnemiesInRange(nearbyEnemies, radius) >= 2 then
		return BOT_ACTION_DESIRE_HIGH, nil
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.CanCastAbilityROnTarget(target)
	if Fu.CanCastOnTargetAdvanced(target) and not target:HasModifier("modifier_arc_warden_tempest_double") then
		return Fu.CanCastOnNonMagicImmune(target)
	end
	return false
end
return X
