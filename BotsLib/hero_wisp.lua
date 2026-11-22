-- Wisp: skill build, item build, and ability use for this hero.
local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
local Dota = require(GetScriptDirectory() .. "/FuncLib/dota/index")
local BotActionDesire = Dota.BotActionDesire
local BotMode = Dota.BotMode
local UnitType = Dota.UnitType
local Buff = require(GetScriptDirectory() .. "/FuncLib/data/buff")
local healingModifiers = Buff.hero_is_healing
local Utils = require(GetScriptDirectory() .. "/FuncLib/systems/utils")
local GetTeamFountainTpPoint = Utils.GetTeamFountainTpPoint
local HasAnyEffect = Utils.HasAnyEffect
local IsValidHero = Utils.IsValidHero
local RelocateRules = require(GetScriptDirectory() .. "/FuncLib/systems/relocate_rules")
local TeamMemory = require(GetScriptDirectory() .. "/FuncLib/systems/team_memory")
local HeroBuilder = require(GetScriptDirectory() .. "/FuncLib/hero/hero_builder")
local buildHeroConfig = HeroBuilder.buildHeroConfig
local buildHeroExport = HeroBuilder.buildHeroExport
local relocateHpThreshold = 0.2
local tetherAllyHpThreshold = 0.75
local tetherManaThreshold = 0.8
local retreatHpThreshold = 0.25
local relocateMinDistance = 3000
local spiritsMinCreeps = 2
local spiritsManaThreshold = 0.4
local bot = GetBot()
local Minion = dofile(GetScriptDirectory() .. "/FuncLib/hero/minion")
local heroConfig = buildHeroConfig(bot, {
	skills = { default = { 2, 1, 2, 3, 2, 6, 2, 3, 3, 3, 6, 1, 1, 1, 6 } },
	talents = { default = { t25 = { 10, 0 }, t20 = { 10, 0 }, t15 = { 0, 10 }, t10 = { 0, 10 } } },
	items = {
		-- Stratz 7.41f, week of 9 Nov 2026: pos 1, 3,982 matches (Util/item-builds/generate.js).
		pos_1 = {
			"item_tango",
			"item_double_branches",
			"item_gauntlets",
			"item_magic_stick",
			"item_magic_wand",
			"item_soul_ring",
			"item_helm_of_the_dominator",
			"item_ultimate_scepter",
			"item_boots",
			"item_maelstrom",
			"item_black_king_bar",
			"item_mjollnir",
			"item_satanic",
			"item_travel_boots",
			"item_ultimate_scepter_2",
			"item_moon_shard",
			"item_butterfly",
			"item_aghanims_shard",
			"item_travel_boots_2",
		},
		-- Stratz 7.41f, week of 9 Nov 2026: pos 2, 14,243 matches (Util/item-builds/generate.js).
		pos_2 = {
			"item_tango",
			"item_double_branches",
			"item_faerie_fire",
			"item_magic_wand",
			"item_null_talisman",
			"item_ultimate_scepter",
			"item_black_king_bar",
			"item_shivas_guard",
			"item_octarine_core",
			"item_sheepstick",
			"item_ultimate_scepter_2",
			"item_wind_waker",
			"item_lotus_orb",
		},
		-- Stratz 7.41f, week of 9 Nov 2026: pos 3, 1,965 matches (Util/item-builds/generate.js).
		pos_3 = {
			"item_tango",
			"item_double_branches",
			"item_gauntlets",
			"item_magic_stick",
			"item_magic_wand",
			"item_soul_ring",
			"item_ultimate_scepter",
			"item_black_king_bar",
			"item_shivas_guard",
			"item_heart",
			"item_ultimate_scepter_2",
			"item_octarine_core",
			"item_kaya_and_sange",
			"item_satanic",
		},
		-- Stratz 7.41f, week of 9 Nov 2026: pos 4, 12,651 matches (Util/item-builds/generate.js).
		pos_4 = {
			"item_tango",
			"item_blood_grenade",
			"item_double_branches",
			"item_magic_stick",
			"item_faerie_fire",
			"item_magic_wand",
			"item_headdress",
			"item_mekansm",
			"item_ring_of_basilius",
			"item_holy_locket",
			"item_arcane_boots",
			"item_glimmer_cape",
			"item_guardian_greaves",
			"item_pipe",
			"item_lotus_orb",
			"item_vladmir",
			"item_moon_shard",
			"item_ultimate_scepter_2",
		},
		-- Stratz 7.41f, week of 9 Nov 2026: pos 5, 37,792 matches (Util/item-builds/generate.js).
		pos_5 = {
			"item_tango",
			"item_blood_grenade",
			"item_magic_stick",
			"item_double_branches",
			"item_faerie_fire",
			"item_magic_wand",
			"item_headdress",
			"item_mekansm",
			"item_holy_locket",
			"item_ring_of_basilius",
			"item_arcane_boots",
			"item_glimmer_cape",
			"item_guardian_greaves",
			"item_ultimate_scepter",
			"item_lotus_orb",
			"item_pipe",
			"item_moon_shard",
			"item_ultimate_scepter_2",
		},
	},
	sell = { "item_black_king_bar", "item_quelling_blade" },
})
local tetherAbility = bot:GetAbilityByName("wisp_tether")
local spiritsAbility = bot:GetAbilityByName("wisp_spirits")
local overchargeAbility = bot:GetAbilityByName("wisp_overcharge")
local relocateAbility = bot:GetAbilityByName("wisp_relocate")
local tetherBreakAbility = bot:GetAbilityByName("wisp_tether_break")
local relocateDelayTalent = bot:GetAbilityByName("special_bonus_unique_wisp_relocate_delay")
local nearbyEnemies = {}
bot.stateTetheredHero = bot.stateTetheredHero
local function isHealing(unit)
	return HasAnyEffect(unit, "modifier_tango_heal", unpack(healingModifiers))
