-- bots/lib/systems/tempo_rules.lua (#12: the lane-front push gate, the early-game anti-dive by tower tier, the Roshan
-- respawn window) and smoke runs of bots/lib/systems/roshan_window.lua and the Roshan kill-time latch on the stub API.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_leshrac" })
	return require(GetScriptDirectory() .. "/lib/systems/tempo_rules")
end

T.test("tempo: the lane-front gate blocks only when the enemies outnumber us there (game 084 43:52)", function()
	local R = rules()
	local function gate(enemies, allies, us, them)
		return { R.LaneFrontBlocks(enemies, allies, us, them) }
	end
	-- Game 084, 43:52-43:59: Leshrac, Weaver and Ringmaster pushing mid with 2 Dire heroes at the wave.
	local g = gate(2, 3, 5, 5)
	T.eq(g[1], false, "2 enemies vs 3 of ours: keep pushing")
	T.eq(g[2], "outnumber", "logged as push-keep")
	g = gate(2, 2, 5, 5)
	T.eq(g[1], false, "2 v 2: keep pushing (equal numbers)")
	g = gate(3, 2, 5, 5)
	T.eq(g[1], true, "3 enemies vs 2: blocked")
	T.eq(g[2], "outnumbered", "reason")
	g = gate(2, 1, 5, 5)
	T.eq(g[1], true, "2 enemies vs a lone pusher: blocked (the old rule's case)")
	g = gate(2, 4, 4, 5)
	T.eq(g[1], true, "fewer of us alive: blocked whatever the front")
	T.eq(g[2], "fewer-alive", "reason")
	g = gate(1, 0, 5, 5)
	T.eq(g[1], false, "one enemy hero: never blocks")
	T.eq(g[2], nil, "no line")
end)

T.test(
	"tempo: early-game dive - the killable / low-target exceptions hold for a tier-1 tower only (game 084)",
	function()
		local R = rules()
		T.eq(R.TowerTier("npc_dota_badguys_tower2_top"), 2, "tier from the name")
		T.eq(R.TowerTier("npc_dota_goodguys_tower1_bot"), 1, "tier 1")
		T.eq(R.TowerTier("npc_dota_badguys_tower4"), 4, "T4")
		T.eq(R.TowerTier("npc_dota_badguys_fort"), nil, "not a tower")
		T.eq(R.TowerTier(nil), nil, "no name")
		-- Game 084, 1:21-1:34: Underlord after the 5% Spirit Bear under Dire's top T2 (killable and low).
		local allowed, why = R.EarlyDiveAllowed(2, true, true)
		T.eq(allowed, false, "T2: no dive even on a killable 5% target")
		T.eq(why, "tower-tier2", "reason")
		allowed, why = R.EarlyDiveAllowed(3, true, false)
		T.eq(allowed, false, "T3 too")
		T.eq(why, "tower-tier2", "reason")
		allowed, why = R.EarlyDiveAllowed(1, true, false)
		T.eq(allowed, true, "T1: a killable target may be chased in")
		T.eq(why, "killable", "reason")
		allowed, why = R.EarlyDiveAllowed(1, false, true)
		T.eq(allowed, true, "T1: a low target with the tower busy")
		T.eq(why, "low-target", "reason")
		allowed, why = R.EarlyDiveAllowed(1, false, false)
		T.eq(allowed, false, "T1: neither: the old anti-dive")
		T.eq(why, "tower", "reason")
		T.eq((R.EarlyDiveAllowed(nil, true, false)), true, "unknown tier: the old rule")
	end
)

T.test("tempo: Roshan respawn phases and the peek interval", function()
	local R = rules()
	T.eq(R.RoshanPhase(nil, false), "never", "no kill yet")
	T.eq(R.RoshanPhase(7 * 60, false), "dead", "under 8 minutes")
	T.eq(R.RoshanPhase(8 * 60, false), "window", "8 minutes: may be up")
	T.eq(R.RoshanPhase(10 * 60 + 59, false), "window", "still in the window")
	T.eq(R.RoshanPhase(11 * 60, false), "up", "11 minutes: surely up")
	T.eq(R.RoshanPhase(4 * 60, true), "window", "turbo: half")
	local function due(over)
		local p =
			{ phase = "window", seen = false, pitVisible = false, tripActive = false, lastTripEnd = nil, now = 100 }
		for k, v in pairs(over or {}) do
			p[k] = v
		end
		return { R.PeekDue(p) }
	end
	T.eq(due()[1], true, "in the window, unseen, no trip yet: go")
	T.eq(due({ phase = "dead" })[2], "phase-dead", "too early")
	T.eq(due({ phase = "up" })[2], "phase-up", "past 11 minutes: counted up anyway")
	T.eq(due({ seen = true })[2], "seen", "already seen")
	T.eq(due({ pitVisible = true })[2], "pit-visible", "a ward or a hero already sees the pit")
	T.eq(due({ tripActive = true })[2], "trip-active", "a trip is running")
	T.eq(due({ lastTripEnd = 50 })[2], "interval", "50s after the last trip")
	T.eq(due({ lastTripEnd = 40 })[1], true, "60s after the last trip: again")
end)

