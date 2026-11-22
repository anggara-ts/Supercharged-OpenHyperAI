-- bots/lib/systems/strength_rules.lua (the strength push decision, lane pick and window end) and a smoke run of
-- bots/lib/systems/strength_push.lua on the stub API (#12).
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	return require(GetScriptDirectory() .. "/lib/systems/strength_rules")
end

-- Game 074, ~45:00 (t=2702-2746 [OHA-CS] lines, bots only): Radiant alchemist 15577 (lvl 18), puck 13446 (18),
-- spirit_breaker 11801 (16), largo 9567 (16) + the human Leshrac (no CS line; ~12000 and level 17 assumed here);
-- Dire undying 15478 (20), wisp 14006 (19), phantom_assassin 18187 (22), winter_wyvern 11583 (18), dark_willow
-- 9891 (19). Radiant was behind: the strength push must hold back there.
local RADIANT_NW = 15577 + 13446 + 11801 + 9567 + 12000
local DIRE_NW = 15478 + 14006 + 18187 + 11583 + 9891
local RADIANT_LVL = (18 + 18 + 16 + 16 + 17) / 5
local DIRE_LVL = (20 + 19 + 22 + 18 + 19) / 5

-- NONE leaves a field unset (a nil in the override table would be skipped by pairs).
local NONE = {}
local function inputs(over)
	local i = {
		laning = false,
		baseThreat = false,
		defendPing = false,
		defendDesire = 0.1,
		aliveUs = 5,
		aliveThem = 5,
		ourNw = RADIANT_NW,
		theirNw = DIRE_NW,
		ourLvl = RADIANT_LVL,
		theirLvl = DIRE_LVL,
		aegis = false,
		ultsReady = 2,
		ultsTotal = 3,
	}
	for k, v in pairs(over or {}) do
		if v == NONE then
			i[k] = nil
		else
			i[k] = v
		end
	end
	return i
end

T.test("strength: game 074 Radiant (behind 2.6 levels and 10% net worth) does not push", function()
	local R = rules()
	local ok, why = R.Decide(inputs())
	T.eq(ok, false, "no strength push")
	T.eq(why, "behind-lvl", "held back by the level deficit")
	-- The enemy net worth is a lower bound (items seen): an under-read that looks like a big lead must not open it.
	ok, why = R.Decide(inputs({ theirNw = 30000 }))
	T.eq(ok, false, "under-read enemy net worth: still no push")
	T.eq(why, "behind-lvl", "levels gate the net worth read")
	ok, why = R.Decide(inputs({ theirNw = NONE }))
	T.eq(ok, false, "net worth unknown: no push")
	T.eq(why, "behind-lvl", "levels only")
end)

T.test("strength: game 074 Dire (2.6 levels and 11% net worth ahead) pushes, by levels", function()
	local R = rules()
	local ok, lead, nwPct, lvlLead = R.Decide(inputs({
		ourNw = DIRE_NW,
		theirNw = RADIANT_NW,
		ourLvl = DIRE_LVL,
		theirLvl = RADIANT_LVL,
	}))
	T.eq(ok, true, "strength push")
	T.eq(lead, "lvl", "the level lead opens it (11% net worth is under 20%)")
	T.near(nwPct, 0.108, 0.01, "net worth lead")
	T.near(lvlLead, 2.6, 0.01, "level lead")
	local okUlts, why = R.Decide(inputs({
		ourNw = DIRE_NW,
		theirNw = RADIANT_NW,
		ourLvl = DIRE_LVL,
		theirLvl = RADIANT_LVL,
		ultsReady = 1,
		ultsTotal = 3,
	}))
	T.eq(okUlts, false, "1 of 3 core ultimates ready: no push")
	T.eq(why, "ults", "skip reason")
end)

T.test("strength: net worth route needs 20% and a level", function()
	local R = rules()
	local ok, lead = R.Decide(inputs({ ourNw = 80000, theirNw = 65000, ourLvl = 19, theirLvl = 18 }))
	T.eq(ok, true, "23% and +1 level: push")
	T.eq(lead, "nw", "net worth route")
	local ok2, why2 = R.Decide(inputs({ ourNw = 80000, theirNw = 65000, ourLvl = 18.2, theirLvl = 18 }))
	T.eq(ok2, false, "23% but +0.2 level: no push")
	T.eq(why2, "no-lead", "skip reason")
	local ok3, why3 = R.Decide(inputs({ ourNw = 70000, theirNw = 65000, ourLvl = 19, theirLvl = 18 }))
	T.eq(ok3, false, "8% and +1 level: no push")
	T.eq(why3, "no-lead", "skip reason")
	local ok4, why4 = R.Decide(inputs({ ourNw = 60000, theirNw = 70000, ourLvl = 21, theirLvl = 18 }))
	T.eq(ok4, false, "+3 levels but 14% behind in net worth: no push")
	T.eq(why4, "behind-nw", "skip reason")
	local ok5, why5 = R.Decide(inputs({ ourNw = 60000, theirNw = NONE, ourLvl = 19.5, theirLvl = 18 }))
	T.eq(ok5, false, "net worth unknown and +1.5 levels: no push")
	T.eq(why5, "no-lead-nw-unknown", "skip reason")
end)

T.test("strength: base, defend, laning and alive counts hold it back", function()
	local R = rules()
	local ahead = { ourNw = 80000, theirNw = 60000, ourLvl = 20, theirLvl = 17 }
	local function why(over)
		local i = inputs(ahead)
		for k, v in pairs(over) do
			i[k] = v
		end
		local _, reason = R.Decide(i)
		return reason
	end
	T.eq(why({ laning = true }), "laning", "laning phase")
	T.eq(why({ baseThreat = true }), "base", "enemies at our base")
	T.eq(why({ defendPing = true }), "defend-ping", "a defend ping")
	T.eq(why({ defendDesire = 0.45 }), "defend", "a lane needs defending")
	T.eq(why({ aliveUs = 4, aliveThem = 5 }), "alive", "fewer alive than them")
	T.eq(why({ aliveUs = 3, aliveThem = 2 }), "alive", "under 4 alive")
	local ok = R.Decide(inputs(ahead))
	T.eq(ok, true, "ahead with nothing to defend: push")
end)

T.test("strength: the scale knob and the Aegis move the thresholds", function()
	local R = rules()
	local i = inputs({ ourNw = 80000, theirNw = 65000, ourLvl = 19, theirLvl = 18 }) -- 23% and +1
	T.eq((R.Decide(i)), true, "scale 1: 23% and +1 is enough")
	T.eq(R.SetScale(1.5), 1.5, "scale set")
	T.eq((R.Decide(i)), false, "scale 1.5: 23% is under 30%")
	T.eq(R.SetScale(9), 2, "scale clamped to 2")
	T.eq(R.SetScale(0.1), 0.5, "scale clamped to 0.5")
	R.SetScale(1)
	local lvlOnly = inputs({ ourNw = NONE, theirNw = NONE, ourLvl = 19.6, theirLvl = 18 })
	T.eq((R.Decide(lvlOnly)), false, "+1.6 levels: no push")
	lvlOnly.aegis = true
	T.eq((R.Decide(lvlOnly)), true, "+1.6 levels with the Aegis (threshold 1.5): push")
end)

T.test("strength: TeamTotal counts an unread or stale hero as unknown, not 0", function()
	local R = rules()
	local ids = { 15, 16 }
	T.eq(R.TeamTotal(ids, { [15] = { value = 100, at = 0 }, [16] = { value = 50, at = 0 } }, 10, 120), 150, "sum")
	T.eq(R.TeamTotal(ids, { [15] = { value = 100, at = 0 } }, 10, 120), nil, "one unread hero")
	T.eq(R.TeamTotal(ids, { [15] = { value = 100, at = 0 }, [16] = { value = 0, at = 0 } }, 10, 120), nil, "zero")
	T.eq(R.TeamTotal(ids, { [15] = { value = 100, at = 0 }, [16] = { value = 50, at = 0 } }, 200, 120), nil, "stale")
	T.eq(R.TeamTotal(ids, { [15] = { value = 100, at = 0 }, [16] = { value = 50, at = 0 } }, 200, nil), 150, "no age")
end)

T.test("strength: lane pick - open high ground first, else the weakest outer building", function()
	local R = rules()
	-- Game 074: Dire's mid T3 and ranged barracks down (mid target = melee barracks), top T1 at 30%.
	local pick = R.PickLane({
		{ lane = 1, tier = 1, hp = 0.3, allyDist = 3000 },
		{ lane = 2, tier = 4, hp = 1.0, allyDist = 6000 },
		{ lane = 3, tier = 2, hp = 1.0, allyDist = 4000 },
	})
	T.eq(pick.lane, 2, "the open mid high ground")
	pick = R.PickLane({
		{ lane = 1, tier = 1, hp = 0.5, allyDist = 5000 },
		{ lane = 2, tier = 2, hp = 1.0, allyDist = 3000 },
		{ lane = 3, tier = 2, hp = 0.9, allyDist = 9000 },
	})
	T.eq(pick.lane, 1, "the half-dead T1 over a full T2 nearer")
	pick = R.PickLane({
		{ lane = 1, tier = 2, hp = 1.0, allyDist = 8000 },
		{ lane = 3, tier = 2, hp = 1.0, allyDist = 2000 },
	})
	T.eq(pick.lane, 3, "same building: the lane our cores are near")
	T.eq(R.PickLane({}), nil, "no lanes")
end)

T.test("strength: a window ends on the building, the timeout, deaths, outnumbered or the lost lead", function()
	local R = rules()
	local arrived = { startedAt = 100, aliveAtStart = 5, arrivedAt = 100 }
	local ahead = {
		ourNw = 80000,
		theirNw = 60000,
		ourLvl = 20,
		theirLvl = 18.8,
		factor = R.DEFAULTS.endFactor,
		targetAlive = true,
		enemiesAtFront = 1,
		alliesAtFront = 4,
	}
	local function endWhy(now, over, state)
		local i = inputs(ahead)
		for k, v in pairs(over or {}) do
			if v == NONE then
				i[k] = nil
			else
				i[k] = v
			end
		end
		return R.EndWhy(state or arrived, now, i)
	end
	T.eq(endWhy(120), nil, "+1.2 levels / 33% at the end threshold: keeps going")
	T.eq(endWhy(120, { ultsReady = 0 }), nil, "ultimates cast in the fight: keeps going")
	T.eq(endWhy(120, { theirNw = NONE }), nil, "an enemy net worth read gone stale: keeps going")
	T.eq(endWhy(120, { targetAlive = false }), "building-down", "the building fell")
	T.eq(endWhy(140), "timeout", "40s after the arrival")
	T.eq(endWhy(150, { targetDropping = true }), nil, "the target still losing HP: extended")
	T.eq(endWhy(160, { targetDropping = true }), "timeout", "the extension is 20s at most")
	local walking = { startedAt = 100, aliveAtStart = 5 }
	T.eq(endWhy(140, nil, walking), nil, "still walking at 40s: the hold clock has not started")
	T.eq(endWhy(145, nil, walking), "no-gather", "nobody at the lane front 45s after the start")
	T.eq(endWhy(120, { aliveUs = 3, aliveThem = 3 }), "deaths", "two of ours died")
	T.eq(endWhy(120, { aliveUs = 4, aliveThem = 5 }), "deaths", "fewer alive than them")
	T.eq(endWhy(120, { enemiesAtFront = 3, alliesAtFront = 2 }), "outnumbered", "3 enemies at the front vs 2")
	T.eq(endWhy(120, { defendDesire = 0.5 }), "defend", "a lane needs defending")
	T.eq(endWhy(120, { ourLvl = 19, theirNw = 75000 }), "no-lead", "+0.2 levels and 7%: lead lost")
	T.eq(R.Cooldown("building-down"), 5, "chain to the next building")
	T.eq(R.Cooldown("timeout"), 20, "cooldown")
end)

T.test("strength push: the team tick runs on the stub API and raises only the window's lane", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	T.stub.time = 1800
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	local S = require(GetScriptDirectory() .. "/lib/systems/strength_push")
	local okTick, err = pcall(S._Tick, bot)
	T.ok(okTick, "tick: " .. tostring(err))
	T.eq(S.LaneDesire(bot, 2, 0.2), 0.2, "no window: the push desire as it was")
	local state = S.State()
	state.active, state.lane, state.startedAt, state.lastTick = true, 2, 1800, 1800
	state.targetName = "badguys_melee_rax_mid"
	bot._level = 20
	Fu.IsCore = function()
		return true
	end
	T.eq(S.LaneDesire(bot, 1, 0.2), 0.2, "another lane: unchanged")
	T.eq(S.LaneDesire(bot, 2, 0.2), S.FLOOR, "the window's lane: raised")
	T.eq(S.LaneDesire(bot, 2, 0.95), 0.95, "a higher push desire (kill window) stays")
	T.eq(S.FarmCap(bot, 0.85), S.FARM_CAP, "farm capped for a bot in the window")
	T.eq(S.FarmCap(bot, 0.5), 0.5, "a low farm desire unchanged")
	bot._retreatFinalDesire = { d = 0.6, t = 1800 }
	T.near(S.LaneDesire(bot, 2, 0.2), 0.58, 0.001, "kept under the bot's retreat desire")
	bot._retreatFinalDesire = nil
	bot._hp = bot._maxHp * 0.3
	T.eq(S.LaneDesire(bot, 2, 0.2), 0.2, "under 45% HP: not raised")
	T.stub.time = 1802
	T.eq(S.FarmCap(bot, 0.85), 0.85, "mark stale after 1s: farm as it was")
end)
