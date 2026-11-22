-- Runs once per bot. Loads that hero file from bots/heroes and thinks for the bot summons.
local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end
local Utils = require(GetScriptDirectory() .. "/lib/systems/utils")
local BotBuild = dofile(GetScriptDirectory() .. "/heroes/" .. string.gsub(botName, "npc_dota_", ""))
if BotBuild == nil then
	log("[ERROR] No build config file found for bot: %s", botName)
	return
end
function MinionThink(minion)
	if not Utils.IsValidUnit(minion) then
		return
	end
	if minion.lastMinionFrameProcessTime == nil then
		minion.lastMinionFrameProcessTime = DotaTime()
	end
	if DotaTime() - minion.lastMinionFrameProcessTime < 0.3 then
		return
	end
	minion.lastMinionFrameProcessTime = DotaTime()
	BotBuild.MinionThink(minion)
end

-- [SHy-ERROR] trap (minions). From ~11:20 every game an unwrapped entry point fails and the engine only
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
		local failCount = (OHA_TRAP_COUNT[name] or 0) + 1
		OHA_TRAP_COUNT[name] = failCount
		if failCount <= 3 then
			local hero = "?"
			pcall(function()
				hero = GetBot():GetUnitName()
			end)
			pcall(print, string.format("[SHy-ERROR] t=%.1f %s %s: %s", DotaTime(), hero, name, tostring(res[2])))
		end
		return fallback
	end
end
MinionThink = OHA_Trap("MinionThink", MinionThink, nil)
-- [SHy-PERF] timing (#52): bots/lib/systems/perf.lua
do
	local Perf = require(GetScriptDirectory() .. "/lib/systems/perf")
	MinionThink = Perf.Wrap("MinionThink", MinionThink)
end
