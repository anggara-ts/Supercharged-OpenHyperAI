-- FuncLib/systems/largo_rules.lua (#198): Largo's beat, song choice, toggle-off and dispel-pull rules, his talent
-- picks, and the Fu helpers every hero file calls.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_largo" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/largo_rules")
end

T.test("largo: a strum is due on the first think at or after each beat, once", function()
	local R = load()
	-- Song on at 100.0 (the anchor): beats at 101, 102, ... (rhythm_interval 1, datafeed hero_id=155).
	T.eq(R.BeatDue(100.5, 100, 100, 1, 0.25), nil, "half a beat in: nothing yet")
	T.eq(R.BeatDue(100.99, 100, 100, 1, 0.25), nil, "never before the beat")
	T.eq(R.BeatDue(101.03, 100, 100, 1, 0.25), 101, "first think after the beat")
	T.eq(R.BeatDue(101.10, 100, 101, 1, 0.25), nil, "that beat was strummed")
	T.eq(R.BeatDue(101.30, 100, 100, 1, 0.25), nil, "too late for that beat: wait for the next")
	T.eq(R.BeatDue(102.05, 100, 101, 1, 0.25), 102, "the next beat")
	T.eq(R.BeatDue(104.10, 100, 101, 1, 0.25), 104, "after skipped beats: the current one")
	T.eq(R.BeatDue(99, 100, 100, 1, 0.25), nil, "before the anchor")
end)

T.test("largo: a re-anchored beat is not strummed twice", function()
	local R = load()
	-- Strummed the beat at 101; a miss moved the anchor to 100.3: 101.3 is too close to 101, 102.3 is the next.
	local anchor = R.Reanchor(100, "miss", true, 0.3)
	T.near(anchor, 100.3, 1e-9, "a miss of a strum that went out moves the beat later")
	T.eq(R.BeatDue(101.35, anchor, 101, 1, 0.25), nil, "0.3s after the last strum: no")
	T.near(R.BeatDue(102.35, anchor, 101, 1, 0.25), 102.3, 1e-9, "the shifted beat")
	T.eq(R.Reanchor(100, "hit", true, 0.3), 100, "a hit keeps the beat")
	T.eq(R.Reanchor(100, "max", true, 0.3), 100, "at the cap: keep the beat")
	T.eq(R.Reanchor(100, "miss", false, 0.3), 100, "a strum that never went out says nothing about the beat")
	T.ok(R.MayReanchor(2, 0), "two shifts with no hit: one more")
	T.ok(not R.MayReanchor(3, 0), "a whole beat swept with no hit: the stacks say nothing, stop")
	T.ok(R.MayReanchor(5, 1), "after a hit the stacks work: keep correcting")
	-- Three misses walk the phase through the whole beat.
	T.near(R.Reanchor(R.Reanchor(R.Reanchor(100, "miss", true), "miss", true), "miss", true), 100.9, 1e-9, "3 shifts")
end)

T.test("largo: strum result from the Groovin' stacks", function()
	local R = load()
	T.eq(R.StrumResult(0, 1, 5), "hit", "a stack gained")
	T.eq(R.StrumResult(3, 4, 5), "hit", "lingering stacks count from where they were")
	T.eq(R.StrumResult(2, 2, 5), "miss", "no stack gained below the cap")
	T.eq(R.StrumResult(2, 1, 5), "miss", "a stack lost")
	T.eq(R.StrumResult(5, 5, 5), "max", "at the cap a hit can't show")
	T.eq(R.StrumResult(5, 4, 5), "miss", "a stack lost at the cap")
end)

T.test("largo: which song", function()
	local R = load()
	local function pick(s)
		local first, second, why = R.ChooseSongs(s)
		return tostring(first) .. "/" .. tostring(second) .. "/" .. tostring(why)
	end
	T.eq(pick({}), "nil/nil/nil", "nothing going on")
	T.eq(pick({ enemies = 2 }), "nil/nil/nil", "enemies near, nobody fighting")
	T.eq(pick({ enemies = 2, fighting = true }), "fight/nil/fight", "a fight: Fight Song")
	T.eq(pick({ enemies = 1, fighting = true, hurtHp = 0.45 }), "vibes/nil/hurt", "an ally under 50%: heal")
	T.eq(pick({ enemies = 1, fighting = true, hurtHp = 0.6 }), "fight/nil/fight", "60% in a fight: keep fighting")
	T.eq(pick({ enemies = 1, fighting = true, hurtHp = 0.6, double = true }), "fight/vibes/fight+hurt", "Scepter")
	T.eq(pick({ escaping = true, hurtHp = 0.4 }), "time/nil/escape", "an escape beats a 40% heal")
	T.eq(pick({ escaping = true, hurtHp = 0.2 }), "vibes/nil/hurt", "under 30%: heal first")
	T.eq(pick({ escaping = true, hurtHp = 0.2, double = true }), "vibes/time/hurt+escape", "Scepter: both")
	T.eq(pick({ chasing = true }), "time/nil/chase", "a chase")
	T.eq(pick({ enemies = 1, fighting = true, chasing = true }), "fight/nil/fight", "a fight beats a chase")
	T.eq(pick({ objective = true }), "fight/nil/objective", "Roshan / Tormentor")
	T.eq(pick({ hurtHp = 0.7 }), "nil/nil/nil", "70% and nothing going on: no song")
end)

