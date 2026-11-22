-- FuncLib/systems/defend.lua Defend.DefendThink (#53): the defend modes' Think. It replaces Valve's defend Think, so
-- every path must issue an order; once a lane is down to its T3, the spot is the rim where the T3 stood.
local T = ...
local Stub = T.stub

-- Radiant base, map-like spots: Ancient, mid T3 and T1, the T4s.
local ANCIENT = { x = -5500, y = -5000 }
local MID_T3 = { x = -4000, y = -3500 }
local MID_T1 = { x = -1500, y = -1200 }

local function building(name, loc)
	local unit = Stub.newUnit({ name = name, team = TEAM_RADIANT, loc = Vector(loc.x, loc.y, 0), hero = false })
	unit.IsBuilding = function()
		return true
	end
	return unit
end

-- A Radiant bot in the mid defend mode; returns the bot, the Defend module, the Dota enums and the order log.
local function setup(opts)
	opts = opts or {}
	local bot = Stub.reset({ hero = "npc_dota_hero_juggernaut", team = TEAM_RADIANT, time = 2500 })
	local Dota = require(GetScriptDirectory() .. "/FuncLib/dota/index")
	local ancient = building("npc_dota_goodguys_fort", ANCIENT)
	Stub.ancients[TEAM_RADIANT] = ancient
	local towers = Stub.towers[TEAM_RADIANT]
	towers[Dota.Tower.Mid3] = building("npc_dota_goodguys_tower3_mid", MID_T3)
	-- Top and bottom still have their T3s (tier 3): mid is the only lane down to the T4s.
	towers[Dota.Tower.Top3] = building("npc_dota_goodguys_tower3_top", { x = -6600, y = -1800 })
	towers[Dota.Tower.Bot3] = building("npc_dota_goodguys_tower3_bot", { x = -3800, y = -6100 })
	towers[Dota.Tower.Base1] = building("npc_dota_goodguys_tower4", { x = -5000, y = -4700 })
	towers[Dota.Tower.Base2] = building("npc_dota_goodguys_tower4", { x = -5300, y = -4400 })
	if opts.t1 then
		towers[Dota.Tower.Mid1] = building("npc_dota_goodguys_tower1_mid", MID_T1)
	end
	local barracks = {}
	_G.GetBarracks = function(team, id)
		return team == TEAM_RADIANT and barracks[id] or nil
	end
	local creeps = {}
	local listAll = GetUnitList
	_G.GetUnitList = function(listType)
		if listType == UNIT_LIST_ENEMY_CREEPS then
			return creeps
		end
		return listAll(listType)
	end
	-- Every creep in these tests walks the mid lane.
	_G.GetAmountAlongLane = function(lane)
		return { amount = 0.3, distance = lane == LANE_MID and 100 or 3000 }
	end
	bot._loc = Vector(-3000, -2800, 0)
	local orders = {}
	bot.Action_MoveToLocation = function(_, loc)
		orders[#orders + 1] = { "move", loc }
	end
	bot.Action_AttackMove = function(_, loc)
		orders[#orders + 1] = { "attack-move", loc }
	end
	bot.Action_AttackUnit = function(_, unit)
		orders[#orders + 1] = { "attack", unit:GetLocation(), unit }
	end
	local Defend = require(GetScriptDirectory() .. "/FuncLib/systems/defend")
	return {
		bot = bot,
		Defend = Defend,
		Dota = Dota,
		orders = orders,
		towers = towers,
		barracks = barracks,
		creeps = creeps,
		ancient = ancient,
	}
end

local function think(g)
	Stub.time = Stub.time + 3
	local before = #g.orders
	g.Defend.DefendThink(g.bot, LANE_MID)
	T.eq(#g.orders, before + 1, "one order per think")
	return g.orders[#g.orders]
end

local function lastStep()
	for i = #Stub.printed, 1, -1 do
		local step = string.match(Stub.printed[i], "hg%-step step=(%S+)")
		if step ~= nil then
			return step
		end
	end
	return nil
end

local function dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function creep(g, x, y)
	local unit = Stub.newUnit({ name = "npc_dota_creep_badguys_melee", team = TEAM_DIRE, loc = Vector(x, y, 0) })
	g.creeps[#g.creeps + 1] = unit
	return unit
end

T.test("defend think: a T1 still up is held", function()
	local g = setup({ t1 = true })
	local order = think(g)
	T.eq(lastStep(), "lane-defend")
	T.ok(dist(order[2], MID_T1) <= 300, "at the T1")
end)

T.test("defend think: the rim stays where the T3 stood, through the T4s and the Ancient", function()
	local g = setup()
	local order = think(g)
	T.eq(lastStep(), "hg-spot", "T3 up, no wave")
	T.ok(dist(order[2], MID_T3) <= 500, "at the T3")
	-- T3 down, barracks up: tier 3, same rim.
	g.towers[g.Dota.Tower.Mid3]._alive = false
	g.barracks[g.Dota.Barracks.MidMelee] = building("npc_dota_goodguys_melee_rax_mid", { x = -4400, y = -3900 })
	order = think(g)
	T.eq(lastStep(), "hg-spot", "T3 down")
	T.ok(dist(order[2], MID_T3) <= 500, "rim at the T3 spot, not the barracks: " .. dist(order[2], MID_T3))
	-- Barracks down (T4s), then the T4s down (Ancient): the rim, not the Ancient (game 068 52:30).
	g.barracks[g.Dota.Barracks.MidMelee]._alive = false
	order = think(g)
	T.eq(lastStep(), "hg-spot", "tier 4")
	T.ok(dist(order[2], MID_T3) <= 500, "rim at tier 4")
	g.towers[g.Dota.Tower.Base1]._alive = false
	g.towers[g.Dota.Tower.Base2]._alive = false
	order = think(g)
	T.eq(lastStep(), "hg-spot", "tier 5")
	T.ok(dist(order[2], MID_T3) <= 500, "rim at tier 5")
	T.ok(dist(order[2], ANCIENT) > 1500, "not at the Ancient")
end)

T.test("defend think: meet the wave at the rim, not further than the step-down", function()
	local g = setup()
	think(g) -- the T3 seen standing
	g.towers[g.Dota.Tower.Mid3]._alive = false
	-- A wave 900 out from the T3 on the ramp, the bot back by the T4s: walk to it.
	g.bot._loc = Vector(-5000, -4600, 0)
	local first = creep(g, MID_T3.x + 640, MID_T3.y + 640)
	local order = think(g)
	T.eq(lastStep(), "hg-wave")
	T.eq(order[3], first, "attacks the wave creep")
	-- A creep far down the lane (3500 out) is not met; the bot holds the rim.
	first._alive = false
	creep(g, MID_T3.x + 2500, MID_T3.y + 2500)
	order = think(g)
	T.eq(lastStep(), "hg-spot")
	T.ok(dist(order[2], MID_T3) <= 500, "holds the rim")
end)

T.test(
	"defend think: heroes at the rim: back alone, fight with the team; heroes at the Ancient call everyone home",
	function()
		local g = setup()
		local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
		Fu.WeAreStronger = function()
			return false
		end
		think(g) -- the T3 seen standing
		g.towers[g.Dota.Tower.Mid3]._alive = false
		local dire = Stub.teams[TEAM_DIRE]
		-- Three heroes on the rim itself (~1900 from the Ancient): a rim fight, not "heroes at the Ancient".
		for i = 1, 3 do
			dire[i]._loc = Vector(MID_T3.x - 180 + 60 * i, MID_T3.y - 180, 0)
		end
		-- Our other four far away (top lane): alone against three, back to the Ancient (the T3 is down).
		local radiant = Stub.teams[TEAM_RADIANT]
		for i = 2, 5 do
			radiant[i]._loc = Vector(-6000, 3000, 0)
		end
		local order = think(g)
		T.eq(lastStep(), "hg-back")
		T.ok(dist(order[2], ANCIENT) <= 800, "back at the Ancient")
		-- Three allies by the Ancient, within reach of the rim (2500): four against three, fight at the rim.
		for i = 2, 4 do
			radiant[i]._loc = Vector(ANCIENT.x + 300, ANCIENT.y + 300 * i, 0)
		end
		order = think(g)
		T.eq(lastStep(), "hg-fight")
		T.ok(dist(order[2], MID_T3) <= 1200, "at the rim, no chase")
		dire[1]._loc = Vector(ANCIENT.x + 500, ANCIENT.y, 0)
		think(g)
		T.eq(lastStep(), "ancient-heroes")
	end
)

T.test("defend think: two waves on two rims: each bot meets its own rim's wave", function()
	local g = setup()
	think(g) -- the T3s seen standing
	g.towers[g.Dota.Tower.Mid3]._alive = false
	g.towers[g.Dota.Tower.Top3]._alive = false
	local TOP_T3 = { x = -6600, y = -1800 }
	-- Creeps north of y=-2600 walk the top lane, the rest mid.
	_G.GetAmountAlongLane = function(lane, loc)
		local creepLane = loc.y > -2600 and LANE_TOP or LANE_MID
		return { amount = 0.3, distance = lane == creepLane and 100 or 3000 }
	end
	-- This bot by the mid rim, one ally by the top rim, the other three far away.
	g.bot._loc = Vector(-4300, -3900, 0)
	local radiant = Stub.teams[TEAM_RADIANT]
	radiant[2]._loc = Vector(-6400, -2200, 0)
	for i = 3, 5 do
		radiant[i]._loc = Vector(3000, 3000, 0)
	end
	local topCreep = creep(g, TOP_T3.x + 300, TOP_T3.y + 300)
	creep(g, TOP_T3.x + 400, TOP_T3.y + 300)
	local midCreep = creep(g, MID_T3.x + 300, MID_T3.y + 300)
	creep(g, MID_T3.x + 400, MID_T3.y + 300)
	local order = think(g)
	T.ok(order[1] == "attack" and order[3] ~= topCreep, "attacks the mid wave, not the top one")
	local lines = table.concat(Stub.printed, " | ")
	T.ok(string.find(lines, "base-assign lane=top", 1, true) ~= nil, "top rim assigned")
	T.ok(string.find(lines, "base-assign lane=mid", 1, true) ~= nil, "mid rim assigned")
	-- The top wave grows and the top ally stays there; this bot keeps the mid rim while its wave lives.
	for _ = 1, 3 do
		creep(g, TOP_T3.x + 500, TOP_T3.y + 300)
	end
	order = think(g)
	T.ok(order[3] ~= topCreep, "still the mid wave")
	T.ok(midCreep:IsAlive(), "mid wave alive")
	-- Desires: this bot reads at least 0.7 for mid and 0 for top; a bot no rim needs reads 0 on both.
	T.ok(g.Defend.GetDefendDesire(g.bot, LANE_MID) >= 0.7, "assigned rim")
	T.eq(g.Defend.GetDefendDesire(g.bot, LANE_TOP), 0, "the other rim")
	T.eq(g.Defend.GetDefendDesire(radiant[4], LANE_MID), 0, "not needed")
end)

T.test("defend think: no Ancient, no buildings: still one order", function()
	local g = setup()
	Stub.ancients[TEAM_RADIANT] = nil
	for id in pairs(g.towers) do
		g.towers[id] = nil
	end
	creep(g, -2000, -2000)
	think(g)
	T.ok(lastStep() ~= nil, "logged a step")
end)

T.test("defend think: group-up holds the point", function()
	local g = setup()
	g.bot._defendGroupUpUntil = Stub.time + 100
	g.bot._defendGroupUpPoint = Vector(-6000, -5600, 0)
	local order = think(g)
	T.eq(lastStep(), "group-up")
	T.eq(order[1], "move")
	g.bot._loc = Vector(-6000, -5600, 0)
	order = think(g)
	T.eq(order[1], "attack-move", "at the point")
end)
