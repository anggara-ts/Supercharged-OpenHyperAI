-- Winter's Curse diagnostics ([OHA-CURSE]): our bots hitting an enemy that Winter's Curse makes immune to their
-- damage. Diagnostics only: nothing here feeds a decision, no order is changed.
-- Winter's Curse (datafeed hero_id=112, winter_wyvern_winters_curse): "The frozen ally and those cursed to attack
-- their ally are immune to all damage from their enemies with the exception of damage from Winter Wyvern or her
-- controlled units." duration 2s, max_duration 6s. The frozen target and the cursed attackers carry
-- modifier_winter_wyvern_winters_curse / _aura (both already in Fu.Buff.enemy_is_immune).
-- Logged: a right-click (the bot's attack target is a cursed enemy) and a unit-target spell or item cast on one.
-- Not logged: area / location spells (Acid Spray, Frogstomp, Tombstone are fine on held enemies, maintainer
-- 2026-11-23), Winter Wyvern's own hits (her damage goes through) and units on the bot's own team (a bot cursed to
-- attack its frozen ally).
-- The state machine (throttle, counts, end of a curse) and the line formats take plain values, so
-- Tests/test_curse_log.lua drives them without the game.
local CurseLog = {}

CurseLog.MODIFIERS = { "modifier_winter_wyvern_winters_curse", "modifier_winter_wyvern_winters_curse_aura" }
CurseLog.HIT_GAP = 2 -- at most one hit line per bot and kind every 2s
CurseLog.BASE_LEFT = 2 -- duration (datafeed): the curse length assumed when the remaining time can't be read
CurseLog.MAX_LEFT = 6 -- max_duration (datafeed)
CurseLog.END_GRACE = 0.5 -- a curse counts as over this long after its last known end

-- Heroes that can cast Winter's Curse (Rubick steals it). Without one in the game the watcher does nothing.
local CASTERS = { npc_dota_hero_winter_wyvern = true, npc_dota_hero_rubick = true }
local EXCLUDED_HERO = "npc_dota_hero_winter_wyvern"

function CurseLog.NewState()
	return { nextLine = {}, attacks = 0, spells = 0, spellNames = {}, endsAt = nil, gameAttacks = 0, gameSpells = 0 }
end

-- The remaining curse time to trust: the read value within 0..max_duration, else the base duration.
function CurseLog.ClampLeft(curseLeft)
	if type(curseLeft) ~= "number" or curseLeft ~= curseLeft or curseLeft < 0 then
		return CurseLog.BASE_LEFT
	end
	return math.min(curseLeft, CurseLog.MAX_LEFT)
end

-- One sighting of a hit on a cursed enemy. kind = "attack" | "spell"; countKey = what to count: an attack sighting
-- counts only on a new swing ("swing"), a spell counts once per ability name per curse (the order is re-issued
-- every think until the cast lands), nil counts nothing. Returns true when the hit line should print.
function CurseLog.Hit(state, now, kind, curseLeft, countKey)
	local endsAt = now + CurseLog.ClampLeft(curseLeft)
	if state.endsAt == nil or endsAt > state.endsAt then
		state.endsAt = endsAt
	end
	if countKey ~= nil then
		if kind == "attack" then
			state.attacks = state.attacks + 1
			state.gameAttacks = state.gameAttacks + 1
		elseif not state.spellNames[countKey] then
			state.spellNames[countKey] = true
			state.spells = state.spells + 1
			state.gameSpells = state.gameSpells + 1
		end
	end
	if now >= (state.nextLine[kind] or -math.huge) then
		state.nextLine[kind] = now + CurseLog.HIT_GAP
		return true
	end
	return false
end

-- Once per tick: when the curse being tracked is over, returns its attack and spell counts (and resets them for the
-- next curse; the game totals stay). nil while no curse is tracked or it is still running.
function CurseLog.Ended(state, now)
	if state.endsAt == nil or now <= state.endsAt + CurseLog.END_GRACE then
		return nil
	end
	local attacks, spells = state.attacks, state.spells
	state.endsAt, state.attacks, state.spells, state.spellNames = nil, 0, 0, {}
	return attacks, spells
end

local function shortName(name)
	return (string.gsub(tostring(name), "^npc_dota_hero_", ""))
end

function CurseLog.HitLine(now, hero, kind, target, ability, curseLeft, extra)
	return string.format(
		"[OHA-CURSE] t=%.0f %s hit kind=%s hero=%s target=%s ability=%s curseLeft=%s%s",
		now,
		shortName(hero),
		kind,
		shortName(hero),
		shortName(target),
		tostring(ability or "attack"),
		type(curseLeft) == "number" and string.format("%.1f", curseLeft) or "?",
		extra or ""
	)
end

function CurseLog.SummaryLine(now, hero, state, attacks, spells)
	return string.format(
		"[OHA-CURSE] t=%.0f %s summary hero=%s attacks=%d spells=%d gameAttacks=%d gameSpells=%d",
		now,
		shortName(hero),
		shortName(hero),
		attacks,
		spells,
		state.gameAttacks,
		state.gameSpells
	)
end

-- Game side ----------------------------------------------------------------------------------------------------

-- A curse caster in the game (read from the picks; rechecked every 30s until one is found).
local casterInGame, casterCheckedAt = false, nil
function CurseLog.CasterInGame()
	if casterInGame then
		return true
	end
	local now = DotaTime()
	if casterCheckedAt ~= nil and now - casterCheckedAt < 30 then
		return false
	end
	casterCheckedAt = now
	for _, team in ipairs({ TEAM_RADIANT, TEAM_DIRE }) do
		local okT, players = pcall(GetTeamPlayers, team)
		if okT and type(players) == "table" then
			for _, pid in ipairs(players) do
				local okN, name = pcall(GetSelectedHeroName, pid)
				if okN and CASTERS[name] then
					casterInGame = true
					return true
				end
			end
		end
	end
	return false
end

-- The curse time left on unit (the longer of the two modifiers), or nil when it can't be read.
local function curseLeftOn(unit)
	local best = nil
	for _, name in ipairs(CurseLog.MODIFIERS) do
		local okIdx, idx = pcall(function()
			return unit:GetModifierByName(name)
		end)
		if okIdx and type(idx) == "number" and idx >= 0 then
			local okDur, dur = pcall(function()
				return unit:GetModifierRemainingDuration(idx)
			end)
			if okDur and type(dur) == "number" and (best == nil or dur > best) then
				best = dur
			end
		end
	end
	return best
end

-- unit is a visible, living enemy of bot under Winter's Curse.
function CurseLog.IsCursedEnemy(bot, unit)
	if unit == nil or unit:IsNull() or not unit:IsAlive() or not unit:CanBeSeen() then
		return false
	end
	if unit:GetTeam() == bot:GetTeam() then
		return false
	end
	for _, name in ipairs(CurseLog.MODIFIERS) do
		if unit:HasModifier(name) then
			return true
		end
	end
	return false
end

-- A hero whose hits on cursed enemies count: a real hero (no illusion or summon), not Winter Wyvern.
local function countsFor(unit)
	return unit ~= nil
		and not unit:IsNull()
		and unit:IsHero()
		and not unit:IsIllusion()
		and unit:GetUnitName() ~= EXCLUDED_HERO
end

local function stateOf(bot)
	if bot._ohaCurse == nil then
		bot._ohaCurse = CurseLog.NewState()
	end
	return bot._ohaCurse
end

-- Every think (ItemUsageThink): the attack target, new swings at it, and the summary when a curse ends.
function CurseLog.Watch(bot)
	if not CurseLog.CasterInGame() or not countsFor(bot) then
		return
	end
	local now = DotaTime()
	local state = stateOf(bot)
	local target = bot:GetAttackTarget()
	local lastAttack = bot:GetLastAttackTime()
	local newSwing = bot._ohaCurseLastAttack ~= nil and lastAttack ~= bot._ohaCurseLastAttack
	bot._ohaCurseLastAttack = lastAttack
	if target ~= nil and CurseLog.IsCursedEnemy(bot, target) then
		local left = curseLeftOn(target)
		if CurseLog.Hit(state, now, "attack", left, newSwing and "swing" or nil) then
			print(CurseLog.HitLine(now, bot:GetUnitName(), "attack", target:GetUnitName(), nil, left))
		end
	end
	local attacks, spells = CurseLog.Ended(state, now)
	if attacks ~= nil then
		print(CurseLog.SummaryLine(now, bot:GetUnitName(), state, attacks, spells))
	end
end

-- From the unit-target cast wrappers (global_overrides.lua GuardCast): a spell or item ordered on a cursed enemy.
-- dmgType / dmg are printed, not filtered on: GetDamageType / GetAbilityDamage are not proven for every spell.
function CurseLog.OnCast(caster, ability, target)
	if ability == nil or target == nil or not CurseLog.CasterInGame() or not countsFor(caster) then
		return
	end
	if not CurseLog.IsCursedEnemy(caster, target) then
		return
	end
	local okName, abilityName = pcall(function()
		return ability:GetName()
	end)
	abilityName = okName and tostring(abilityName) or "?"
	local okType, dmgType = pcall(function()
		return ability:GetDamageType()
	end)
	local okDmg, dmg = pcall(function()
		return ability:GetAbilityDamage()
	end)
	local now = DotaTime()
	local left = curseLeftOn(target)
	if CurseLog.Hit(stateOf(caster), now, "spell", left, abilityName) then
		local extra = string.format(
			" dmgType=%s dmg=%s",
			okType and tostring(dmgType) or "?",
			okDmg and type(dmg) == "number" and string.format("%.0f", dmg) or "?"
		)
		print(CurseLog.HitLine(now, caster:GetUnitName(), "spell", target:GetUnitName(), abilityName, left, extra))
	end
end

return CurseLog
