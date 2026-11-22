-- FuncLib/systems/drum_rules.lua (#9): when the Drum of Endurance / Boots of Bearing active is used.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/drum_rules")
end

T.test("drum rules: 7.42 game data", function()
	local R = load()
	T.eq(R.RADIUS, 1200, "radius 1200 (items.txt item_ancient_janggo / item_boots_of_bearing)")
end)

T.test("drum rules: each case", function()
	local R = load()
	T.eq(R.Why({}), nil, "nothing going on")
	T.eq(R.Why({ retreating = true, hitByHero = true, allies = 1 }), "escape", "retreating and hit")
	T.eq(R.Why({ retreating = true, hitByHero = false }), nil, "retreating, not hit")
	T.eq(R.Why({ retreating = false, hitByHero = true }), nil, "hit but not retreating")
	T.eq(R.Why({ inFight = true, allies = 2, enemies = 1 }), "fight", "a fight with an ally in the radius")
	T.eq(R.Why({ inFight = true, allies = 1, enemies = 2 }), nil, "a fight alone: the bot only buffs itself")
	T.eq(R.Why({ inFight = true, allies = 3, enemies = 0 }), nil, "no enemy hero near")
	-- Chase: within 900 and getting away (moving away or out of attack range).
	local chase = { goingOn = true, targetDist = 500, attackRange = 150, targetMovingAway = false }
	T.eq(R.Why(chase), "chase", "melee bot, target 500 away: out of attack range")
	chase.attackRange = 600
	T.eq(R.Why(chase), nil, "ranged bot, target 500 away and not running: no cast")
	chase.targetMovingAway = true
	T.eq(R.Why(chase), "chase", "target running away")
	chase.targetDist = 901
	T.eq(R.Why(chase), nil, "beyond 900")
	T.eq(R.Why({ goingOn = false, targetDist = 500, attackRange = 150, targetMovingAway = true }), nil, "not going on")
	T.eq(R.Why({ goingOn = true, attackRange = 150 }), nil, "no hero target")
	-- Push: 2+ allied heroes (the bot counted) hitting a building.
	T.eq(R.Why({ alliesOnBuilding = 2 }), "push", "two heroes on the tower")
	T.eq(R.Why({ alliesOnBuilding = 1 }), nil, "one hero on the tower")
end)

T.test("drum rules: order escape > fight > chase > push", function()
	local R = load()
	local all = {
		retreating = true,
		hitByHero = true,
		inFight = true,
		allies = 3,
		enemies = 2,
		goingOn = true,
		targetDist = 500,
		attackRange = 150,
		targetMovingAway = true,
		alliesOnBuilding = 3,
	}
	T.eq(R.Why(all), "escape", "escape first")
	all.retreating = false
	T.eq(R.Why(all), "fight", "then fight")
	all.inFight = false
	T.eq(R.Why(all), "chase", "then chase")
	all.goingOn = false
	T.eq(R.Why(all), "push", "then push")
end)

T.test("drum rules: never inside Vendetta or invisible", function()
	local R = load()
	T.eq(R.Why({ vendetta = true, retreating = true, hitByHero = true }), nil, "Nyx Vendetta")
	T.eq(R.Why({ invisible = true, alliesOnBuilding = 3 }), nil, "invisible")
end)