T.test("largo: the song ends only after a few seconds with no reason, or with no mana", function()
	local R = load()
	T.eq(R.ToggleOffReason(10, 9, true, 3), nil, "a reason a second ago")
	T.eq(R.ToggleOffReason(12.9, 10, true, 3), nil, "2.9s: keep singing")
	T.eq(R.ToggleOffReason(13, 10, true, 3), "idle", "3s with no reason")
	T.eq(R.ToggleOffReason(10, 10, false, 3), "mana", "no mana for one song")
	T.eq(R.ToggleOffReason(10, 10, true, 3, 2), nil, "two beats with no song out: keep trying")
	T.eq(R.ToggleOffReason(10, 10, true, 3, 3), "no-cast", "three beats with no song out: stop, he is disarmed")
	T.ok(R.CanStartSong(105, 35, 1, 3), "3 beats of a 35 song")
	T.ok(not R.CanStartSong(104, 35, 1, 3), "not quite 3 beats")
	T.ok(not R.CanStartSong(150, 35, 2, 3), "Scepter: 3 beats of two songs")
end)

T.test("largo: a dispel lick never drags a fighting ally out of its range", function()
	local R = load()
	-- pull_distance_ally 375 (datafeed hero_id=155).
	T.ok(not R.DispelPullOk(true, 120, 150, 375, false), "melee ally hitting its target")
	T.ok(not R.DispelPullOk(true, 500, 600, 375, false), "ranged ally in range")
	T.ok(R.DispelPullOk(true, 120, 150, 375, true), "asleep or stunned: it isn't fighting anyway")
	T.ok(R.DispelPullOk(true, 900, 150, 375, false), "not in range of its target")
	T.ok(R.DispelPullOk(false, 120, 150, 375, false), "not fighting")
	T.ok(R.DispelPullOk(true, nil, 150, 375, false), "no target")
end)

T.test("largo: Croak of Genius on himself or an ally", function()
	local R = load()
	local function pick(o)
		local target, why = R.CroakTarget(o)
		return tostring(target) .. "/" .. tostring(why)
	end
	T.eq(pick({}), "nil/nil", "nobody needs it")
	T.eq(pick({ selfWants = true, alone = true }), "self/self-mana", "alone before a song")
	T.eq(pick({ selfWants = true }), "self/self-mana", "no ally fighting: himself")
	T.eq(pick({ allyWants = true }), "ally/ally", "an ally fighting, Largo has no use for it")
	T.eq(pick({ allyWants = true, allyIsCore = true, selfWants = true }), "ally/ally", "no Shard: a core's fight wins")
	T.eq(
		pick({ allyWants = true, selfWants = true }),
		"self/self-mana",
		"no Shard: a support's fight loses to the songs"
	)
	T.eq(pick({ hasShard = true, allyWants = true, selfWants = true }), "ally/shard-share", "Shard: Largo gets it too")
	T.eq(pick({ hasShard = true, selfWants = true, alone = true }), "self/self-mana", "Shard, alone: himself")
end)

T.test("largo: Frogstomp lane harass only with spare mana, away from the tower, not outnumbered", function()
	local R = load()
	local base = { mpRatio = 0.9, manaAfterOk = true, inEnemyTowerRange = false, enemiesNear = 2, alliesNear = 2 }
	local function check(over)
		local o = {}
		for k, v in pairs(base) do
			o[k] = v
		end
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		local ok, why = R.LaneStompOk(o)
		return tostring(ok) .. "/" .. tostring(why)
	end
	T.eq(check(), "true/nil", "2v2 lane, 90% mana")
	T.eq(check({ mpRatio = 0.7 }), "false/mana", "70% mana: keep it")
	T.eq(check({ manaAfterOk = false }), "false/reserve", "no mana left for Lick and Croak")
	T.eq(check({ inEnemyTowerRange = true }), "false/tower", "inside the enemy tower's range (game 071 5:55)")
	T.eq(check({ enemiesNear = 3 }), "false/outnumbered", "3 enemies against 2")
	T.eq(check({ retreating = true }), "false/retreating", "running home")
end)