T.test("tempo: the peeker is the nearest healthy support, else the nearest healthy bot", function()
	local R = rules()
	local pick = R.PickPeeker({
		{ id = 1, support = false, dist = 1000, ok = true },
		{ id = 2, support = true, dist = 5000, ok = true },
		{ id = 3, support = true, dist = 3000, ok = false },
		{ id = 4, support = true, dist = 4000, ok = true },
	})
	T.eq(pick.id, 4, "the nearest support that is free")
	pick = R.PickPeeker({
		{ id = 1, support = false, dist = 6000, ok = true },
		{ id = 2, support = true, dist = 1000, ok = false },
		{ id = 3, support = false, dist = 2000, ok = true },
	})
	T.eq(pick.id, 3, "no free support: the nearest free bot")
	T.eq(R.PickPeeker({ { id = 1, support = true, dist = 10, ok = false } }), nil, "nobody free")
end)

T.test("tempo: the Roshan window call - late, all alive, nothing to defend, no lead push", function()
	local R = rules()
	local function call(over)
		local c = {
			roshAlive = true,
			now = 44 * 60,
			aliveUs = 5,
			aliveThem = 5,
			teamSize = 5,
			defendDesire = 0.1,
			defendPing = false,
			baseThreat = false,
			leadPush = false,
			active = false,
		}
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return { R.RoshanCallOk(c) }
	end
	T.eq(call()[1], true, "game 084 at 44:00 with Roshan up: call")
	T.eq(call({ roshAlive = false })[2], "rosh-dead", "Roshan not known up")
	T.eq(call({ now = 25 * 60 })[2], "early", "before 30:00")
	T.eq(call({ aliveUs = 4 })[2], "alive", "one of ours dead: no new call")
	T.eq(call({ aliveUs = 4, aliveThem = 4, active = true })[1], true, "a running call survives one death (4 v 4)")
	T.eq(call({ aliveUs = 4, aliveThem = 5, active = true })[1], false, "but not fewer than them")
	T.eq(call({ aliveUs = 3, aliveThem = 2, active = true })[2], "alive", "under 4 alive: off")
	T.eq(call({ defendDesire = 0.5 })[2], "defend", "a lane to defend")
	T.eq(call({ defendPing = true })[2], "defend", "a defend ping")
	T.eq(call({ baseThreat = true })[2], "base", "enemies at our base")
	T.eq(call({ leadPush = true })[2], "lead-push", "a team that leads pushes instead")
end)

T.test("roshan window: the team tick runs on the stub API; the kill time is latched on the DotaTime clock", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_leshrac" })
	T.stub.time = 2097
	-- Game 084: GetRoshanKillTime read ~195s ahead of DotaTime().
	_G.GetRoshanKillTime = function()
		return 2292
	end
	local Fu = require(GetScriptDirectory() .. "/lib/func_utils")
	T.eq(Fu.GetRoshanKillTime(), 2097, "the kill is the DotaTime of the first read")
	T.stub.time = 2097 + 300
	T.eq(Fu.GetRoshanKillTime(), 2097, "unchanged raw value: same kill time")
	T.eq(Fu.IsRoshanAlive(), false, "5 minutes after the kill: dead")
	T.stub.time = 2097 + 661
	T.eq(Fu.IsRoshanAlive(), true, "11 minutes after the kill (not 11 minutes after the raw value)")
	local W = require(GetScriptDirectory() .. "/lib/systems/roshan_window")
	T.stub.time = 2097 + 8 * 60 + 5
	local okTick, err = pcall(W._Tick)
	T.ok(okTick, "tick: " .. tostring(err))
	local state = W.State()
	T.eq(state.phase, "window", "8:05 after the kill: the respawn window")
	T.eq(W.Desire(bot, 0), W.Desire(bot, 0), "desire stable within the tick")
	T.eq(type(W.EvenTakeOk(5, 5)), "boolean", "even-take answer")
	T.eq(W.Think(bot) == true or W.Think(bot) == false, true, "think runs")
end)

T.test("roshan window: an armed call raises a timer desire to the call strength and lifts the even refusal", function()
	local bot = T.stub.reset({ hero = "npc_dota_hero_leshrac" })
	T.stub.time = 44 * 60
	local W = require(GetScriptDirectory() .. "/lib/systems/roshan_window")
	local state = W.State()
	state.armed, state.lastTick = true, T.stub.time
	bot._roshWhy = "timer"
	T.eq(W.Desire(bot, 0.3), W.CALL_DESIRE, "timer at 0.30: raised to the call")
	T.eq(bot._roshWhy, "rosh-window", "reason for the strength push's Roshan first")
	T.eq(W.EvenTakeOk(5, 5), true, "5 v 5 may take Roshan while armed")
	T.eq(W.EvenTakeOk(4, 5), false, "not with fewer of ours")
	bot._roshWhy = "even(5v5)"
	T.eq(W.Desire(bot, 0), 0, "a refusal stays a refusal")
	bot._roshWhy = "human-invite"
	T.eq(W.Desire(bot, 0.2), 0.2, "a human team's invite is not raised")
	bot._roshWhy = "timer"
	bot._retreatFinalDesire = { d = 0.7, t = T.stub.time }
	T.near(W.Desire(bot, 0.3), 0.68, 0.001, "kept under the bot's retreat")
	bot._retreatFinalDesire = nil
	state.armed = false
	T.eq(W.Desire(bot, 0.3), 0.3, "not armed: unchanged")
end)
