-- bots/lib/systems/objective_travel.lua (issue #53): the gate route time, when a Fiend's Gate is worth casting,
-- and that a 7.42 hero (no twin_gate_portal_warp) never plans a trip through a Twin Gate.
local T = ...

local function load(opts)
	T.stub.reset(opts or { hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/lib/systems/objective_travel")
end

T.test("travel: gate route = walk to the gate + 4s channel + 1s + walk from the other gate", function()
	local Travel = load()
	-- 7.42 game data: twin_gate_portal_warp AbilityChannelTime 4.0.
	T.near(Travel.GateSeconds(3000, 2000, 300), 3000 / 300 + 4 + 1 + 2000 / 300, 0.001, "default channel")
	T.near(Travel.GateSeconds(3000, 2000, 300, 0), 3000 / 300 + 4 + 1 + 2000 / 300, 0.001, "channel 0 = default")
	T.near(Travel.GateSeconds(600, 600, 300, 6), 2 + 6 + 1 + 2, 0.001, "channel from the ability")
end)

T.test("travel: a Fiend's Gate only helps when someone can walk through it, or with Scepter", function()
	local Travel = load()
	T.eq(Travel.PortalWorthCasting(false, 0, false), false, "7.42, bots only, no Scepter")
	T.eq(Travel.PortalWorthCasting(false, 1, false), true, "a human ally")
	T.eq(Travel.PortalWorthCasting(false, 0, true), true, "Scepter: Pit of Malice at the far portal")
	T.eq(Travel.PortalWorthCasting(true, 0, false), true, "the warp ability is back")
end)

local function printed(pattern)
	local count = 0
	for _, line in ipairs(T.stub.printed or {}) do
		if string.find(tostring(line), pattern) then
			count = count + 1
		end
	end
	return count
end

T.test("travel: without the warp ability (7.42) a far trip never goes through a Twin Gate", function()
	local Travel = load()
	-- Two gates in opposite corners; the bot stands next to the top-left one, the target is near the other, so
	-- the gate would be much faster if the bot could warp.
	local nearGate = T.stub.newUnit({ name = "npc_dota_unit_twin_gate", team = 4, loc = Vector(-6200, 5200, 0) })
	local farGate = T.stub.newUnit({ name = "npc_dota_unit_twin_gate", team = 4, loc = Vector(6000, -5000, 0) })
	-- The stub's unit list holds heroes only; Stub.reset puts the original back.
	rawset(_G, "GetUnitList", function()
		return { nearGate, farGate }
	end)
	local bot = GetBot()
	bot._loc = Vector(-6000, 5000, 0)
	-- 7.42: the hero has no warp abilities (the stub makes up any name it is asked for).
	local stubGetAbilityByName = bot.GetAbilityByName
	bot.GetAbilityByName = function(self, name)
		if string.find(name, "portal_warp", 1, true) then
			return nil
		end
		return stubGetAbilityByName(self, name)
	end
	local target = Vector(5000, -4000, 0)
	local _, how = Travel.Best(bot, target)
	T.ok(how ~= "gate", "no gate route without the ability, got " .. tostring(how))
	T.eq(Travel.Go(bot, target, "tormentor"), false, "walk: Go gives no order")
	T.stub.time = 0.5
	T.eq(Travel.Go(bot, target, "roshan"), false, "still walking")
	T.eq(printed("warp%-abilities twin=false portal=false"), 1, "ability check logged once per bot")
	T.eq(printed("%[SHy%-TRAVEL%].* gate "), 0, "no gate trip logged")
end)
