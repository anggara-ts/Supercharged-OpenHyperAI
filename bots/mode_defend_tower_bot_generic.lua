-- Defend the bottom lane. The decision itself is in bots/lib/systems/defend.lua.
local Defend = require(GetScriptDirectory() .. "/lib/systems/defend")
local bot = GetBot()
local botName = bot:GetUnitName()
function GetDesire()
	if ShouldSkipBotThink(bot) then
		return 0
	end
	return Defend.GetDefendDesire(bot, LANE_BOT)
end
-- #53: our defend movement (high-ground rim, waves, lane defence). Without a Think here Valve's own defend Think ran.
function Think()
	Defend.DefendThink(bot, LANE_BOT)
end
if SafeCall then
	local originalGetDesire = GetDesire
	local originalThink = Think
	if originalGetDesire then
		GetDesire = SafeCall(originalGetDesire, 0, "DEFEND_TOWER_BOT_GetDesire")
	end
	if originalThink then
		Think = SafeCall(originalThink, nil, "DEFEND_TOWER_BOT_Think")
	end
end
-- [SHy-PERF] timing (#52): bots/lib/systems/perf.lua
do
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	GetDesire = Perf.Wrap("defend_tower_bot.GetDesire", GetDesire)
	Think = Perf.Wrap("defend_tower_bot.Think", Think)
end
