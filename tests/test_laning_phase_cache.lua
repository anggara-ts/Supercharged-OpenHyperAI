-- The team's shared game-state tables (bots/lib/systems/cache.lua, push.lua, defend.lua) hold isLaningPhase, which is
-- one bot's own flag (bot.isInLanePhase, set by its laning mode). Every read must give the calling bot its own flag,
-- not the flag of the teammate that filled the table (#165, game 085 13:37: Lina's bottom push flipped between 0.99 and
-- the laning gate whenever Marci, still in her laning phase, had filled the table).
local T = ...
local Stub = T.stub

local function setup()
	Stub.reset({ team = TEAM_DIRE, time = 817 })
	local Cache = require(GetScriptDirectory() .. "/lib/systems/cache")
	local first, second = Stub.teams[TEAM_DIRE][1], Stub.teams[TEAM_DIRE][2]
	first.isInLanePhase = true
	second.isInLanePhase = false
	return Cache, first, second
end

local function lastPhaseLine()
	for i = #Stub.printed, 1, -1 do
		if string.find(Stub.printed[i], "[SHy-PHASE]", 1, true) then
			return Stub.printed[i]
		end
	end
	return nil
end

T.test("laning phase cache: each bot reads its own flag within one cache window", function()
	local Cache, first, second = setup()
	Stub.bot = first
	T.eq(Cache.getGlobalGameState().isLaningPhase, true, "the bot that fills the table: its own flag")
	Stub.bot = second
	T.eq(Cache.getGlobalGameState().isLaningPhase, false, "a teammate in the same 0.5s: its own flag, not the filler's")
	Stub.bot = first
	T.eq(Cache.getGlobalGameState().isLaningPhase, true, "back to the first bot")
end)

T.test("laning phase cache: the corrected read is logged with the bot that read it before", function()
	local Cache, first, second = setup()
	Stub.bot = first
	Cache.getGlobalGameState()
	T.eq(lastPhaseLine(), nil, "no line while the table holds the caller's own flag")
	Stub.bot = second
	Cache.getGlobalGameState()
	local line = lastPhaseLine()
	T.ok(line ~= nil, "a line when the table held a teammate's flag")
	T.ok(string.find(line, "own=false cached=true", 1, true) ~= nil, line)
	local firstName = string.gsub(first:GetUnitName(), "npc_dota_hero_", "")
	T.ok(string.find(line, "by=" .. firstName, 1, true) ~= nil, line)
	-- Throttled: the same bot corrected again within 30s prints nothing more.
	local count = #Stub.printed
	Stub.bot = first
	Cache.getGlobalGameState()
	Stub.bot = second
	Cache.getGlobalGameState()
	local lines = 0
	for i = count + 1, #Stub.printed do
		if string.find(Stub.printed[i], "laning-own " .. "own=false", 1, true) then
			lines = lines + 1
		end
	end
	T.eq(lines, 0, "second's line is throttled")
end)

T.test("laning phase cache: a bot whose own flag changed says by=self", function()
	local Cache, first = setup()
	Stub.bot = first
	Cache.getGlobalGameState()
	first.isInLanePhase = false
	T.eq(Cache.getGlobalGameState().isLaningPhase, false, "the new flag")
	T.ok(string.find(lastPhaseLine() or "", "by=self", 1, true) ~= nil, tostring(lastPhaseLine()))
end)

T.test("laning phase cache: push.lua and defend.lua read through Cache.OwnLaningPhase", function()
	for _, path in ipairs({ "bots/lib/systems/push.lua", "bots/lib/systems/defend.lua" }) do
		local src = T.read(path)
		local body = string.match(src, "\nfunction getGameState%(%)(.-)\nend\n")
		T.ok(body ~= nil, path .. ": getGameState found")
		local _, owned = string.gsub(body, "return Cache%.OwnLaningPhase%(gameStateCache", "")
		local _, returns = string.gsub(body, "return ", "")
		T.eq(owned, 2, path .. ": both returns go through Cache.OwnLaningPhase")
		T.eq(returns, 2, path .. ": no other return")
	end
end)
