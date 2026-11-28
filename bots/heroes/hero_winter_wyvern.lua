-- Winter Wyvern: skill build, item build, and ability use for this hero.
local X = {}
local bot = GetBot()
local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
local AbilityContext = require(GetScriptDirectory() .. "/lib/systems/ability_context")
local AllyEscapeRules = require(GetScriptDirectory() .. "/lib/systems/ally_escape_rules")
local Minion = require(GetScriptDirectory() .. "/lib/hero/minion")
local sTalentList = Fu.Skill.GetTalentList(bot)
local sAbilityList = Fu.Skill.GetAbilityList(bot)
local sRole = Fu.Item.GetRoleItemsBuyList(bot)
local tTalentTreeList = { ["t25"] = { 10, 0 }, ["t20"] = { 10, 0 }, ["t15"] = { 10, 0 }, ["t10"] = { 0, 10 } }
local tAllAbilityBuildList = { { 1, 2, 2, 3, 2, 6, 2, 1, 1, 1, 6, 3, 3, 3, 6 } }
local nAbilityBuildList = Fu.Skill.GetRandomBuild(tAllAbilityBuildList)
local nTalentBuildList = Fu.Skill.GetTalentBuild(tTalentTreeList)
local sUtility = "item_team_aura"
local sRoleItemsBuyList = {}
-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 29,497 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_4"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_blink",
	"item_glimmer_cape",
	"item_force_staff",
	"item_aghanims_shard",
	"item_headdress",
	sUtility,
	"item_guardian_greaves",
	"item_cyclone",
	"item_hurricane_pike",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 75,070 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_5"] = {
	"item_tango",
	"item_blood_grenade",
	"item_double_branches",
	"item_magic_stick",
	"item_faerie_fire",
	"item_magic_wand",
	"item_ring_of_basilius",
	"item_arcane_boots",
	"item_blink",
	"item_glimmer_cape",
	"item_force_staff",
	"item_aghanims_shard",
	"item_mekansm",
	sUtility,
	"item_guardian_greaves",
	"item_cyclone",
	"item_hurricane_pike",
	"item_moon_shard",
	"item_ultimate_scepter_2",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 2,146 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_3"] = {
	"item_tango",
	"item_double_branches",
	"item_double_circlet",
	"item_faerie_fire",
	"item_null_talisman",
	"item_magic_wand",
	"item_power_treads",
	"item_witch_blade",
	"item_hurricane_pike",
	"item_ultimate_scepter",
	sUtility,
	"item_ultimate_scepter_2",
	"item_skadi",
	"item_sphere",
	"item_black_king_bar",
	"item_aghanims_shard",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 3,923 matches (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_2"] = {
	"item_tango",
	"item_double_branches",
	"item_circlet",
	"item_faerie_fire",
	"item_mantle",
	"item_null_talisman",
	"item_magic_wand",
	"item_power_treads",
	"item_witch_blade",
	"item_blink",
	"item_dragon_lance",
	"item_ultimate_scepter",
	"item_hurricane_pike",
	"item_devastator",
	"item_ultimate_scepter_2",
	"item_black_king_bar",
	"item_sphere",
	"item_aghanims_shard",
	"item_moon_shard",
}
-- Stratz 7.41f, week of 9 Nov 2026: pos 1 has 497 matches, built from pos 2 (3,923) (tools/item-builds/generate.js).
sRoleItemsBuyList["pos_1"] = sRoleItemsBuyList["pos_2"]
X["sBuyList"] = sRoleItemsBuyList[sRole]
X["sSellList"] = { "item_black_king_bar", "item_quelling_blade", "item_skadi", "item_witch_blade" }
if Fu.Role.IsPvNMode() or Fu.Role.IsAllShadow() then
	X["sBuyList"], X["sSellList"] = { "PvN_antimage" }, {}
end
nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"] =
	Fu.SetUserHeroInit(nAbilityBuildList, nTalentBuildList, X["sBuyList"], X["sSellList"])
X["sSkillList"] = Fu.Skill.GetSkillList(sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList)
-- Cast when cornered (retreating into 3+ enemies with no way out), before running further.
X["LastStandSpells"] = { { name = "winter_wyvern_winters_curse", kind = "unit" } }
X["bDefaultItem"] = false
function X.MinionThink(minionUnit)
	Minion.MinionThink(minionUnit)
end
local arcticBurnAbility =
	SafeAbility(bot:GetAbilityByName("winter_wyvern_arctic_burn"), "winter_wyvern_arctic_burn", "winter_wyvern")
local splinterBlastAbility =
	SafeAbility(bot:GetAbilityByName("winter_wyvern_splinter_blast"), "winter_wyvern_splinter_blast", "winter_wyvern")
local coldEmbraceAbility =
	SafeAbility(bot:GetAbilityByName("winter_wyvern_cold_embrace"), "winter_wyvern_cold_embrace", "winter_wyvern")
local wintersCurseAbility =
	SafeAbility(bot:GetAbilityByName("winter_wyvern_winters_curse"), "winter_wyvern_winters_curse", "winter_wyvern")
-- X.SampleAllyEnemyDist: player ID -> { { t =, dist = }, ... } oldest first, and the next sample time.
local allyEnemyDist = {}
local sampleAllyAt = -999
-- [SHy-WYVERN] lines: throttled per reason, at most once per 5s.
function X.LogWyvern(why, fmt, ...)
	X.LogWyvernAs(why, why, fmt, ...)