T.test("largo: end the song only for a clearly better Lick or Frogstomp", function()
	local R = load()
	T.ok(R.BreakSongFor("kill", 5, 1, 0), "a kill, even at 5 stacks")
	T.ok(R.BreakSongFor("ally-save", 5, 1, 0), "an ally save")
	T.ok(R.BreakSongFor("ally-dispel:bane_nightmare", 4, 1, 1), "an ally dispel")
	T.ok(R.BreakSongFor("channel", 5, 1, 0), "a channel stopped")
	T.ok(R.BreakSongFor("fight-aoe", 5, 3, 2), "a stomp on 3 heroes")
	T.ok(R.BreakSongFor("fight-aoe", 2, 2, 1), "2 heroes, 2 stacks: little to lose")
	T.ok(not R.BreakSongFor("fight-aoe", 3, 2, 1), "2 heroes at 3 stacks: keep singing")
	T.ok(R.BreakSongFor("chase", 1, 1, 1), "a pull into our fight")
	T.ok(not R.BreakSongFor("chase", 1, 1, 0), "a pull with nobody of ours near")
	T.ok(not R.BreakSongFor("chase", 4, 1, 2), "a pull at 4 stacks: keep singing")
	T.ok(not R.BreakSongFor("fight-target", 0, 1, 2), "a one-hero stomp: no")
	T.ok(not R.BreakSongFor("harass", 0, 1, 0), "lane harass: no")
	T.ok(not R.BreakSongFor("enemy-dispel:ursa_overpower", 0, 1, 2), "an enemy dispel: no")
	T.ok(not R.BreakSongFor(nil, 0, 0, 0), "nothing")
end)

-- The level-up list from the hero file with the real ability slots (Tests/data/hero_abilities.lua).
T.test("largo: talents at 20 and 25 are two Lick charges and twice the stomps", function()
	local data = assert(loadstring(T.read("Tests/data/hero_abilities.lua"), "hero_abilities"))()
	local entries = {}
	for index, entry in ipairs(data.largo) do
		local name, flags = string.match(entry .. "|", "^([^|]*)|([^|]*)")
		entries[index] = {
			name = name,
			ultimate = string.find(flags, "u") ~= nil,
			hidden = string.find(flags, "h") ~= nil,
			behavior = string.find(flags, "n") and 64 or 0,
		}
	end
	local unit = Stub.reset({ hero = "npc_dota_hero_largo", slot = 5 })
	Stub.setSlots(unit, entries)
	local ok, hero = Stub.load("BotsLib/hero_largo")
	T.ok(ok, tostring(hero))
	local talents = {}
	for point = 1, 30 do
		local name = hero.sSkillList[point]
		if name ~= nil and string.find(name, "^special_bonus_unique_largo") then
			talents[#talents + 1] = name
		end
	end
	T.eq(talents[1], "special_bonus_unique_largo_2", "level 10: Catchy Lick regen")
	T.eq(talents[2], "special_bonus_unique_largo_4", "level 15: Catchy Lick range and pull")
	T.eq(talents[3], "special_bonus_unique_largo_8", "level 20: two Catchy Lick charges")
	T.eq(talents[4], "special_bonus_unique_largo_5", "level 25: twice the Frogstomp stomps")
end)

-- Hero files call shared helpers as Fu.Name: a name that func_utils does not define is a script error when that
-- line runs (#198: Largo's Fu.IsThereCoreInLocation never existed; Invoker's Fu.Unit neither).
T.test("every Fu.Name a hero file uses exists in func_utils", function()
	Stub.reset({ hero = "npc_dota_hero_largo" })
	local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")
	local missing = {}
	for _, path in ipairs(T.files("^BotsLib/hero_[%w_]+%.lua$")) do
		local seen = {}
		for name in string.gmatch(T.read(path), "%f[%w_%.]Fu%.([%a_][%w_]*)") do
			if Fu[name] == nil and not seen[name] then
				seen[name] = true
				missing[#missing + 1] = path .. ": Fu." .. name
			end
		end
	end
	T.eq(table.concat(missing, ", "), "", "undefined Fu helpers")
end)
