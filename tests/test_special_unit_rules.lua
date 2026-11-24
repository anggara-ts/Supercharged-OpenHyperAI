-- bots/lib/systems/special_unit_rules.lua (#185): Undying's Tombstone, and the team roam desire it gives.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/lib/systems/special_unit_rules")
end

T.test("tombstone: hits left from its health", function()
	local R = rules()
	-- npc_units.txt (7.42): tombstone1 StatusHealth 20 for 5 hero hits (4 per hit).
	T.eq(R.TombstoneHitsLeft(20, 20), 5, "full level-1 Tombstone: 5 hits")
	T.eq(R.TombstoneHitsLeft(12, 32), 3, "level 4, 12 health left: 3 hits")
	T.eq(R.TombstoneHitsLeft(9, 20), 3, "9 health: 3 hits (rounded up)")
	-- If the API reports pips instead.
	T.eq(R.TombstoneHitsLeft(2, 5), 2, "pip scale: 2 left")
	T.eq(R.TombstoneHitsLeft(0, 20), 0, "dead")
end)

T.test("tombstone: priority above attack mode when close, nearly dead or allies in it", function()
	local R = rules()
	T.ok(R.TOMBSTONE_PRIORITY_DESIRE > 0.95, "above attack mode's 0.95")
	-- dist, attackRange, hitsLeft, alliesInRadius, alliesNear, enemiesNear, retreating, hpRatio
	local desire, priority = R.TombstoneDesire(550, 150, 5, 1, 1, 3, false, 0.7)
	T.eq(priority, true, "within 600, outnumbered 1 vs 3: no even-fight gate")
	T.eq(desire, R.TOMBSTONE_PRIORITY_DESIRE, "priority desire")
	T.eq(select(2, R.TombstoneDesire(1100, 150, 3, 1, 1, 2, false, 0.7)), true, "3 hits left, inside the radius")
	T.eq(select(2, R.TombstoneDesire(1400, 150, 2, 1, 1, 1, false, 0.7)), false, "nearly dead but outside the radius")
	T.eq(select(2, R.TombstoneDesire(1400, 150, 6, 2, 2, 2, false, 0.7)), true, "two allies stand in its radius")
	T.eq(select(2, R.TombstoneDesire(300, 150, 1, 3, 3, 1, true, 0.7)), false, "never while retreating")
	T.eq(select(2, R.TombstoneDesire(300, 150, 1, 3, 3, 1, false, 0.2)), false, "never under 25% HP")
end)

T.test("tombstone: with enemy heroes in the fight only a quick kill comes first", function()
	local R = rules()
	-- dist, attackRange, hitsLeft, alliesInRadius, alliesNear, enemiesNear, retreating, hpRatio, fight
	-- Game 069 37:39: Axe at a full Tombstone (8 hits), 1 hero on it, 4 enemies, Berserker's Call ready: fight.
	local desire, priority, why =
		R.TombstoneDesire(300, 150, 8, 3, 3, 4, false, 0.8, { enemies = 4, hitters = 1, teamfightReady = true })
	T.eq(priority, false, "no priority")
	T.eq(why, "teamfight-ready", "why=teamfight-ready")
	T.eq(desire, 0, "he fights")
	-- Same without the spell: 8s to kill alone -> slow-kill; outnumbered, so the old rule gives 0.
	desire, priority, why =
		R.TombstoneDesire(300, 150, 8, 3, 3, 4, false, 0.8, { enemies = 4, hitters = 1, teamfightReady = false })
	T.eq(priority, false, "no priority")
	T.eq(why, "slow-kill", "why=slow-kill")
	T.eq(desire, 0, "behind in the fight: 0")
	-- Game 068 t=506: Alchemist 1 vs 3, 5 hits, 249 away: 5s alone -> slow-kill.
	T.eq(
		select(3, R.TombstoneDesire(249, 150, 5, 1, 1, 3, false, 0.97, { enemies = 3, hitters = 1 })),
		"slow-kill",
		"068 t=506 Alchemist"
	)
	-- Game 068 t=158: Zeus 2 vs 2, 5 hits, two heroes on it: 2.5s -> priority.
	T.eq(select(2, R.TombstoneDesire(400, 600, 5, 2, 2, 2, false, 0.9, { enemies = 2, hitters = 2 })), true, "068 Zeus")
	-- Even fight, slow kill: the old rule, held under attack mode.
	desire = R.TombstoneDesire(300, 150, 8, 1, 2, 2, false, 0.9, { enemies = 2, hitters = 1 })
	T.near(desire, R.TOMBSTONE_FIGHT_CAP, 1e-9, "capped at 0.9, under attack mode")
	-- 3 hits or fewer: priority even with enemies; with a teamfight spell ready only at 2 hits or fewer.
	T.eq(select(2, R.TombstoneDesire(300, 150, 3, 1, 1, 4, false, 0.8, { enemies = 4, hitters = 1 })), true, "3 hits")
	T.eq(
		select(
			2,
			R.TombstoneDesire(300, 150, 3, 1, 1, 4, false, 0.8, { enemies = 4, hitters = 1, teamfightReady = true })
		),
		false,
		"3 hits, spell ready: fight"
	)
	T.eq(
		select(
			2,
			R.TombstoneDesire(300, 150, 2, 1, 1, 4, false, 0.8, { enemies = 4, hitters = 1, teamfightReady = true })
		),
		true,
		"2 hits, spell ready: kill it"
	)
	-- No enemy hero within reach: clear it first as before, spell or not.
	T.eq(
		select(
			2,
			R.TombstoneDesire(300, 150, 8, 1, 1, 0, false, 0.8, { enemies = 0, hitters = 1, teamfightReady = true })
		),
		true,
		"no enemies: priority"
	)
	T.eq(R.TombstoneKillTime(8, 1), 8, "8 hits, 1 hero: 8s at 1 hit per second")
end)

T.test("tombstone: outside the priority the old even-fight rule", function()
	local R = rules()
	local desire, priority = R.TombstoneDesire(800, 600, 6, 1, 2, 2, false, 0.9)
	T.eq(priority, false, "far, full health, one ally in it")
	T.near(desire, 0.96, 1e-9, "within attack range + 200 at 90% HP")
	T.near((R.TombstoneDesire(900, 150, 6, 1, 2, 2, false, 0.9)), 0.56, 1e-9, "farther: 0.56")
	T.eq((R.TombstoneDesire(900, 150, 6, 1, 1, 2, false, 0.9)), 0, "behind in the fight: 0")
end)

T.test("tombstone: a zombie-slowed bot hits it instead of running", function()
	local R = rules()
	T.eq(R.TombstoneHitWhenSlowed(350, 3), true, "350 away, 3 hits")
	T.eq(R.TombstoneHitWhenSlowed(350, 4), false, "4 hits: run")
	T.eq(R.TombstoneHitWhenSlowed(500, 2), false, "farther than 400: run")
end)

-- Team roam's final desire: the laning-phase cap (0.72) and the push cap (0.5) must not apply.
local function roamWithTombstone(hits)
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	local bot = GetBot()
	-- Mid map: near our ancient team roam stops for the ancient threat (the Tombstone counts as an enemy there).
	bot._loc = Vector(0, 0, 0)
	local tombstone = T.stub.newUnit({
		name = "npc_dota_unit_tombstone1",
		team = TEAM_DIRE,
		loc = bot:GetLocation() + Vector(300, 0, 0),
		maxHp = 20,
		hp = hits * 4,
		hero = false,
	})
	local listUnits = GetUnitList
	GetUnitList = function(listType)
		local units = listUnits(listType)
		if listType == UNIT_LIST_ENEMIES then
			units[#units + 1] = tombstone
		end
		return units
	end
	local ok, err = T.stub.load("mode_team_roam_generic")
	T.ok(ok, tostring(err))
	return bot
end

T.test("team roam: a Tombstone 300 away beats attack mode in the laning phase", function()
	local bot = roamWithTombstone(5)
	bot.isInLanePhase = true
	local desire = GetDesire()
	T.ok(desire > 0.95, "above attack mode, laning cap not applied: " .. tostring(desire))
	T.eq(bot._tombstonePriority, true, "priority flag")
	local line
	for _, printed in ipairs(T.stub.printed) do
		line = line
			or (string.find(printed, "special%-unit unit=tombstone hits%-left=5 hp=20 maxHp=20 dist=300") and printed)
	end
	T.ok(line ~= nil, "[SHy-ROAM] special-unit line")
end)

T.test("team roam: the Tombstone priority is not capped while pushing", function()
	local bot = roamWithTombstone(2)
	bot.GetActiveMode = function()
		return BOT_MODE_PUSH_TOWER_MID
	end
	bot.GetActiveModeDesire = function()
		return 0.9
	end
	local desire = GetDesire()
	T.ok(desire > 0.95, "push cap (0.5) not applied: " .. tostring(desire))
end)
