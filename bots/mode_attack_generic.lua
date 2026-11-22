-- Attack mode. Picks a fight target and how badly the bot wants that fight.
local bot = GetBot()
local botName = bot:GetUnitName()
local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
local AttackOverride
if not ShouldSkipBotThink(bot) and Utils.BuggyHeroesDueToValveTooLazy[botName] then
	AttackOverride = dofile(GetScriptDirectory() .. "/lib/systems/override_generic/mode_attack_generic")
end
-- Heroes not on the list keep Valve's attack mode: this file defines no GetDesire/Think for them,
-- and defining one would replace Valve's with no way to call it. Their attack-mode extras (kiting:
-- bots/lib/hero/special_units.lua TryKiteInAttack) run from the per-think item/ability hook. The
-- flag tells that hook this hero kites from the override's Think instead.
if AttackOverride ~= nil then
	bot._ohaAttackOverride = true
	function GetDesire()
		if ShouldSkipBotThink(bot) then
			return 0
		end
		return math.min(AttackOverride.GetDesire(), BOT_MODE_DESIRE_ABSOLUTE)
	end
	function Think()
		if ShouldSkipBotThink(bot) then
			return
		end
		return AttackOverride.Think()
	end
	function OnStart()
		return AttackOverride.OnStart()
	end
	function OnEnd()
		return AttackOverride.OnEnd()
	end
end
-- Difficulty (#232): reads the lobby difficulty once at load ([SHy-DIFF] ... src=api|default). A Passive bot does not
-- fight heroes: no attack mode at all (this replaces Valve's for it). Every other level keeps the lines above.
if
	not ShouldSkipBotThink(bot)
	and not require(GetScriptDirectory() .. "/lib/systems/difficulty_hooks").FightsHeroes(bot)
then
	function GetDesire()
		return 0
	end
	function Think() end
end
if SafeCall then
	local originalGetDesire = GetDesire
	local originalThink = Think
	if originalGetDesire then
		GetDesire = SafeCall(originalGetDesire, 0, "ATTACK_GetDesire")
	end
	if originalThink then
		Think = SafeCall(originalThink, nil, "ATTACK_Think")
	end
end
-- [SHy-PERF] timing (#52): bots/lib/systems/perf.lua
do
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	GetDesire = Perf.Wrap("attack.GetDesire", GetDesire)
	Think = Perf.Wrap("attack.Think", Think)
end
