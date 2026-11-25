-- bots/lib/systems/objective_travel.lua (issue #53): the gate route time, who can walk through a Fiend's Gate, that a
-- 7.42 hero (no twin_gate_portal_warp) never plans a trip through a Twin Gate, and Underlord's Scepter gate pit.
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

T.test("travel: someone can walk through a Fiend's Gate only with a human ally or the warp ability", function()
	local Travel = load()
	T.eq(Travel.PortalWalkable(false, 0), false, "7.42, bots only")
	T.eq(Travel.PortalWalkable(false, 1), true, "a human ally")
	T.eq(Travel.PortalWalkable(true, 0), true, "the warp ability is back")
end)

local function underlord()
	T.stub.reset({ hero = "npc_dota_hero_abyssal_underlord" })
	local ok, result = T.stub.load("bots/heroes/hero_abyssal_underlord")
	if not ok then
		error(tostring(result), 0)
	end
	return result
end

T.test("underlord: the Scepter gate's pit is aimed where it catches the most enemies", function()
	local X = underlord()
	local spot, count = X.GatePitSpot({}, 350)
	T.eq(spot, nil, "no enemies: no spot")
	T.eq(count, 0, "no enemies: none caught")
	-- two enemies 600 apart and one far off: the midpoint of the two catches both (pit radius 400, aim 350)
	spot, count = X.GatePitSpot({ Vector(0, 0, 0), Vector(600, 0, 0), Vector(3000, 0, 0) }, 350)
	T.eq(count, 2, "two of three")
	T.near(spot.x, 300, 0.001, "between the two")
	T.near(spot.y, 0, 0.001, "between the two (y)")
	spot, count = X.GatePitSpot({ Vector(0, 0, 0), Vector(900, 0, 0) }, 350)
	T.eq(count, 1, "too far apart for one pit")
end)

T.test("underlord: when the Scepter gate's pit is worth casting", function()
	local X = underlord()
	-- why, distance to the spot, enemies in the pit, ally hp ratio, enemies near the ally
	T.eq(X.GatePitWorth("save", 3000, 1, 0.5, 1), true, "hurt ally, one enemy on him")
	T.eq(X.GatePitWorth("save", 3000, 1, 0.9, 1), false, "healthy ally, one enemy: not worth the ultimate")
	T.eq(X.GatePitWorth("save", 3000, 1, 0.9, 2), true, "two enemies on the ally")
	T.eq(X.GatePitWorth("save", 3000, 0, 0.3, 1), false, "the pit would catch nobody")
	T.eq(X.GatePitWorth("save", 1400, 1, 0.3, 1), false, "closer than the gate's minimum_distance 1500")
	T.eq(X.GatePitWorth("fight", 3000, 2, 1, 2), true, "two enemies in the pit")
	T.eq(X.GatePitWorth("fight", 3000, 1, 1, 3), false, "a fight needs two in the pit")
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

-- Underlord (Radiant slot 1, bottom-left) with his gate ready and Pit of Malice learned, at 20:00; an ally far
-- away in the middle of the map with one enemy hero on him.
local function gateScene(opts)
	local X = underlord()
	T.stub.time = 1200
	local bot = GetBot()
	bot.HasScepter = function()
		return opts.scepter == true
	end
	local gate = bot:GetAbilityByName("abyssal_underlord_dark_portal")
	gate.IsFullyCastable = function()
		return true
	end
	bot:GetAbilityByName("abyssal_underlord_pit_of_malice").GetLevel = function()
		return 1
	end
	local ally = T.stub.teams[TEAM_RADIANT][2]
	local enemy = T.stub.teams[TEAM_DIRE][1]
	if opts.allyHit then
		ally._loc = Vector(2000, 0, 0)
		ally._hp = 300
		ally.WasRecentlyDamagedByAnyHero = function()
			return true
		end
		enemy._loc = Vector(2200, 100, 0)
	end
	return X, bot, gate, ally, enemy
end

T.test("underlord: with Scepter the gate drops a Pit of Malice on the enemy beating a far ally", function()
	local X, bot = gateScene({ scepter = true, allyHit = true })
	local desire, loc = X.ConsiderFiendsGate()
	T.ok(desire > 0, "cast")
	T.ok(loc ~= 0 and math.abs(loc.x - 2200) < 1 and math.abs(loc.y - 100) < 1, "on the enemy")
	T.ok(GetUnitToLocationDistance(bot, loc) > 1500, "beyond minimum_distance")
	T.eq(printed("gate%-pit why=save ally=lina enemies=1"), 1, "logged")
end)

T.test("underlord: bots only, no Scepter, nothing far: no gate, the skip is logged", function()
	local X = gateScene({ scepter = false })
	local desire = X.ConsiderFiendsGate()
	T.eq(desire, 0, "no cast")
	T.eq(printed("fiends%-gate%-off why=no%-warp humans=0 scepter=false self=untested"), 1, "skip logged")
end)

T.test("underlord: the first far gate is a self-test that measures whether he teleported", function()
	T.eq(underlord().GateSelfResult(true, 1800), "yes", "jumped")
	T.eq(underlord().GateSelfResult(true, 400), "no", "cast, walked only")
	T.eq(underlord().GateSelfResult(false, 0), "retry", "the cast never happened")

	-- no Scepter: an ally under attack 4000+ away is a reason for the self-test cast
	local X, bot, gate = gateScene({ scepter = false, allyHit = true })
	local desire, loc = X.ConsiderFiendsGate()
	T.ok(desire > 0, "self-test cast")
	X.GateSelfStart(loc, "selftest-ally", "lina")
	T.eq(printed("gate%-self cast why=selftest%-ally at=2000,0 target=lina"), 1, "cast logged")
	gate.GetCooldownTimeRemaining = function()
		return 90
	end
	T.stub.time = 1201
	X.GateSelfWatch()
	T.eq(printed("gate%-self result="), 0, "still watching")
	bot._loc = Vector(2000, 0, 0)
	T.stub.time = 1202
	X.GateSelfWatch()
	T.eq(printed("gate%-self result=yes moved=%d+ at=2000,0 nearTarget=yes"), 1, "teleport seen")
	T.eq(bot._gateSelf.state, "yes", "from now on a global trip")

	-- he did not move: "no" after the watch, and the bots-only skip stays
	X, bot, gate = gateScene({ scepter = false, allyHit = true })
	desire, loc = X.ConsiderFiendsGate()
	X.GateSelfStart(loc, "selftest-ally", "lina")
	gate.GetCooldownTimeRemaining = function()
		return 90
	end
	T.stub.time = 1208
	X.GateSelfWatch()
	T.eq(printed("gate%-self result=no moved=0 .* nearTarget=no .* cast=true"), 1, "no teleport")
	T.eq(bot._gateSelf.state, "no", "measured")
	T.eq(desire > 0 and X.ConsiderFiendsGate() or -1, 0, "no more self-test casts")
end)
