-- bots/lib/systems/largo_rules.lua (#198): Largo's beat, song choice, toggle-off and dispel-pull rules, his talent
-- picks, and the Fu helpers every hero file calls.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_largo" })
	return require(GetScriptDirectory() .. "/lib/systems/largo_rules")
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
	T.ok(not R.MayReanchor(0, 5, 1), "a proven beat: one miss doesn't move it (game 071)")
	T.ok(R.MayReanchor(5, 1, 2), "a proven beat: two on-time misses in a row move it")
	T.ok(R.ShouldRepush(0.1, 1), "order lost right after the beat: push again")
	T.ok(not R.ShouldRepush(0.4, 2), "past the window: wait for the next beat")
	T.ok(not R.ShouldRepush(0.1, 6), "six pushes: give up")
	T.ok(R.CountsAsNoCast(false, nil, false), "a lost order in a fight counts")
	T.ok(R.CountsAsNoCast(false, "nil", false), "no song handle counts")
	T.ok(not R.CountsAsNoCast(false, nil, true), "a lost order while he runs does not (game 071 18:00)")
	T.ok(not R.CountsAsNoCast(false, "cooldown", false), "the shared cooldown: a song just went out")
	T.ok(not R.CountsAsNoCast(true, nil, false), "a song that went out")
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

T.test("largo: the Groovin' cap follows the Rhapsody level (7.42a max_stacks 4/5/6)", function()
	local R = load()
	-- Datafeed hero_id=155 (7.42a): max_stacks [4,5,6]. Game 083 (server 6996) at level 1: 102 strums before=4 after=4
	-- read as misses against a fixed cap of 5, moved a proven beat and ended the song as silent every 6s.
	T.eq(R.MaxStacks(4, 1), 4, "the ability's own value")
	T.eq(R.MaxStacks(0, 1), 4, "no read: the 7.42a value for level 1")
	T.eq(R.MaxStacks(nil, 3), 6, "no read: level 3")
	T.eq(R.MaxStacks(0, 0), 5, "not trained: the old cap")
	T.eq(R.StrumResult(4, 4, R.MaxStacks(4, 1)), "max", "game 083 t=1662: at the level-1 cap, not a miss")
	T.eq(R.StrumResult(5, 6, R.MaxStacks(6, 3)), "hit", "level 3 goes on to 6")
	T.eq(R.StrumResult(6, 6, R.MaxStacks(6, 3)), "max", "and stops there")
	T.ok(not R.MayReanchor(0, 4, 0), "at the cap the miss streak stays 0: the beat stays")
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
	T.eq(pick({ hurtHp = 0.7 }), "nil/nil/nil", "70% with no mana known: no song")
	T.eq(pick({ escaping = true, hurtHp = 0.34 }), "vibes/nil/hurt", "under 35% beats the run song")
end)

T.test("largo: the heal follows the group's need (game 071 ~26:00)", function()
	local R = load()
	local function pick(s)
		local first, second, why = R.ChooseSongs(s)
		return tostring(first) .. "/" .. tostring(second) .. "/" .. tostring(why)
	end
	-- 25:40-25:50: allies at 60-75%, Largo with 758-861 mana (about 80%), Island Elixir heals 55 a strum (level 2).
	local group = { hurtHp = 0.6, missing = 1600, healCount = 4, under65 = 2, healPerStrum = 55, mpRatio = 0.8 }
	local function with(over)
		local o = {}
		for k, v in pairs(group) do
			o[k] = v
		end
		for k, v in pairs(over) do
			o[k] = v
		end
		return o
	end
	T.eq(pick(with({ enemies = 2, fighting = true })), "vibes/nil/group-hurt", "a fight, two allies under 65%")
	T.eq(pick(with({ enemies = 2, fighting = true, under65 = 1, hurtHp = 0.7 })), "fight/nil/fight", "one ally at 70%")
	T.eq(pick(with({ escaping = true })), "time/nil/escape", "an escape at 60%: run")
	T.eq(pick(with({ escaping = true, double = true })), "time/vibes/escape+hurt", "Scepter: run and heal")
	T.eq(pick(with({})), "vibes/nil/top-up", "after the fight: top the group up")
	T.eq(pick(with({ hurtHp = 0.85, missing = 400 })), "nil/nil/nil", "everyone above 80%, under 3 strums missing")
	T.eq(
		pick(with({ hurtHp = 0.82, missing = 900 })),
		"nil/nil/nil",
		"above 80% and 4 strums missing: not worth a song"
	)
	T.eq(pick(with({ hurtHp = 0.82, missing = 1200 })), "vibes/nil/top-up", "above 80% but 5+ strums missing")
	T.eq(pick(with({ mpRatio = 0.3 })), "nil/nil/nil", "30% mana: keep it for the fight")
end)

T.test("largo: a top-up song, once on, heals the group up (game 074 on / idle-off loop)", function()
	local R = load()
	local function pick(s)
		local first, _, why = R.ChooseSongs(s)
		return tostring(first) .. "/" .. tostring(why)
	end
	-- Game 074 t=1146: lowest 0.88, 222 HP missing on two heroes, 30 a strum (level 1): 3.7 strums.
	local small = { hurtHp = 0.88, missing = 222, healCount = 2, healPerStrum = 30, mpRatio = 0.64 }
	T.eq(pick(small), "nil/nil", "not worth starting a song")
	small.singing = true
	T.eq(pick(small), "vibes/top-up", "already singing: heal it up")
	-- One strum later: 162 HP missing, 2.7 strums.
	T.eq(
		pick({ hurtHp = 0.9, missing = 162, healCount = 2, healPerStrum = 30, mpRatio = 0.62, singing = true }),
		"vibes/top-up",
		"2.7 strums missing: keep going"
	)
	T.eq(
		pick({ hurtHp = 0.93, missing = 50, healCount = 2, healPerStrum = 30, mpRatio = 0.6, singing = true }),
		"nil/nil",
		"full: let the song end"
	)
	T.eq(pick({ hurtHp = 0.85, healPerStrum = 30, mpRatio = 0.35, singing = true }), "vibes/top-up", "35% mana once on")
	T.eq(pick({ hurtHp = 0.85, healPerStrum = 30, mpRatio = 0.25, singing = true }), "nil/nil", "25%: keep it")
	T.ok(R.TopUpWanted(0.79, 0, 0.5, false), "under 80% starts it")
	T.ok(not R.TopUpWanted(0.85, 4, 0.5, false), "85% and 4 strums: not started")
	T.ok(R.TopUpWanted(0.85, 0, 0.5, true), "85% once on: keep healing")
	T.ok(not R.TopUpWanted(0.92, 1.5, 0.5, true), "92% and 1.5 strums: done")
end)

T.test("largo: no new top-up right after an idle or silent toggle-off", function()
	local R = load()
	-- Game 083 t=1800 idle off (lowest 0.98), t=1801 a camp hit Largo: lowest 0.80 (just under), 1.7s later.
	T.ok(not R.TopUpWanted(0.79, 2.4, 0.95, false, 1.7), "game 083 t=1801: waits")
	T.ok(R.TopUpWanted(0.79, 2.4, 0.95, false, 3.6), "after the rest: starts")
	-- Game 081 t=1630: an ally walked in at 63%, 1.5s after the group was healed.
	T.ok(not R.TopUpWanted(0.63, 9.4, 0.44, false, 1.5), "game 081 t=1630: waits")
	T.ok(R.TopUpWanted(0.79, 0, 0.5, false, nil), "no toggle-off yet: no wait")
	T.ok(R.TopUpWanted(0.85, 0, 0.5, true, 0.5), "a song that is on keeps going")
	-- The rest is for the top-up only: the urgent and in-fight heals and the other songs don't wait.
	local function pick(s)
		local first, _, why = R.ChooseSongs(s)
		return tostring(first) .. "/" .. tostring(why)
	end
	T.eq(pick({ hurtHp = 0.75, healPerStrum = 30, mpRatio = 0.8, sinceRestOff = 1.5 }), "nil/nil", "top-up waits")
	T.eq(pick({ hurtHp = 0.3, healPerStrum = 30, mpRatio = 0.8, sinceRestOff = 1.5 }), "vibes/hurt", "urgent: no wait")
	T.eq(
		pick({ enemies = 1, fighting = true, hurtHp = 0.45, healPerStrum = 30, mpRatio = 0.8, sinceRestOff = 1.5 }),
		"vibes/hurt",
		"in a fight: no wait"
	)
	T.eq(
		pick({ enemies = 2, fighting = true, mpRatio = 0.8, sinceRestOff = 0.5 }),
		"fight/fight",
		"fight song: no wait"
	)
	T.eq(R.TOP_UP_REST < 5, true, "under the 5s stack_duration: the stacks still linger")
end)

T.test("largo: a save lick only on a bot ally, with no enemy near Largo, pulled away from the enemy", function()
	local R = load()
	-- Game 081 35:07: the human Vengeful Spirit licked toward the enemy while running away.
	T.eq(select(2, R.SaveLickOk(true, 0, 500, 800)), "human", "never on a human")
	T.eq(select(2, R.SaveLickOk(false, 1, 500, 800)), "enemy-near-me", "an enemy hero near Largo")
	T.eq(select(2, R.SaveLickOk(false, 0, 500, 400)), "not-safer", "the pull takes it closer to the enemy")
	T.eq(select(2, R.SaveLickOk(false, 0, 500, 500)), "not-safer", "no gain")
	T.ok(R.SaveLickOk(false, 0, 500, 850), "a bot ally pulled 350 away from the enemy")
end)

T.test("largo: a toggle order that has not taken is not sent again before the cooldown", function()
	local R = load()
	-- The toggle's cooldown is 1.5s (datafeed hero_id=155).
	T.ok(R.ToggleOrderReady(10, -99, -99), "no order yet")
	T.ok(not R.ToggleOrderReady(10.3, 10, 10.05), "the order took 0.05s later: not within 0.5s")
	T.ok(R.ToggleOrderReady(10.6, 10, 10.05), "the order took: the next one after 0.5s")
	T.ok(not R.ToggleOrderReady(11, 10, 5), "not taken yet (game 073 t=2142-2143): no second order 1s later")
	T.ok(R.ToggleOrderReady(11.5, 10, 5), "not taken after 1.5s: send again")
end)

T.test("largo: the song ends only after a few seconds with no reason, or with no mana", function()
	local R = load()
	T.eq(R.ToggleOffReason(10, 9, true, 3), nil, "a reason a second ago")
	T.eq(R.ToggleOffReason(12.9, 10, true, 3), nil, "2.9s: keep singing")
	T.eq(R.ToggleOffReason(13, 10, true, 3), "idle", "3s with no reason")
	T.eq(R.ToggleOffReason(10, 10, false, 3), "mana", "no mana for one song")
	T.eq(R.ToggleOffReason(10, 10, true, 3, 2), nil, "two beats with no song out: keep trying")
	T.eq(R.ToggleOffReason(10, 10, true, 3, 3), "no-cast", "three beats with no song out: stop, he is disarmed")
	T.eq(R.ToggleOffReason(10, 10, true, 3, 0, 1.2), nil, "1.2s free with no order: the next beat comes")
	T.eq(R.ToggleOffReason(10, 10, true, 3, 0, 1.6), "silent", "1.6s free with no order: no silent song")
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
	-- Duration 15/20/25/30 against cooldown 25 (datafeed 155): from level 3 it covers the whole cooldown.
	T.eq(pick({ level = 1 }), "nil/nil", "level 1, nothing to sing: keep it")
	T.eq(pick({ level = 1, selfWants = true }), "self/self-mana", "level 1 before a song")
	T.eq(pick({ level = 2, selfWants = true, alone = true }), "self/self-mana", "level 2 alone before a song")
	T.eq(pick({ level = 2 }), "nil/nil", "level 2 (20s of 25): only for a song or a combo")
	T.eq(pick({ level = 3 }), "self/self-upkeep", "level 3 (25s of 25): keep it up on himself")
	T.eq(pick({ level = 4 }), "self/self-upkeep", "level 4 (30s of 25)")
	T.eq(pick({ level = 4, selfHasBuff = true }), "nil/nil", "already on him")
	T.eq(pick({ level = 3, allyFighting = true, spellAlly = true }), "ally/ally-nuker", "a nuker going in")
	T.eq(pick({ level = 3, allyFighting = true }), "self/self-upkeep", "a physical core going in: himself")
	T.eq(pick({ level = 1, allyFighting = true, selfWants = true }), "self/self-mana", "physical core, level 1")
	T.eq(pick({ level = 2, hasShard = true, allyFighting = true }), "ally/shard-share", "Shard: Largo gets it too")
	T.eq(
		pick({ level = 3, hasShard = true, alone = true, mpRatio = 0.8 }),
		"self/shard-upkeep",
		"Shard, alone: himself"
	)
	-- Level 3+ with the Shard: always, no fight needed (maintainer 2026-11-22).
	T.eq(
		pick({ level = 3, hasShard = true, magicAllyNear = true, mpRatio = 0.3 }),
		"ally/shard-upkeep",
		"a magic ally near"
	)
	T.eq(pick({ level = 4, hasShard = true, mpRatio = 0.6 }), "self/shard-upkeep", "no magic ally, 60% mana: himself")
	T.eq(pick({ level = 4, hasShard = true, mpRatio = 0.5 }), "nil/nil", "no magic ally, 50% mana: wait")
	T.eq(pick({ level = 4, hasShard = true, mpRatio = 0.5, selfWants = true }), "self/self-mana", "low mana, a song")
	T.eq(pick({ level = 4, hasShard = true, mpRatio = 0.5, allyFighting = true }), "ally/shard-share", "a fight")
	T.eq(pick({ level = 3, hasShard = true, mpRatio = 0.9, selfHasBuff = true }), "nil/nil", "already on him")
	T.eq(pick({ level = 2, hasShard = true, magicAllyNear = true }), "nil/nil", "level 2: no upkeep yet")
end)

T.test("largo: a spell-damage ally, not a physical core", function()
	local R = load()
	T.ok(R.IsSpellDamageAlly(900, 300, 3), "a nuker (Lina): magic above physical")
	T.ok(R.IsSpellDamageAlly(600, 1000, 2), "a spell kit with 60% of the physical damage")
	T.ok(not R.IsSpellDamageAlly(0, 1200, 0), "Phantom Assassin: no magic")
	T.ok(not R.IsSpellDamageAlly(300, 1500, 1), "Sven: one Storm Hammer against his attacks")
	T.ok(not R.IsSpellDamageAlly(400, 1000, 1), "one spell, attacks first")
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
	T.ok(R.BreakSongFor("rooted", 5, 1, 0, false), "no song worth playing: any play (game 071 23:10)")
	T.ok(R.BreakSongFor("fight-target", 5, 1, 0, false), "no song worth playing: a one-hero stomp too")
	T.ok(not R.BreakSongFor("fight-target", 5, 1, 0, true), "a song worth playing: not for a one-hero stomp")
	T.ok(not R.BreakSongFor(nil, 0, 0, 0, false), "no play at all")
end)

-- The level-up list from the hero file with the real ability slots (tests/data/hero_abilities.lua).
T.test("largo: talents at 20 and 25 are two Lick charges and twice the stomps", function()
	local data = assert(loadstring(T.read("tests/data/hero_abilities.lua"), "hero_abilities"))()
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
	local ok, hero = Stub.load("bots/heroes/hero_largo")
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
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local missing = {}
	for _, path in ipairs(T.files("^bots/heroes/hero_[%w_]+%.lua$")) do
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
