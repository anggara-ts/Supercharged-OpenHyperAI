-- Defend the mid lane. The decision itself is in bots/lib/systems/defend.lua.
local Defend = require(GetScriptDirectory() .. "/lib/systems/defend")
local bot = GetBot()
function GetDesire()
	if ShouldSkipBotThink(bot) then
		return 0
	end
	return Defend.GetDefendDesire(bot, LANE_MID)
end
-- #53: our defend movement (high-ground rim, waves, lane defence). Without a Think here Valve's own defend Think ran.
function Think()
	Defend.DefendThink(bot, LANE_MID)
end
if SafeCall then
	local getDesire = GetDesire
	local think = Think
	if getDesire then
		GetDesire = SafeCall(getDesire, 0, "DEFEND_TOWER_MID_GetDesire")
	end
	if think then
		Think = SafeCall(think, nil, "DEFEND_TOWER_MID_Think")
	end
end
-- [SHy-PERF] timing (#52): bots/lib/systems/perf.lua
do
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	GetDesire = Perf.Wrap("defend_tower_mid.GetDesire", GetDesire)
	Think = Perf.Wrap("defend_tower_mid.Think", Think)
end