end
local function isFighting(hero)
	local attackedRecently = GameTime() - hero:GetLastAttackTime() < 0.33
	local attackTarget = hero:GetAttackTarget()
	return Fu.IsGoingOnSomeone(hero)
		or attackTarget ~= nil and attackTarget:GetTeam() == GetOpposingTeam() and attackedRecently
		or #hero:GetNearbyCreeps(200, true) > 2
end
local function isTethered()
	return bot:HasModifier("modifier_wisp_tether")
end
local function considerTether()
	if not isTethered() then
		bot.stateTetheredHero = nil
	end
	if not tetherAbility:IsFullyCastable() or not tetherBreakAbility:IsHidden() then
		return BotActionDesire.None, nil
	end
	local castRange = tetherAbility:GetCastRange()
	local nearbyAllies = bot:GetNearbyHeroes(castRange, false, BotMode.None) or {}
	for _, allyHero in ipairs(nearbyAllies) do
		do
			local shouldContinue
			repeat
				-- Tether is SPELL_IMMUNITY_ALLIES_YES: a BKB carry can be tethered (the magic-immune
				-- skip dropped Io's main fight target). Illusions of allies are skipped instead.
				if allyHero == bot or not allyHero:IsAlive() or allyHero:IsIllusion() then
					shouldContinue = true
					break
				end
				if Fu.IsRetreating(bot) or Fu.GetHP(bot) < retreatHpThreshold then
					if Fu.IsRetreating(allyHero) then
						return BotActionDesire.High, allyHero
					end
					shouldContinue = true
					break
				end
				if
					Fu.GetHP(allyHero) < tetherAllyHpThreshold
					or Fu.GetMP(bot) > tetherManaThreshold
					or isHealing(bot)
					or isFighting(allyHero)
				then
					return BotActionDesire.High, allyHero
				end
				shouldContinue = true
			until true
			if not shouldContinue then
				break
			end
		end
	end
	return BotActionDesire.None, nil
end
local function considerOvercharge()
	if not overchargeAbility:IsFullyCastable() then
		return BotActionDesire.None
	end
	if isTethered() and bot.stateTetheredHero ~= nil and isFighting(bot.stateTetheredHero) then
		return BotActionDesire.High
	end
	return BotActionDesire.None
end
local function considerSpirits()
	if not spiritsAbility:IsFullyCastable() then
		return BotActionDesire.None
	end
	-- Was "#nearbyEnemies >= 1" (any enemy hero within 1600): spirits circle Io at 200-650 range, so they
	-- were cast (90-120 mana) at heroes they could not reach. Now: an enemy hero within 800.
	for _, enemyHero in ipairs(nearbyEnemies) do
		if IsValidHero(enemyHero) and GetUnitToUnitDistance(bot, enemyHero) <= 800 then
			return BotActionDesire.High
		end
	end
	if #bot:GetNearbyNeutralCreeps(500, true) >= spiritsMinCreeps and Fu.GetMP(bot) > spiritsManaThreshold then
		return BotActionDesire.Moderate
	end
	return BotActionDesire.None
end
-- Relocate (#47). The rules and the game-file values are in FuncLib/systems/relocate_rules.lua.
local function relocateDelay()
	local talent = relocateDelayTalent ~= nil and relocateDelayTalent:IsTrained()
	return RelocateRules.CastDelay(relocateAbility:GetLevel(), talent)
end
local function nearOwnFountain(unit)
	return unit:HasModifier("modifier_fountain_aura_buff") or Fu.GetDistanceFromAllyFountain(unit) < 2500
end
local function enemyHeroCount(unit, radius)
	return #(unit:GetNearbyHeroes(radius, true, BotMode.None) or {})
end
-- HP history for the damage rate: Io and the tethered ally, sampled every think before any early return.
local selfSamples = {}
local allySamples = { unit = nil, samples = {} }
local function sampleHp()
	local now = DotaTime()
	if bot:IsAlive() then
		RelocateRules.AddSample(selfSamples, now, Fu.GetHP(bot))
	else
		selfSamples = {}
	end
	local ally = bot.stateTetheredHero
	if not isTethered() or not IsValidHero(ally) then
		allySamples = { unit = nil, samples = {} }
		return
	end
	if allySamples.unit ~= ally then
		allySamples = { unit = ally, samples = {} }
	end
	RelocateRules.AddSample(allySamples.samples, now, Fu.GetHP(ally))
end
-- The save to the fountain: the tethered ally (or Io) would not last the cast delay at the HP it is losing, or is
-- focused at low HP. Only with the tether up and the ally well inside the 1000 tether radius (the ally comes along
-- only if still tethered when the teleport happens), never for an ally already at the fountain or in a TP channel.
local function considerRelocateSave()
	if not relocateAbility:IsFullyCastable() or not isTethered() then
		return nil
	end
	local ally = bot.stateTetheredHero
	if not IsValidHero(ally) or GetUnitToUnitDistance(bot, ally) > RelocateRules.TETHER_SAFE then
		return nil
	end
	if
		nearOwnFountain(bot)
		or nearOwnFountain(ally)
		or bot:HasModifier("modifier_teleporting")
		or ally:HasModifier("modifier_teleporting")
	then
		return nil
	end
	local delay = relocateDelay()
	local unit, who = ally, "ally"
	local rate = RelocateRules.LossRate(allySamples.samples)
	local needed, why, ttd = RelocateRules.SaveNeeded(Fu.GetHP(ally), rate, delay, enemyHeroCount(ally, 1200))
	if not needed then
		unit, who = bot, "self"
		rate = RelocateRules.LossRate(selfSamples)
		needed, why, ttd = RelocateRules.SaveNeeded(Fu.GetHP(bot), rate, delay, enemyHeroCount(bot, 1200))
	end
	if not needed then
		return nil
	end
	return {
		kind = "save",
		why = who .. "-" .. why,
		ally = ally,
		hp = Fu.GetHP(unit),
		dps = rate * unit:GetMaxHealth(),
		ttd = ttd,
		delay = delay,
		target = GetTeamFountainTpPoint(),
	}
end
local function considerRelocate()
	if not relocateAbility:IsFullyCastable() then
		return nil
	end
	if not isTethered() and #nearbyEnemies >= 1 and Fu.GetHP(bot) < relocateHpThreshold then
		return {
			kind = "self",
			why = "self-low",
			hp = Fu.GetHP(bot),
			dps = RelocateRules.LossRate(selfSamples) * bot:GetMaxHealth(),
			delay = relocateDelay(),
			target = GetTeamFountainTpPoint(),
		}
	end
	for _, allyHero in ipairs(GetUnitList(UnitType.AlliedHeroes)) do
		if
			IsValidHero(allyHero)
			and Fu.IsInTeamFight(allyHero, 1200)
			and GetUnitToUnitDistance(bot, allyHero) > relocateMinDistance
			and allyHero:WasRecentlyDamagedByAnyHero(2)
		then
			return {
				kind = "join",
				why = "join",
				ally = isTethered() and bot.stateTetheredHero or nil,
				hp = Fu.GetHP(bot),
				dps = 0,
				delay = relocateDelay(),
				target = allyHero:GetLocation(),
			}
		end
	end
	return nil
end
local relocateState = nil
local function unitName(unit)
	if unit ~= nil and not unit:IsNull() then
		return unit:GetUnitName()
	end
	return "none"
end
local function unitAlive(unit)
	return unit ~= nil and not unit:IsNull() and unit:IsAlive()
end
local function issueRelocate(plan)
	bot:Action_UseAbilityOnLocation(relocateAbility, plan.target)
	if relocateState == nil then
		plan.orderAt = DotaTime()
		plan.allyName = unitName(plan.ally)
		relocateState = plan
	end
end
local function heroesNear(listType, loc, radius, skipA, skipB)
	local count = 0
	for _, hero in ipairs(GetUnitList(listType)) do
		if
			IsValidHero(hero)
			and hero ~= skipA
			and hero ~= skipB
			and not hero:IsIllusion()
			and GetUnitToLocationDistance(hero, loc) <= radius
		then
			count = count + 1
		end
	end
	return count
end
-- Seconds to Io's return: the return modifier when the API shows it, else the timer from the cast.
local function returnLeft(state, now)
	local ok, left = pcall(function()
		local index = bot:GetModifierByName("modifier_wisp_relocate_return")
		if index ~= nil and index >= 0 then
			return bot:GetModifierRemainingDuration(index)
		end
		return nil
	end)
	if ok and type(left) == "number" then
		return left, "modifier"
	end
	return state.returnAt - now, "timer"
end
local function clearRelocate()
	relocateState = nil
	TeamMemory.Set(bot:GetTeam(), "wispRelocate", nil)
end
-- Follows one Relocate from the order to the return: the cast line once the cooldown shows it went off, the result
-- after the teleport, the keep / break decision before the return, and where both ended up. Returns true when it
-- issued an order this think.
local function relocateTick()
	local state = relocateState
	if state == nil then
		return false
	end
	local now = DotaTime()
	if not state.confirmed then
		if relocateAbility:GetCooldownTimeRemaining() > 0 then
			state.confirmed = true
			state.teleportAt = now + state.delay
			state.resultAt = state.teleportAt + 1
			state.returnAt = state.teleportAt + RelocateRules.RETURN_TIME
			state.origin = bot:GetLocation()
			print(
				string.format(
					"[OHA-WISP] t=%.0f wisp relocate why=%s ally=%s hp=%.2f dps=%.0f ttd=%s delay=%.2f",
					now,
					state.why,
					state.allyName,
					state.hp,
					state.dps,
					state.ttd ~= nil and string.format("%.1f", state.ttd) or "-",
					state.delay
				)
			)
			if state.kind == "save" then
				bot._noTpUntil = state.returnAt
				if unitAlive(state.ally) then
					state.memory = {
						allyId = state.ally:GetPlayerID(),
						io = bot,
						teleportAt = state.teleportAt,
						returnAt = state.returnAt,
						released = false,
					}
					TeamMemory.Set(bot:GetTeam(), "wispRelocate", state.memory)
				end
			end
		elseif now - state.orderAt > 1.5 then
			print(
				string.format(
					"[OHA-WISP] t=%.0f wisp relocate-order-lost why=%s ally=%s",
					now,
					state.why,
					state.allyName
				)
			)
			clearRelocate()
		end
		return false
	end
	if now < state.teleportAt then
		-- The return goes back to where Io stood when it left.
		state.origin = bot:GetLocation()
		return false
	end
	if not state.resultDone then
		if now < state.resultAt then
			return false
		end
		state.resultDone = true
		local arrived = bot:IsAlive() and GetUnitToLocationDistance(bot, state.target) < 1200
		local allyAlive = unitAlive(state.ally)
		local allyThere = allyAlive and GetUnitToLocationDistance(state.ally, state.target) < 1200
		local died = "none"
		if not bot:IsAlive() and state.ally ~= nil and not allyAlive then
			died = "both"
		elseif not bot:IsAlive() then
			died = "io"
		elseif state.ally ~= nil and not allyAlive then
			died = "ally"
		end
		print(
			string.format(
				"[OHA-WISP] t=%.0f wisp relocate-result why=%s ally=%s arrived=%s tether=%s died=%s ioReturn=%s allyReturn=%s originEnemies=%d",
				now,
				state.why,
				state.allyName,
				tostring(arrived),
				tostring(allyThere and isTethered()),
				died,
				tostring(bot:HasModifier("modifier_wisp_relocate_return")),
				tostring(allyAlive and state.ally:HasModifier("modifier_wisp_relocate_return")),
				heroesNear(UnitType.EnemyHeroes, state.origin, 1500)
			)
		)
		if not arrived then
			bot._noTpUntil = nil
			clearRelocate()
			return false
		end
		if not allyThere then
			state.ally = nil
			if state.memory ~= nil then
				state.memory.released = true
			end
		end
		return false
	end
	local left, leftSource = returnLeft(state, now)
	if not state.decided then
		if state.kind ~= "save" or state.ally == nil then
			state.decided = true
		elseif left <= 1.0 then
			state.decided = true
			local allyAlive = unitAlive(state.ally)
			local decision, why = RelocateRules.ReturnDecision({
				allyAlive = allyAlive,
				tetherUp = isTethered(),
				allyHp = allyAlive and Fu.GetHP(state.ally) or 0,
				alliesAtOrigin = heroesNear(UnitType.AlliedHeroes, state.origin, 1500, bot, state.ally),
				enemiesAtOrigin = heroesNear(UnitType.EnemyHeroes, state.origin, 1500),
			})
			print(
				string.format(
					"[OHA-WISP] t=%.0f wisp relocate-return %s why=%s ally=%s hp=%.2f left=%.1f src=%s",
					now,
					decision,
					why,
					state.allyName,
					allyAlive and Fu.GetHP(state.ally) or 0,
					left,
					leftSource
				)
			)
			if decision == "break" then
				state.breakTether = true
				if state.memory ~= nil then
					state.memory.released = true
				end
			end
		end
	end
	-- Break the tether so the ally stays home; Io itself cannot cancel its return (no such ability in the game file).
	if state.breakTether and isTethered() and left > 0.1 then
		if tetherBreakAbility ~= nil and not tetherBreakAbility:IsHidden() and tetherBreakAbility:IsFullyCastable() then
			bot:Action_UseAbility(tetherBreakAbility)
			return true
		end
	end
	if now >= state.returnAt + 1.5 then
		print(
			string.format(
				"[OHA-WISP] t=%.0f wisp relocate-return-result ally=%s ioFountain=%d allyFountain=%d",
				now,
				state.allyName,
				Fu.GetDistanceFromAllyFountain(bot),
				unitAlive(state.ally) and Fu.GetDistanceFromAllyFountain(state.ally) or -1
			)
		)
		clearRelocate()
	end
	return false
end
-- Between the teleport and the return Io stays with the relocated ally so the tether holds.
local function relocateHolding()
	local state = relocateState
	return state ~= nil
		and state.confirmed
		and state.ally ~= nil
		and not state.breakTether
		and DotaTime() < (state.returnAt or 0)
end
local function skillsComplement()
	-- Before the early returns: the damage rate needs samples while Io is stunned too, and the Relocate result is due
	-- whatever Io is doing.
	sampleHp()
	if Fu.CanNotUseAbility(bot) or bot:IsInvisible() then
		pcall(relocateTick)
		return
	end
	local okTick, ordered = pcall(relocateTick)
	if okTick and ordered then
		return
	end
	nearbyEnemies = bot:GetNearbyHeroes(1600, true, BotMode.None) or {}
	-- The save goes first: a danger think used to cast Spirits or Overcharge instead (#47).
	local savePlan = considerRelocateSave()
	if savePlan ~= nil then
		issueRelocate(savePlan)
		return
	end
	-- No new tether while the ally is being let go before the return (it would bring the ally back after all).
	local releasing = relocateState ~= nil and relocateState.breakTether
	local tetherDesire, tetherTarget = BotActionDesire.None, nil
	if not releasing then
		tetherDesire, tetherTarget = considerTether()
	end
	if tetherDesire > 0 and tetherTarget then
		bot:Action_UseAbilityOnEntity(tetherAbility, tetherTarget)
		bot.stateTetheredHero = tetherTarget
		return
	end
	local overchargeDesire = considerOvercharge()
	if overchargeDesire > 0 then
		bot:Action_UseAbility(overchargeAbility)
		return
	end
	local spiritsDesire = considerSpirits()
	if spiritsDesire > 0 then
		bot:Action_UseAbility(spiritsAbility)
		return
	end
	local relocatePlan = considerRelocate()
	if relocatePlan ~= nil then
		issueRelocate(relocatePlan)
		return
	end
	-- Follow the tethered ally: the tether breaks past 1000 range (MAX TETHER DISTANCE in the
	-- datafeed) and nothing kept Io near the ally, so modes walked Io away and broke it. While a Relocate is under
	-- way (the delay, then the fountain until the return) Io follows even when retreating, so the tether holds.
	local tetheredHero = bot.stateTetheredHero
	if
		isTethered()
		and IsValidHero(tetheredHero)
		and (not Fu.IsRetreating(bot) or relocateHolding())
		and GetUnitToUnitDistance(bot, tetheredHero) > 650
	then
		if DotaTime() >= (bot._wispFollowLogAt or -999) then
			bot._wispFollowLogAt = DotaTime() + 5
			pcall(
				print,
				string.format(
					"[OHA-WISP] t=%.0f follow-tether ally=%s dist=%d",
					DotaTime(),
					tetheredHero:GetUnitName(),
					GetUnitToUnitDistance(bot, tetheredHero)
				)
			)
		end
		bot:Action_MoveToLocation(tetheredHero:GetLocation())
	end
end
local function minionThink(minion)
	if Minion.IsValidUnit(minion) then
		Minion.IllusionThink(minion)
	end
end
local X = buildHeroExport(heroConfig, skillsComplement, minionThink)
return X