end
-- The same, with its own throttle key (two kinds of embrace-skip line don't hide each other).
function X.LogWyvernAs(key, why, fmt, ...)
	bot._wwLogAt = bot._wwLogAt or {}
	if DotaTime() < (bot._wwLogAt[key] or -999) then
		return
	end
	bot._wwLogAt[key] = DotaTime() + 5
	pcall(print, string.format("[SHy-WYVERN] t=%.0f " .. why .. " " .. fmt, DotaTime(), ...))
end
-- The ally's ready-or-not item of that name in its main or neutral slots, or nil.
function X.AllyItem(ally, name)
	local slot = ally:FindItemSlot(name)
	if slot == nil or slot < 0 or slot > 5 and slot ~= 16 then
		return nil
	end
	return ally:GetItemInSlot(slot)
end
-- Is the ally escaping (AllyEscapeRules, #238 game 083 44:51): an escape modifier on it, or an escape spell or item
-- cast in the last 1s or in its cast point now, or a Dark Willow whose own script has ordered an escape Shadow
-- Realm (ally._dwRealm, set by hero_dark_willow.lua at the order, why=retreat|dodge; the realm buff only shows 0.3s
-- later, game 083: mod=0.30, as long as the embrace's cast point). Returns the modifier, or nil and the spell and
-- how long ago ("phase": in its cast point, "order": her script's order), and for a jump why it counts
-- (JumpIsEscape: "retreat" or "away"), or nil.
-- A jump that goes either way (AllyEscapeRules.EITHER_WAY: a blink, leap or Force Staff) counts only when the ally
-- moved away from the enemy heroes or is in retreat mode (game 091, 34:51: Dark Willow's Blink onto Axe skipped the
-- embrace). One that doesn't count is passed over, and the other spells are still checked. Logs:
--   [SHy-WYVERN] escape-not-counted why=initiation|unknown ally= spell= ago= before= now=  (once per 5s)
function X.AllyEscaping(ally)
	local realm = ally._dwRealm
	if type(realm) == "table" and realm.why ~= nil and realm.why ~= "attack" then
		return nil, "dark_willow_shadow_realm", "order"
	end
	for _, name in ipairs(AllyEscapeRules.MODIFIERS) do
		if ally:HasModifier(name) then
			return name
		end
	end
	local passed = nil
	for _, name in ipairs(AllyEscapeRules.SPELLS) do
		local ability
		if string.sub(name, 1, 5) == "item_" then
			ability = X.AllyItem(ally, name)
		else
			ability = ally:GetAbilityByName(name)
		end
		if ability ~= nil and not ability:IsNull() then
			local agoText, ago = nil, nil
			if ability:IsInAbilityPhase() then
				agoText = "phase"
			else
				local just, secondsAgo =
					AllyEscapeRules.JustCast(ability:GetCooldown(), ability:GetCooldownTimeRemaining())
				if just then
					ago = secondsAgo
					agoText = string.format("%.2f", secondsAgo)
				end
			end
			if agoText ~= nil then
				if not AllyEscapeRules.EITHER_WAY[name] then
					return nil, name, agoText
				end
				-- In its cast point the ally has not moved yet: no sample before (only retreat mode counts).
				local before = ago ~= nil
						and AllyEscapeRules.SampleBefore(allyEnemyDist[ally:GetPlayerID()], DotaTime(), ago)
					or nil
				local nowDist = X.NearestEnemyDist(ally)
				local counts, jumpWhy =
					AllyEscapeRules.JumpIsEscape(before, nowDist, ally:GetActiveMode() == BOT_MODE_RETREAT)
				if counts then
					return nil, name, agoText, jumpWhy
				end
				passed = passed
					or {
						name = name,
						ago = agoText,
						why = jumpWhy,
						before = before ~= nil and before.dist or nil,
						now = nowDist,
					}
			end
		end
	end
	if passed ~= nil then
		X.LogWyvernAs(
			"escape-not-counted",
			"escape-not-counted",
			"why=%s ally=%s spell=%s ago=%s before=%s now=%s",
			passed.why,
			(string.gsub(ally:GetUnitName(), "npc_dota_hero_", "")),
			passed.name,
			passed.ago,
			passed.before ~= nil and string.format("%.0f", passed.before) or "-",
			passed.now ~= nil and string.format("%.0f", passed.now) or "-"
		)
	end
	return nil
end
-- The nearest visible real enemy hero within 1600 of the unit, or nil.
function X.NearestEnemyDist(unit)
	local nearest = nil
	for _, foe in pairs(Fu.GetNearbyHeroes(unit, 1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(foe) and not Fu.IsSuspiciousIllusion(foe) then
			local dist = GetUnitToUnitDistance(unit, foe)
			if nearest == nil or dist < nearest then
				nearest = dist
			end
		end
	end
	return nearest
end
-- Each ally's nearest enemy hero 4 times a second for the last 2s (by player ID), so X.AllyEscaping can tell whether
-- a jump moved it away (AllyEscapeRules.SampleBefore). Runs at the top of every SkillsComplement.
function X.SampleAllyEnemyDist()
	local now = DotaTime()
	if now < sampleAllyAt then
		return
	end
	sampleAllyAt = now + 0.25
	for i = 1, 5 do
		local ally = GetTeamMember(i)
		if ally ~= nil and not ally:IsNull() and not ally:IsAlive() then
			allyEnemyDist[ally:GetPlayerID()] = nil
		elseif ally ~= nil and not ally:IsNull() then
			local pid = ally:GetPlayerID()
			local samples = allyEnemyDist[pid] or {}
			while samples[1] ~= nil and samples[1].t < now - 2 do
				table.remove(samples, 1)
			end
			samples[#samples + 1] = { t = now, dist = X.NearestEnemyDist(ally) }
			allyEnemyDist[pid] = samples
		end
	end
end
-- True when a visible real enemy hero within 1600 of the ally has it as its attack target.
function X.IsAttackedByEnemyHero(ally)
	for _, foe in pairs(Fu.GetNearbyHeroes(ally, 1600, true, BOT_MODE_NONE) or {}) do
		if Fu.IsValidHero(foe) and not Fu.IsSuspiciousIllusion(foe) and foe:GetAttackTarget() == ally then
			return true
		end
	end
	return false
end
-- Cold Embrace freezes the ally, which ends a channel (game 077, 6:02: it cancelled Undying's Town Portal out of the
-- bottom lane). On a channelling ally (a TP or a channelled spell) it goes only when the enemy heroes attacking it
-- are expected to kill it before the channel ends (Fu.ChannelSaveCheck; maintainer: "if enemy guaranteed to kill
-- ally using attack hit, it is plausible"); otherwise the channel is the save. Cast point 0.3 (datafeed, hero 112).
-- Every ally-target embrace goes through here. Logs:
--   [SHy-WYVERN] embrace-save why= ally= hp= channel=no|yes [kind= left= dmg= health= ratio= attackers=]
--   [SHy-WYVERN] embrace-skip why=channel ally= kind= left= dmg= health= ratio= attackers=  (once per 5s)
--   [SHy-WYVERN] embrace-skip why=escaping save= ally= hp= mod= spell= ago= jump=  (once per 5s): the ally is escaping
--                (X.AllyEscaping; game 083 44:51), checked before the channel rule (Phase Shift is a channel).
local EMBRACE_CAST_POINT = 0.3
function X.EmbraceAlly(allyHero, why)
	local name = (string.gsub(allyHero:GetUnitName(), "npc_dota_hero_", ""))
	local escapeMod, escapeSpell, escapeAgo, escapeJump = X.AllyEscaping(allyHero)
	if escapeMod ~= nil or escapeSpell ~= nil then
		X.LogWyvernAs(
			"embrace-skip-escaping",
			"embrace-skip",
			"why=escaping save=%s ally=%s hp=%.2f mod=%s spell=%s ago=%s jump=%s",
			why,
			name,
			Fu.GetHP(allyHero),
			escapeMod or "-",
			escapeSpell or "-",
			escapeAgo or "-",
			escapeJump or "-"
		)
		return false
	end
	local channelling, allowed, info = Fu.ChannelSaveCheck(allyHero, EMBRACE_CAST_POINT)
	if not channelling then
		X.LogWyvern("embrace-save", "why=%s ally=%s hp=%.2f channel=no", why, name, Fu.GetHP(allyHero))
		return true
	end
	local fields = string.format(
		"ally=%s kind=%s left=%.1f src=%s dmg=%.0f health=%.0f ratio=%.2f attackers=%d",
		name,
		info.kind,
		info.left,
		info.src,
		info.dmg,
		info.hp,
		info.ratio,
		info.attackers
	)
	if allowed then
		X.LogWyvern("embrace-save", "why=%s hp=%.2f channel=yes %s", why, Fu.GetHP(allyHero), fields)
		return true
	end
	X.LogWyvern("embrace-skip", "why=channel save=%s %s", why, fields)
	return false
end
local arcticBurnDesire
local splinterBlastDesire, splinterBlastTarget
local coldEmbraceDesire, coldEmbraceTarget
local wintersCurseDesire, wintersCurseTarget
local botTarget
local isEngaging
local isRetreating
local hpRatio
function X.SkillsComplement()
	X.SampleAllyEnemyDist()
	X.EmbraceCastCheck()
	if Fu.CanNotUseAbility(bot) then
		return
	end
	local context = AbilityContext.Build(bot)
	isEngaging = context.isEngaging
	isRetreating = context.isRetreating
	hpRatio = context.hp
	botTarget = context.target
	wintersCurseDesire, wintersCurseTarget = X.ConsiderWintersCurse()
	if wintersCurseDesire > 0 then
		bot:Action_UseAbilityOnEntity(wintersCurseAbility, wintersCurseTarget)
		return
	end
	coldEmbraceDesire, coldEmbraceTarget = X.ConsiderColdEmbrace()
	if coldEmbraceDesire > 0 then
		bot:Action_UseAbilityOnEntity(coldEmbraceAbility, coldEmbraceTarget)
		if coldEmbraceTarget ~= bot then
			bot._wwEmbrace = { ally = coldEmbraceTarget, at = DotaTime() }
		end
		return
	end
	splinterBlastDesire, splinterBlastTarget = X.ConsiderSplinterBlast()
	if splinterBlastDesire > 0 then
		bot:Action_UseAbilityOnEntity(splinterBlastAbility, splinterBlastTarget)
		return
	end
	arcticBurnDesire = X.ConsiderArcticBurn()
	if arcticBurnDesire > 0 then
		bot:Action_UseAbility(arcticBurnAbility)
		return
	end
end
function X.ConsiderArcticBurn()
	if not arcticBurnAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE
	end
	local attackRangeBonus = arcticBurnAbility:GetSpecialValueInt("attack_range_bonus")
	local attackRange = bot:GetAttackRange()
	local burnAttackRange = attackRange + attackRangeBonus
	if not bot:HasScepter() then
		if Fu.IsStuck(bot) then
			return BOT_ACTION_DESIRE_HIGH
		end
		if isEngaging then
			if
				Fu.IsValidTarget(botTarget)
				and Fu.CanCastOnNonMagicImmune(botTarget)
				and Fu.IsInRange(bot, botTarget, burnAttackRange)
				and not Fu.IsSuspiciousIllusion(botTarget)
				and not Fu.IsDisabled(botTarget)
				and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			then
				local nearbyAllies = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
				local nearbyEnemies = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
				if nearbyAllies ~= nil and nearbyEnemies ~= nil and #nearbyAllies >= #nearbyEnemies then
					if Fu.IsInLaningPhase() then
						if Fu.IsChasingTarget(bot, botTarget) then
							return BOT_ACTION_DESIRE_HIGH
						end
					else
						return BOT_ACTION_DESIRE_HIGH
					end
				end
			end
		end
		if isRetreating then
			local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
			for _, enemyHero in pairs(nearbyEnemies) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.IsChasingTarget(enemyHero, bot)
					and not Fu.IsSuspiciousIllusion(enemyHero)
					and not Fu.IsDisabled(enemyHero)
				then
					local nearbyAllies = Fu.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
					local targetAllies = Fu.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
					if
						nearbyAllies ~= nil
						and targetAllies ~= nil
						and (#targetAllies > #nearbyAllies or bot:WasRecentlyDamagedByAnyHero(2))
					then
						return BOT_ACTION_DESIRE_HIGH
					end
				end
			end
		end
	else
		-- Was "not toggle == false" (= toggle on), which turned the scepter toggle OFF when stuck.
		if Fu.IsStuck(bot) and arcticBurnAbility:GetToggleState() == false then
			return BOT_ACTION_DESIRE_HIGH
		end
		if isEngaging then
			if
				Fu.IsValidTarget(botTarget)
				and Fu.CanCastOnNonMagicImmune(botTarget)
				and Fu.IsInRange(bot, botTarget, burnAttackRange)
				and not Fu.IsSuspiciousIllusion(botTarget)
				and not Fu.IsDisabled(botTarget)
				and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
			then
				if arcticBurnAbility:GetToggleState() == false then
					return BOT_ACTION_DESIRE_HIGH
				else
					return BOT_ACTION_DESIRE_NONE
				end
			end
		end
		if Fu.IsInTeamFight(bot, burnAttackRange) then
			local enemiesInRange = Fu.GetEnemiesNearLoc(bot:GetLocation(), burnAttackRange)
			if enemiesInRange ~= nil and #enemiesInRange >= 1 then
				if arcticBurnAbility:GetToggleState() == false then
					return BOT_ACTION_DESIRE_HIGH
				else
					return BOT_ACTION_DESIRE_NONE
				end
			end
		end
		if isRetreating then
			local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
			if nearbyEnemies ~= nil and #nearbyEnemies == 0 then
				if arcticBurnAbility:GetToggleState() == true then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
			for _, enemyHero in pairs(nearbyEnemies) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.IsChasingTarget(enemyHero, bot)
					and not Fu.IsSuspiciousIllusion(enemyHero)
					and not Fu.IsDisabled(enemyHero)
				then
					local nearbyAllies = Fu.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
					local targetAllies = Fu.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
					if
						nearbyAllies ~= nil
						and targetAllies ~= nil
						and (#targetAllies > #nearbyAllies or bot:WasRecentlyDamagedByAnyHero(2))
					then
						if arcticBurnAbility:GetToggleState() == false then
							return BOT_ACTION_DESIRE_HIGH
						else
							return BOT_ACTION_DESIRE_NONE
						end
					end
				end
			end
		end
		if arcticBurnAbility:GetToggleState() == true then
			local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1500, true, BOT_MODE_NONE)
			if #nearbyEnemies <= 0 then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end
function X.ConsiderSplinterBlast()
	if not splinterBlastAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, splinterBlastAbility:GetCastRange())
	local damage = splinterBlastAbility:GetSpecialValueInt("damage")
	local splitRadius = splinterBlastAbility:GetSpecialValueInt("split_radius")
	local manaCost = splinterBlastAbility:GetManaCost()
	-- Kill secure: heroes were listed within castRange and then required NOT in castRange, so
	-- this never fired. The primary target takes no damage (splinters hit units around it), so
	-- list heroes out to castRange + split radius and cast on a unit near them that is in cast range.
	local enemiesInReach = Fu.GetNearbyHeroes(bot, math.min(1600, castRange + splitRadius), true, BOT_MODE_NONE)
	for _, enemyHero in pairs(enemiesInReach) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnNonMagicImmune(enemyHero)
			and Fu.CanKillTarget(enemyHero, damage, DAMAGE_TYPE_MAGICAL)
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and not enemyHero:HasModifier("modifier_abaddon_borrowed_time")
			and not enemyHero:HasModifier("modifier_dazzle_shallow_grave")
			and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and not enemyHero:HasModifier("modifier_oracle_false_promise_timer")
			and not enemyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
		then
			local creepsNearTarget = enemyHero:GetNearbyCreeps(splitRadius, true)
			for _, creep in pairs(creepsNearTarget) do
				if Fu.IsValid(creep) and Fu.CanCastOnNonMagicImmune(creep) and Fu.IsInRange(bot, creep, castRange) then
					X.LogWyvern("splinter-kill", "target=%s via=%s", enemyHero:GetUnitName(), creep:GetUnitName())
					return BOT_ACTION_DESIRE_HIGH, creep
				end
			end
			local targetAllies = Fu.GetNearbyHeroes(enemyHero, splitRadius, false, BOT_MODE_NONE)
			for _, heroNearTarget in pairs(targetAllies) do
				if
					Fu.IsValidHero(heroNearTarget)
					and Fu.CanCastOnNonMagicImmune(heroNearTarget)
					and Fu.IsNotSelf(enemyHero, heroNearTarget)
					and Fu.IsInRange(bot, heroNearTarget, castRange)
				then
					X.LogWyvern(
						"splinter-kill",
						"target=%s via=%s",
						enemyHero:GetUnitName(),
						heroNearTarget:GetUnitName()
					)
					return BOT_ACTION_DESIRE_HIGH, heroNearTarget
				end
			end
		end
	end
	if isEngaging then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.CanCastOnNonMagicImmune(botTarget)
			and Fu.IsInRange(bot, botTarget, castRange)
			and not Fu.IsSuspiciousIllusion(botTarget)
			and not Fu.IsDisabled(botTarget)
			and not botTarget:HasModifier("modifier_faceless_void_chronosphere_freeze")
			and not botTarget:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			local nearbyAllies = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			local nearbyEnemies = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			if nearbyAllies ~= nil and nearbyEnemies ~= nil and #nearbyAllies >= #nearbyEnemies then
				local creepsNearTarget = botTarget:GetNearbyCreeps(splitRadius, true)
				for _, creep in pairs(creepsNearTarget) do
					if Fu.IsValid(creep) and Fu.CanCastOnNonMagicImmune(creep) then
						return BOT_ACTION_DESIRE_HIGH, creep
					end
				end
				local targetAllies = Fu.GetNearbyHeroes(botTarget, splitRadius, false, BOT_MODE_NONE)
				for _, enemyHero in pairs(targetAllies) do
					if
						Fu.IsValidHero(enemyHero)
						and Fu.CanCastOnNonMagicImmune(enemyHero)
						and Fu.IsNotSelf(botTarget, enemyHero)
					then
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					end
				end
			end
		end
	end
	if isRetreating then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsChasingTarget(enemyHero, bot)
				and Fu.IsInRange(bot, enemyHero, castRange)
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and not enemyHero:HasModifier("modifier_winter_wyvern_arctic_burn_slow")
			then
				local nearbyAllies = Fu.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local targetAllies = Fu.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
				if
					nearbyAllies ~= nil
					and targetAllies ~= nil
					and (#targetAllies > #nearbyAllies or bot:WasRecentlyDamagedByAnyHero(2))
				then
					local creepsNearTarget = enemyHero:GetNearbyCreeps(splitRadius, true)
					for _, creep in pairs(creepsNearTarget) do
						if Fu.IsValid(creep) and Fu.CanCastOnNonMagicImmune(creep) then
							return BOT_ACTION_DESIRE_HIGH, creep
						end
					end
					targetAllies = Fu.GetNearbyHeroes(enemyHero, splitRadius, false, BOT_MODE_NONE)
					for _, heroNearTarget in pairs(targetAllies) do
						if
							Fu.IsValidHero(heroNearTarget)
							and Fu.CanCastOnNonMagicImmune(heroNearTarget)
							and Fu.IsNotSelf(enemyHero, heroNearTarget)
						then
							return BOT_ACTION_DESIRE_HIGH, heroNearTarget
						end
					end
				end
			end
		end
	end
	if Fu.IsPushing(bot) or Fu.IsDefending(bot) then
		local killableCreeps = {}
		local toughCreep = nil
		local laneCreeps = bot:GetNearbyLaneCreeps(1600, true)
		for _, creep in pairs(laneCreeps) do
			if Fu.IsValid(creep) and Fu.CanBeAttacked(creep) then
				if creep:GetHealth() <= damage then
					table.insert(killableCreeps, creep)
				end
				if creep:GetHealth() > damage then
					toughCreep = creep
				end
			end
		end
		if
			toughCreep ~= nil
			and #killableCreeps >= 3
			and Fu.GetManaAfter(manaCost) > 0.4
			and not Fu.IsThereNonSelfCoreNearby(1200)
		then
			return BOT_ACTION_DESIRE_HIGH, toughCreep
		end
		if
			toughCreep == nil
			and #killableCreeps >= 4
			and Fu.GetManaAfter(manaCost) > 0.4
			and not Fu.IsThereNonSelfCoreNearby(1200)
		then
			return BOT_ACTION_DESIRE_HIGH, killableCreeps[1]
		end
		if laneCreeps ~= nil and #laneCreeps >= 4 and Fu.GetManaAfter(manaCost) > 0.4 then
			return BOT_ACTION_DESIRE_HIGH, laneCreeps[1]
		end
		local aoeLocation = bot:FindAoELocation(true, true, bot:GetLocation(), 1600, splitRadius, 0, 0)
		local nearbyEnemies = Fu.GetEnemiesNearLoc(aoeLocation.targetloc, splitRadius)
		if
			nearbyEnemies ~= nil
			and #nearbyEnemies >= 2
			and Fu.Utils.IsValidUnit(nearbyEnemies[1])
			and Fu.IsInRange(bot, nearbyEnemies[1], castRange)
		then
			return BOT_ACTION_DESIRE_HIGH, nearbyEnemies[1]
		end
	end
	if Fu.IsLaning(bot) then
		local killableCreeps = {}
		local toughCreep = nil
		local laneCreeps = bot:GetNearbyLaneCreeps(1600, true)
		for _, creep in pairs(laneCreeps) do
			if Fu.IsValid(creep) and Fu.CanBeAttacked(creep) then
				if creep:GetHealth() <= damage then
					table.insert(killableCreeps, creep)
				end
				if creep:GetHealth() > damage then
					toughCreep = creep
				end
			end
		end
		if
			toughCreep ~= nil
			and #killableCreeps >= 3
			and Fu.GetManaAfter(manaCost) > 0.5
			and not Fu.IsThereNonSelfCoreNearby(1200)
		then
			return BOT_ACTION_DESIRE_HIGH, toughCreep
		end
		if
			toughCreep == nil
			and #killableCreeps >= 4
			and Fu.GetManaAfter(manaCost) > 0.5
			and not Fu.IsThereNonSelfCoreNearby(1200)
		then
			return BOT_ACTION_DESIRE_HIGH, killableCreeps[1]
		end
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), castRange)
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.CanCastOnNonMagicImmune(enemyHero)
				and Fu.GetManaAfter(manaCost) > 0.35
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and not enemyHero:HasModifier("modifier_winter_wyvern_arctic_burn_slow")
			then
				local nearbyAllies = Fu.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE)
				for _, allyHero in pairs(nearbyAllies) do
					if
						Fu.IsValidHero(allyHero)
						and (Fu.IsChasingTarget(enemyHero, allyHero) or enemyHero:GetAttackTarget() == allyHero)
						and not Fu.IsSuspiciousIllusion(allyHero)
					then
						local creepsNearTarget = enemyHero:GetNearbyCreeps(splitRadius, true)
						for _, creep in pairs(creepsNearTarget) do
							if Fu.IsValid(creep) and Fu.CanCastOnNonMagicImmune(creep) then
								return BOT_ACTION_DESIRE_HIGH, creep
							end
						end
						local targetAllies = Fu.GetNearbyHeroes(enemyHero, splitRadius, false, BOT_MODE_NONE)
						for _, heroNearTarget in pairs(targetAllies) do
							if
								Fu.IsValidHero(heroNearTarget)
								and Fu.CanCastOnNonMagicImmune(heroNearTarget)
								and Fu.IsNotSelf(enemyHero, heroNearTarget)
							then
								return BOT_ACTION_DESIRE_HIGH, heroNearTarget
							end
						end
					end
				end
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
-- An ally embrace in its 0.3s cast point (datafeed hero 112) whose ally started escaping after the order: stop the
-- cast. Game 083, 44:51: Wyvern's embrace-save line came before Dark Willow's shadow-realm-cast line in the same
-- second, so the check at the decision could not see the realm. Runs every think, before the CanNotUseAbility return
-- (true while casting). Whether Action_ClearActions(true) stops a cast point is unverified (docs/BOT_API_RUNTIME.md:
-- it stops an attack wind-up), so a result line follows 0.5s later. Lines:
--   [SHy-WYVERN] embrace-cancel why=escaping ally= hp= mod= spell= ago=
--   [SHy-WYVERN] embrace-cancel-result ally= cast=yes|no  (cast=yes: the embrace went out anyway)
function X.EmbraceCastCheck()
	local pending = bot._wwEmbrace
	if pending == nil then
		return
	end
	local now = DotaTime()
	if pending.cancelAt ~= nil then
		if now - pending.cancelAt >= 0.5 then
			bot._wwEmbrace = nil
			X.LogWyvern(
				"embrace-cancel-result",
				"ally=%s cast=%s",
				pending.name,
				coldEmbraceAbility:GetCooldownTimeRemaining() > 0 and "yes" or "no"
			)
		end
		return
	end
	-- 1s: the 0.3s cast point plus a turn towards the ally.
	if now - pending.at > 1.0 then
		bot._wwEmbrace = nil
		return
	end
	local ally = pending.ally
	if not coldEmbraceAbility:IsInAbilityPhase() or not Fu.IsValidHero(ally) then
		return
	end
	local escapeMod, escapeSpell, escapeAgo, escapeJump = X.AllyEscaping(ally)
	if escapeMod == nil and escapeSpell == nil then
		return
	end
	bot:Action_ClearActions(true)
	pending.cancelAt = now
	pending.name = (string.gsub(ally:GetUnitName(), "npc_dota_hero_", ""))
	X.LogWyvern(
		"embrace-cancel",
		"why=escaping ally=%s hp=%.2f mod=%s spell=%s ago=%s jump=%s",
		pending.name,
		Fu.GetHP(ally),
		escapeMod or "-",
		escapeSpell or "-",
		escapeAgo or "-",
		escapeJump or "-"
	)
end
function X.ConsiderColdEmbrace()
	if not coldEmbraceAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, coldEmbraceAbility:GetCastRange())
	local duration = coldEmbraceAbility:GetSpecialValueFloat("duration")
	local healAdditive = coldEmbraceAbility:GetSpecialValueInt("heal_additive")
	-- datafeed: heal_percentage is fractional (1.5/2.5/3.5/4.5); GetSpecialValueInt truncated it
	local healPercentage = coldEmbraceAbility:GetSpecialValueFloat("heal_percentage") / 100
	local alliesInCastRange = Fu.GetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)
	for _, allyHero in pairs(alliesInCastRange) do
		if
			Fu.IsValidHero(allyHero)
			and Fu.IsCore(allyHero)
			and not Fu.IsSuspiciousIllusion(allyHero)
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
		then
			local enemiesNearAlly = Fu.GetNearbyHeroes(allyHero, 1600, true, BOT_MODE_NONE)
			for _, enemyHero in pairs(enemiesNearAlly) do
				if
					Fu.IsValidHero(enemyHero)
					and enemyHero:GetAttackTarget() == allyHero
					and not Fu.IsSuspiciousIllusion(enemyHero)
				then
					if
						(
							allyHero:HasModifier("modifier_legion_commander_duel") and Fu.GetHP(allyHero) < 0.25
							or allyHero:HasModifier("modifier_enigma_black_hole_pull")
							or allyHero:HasModifier("modifier_faceless_void_chronosphere_freeze")
						) and X.EmbraceAlly(allyHero, "disabled")
					then
						return BOT_ACTION_DESIRE_HIGH, allyHero
					end
				end
			end
		end
	end
	if isEngaging then
		if
			Fu.IsValidTarget(botTarget)
			and Fu.IsInRange(bot, botTarget, bot:GetCurrentVisionRange())
			and not Fu.IsSuspiciousIllusion(botTarget)
		then
			local alliesNearTarget = Fu.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			local nearbyEnemies = Fu.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			if alliesNearTarget ~= nil and nearbyEnemies ~= nil and #alliesNearTarget >= #nearbyEnemies then
				local nearbyAllies = Fu.GetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)
				for _, allyHero in pairs(nearbyAllies) do
					if
						Fu.IsValidHero(allyHero)
						and Fu.GetHP(allyHero) < 0.3
						and Fu.IsCore(allyHero)
						and not Fu.IsSuspiciousIllusion(allyHero)
						and not Fu.IsInEtherealForm(allyHero)
						and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
						and not allyHero:HasModifier("modifier_necrolyte_sadist_active")
					then
						if X.EmbraceAlly(allyHero, "fight-core") then
							return BOT_ACTION_DESIRE_HIGH, allyHero
						end
					end
				end
				for _, allyHero in pairs(nearbyAllies) do
					if
						Fu.IsValidHero(allyHero)
						and Fu.GetHP(allyHero) < 0.25
						and not Fu.IsCore(allyHero)
						and not Fu.IsSuspiciousIllusion(allyHero)
						and not Fu.IsInEtherealForm(allyHero)
						and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
						and X.EmbraceAlly(allyHero, "fight-support")
					then
						return BOT_ACTION_DESIRE_HIGH, allyHero
					end
				end
			end
		end
	end
	if isRetreating then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsChasingTarget(enemyHero, bot)
				and hpRatio < 0.25
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				-- Was "not not enemyHero:HasModifier(fountain)": only fired while the chasing enemy stood in
				-- the fountain, so the retreat self-embrace never happened. Meant: Wyvern not at base.
				and not bot:HasModifier("modifier_fountain_aura_buff")
			then
				local nearbyAllies = Fu.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local targetAllies = Fu.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
				if
					nearbyAllies ~= nil
					and targetAllies ~= nil
					and (#targetAllies > #nearbyAllies or bot:WasRecentlyDamagedByAnyHero(1))
				then
					return BOT_ACTION_DESIRE_HIGH, bot
				end
			end
		end
	end
	for _, allyHero in pairs(alliesInCastRange) do
		if
			Fu.IsValidHero(allyHero)
			and Fu.GetHP(allyHero) < 0.25
			and not Fu.IsSuspiciousIllusion(allyHero)
			and not Fu.IsInEtherealForm(allyHero)
			and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			-- Was "not not": the low-HP ally save fired only on allies standing in the fountain.
			-- Now: ally not at base, hit by a hero in the last 2.5s and an enemy hero is attacking it
			-- right now (the cocoon freezes the ally, so not on one who is getting away).
			and not allyHero:HasModifier("modifier_fountain_aura_buff")
			and allyHero:WasRecentlyDamagedByAnyHero(2.5)
			and X.IsAttackedByEnemyHero(allyHero)
			and X.EmbraceAlly(allyHero, "low-hp")
		then
			return BOT_ACTION_DESIRE_HIGH, allyHero
		end
	end
	if Fu.IsDoingTormentor(bot) then
		if Fu.IsTormentor(botTarget) and Fu.IsInRange(bot, botTarget, 500) then
			if hpRatio < 0.2 then
				return BOT_ACTION_DESIRE_HIGH, bot
			end
			local nearbyAllies = Fu.GetNearbyHeroes(bot, castRange, false, BOT_MODE_NONE)
			for _, allyHero in pairs(nearbyAllies) do
				if
					Fu.IsValidHero(allyHero)
					and Fu.GetHP(allyHero) < 0.3
					and not allyHero:IsIllusion()
					and not allyHero:HasModifier("modifier_abaddon_borrowed_time")
					and not allyHero:HasModifier("modifier_dazzle_shallow_grave")
					and not allyHero:HasModifier("modifier_templar_assassin_refraction_absorb")
					and not allyHero:HasModifier("modifier_obsidian_destroyer_astral_imprisonment_prison")
					and X.EmbraceAlly(allyHero, "tormentor")
				then
					return BOT_ACTION_DESIRE_HIGH, allyHero
				end
			end
		end
	end
	if hpRatio < 0.2 then
		return BOT_ACTION_DESIRE_HIGH, bot
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
function X.ConsiderWintersCurse()
	if not wintersCurseAbility:IsFullyCastable() then
		return BOT_ACTION_DESIRE_NONE, nil
	end
	local castRange = Fu.GetProperCastRange(false, bot, wintersCurseAbility:GetCastRange())
	local curseRadius = wintersCurseAbility:GetSpecialValueInt("radius")
	local duration = wintersCurseAbility:GetSpecialValueFloat("duration")
	if Fu.IsInTeamFight(bot, castRange + 200) then
		local enemiesInRange = Fu.GetEnemiesNearLoc(bot:GetLocation(), castRange + 200)
		if enemiesInRange ~= nil and #enemiesInRange >= 3 then
			local nearbyAllies = Fu.GetAlliesNearLoc(bot:GetLocation(), 1000)
			if nearbyAllies ~= nil and #nearbyAllies <= #enemiesInRange then
				local weakestEnemy = Fu.GetAttackableWeakestUnit(bot, castRange + 200, true, true)
				if weakestEnemy ~= nil then
					local nearbyAllies = Fu.GetNearbyHeroes(weakestEnemy, 400, true, BOT_MODE_NONE)
					if nearbyAllies == nil or #nearbyAllies <= 0 then
						if
							Fu.IsValidHero(weakestEnemy)
							and Fu.GetHP(weakestEnemy) >= 0.5
							and not Fu.IsSuspiciousIllusion(weakestEnemy)
							and not Fu.IsDisabled(weakestEnemy)
							and not weakestEnemy:HasModifier("modifier_necrolyte_reapers_scythe")
							and not Fu.IsUnderLongDurationStun(weakestEnemy)
						then
							return BOT_ACTION_DESIRE_HIGH, weakestEnemy
						end
					end
				end
			end
		end
	end
	if isEngaging then
		local bestTarget = nil
		local highestDamage = 0
		local nearbyEnemies = Fu.GetEnemiesNearLoc(bot:GetLocation(), bot:GetCurrentVisionRange())
		if nearbyEnemies ~= nil and #nearbyEnemies >= 3 then
			for _, enemyHero in pairs(nearbyEnemies) do
				if
					Fu.IsValidHero(enemyHero)
					and Fu.IsInRange(bot, enemyHero, castRange)
					and not Fu.IsSuspiciousIllusion(enemyHero)
					and not Fu.IsDisabled(enemyHero)
					and Fu.GetHP(enemyHero) >= 0.5
					and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
					and not Fu.IsUnderLongDurationStun(enemyHero)
				then
					local nearbyAllies = Fu.GetAlliesNearLoc(enemyHero:GetLocation(), 400)
					local targetAllies = Fu.GetEnemiesNearLoc(enemyHero:GetLocation(), 1200)
					local estimatedDamage = enemyHero:GetEstimatedDamageToTarget(true, bot, duration, DAMAGE_TYPE_ALL)
					if
						(nearbyAllies == nil or #nearbyAllies <= 0)
						and targetAllies ~= nil
						and estimatedDamage > highestDamage
					then
						targetAllies = Fu.GetEnemiesNearLoc(enemyHero:GetLocation(), curseRadius)
						if targetAllies ~= nil and #targetAllies >= 2 then
							highestDamage = estimatedDamage
							bestTarget = enemyHero
						end
					end
				end
			end
			if bestTarget ~= nil then
				return BOT_ACTION_DESIRE_HIGH, bestTarget
			end
		end
	end
	if isRetreating then
		local nearbyEnemies = Fu.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nearbyEnemies) do
			if
				Fu.IsValidHero(enemyHero)
				and Fu.IsChasingTarget(enemyHero, bot)
				and hpRatio < 0.5
				and not Fu.IsSuspiciousIllusion(enemyHero)
				and not Fu.IsDisabled(enemyHero)
				and Fu.IsInRange(bot, enemyHero, castRange)
				and Fu.GetHP(enemyHero) > 0.5
				and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
				and not Fu.IsUnderLongDurationStun(enemyHero)
			then
				local nearbyAllies = Fu.GetAlliesNearLoc(enemyHero:GetLocation(), 1200)
				local targetAllies = Fu.GetEnemiesNearLoc(enemyHero:GetLocation(), 1200)
				-- Was "#nearbyAllies >= 2" (an ally besides Wyvern) and "#targetAllies >= 1" in radius, which enemyHero alone met:
				-- a Wyvern fleeing alone never cursed two chasers. Now: an ally there, or a second
				-- enemy in the curse radius to be cursed into attacking enemyHero.
				if
					nearbyAllies ~= nil
					and targetAllies ~= nil
					and (#targetAllies > #nearbyAllies or bot:WasRecentlyDamagedByAnyHero(2.5))
				then
					targetAllies = Fu.GetEnemiesNearLoc(enemyHero:GetLocation(), curseRadius)
					if targetAllies ~= nil and (#nearbyAllies >= 2 and #targetAllies >= 1 or #targetAllies >= 2) then
						if #nearbyAllies < 2 then
							X.LogWyvern(
								"curse-escape",
								"target=%s cursed=%d",
								enemyHero:GetUnitName(),
								#targetAllies - 1
							)
						end
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					end
				end
			end
		end
	end
	local enemiesInReach = Fu.GetNearbyHeroes(bot, castRange, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(enemiesInReach) do
		if
			Fu.IsValidHero(enemyHero)
			and Fu.CanCastOnMagicImmune(enemyHero)
			and enemyHero:IsChanneling()
			and not Fu.IsSuspiciousIllusion(enemyHero)
			and Fu.GetHP(enemyHero) >= 0.4
			and not enemyHero:HasModifier("modifier_necrolyte_reapers_scythe")
			and not Fu.IsUnderLongDurationStun(enemyHero)
		then
			local nearbyAllies = Fu.GetAlliesNearLoc(enemyHero:GetLocation(), 400)
			local retreatingAllies = Fu.GetRetreatingAlliesNearLoc(enemyHero:GetLocation(), 400)
			local nearbyEnemies = Fu.GetEnemiesNearLoc(enemyHero:GetLocation(), curseRadius)
			if
				(nearbyAllies == nil or #nearbyAllies <= 0 or #retreatingAllies > 0)
				and nearbyEnemies ~= nil
				and #nearbyEnemies >= 2
			then
				return BOT_ACTION_DESIRE_HIGH, enemyHero
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
return X
