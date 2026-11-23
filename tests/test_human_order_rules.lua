-- bots/lib/systems/human_order_rules.lua (#222): what a human's ping or chat command means, request checks,
-- insist, responder pick.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	return require(GetScriptDirectory() .. "/lib/systems/human_order_rules")
end

T.test("human orders: chat commands parse, other commands do not", function()
	local R = rules()
	T.eq(R.ParseChat("!push top").kind, "push", "!push top")
	T.eq(R.ParseChat("!push top").lane, "top", "!push top lane")
	T.eq(R.ParseChat("  !PUSH Mid ").lane, "mid", "case and spaces")
	T.eq(R.ParseChat("!push b").lane, "bot", "short lane")
	T.eq(R.ParseChat("!push").kind, "push", "!push without a lane")
	T.eq(R.ParseChat("!push").lane, nil, "no lane: the bots ask which")
	T.eq(R.ParseChat("!push river").lane, nil, "unknown lane")
	T.eq(R.ParseChat("!def bot").kind, "defend", "!def")
	T.eq(R.ParseChat("!defend top").lane, "top", "!defend")
	T.eq(R.ParseChat("!rosh").kind, "rosh", "!rosh")
	T.eq(R.ParseChat("!group").kind, "group", "!group")
	T.eq(R.ParseChat("!no").kind, "no", "!no")
	T.eq(R.ParseChat("!rosh now"), nil, "extra words on !rosh")
	-- Maintainer 2026-11-23: a chat command is FORCE NEAR, "all" makes it FORCE ALL.
	T.eq(R.ParseChat("!push bot").all, false, "!push bot: force near")
	T.eq(R.ParseChat("!push bot all").all, true, "!push bot all: force all")
	T.eq(R.ParseChat("!push bot all").lane, "bot", "!push bot all keeps its lane")
	T.eq(R.ParseChat("!push all top").lane, "top", "all first")
	T.eq(R.ParseChat("!def mid all").kind, "defend", "!def mid all")
	T.eq(R.ParseChat("!rosh all").all, true, "!rosh all")
	T.eq(R.ParseChat("!group all").kind, "group", "!group all")
	T.eq(R.ParseChat("!push all").lane, nil, "!push all without a lane: which lane")
	T.eq(R.ParseChat("!push top mid").lane, nil, "two lanes: which lane")
	T.eq(R.ParseChat("!no all"), nil, "!no takes no words")
	-- The other commands stay theirs (#210 !pos, #215 !about, the draft's !pick / !ban, !sp, !debug).
	for _, text in ipairs({
		"!pos",
		"!pos 2",
		"!3pos 5",
		"!about",
		"!pick axe",
		"!ban axe",
		"!sp en",
		"!speak ru",
		"!debug",
		"!verbose",
		"push top",
		"gg",
	}) do
		T.eq(R.ParseChat(text), nil, text)
	end
	T.eq(R.ParseChat(nil), nil, "nil text")
end)

T.test("human orders: the same ping again within 2s is an insist", function()
	local R = rules()
	local first = { time = 100, x = 4825, y = -3676 }
	T.eq(R.IsInsist(nil, first), false, "no previous ping")
	T.eq(R.IsInsist(first, first), false, "the same ping read twice")
	T.eq(R.IsInsist(first, { time = 101.5, x = 4900, y = -3700 }), true, "79 away, 1.5s later")
	T.eq(R.IsInsist(first, { time = 103, x = 4900, y = -3700 }), false, "3s later: too slow for an insist")
	T.eq(R.IsInsist(first, { time = 106, x = 4825, y = -3676 }), false, "6s later")
	T.eq(R.IsInsist(first, { time = 101, x = 5300, y = -3676 }), false, "475 away")
	local onHero = { time = 100, x = 0, y = 0, targetKey = "hero15" }
	T.eq(R.IsInsist(onHero, { time = 101.8, x = 900, y = 0, targetKey = "hero15" }), true, "same hero, moved")
end)

-- Maintainer 2026-11-23: "1 ping = ask / 2 ping = force ally nearby ping / 3+ ping = force all ally accross map".
T.test("human orders: ping tiers by count, each ping within 2s of the one before", function()
	local R = rules()
	local function chain(times, xs, key)
		local prev, count = nil, 0
		for i, time in ipairs(times) do
			local ping = { time = time, x = xs and xs[i] or 0, y = 0, targetKey = key }
			count = R.PingCount(prev, ping)
			ping.count = count
			prev = ping
		end
		return count, R.Tier(count)
	end
	T.eq(select(2, chain({ 100 })), "ask", "1 ping: ask")
	T.eq(select(2, chain({ 100, 101.5 })), "force-near", "2 pings 1.5s apart: force near")
	T.eq(select(2, chain({ 100, 101.5, 103 })), "force-all", "3 pings 1.5s apart: force all")
	T.eq(chain({ 100, 101.5, 103, 104.5 }), 4, "4 pings: count 4")
	T.eq(select(2, chain({ 100, 101.5, 103, 104.5 })), "force-all", "4 pings: still force all")
	T.eq(select(2, chain({ 100, 102.5 })), "ask", "2 pings 2.5s apart: two asks")
	T.eq(select(2, chain({ 100, 101.5, 104 })), "ask", "the third 2.5s late starts a new chain")
	T.eq(select(2, chain({ 100, 102.5, 104 })), "force-near", "a late second ping, then 1.5s: force near")
	-- The chain is per gap, not from the first ping: 3 pings 1.5s apart span 3s and still count.
	T.eq(select(2, chain({ 100, 101.5, 103 }, { 0, 100, 200 })), "force-all", "small moves within 300")
	T.eq(select(2, chain({ 100, 101.5 }, { 0, 400 })), "ask", "400 away: another spot")
	-- The same target moved: a hero ping follows the hero.
	T.eq(select(2, chain({ 100, 101.5, 103 }, { 0, 900, 1800 }, "hero15")), "force-all", "same hero, moved")
	T.eq(R.Tier(nil), "ask", "no count: ask")
end)

T.test("human orders: building names give lane and tier", function()
	local R = rules()
	local lane, tier = R.BuildingInfo("npc_dota_badguys_tower2_top")
	T.eq(lane, "top", "T2 top lane")
	T.eq(tier, 2, "T2 tier")
	lane, tier = R.BuildingInfo("npc_dota_goodguys_melee_rax_bot")
	T.eq(lane, "bot", "rax lane")
	T.eq(tier, 3, "rax tier")
	lane, tier = R.BuildingInfo("npc_dota_badguys_tower4")
	T.eq(lane, "mid", "T4: mid")
	T.eq(tier, 4, "T4 tier")
	lane, tier = R.BuildingInfo("npc_dota_goodguys_fort")
	T.eq(tier, 5, "Ancient")
	T.eq(R.BuildingInfo("npc_dota_goodguys_fillers"), nil, "fillers")
	T.eq(R.BuildingInfo("npc_dota_hero_axe"), nil, "not a building")
end)

-- Game 074, 7:12: the human (Leshrac) pinged a neutral camp near Alchemist to send him to farm it
-- ([SHy-PING] 4825 -3676 0 normal=true t=432.3); the camp spot is 4649,-3699 ([SHy-CAMP] survey idx=1 type=large).
T.test("human orders: game 074 camp ping is a farm order, not refused before 5:00 rules", function()
	local R = rules()
	local camps = { { x = -4824, y = 3915 }, { x = 4649, y = -3699 } }
	local index, dist = R.NearestCamp(camps, 4825, -3676)
	T.eq(index, 2, "the large camp")
	T.near(dist, 177.5, 1, "177 from the camp spot")
	T.eq(R.NearestCamp(camps, 0, 0), nil, "no camp near the middle")
	local kind = R.Classify({ normal = true, visible = true, campDist = dist })
	T.eq(kind, "farm", "camp ping")
	local verdict, why = R.Check("farm", "ask", { now = 432, aliveAllies = 5, available = 4, enemiesNear = 0 })
	T.eq(verdict, "go", "farm at 7:12 goes")
	T.eq(why, "agree", "agreed")
	T.eq(R.Need("farm", {}), 1, "one bot farms it")
	-- Alchemist (core, 900 away) gets it over a support 700 away; a fighting bot waits.
	local obey = R.PickResponders("farm", {
		{ id = 10, dist = 700, state = "ok", core = false },
		{ id = 11, dist = 900, state = "ok", core = true },
		{ id = 12, dist = 300, state = "fight", core = true },
	}, 1)
	T.eq(obey[1], 11, "the core goes")
	T.eq(#obey, 1, "only one")
end)

T.test("human orders: what a ping is on", function()
	local R = rules()
	T.eq(R.Classify({ normal = false, visible = true }), "danger", "X-ping in the open: back off")
	T.eq(R.Classify({ normal = false, visible = false }), "danger", "X-ping in the fog: back off")
	T.eq(R.Classify({ normal = false, visible = false, recentEnemySeen = true }), "danger", "X-ping, hero seen: danger")
	T.eq(R.Classify({ normal = false, visible = true, enemyBuildingDist = 300 }), "push", "a ping on their tower")
	T.eq(R.Classify({ normal = false, visible = true, ourBuildingDist = 300 }), "defend", "X-ping on our tower")
	T.eq(R.Classify({ normal = false, visible = true, enemyHero = true }), "gank", "a ping on an enemy hero")
	T.eq(R.Classify({ normal = false, roshan = true }), "rosh", "a ping on Roshan")
	T.eq(R.Classify({ normal = false, visible = true, campDist = 150 }), "farm", "a ping on a camp")
	T.eq(R.Classify({ normal = false, visible = true, waveSide = "theirs" }), "push", "a ping on their wave")
	T.eq(R.Classify({ normal = true, enemyHero = true, enemyHeroInFight = true }), "focus", "hero in a fight")
	T.eq(R.Classify({ normal = true, enemyHero = true }), "gank", "hero alone")
	T.eq(R.Classify({ normal = true, roshan = true, visible = false }), "rosh", "Roshan pit")
	T.eq(R.Classify({ normal = true, visible = true, enemyBuildingDist = 300 }), "push", "enemy tower")
	T.eq(R.Classify({ normal = true, visible = true, ourBuildingDist = 300 }), "defend", "our tower")
	T.eq(R.Classify({ normal = true, visible = true, waveSide = "theirs" }), "push", "wave at their tower")
	T.eq(R.Classify({ normal = true, visible = true, waveSide = "ours" }), "defend", "wave coming to ours")
	T.eq(R.Classify({ normal = true, visible = true, campDist = 200, ourBuildingDist = 600 }), "farm", "camp nearer")
	T.eq(R.Classify({ normal = true, visible = true, campDist = 550, ourBuildingDist = 200 }), "defend", "tower nearer")
	T.eq(R.Classify({ normal = true, visible = false, recentEnemySeen = true }), "chase", "fog, hero seen there")
	T.eq(R.Classify({ normal = true, visible = false }), "fog", "fog, nothing seen")
	T.eq(R.Classify({ normal = true, visible = true }), "move", "an empty visible spot")
end)

-- Game 075: pings clicked on a target come through as non-normal pings, and every one was read as danger and
-- refused (`order kind=danger ... verdict=refuse why=nobody-free`).
T.test("human orders: game 075 pings on a tower and on a hero are read by their target", function()
	local R = rules()
	-- t=111.5 `6279 -2150 0 normal=false`: the Dire bottom T1 is at 6269,-2240 (the !push bot order's at=).
	local dx, dy = 6279 - 6269, -2150 - -2240
	local towerDist = math.sqrt(dx * dx + dy * dy)
	T.near(towerDist, 90.6, 1, "91 from the tower")
	T.ok(towerDist <= R.ENEMY_BUILDING_RADIUS, "within the building radius")
	T.eq(R.Classify({ normal = false, visible = true, enemyBuildingDist = towerDist }), "push", "t=111 tower ping")
	-- t=12.0 `763 904` and t=43.7 `883 950`: the Dire mid T1 is at 832,848 (order id=8 at=).
	T.eq(R.Classify({ normal = false, visible = true, enemyBuildingDist = 89 }), "push", "t=12 mid tower ping")
	T.eq(R.Classify({ normal = false, visible = true, enemyBuildingDist = 114 }), "push", "t=44 mid tower ping")
	-- t=80.4 `6283 -4364 normal=false` on Winter Wyvern, nobody fighting her: a gank, not danger.
	T.eq(R.Classify({ normal = false, visible = true, enemyHero = true }), "gank", "t=80 Winter Wyvern")
	T.eq(R.Classify({ normal = false, enemyHero = true, enemyHeroInFight = true }), "focus", "hero in a fight")
	-- A push ping before 5:00 is still a request the bots refuse with a reason (insist to make them go).
	local verdict, why = R.Check("push", "ask", { now = 111, aliveAllies = 5, available = 3, tier = 1 })
	T.eq(verdict, "refuse", "t=111 push request")
	T.eq(why, "too-early", "too early, ping again to insist")
	T.eq(R.Check("push", "force-near", { now = 111, aliveAllies = 5, available = 3, tier = 1 }), "go", "insist")
end)

T.test("human orders: a danger ping needs no responders", function()
	local R = rules()
	T.eq(R.Check("danger", "ask", { available = 0 }), "go", "nobody near: still a warning")
	T.eq(R.Verdict("go", 0, 0, "danger"), "go", "never refuse why=nobody-free")
	T.eq(R.Verdict("go", 0, 0, "gank"), "refuse", "other kinds still need someone")
	local obey, _, _, decisions = R.PickResponders("danger", {
		{ id = 1, dist = 900, state = "ok" },
		{ id = 2, dist = 1300, state = "ok" },
		{ id = 3, dist = 600, state = "fight" },
	}, R.Need("danger", {}))
	T.eq(#obey, 1, "only the bot within 1200 backs off")
	T.eq(obey[1], 1, "the bot 900 away")
	T.eq(decisions[3].answer, "far", "1300 away: not affected")
	T.eq(R.DANGER_RADIUS, 1200, "maintainer: ~1200")
	T.ok(R.DANGER_SAFE > R.DANGER_RADIUS, "backs off past the radius")
	T.eq(#R.ReplyPlan("danger", "go", "agree", { 1 }, nil, {}), 0, "no chat reply")
	-- Three X-pings stay a danger ping: never forced (no team TP onto the danger spot).
	obey = R.PickResponders("danger", {
		{ id = 1, dist = 900, state = "ok" },
		{ id = 2, dist = 3000, state = "ok" },
	}, R.Need("danger", {}), { tier = "force-all" })
	T.eq(#obey, 1, "force tier ignored for danger")
end)

-- Game 075, t=60: `!push bot` picked Puck (mid, 6689) and Largo (top, 14016) while Alchemist was in the bottom
-- lane, harassed by Undying (`[SHy-RETREAT] t=58 undying anti-dive why=tower target=alchemist`): his "fight" state
-- made him queue behind free bots anywhere on the map, and the T1 needs only 2.
T.test("human orders: game 075 !push bot asks the bottom laners first", function()
	local R = rules()
	local cands = {
		{ id = 9, dist = 900, state = "fight", core = true, lane = "bot" }, -- alchemist
		{ id = 7, dist = 6689, state = "ok", core = true, lane = "mid" }, -- puck
		{ id = 8, dist = 14016, state = "ok", core = false, lane = "top" }, -- largo
		{ id = 6, dist = 13000, state = "fight", core = true, lane = "top" }, -- spirit_breaker
	}
	local need = R.Need("push", { tier = 1, enemiesNear = 0 })
	T.eq(need, 2, "T1: two")
	local obey, queue, _, decisions = R.PickResponders("push", cands, need, { lane = "bot", now = 60 })
	T.eq(obey[1], 9, "Alchemist, in the bottom lane, first")
	T.eq(obey[2], 7, "then the nearest free bot")
	T.eq(#obey, 2, "two")
	T.eq(#queue, 0, "nobody queued")
	T.eq(decisions[1].answer, "obey", "Alchemist obeys while trading in his lane")
	local largo = nil
	for _, d in ipairs(decisions) do
		if d.id == 8 then
			largo = d
		end
	end
	T.eq(largo.answer, "far", "before 10:00 no support from across the map")
	local names = { [9] = "alchemist", [7] = "puck", [8] = "largo", [6] = "spirit_breaker" }
	T.eq(
		R.CandsText(decisions, function(id)
			return names[id]
		end),
		"alchemist:obey/fight:900,puck:obey:6689,spirit_breaker:wait/fight:13000,largo:far:14016",
		"every candidate on the order line"
	)
	T.eq(R.Available(decisions), 3, "far bots do not count as available")
	-- After 10:00 the far support may go; the laner rule gives way to distance (Alchemist is still nearest).
	obey = R.PickResponders("push", cands, 3, { lane = "bot", now = 900 })
	T.eq(obey[3], 8, "15:00: Largo may come")
	-- A bot's own lane only counts in the laning stage: at 15:00 a bottom laner far away is not first.
	obey = R.PickResponders("push", {
		{ id = 1, dist = 9000, state = "ok", core = true, lane = "bot" },
		{ id = 2, dist = 3000, state = "ok", core = true, lane = "mid" },
	}, 1, { lane = "bot", now = 900 })
	T.eq(obey[1], 2, "15:00: the nearest")
	obey = R.PickResponders("push", {
		{ id = 1, dist = 9000, state = "ok", core = true, lane = "bot" },
		{ id = 2, dist = 3000, state = "ok", core = true, lane = "mid" },
	}, 1, { lane = "bot", now = 60 })
	T.eq(obey[1], 1, "1:00: the bottom laner")
	-- A dead bot prints "-" for its distance.
	T.eq(
		R.CandsText({ { id = 1, state = "dead", dist = math.huge, answer = "ignore" } }, function()
			return "zeus"
		end),
		"zeus:ignore/dead:-",
		"dead"
	)
end)

-- Maintainer 2026-11-23: "response 'on my way' only when acknowledging. no reply for 'cant do'".
T.test("human orders: replies - on my way from every bot that goes, a reason only when nobody goes", function()
	local R = rules()
	-- Someone goes: one "On my way!" per bot that goes, no refusal line (the bots that can't go stay quiet).
	local plan = R.ReplyPlan("push", "go", "forced", { 9, 7 }, { id = 3, key = "retreat" }, { now = 500 })
	T.eq(#plan, 2, "two on my way, nothing else")
	T.eq(plan[1].id, 9, "first responder")
	T.eq(plan[1].key, "on-my-way", "on my way")
	T.eq(plan[1].index, 1, "first line")
	T.eq(plan[2].id, 7, "second responder")
	T.eq(plan[2].index, 2, "a different line")
	for _, line in ipairs(plan) do
		T.eq(line.key, "on-my-way", "no refusal line when a bot goes")
	end
	-- The same ping chain again: the bots that already said it stay quiet, a new one speaks.
	plan = R.ReplyPlan("push", "go", "forced", { 9, 7, 5 }, nil, { now = 501, acked = { [9] = true, [7] = true } })
	T.eq(#plan, 1, "only the new bot")
	T.eq(plan[1].id, 5, "the bot that joined with the force")
	T.eq(plan[1].index, 1, "its line")
	-- Everyone joins later (fighting / dead): nothing now, each says "On my way!" when it joins.
	T.eq(#R.ReplyPlan("push", "queue", "forced", {}, nil, { now = 500 }), 0, "queue: no reply")
	-- Nobody goes: one short reason, said after the 2s a repeated ping has to force the order.
	plan = R.ReplyPlan("push", "refuse", "too-early", {}, nil, { now = 200 })
	T.eq(#plan, 1, "a refused request: one reason")
	T.eq(plan[1].key, "too-early", "the reason")
	T.eq(plan[1].id, nil, "said by the bot that read it")
	T.eq(plan[1].delay, R.INSIST_SECONDS, "held for the insist window")
	plan = R.ReplyPlan("gank", "refuse", "nobody-free", {}, { id = 4, key = "dead", seconds = 20 }, { now = 900 })
	T.eq(plan[1].key, "dead", "nobody free: the nearest says why")
	T.eq(plan[1].seconds, 20, "with the respawn time")
	T.eq(plan[1].id, 4, "that bot says it")
	T.eq(R.ReplyPlan("gank", "refuse", "nobody-free", {}, nil, { now = 900 })[1].key, "busy", "nobody at all")
	-- At most one reason per 30s per team.
	T.eq(
		#R.ReplyPlan("push", "refuse", "outnumbered", {}, nil, { now = 920, lastRefusalAt = 900 }),
		0,
		"20s later: quiet"
	)
	T.eq(#R.ReplyPlan("push", "refuse", "outnumbered", {}, nil, { now = 930, lastRefusalAt = 900 }), 1, "30s later")
	T.ok(R.RefusalAllowed(0, nil), "the first one")
	T.ok(R.IsRefusalKey("too-early") and R.IsRefusalKey("busy"), "reasons")
	T.ok(not R.IsRefusalKey("on-my-way") and not R.IsRefusalKey("which_lane"), "not reasons")
	T.eq(R.REPLY_GAP_SECONDS, 0.5, "replies ~0.5s apart")
end)

-- Maintainer 2026-11-23: 2 pings (or a chat command) = every bot within ~4000 or at that lane, whatever the checks
-- say; 3+ pings (or "all") = every bot. Dead, channelling and very low bots queue and join later.
T.test("human orders: force near takes every bot within 4000 or at the lane, force all every bot", function()
	local R = rules()
	local cands = {
		{ id = 1, dist = 1500, state = "ok", hp = 0.9, core = true, lane = "mid" },
		{ id = 2, dist = 3900, state = "retreat", hp = 0.5, core = false, lane = "top" },
		{ id = 3, dist = 4100, state = "ok", hp = 0.9, core = true, lane = "top" },
		{ id = 4, dist = 9000, state = "fight", hp = 0.8, core = true, lane = "bot" },
		{ id = 5, dist = math.huge, state = "dead", hp = 0, core = false, lane = "bot" },
	}
	-- A gank (max 6000, need 2 on a request).
	local obey, queue = R.PickResponders("gank", cands, 2, { now = 900, tier = "ask" })
	T.eq(#obey, 2, "ask: two")
	obey, queue = R.PickResponders("gank", cands, 2, { now = 900, tier = "force-near" })
	T.eq(#obey, 2, "force near: the two within 4000, the retreating one too")
	T.eq(obey[1], 1, "nearest first")
	T.eq(obey[2], 2, "the retreating bot obeys a force")
	T.eq(#queue, 0, "the dead bot is not near anything")
	obey, queue = R.PickResponders("gank", cands, 2, { now = 900, tier = "force-all" })
	T.eq(#obey, 4, "force all: every living bot, fighting or 9000 away")
	T.eq(#queue, 1, "the dead bot queues")
	T.eq(queue[1], 5, "and joins on respawn")
	-- A focus (max 2000 on a request) is widened to 4000 by force near.
	obey = R.PickResponders("focus", cands, 5, { now = 900, tier = "force-near" })
	T.eq(#obey, 2, "focus force near: 4000, not 2000")
	-- Force near on a lane order: a bot standing on that lane goes even when it is farther than 4000.
	local laneCands = {
		{ id = 1, dist = 6000, state = "ok", hp = 0.9, core = true, lane = "mid", onLane = true },
		{ id = 2, dist = 6000, state = "ok", hp = 0.9, core = true, lane = "mid", onLane = false },
		{ id = 3, dist = 7000, state = "ok", hp = 0.9, core = false, lane = "bot" },
	}
	obey = R.PickResponders("push", laneCands, 2, { lane = "bot", now = 900, tier = "force-near" })
	T.eq(#obey, 1, "15:00: only the bot on the bottom lane")
	T.eq(obey[1], 1, "on the lane")
	obey = R.PickResponders("push", laneCands, 2, { lane = "bot", now = 60, tier = "force-near" })
	T.eq(#obey, 2, "1:00: the bottom laner too (its own lane), not the mid bot off the lane")
	-- A camp still takes one bot under a force.
	obey = R.PickResponders("farm", cands, 1, { now = 900, tier = "force-all" })
	T.eq(#obey, 1, "a forced camp: one bot")
	-- The checks don't stop a force.
	local facts = { now = 200, aliveAllies = 2, available = 3, enemiesNear = 5, tier = 2 }
	T.eq(R.Check("push", "ask", facts), "refuse", "a request is refused")
	T.eq(R.Check("push", "force-near", facts), "go", "force near goes")
	T.eq(R.Check("push", "force-all", facts), "go", "force all goes")
	-- A forced order lasts until the farthest bot can be there.
	T.eq(R.OrderSeconds("push", "ask", 50), R.ORDER_SECONDS, "a request: 25s")
	T.eq(R.OrderSeconds("push", "force-all", 30), 45, "ETA 30 + 15")
	T.eq(R.OrderSeconds("push", "force-all", 2), R.ORDER_SECONDS, "at least 25s")
	T.eq(R.OrderSeconds("push", "force-all", 200), R.FORCE_MAX_SECONDS, "at most 60s")
	T.eq(R.OrderSeconds("danger", "force-all", 30), R.DANGER_SECONDS, "danger: 6s")
end)

T.test("human orders: a force skips dead, channelling and very low bots, they join when back", function()
	local R = rules()
	T.eq(R.ForceAnswer({ state = "ok", hp = 0.9 }), "obey", "healthy")
	T.eq(R.ForceAnswer({ state = "low-hp", hp = 0.25 }), "obey", "25%: a force still takes it")
	T.eq(R.ForceAnswer({ state = "fight", hp = 0.6 }), "obey", "fighting: goes")
	T.eq(R.ForceAnswer({ state = "base", hp = 0.9 }), "obey", "holding the base: goes")
	local answer, why = R.ForceAnswer({ state = "low-hp", hp = 0.15 })
	T.eq(answer, "queue", "15%: queued")
	T.eq(why, "low-hp", "why=low-hp")
	answer, why = R.ForceAnswer({ state = "dead", hp = 0 })
	T.eq(why, "dead", "why=dead")
	answer, why = R.ForceAnswer({ state = "ok", hp = 0.9, channeling = true })
	T.eq(answer, "queue", "a TP in progress: queued")
	T.eq(why, "channel", "why=channel")
	local cands = {
		{ id = 1, dist = 800, state = "low-hp", hp = 0.15 },
		{ id = 2, dist = 1200, state = "ok", hp = 0.9, channeling = true },
		{ id = 3, dist = 2000, state = "ok", hp = 0.8 },
	}
	local obey, queue, _, decisions = R.PickResponders("gank", cands, 2, { now = 900, tier = "force-near" })
	T.eq(#obey, 1, "one goes now")
	T.eq(obey[1], 3, "the healthy bot")
	T.eq(#queue, 2, "two queue")
	T.eq(decisions[1].why, "low-hp", "low bot: why")
	T.eq(decisions[2].why, "channel", "channelling bot: why")
	T.eq(
		R.CandsText(decisions, function(id)
			return "hero" .. id
		end),
		"hero1:queue/low-hp:800,hero2:queue/channel:1200,hero3:obey:2000",
		"the order line shows why each bot waits"
	)
	T.eq(R.Verdict("go", 0, 2, "gank"), "queue", "everyone queued: the order waits for them")
	-- Rejoin: a respawned bot at once, a low one when healed to 50%, a channelling one when the channel ends.
	T.eq(R.ForceRejoin("dead", { state = "dead", hp = 0 }), false, "still dead")
	T.eq(R.ForceRejoin("dead", { state = "ok", hp = 1 }), true, "respawned")
	T.eq(R.ForceRejoin("low-hp", { state = "ok", hp = 0.3 }), false, "30%: not healed yet")
	T.eq(R.ForceRejoin("low-hp", { state = "ok", hp = 0.55 }), true, "55%: healed")
	T.eq(R.ForceRejoin("channel", { state = "ok", hp = 0.9, channeling = true }), false, "still channelling")
	T.eq(R.ForceRejoin("channel", { state = "ok", hp = 0.9 }), true, "channel over")
end)

T.test("human orders: a ping is a request, insist and chat are orders", function()
	local R = rules()
	local facts = { now = 200, aliveAllies = 5, available = 4, enemiesNear = 0, tier = 1, ourCreepsNear = true }
	T.eq(R.Check("push", "ask", facts), "refuse", "push at 3:20")
	T.eq(select(2, R.Check("push", "ask", facts)), "too-early", "why")
	T.eq(R.Check("push", "force-near", facts), "go", "insist goes")
	T.eq(R.Check("push", "force-all", facts), "go", "!push goes")
	facts.now = 900
	T.eq(R.Check("push", "ask", facts), "go", "push at 15:00")
	facts.tier = 2
	facts.ourCreepsNear = false
	T.eq(select(2, R.Check("push", "ask", facts)), "no-creeps", "T2 without our creeps")
	facts.tier, facts.ourCreepsNear = 1, true
	facts.enemiesNear = 5
	T.eq(select(2, R.Check("push", "ask", facts)), "outnumbered", "5 enemies, 4 of us")
	facts.enemiesNear, facts.baseUnderAttack = 0, true
	T.eq(select(2, R.Check("gank", "ask", facts)), "base-under-attack", "base under attack")
	T.eq(R.Check("defend", "ask", facts), "go", "a defence is never refused")
	facts.baseUnderAttack, facts.aliveAllies = false, 2
	T.eq(select(2, R.Check("push", "ask", facts)), "too-few-alive", "2 alive")
	T.eq(select(2, R.Check("rosh", "force-near", { roshanAlive = false, available = 3 })), "roshan-dead", "!rosh, dead")
	T.eq(select(2, R.Check("push", "force-all", { available = 0 })), "nobody-free", "nobody can go")
	T.eq(R.Check("danger", "ask", { available = 0 }), "go", "danger needs nobody")
end)

T.test("human orders: who answers", function()
	local R = rules()
	T.eq(R.BotState({ alive = false }), "dead", "dead")
	T.eq(R.BotState({ alive = true, hp = 0.9, retreating = true }), "retreat", "retreating")
	T.eq(R.BotState({ alive = true, hp = 0.2 }), "low-hp", "low")
	T.eq(R.BotState({ alive = true, hp = 0.9, holdingBase = true }), "base", "holding the base")
	T.eq(R.BotState({ alive = true, hp = 0.9, inFight = true }), "fight", "fighting")
	T.eq(R.BotState({ alive = true, hp = 0.9, inFight = true, losing = true }), "losing", "losing")
	T.eq(R.Answer("push", "fight"), "queue", "a fight first, then the push")
	T.eq(R.Answer("push", "losing"), "obey", "a lost fight may be left")
	T.eq(R.Answer("focus", "fight"), "obey", "focus is about the fight")
	T.eq(R.Answer("danger", "fight"), "ignore", "danger does not pull a bot out of a fight")
	T.eq(R.Answer("push", "retreat"), "ignore", "retreating bots stay out")
	local cands = {
		{ id = 1, dist = 3000, state = "ok" },
		{ id = 2, dist = 1000, state = "ok" },
		{ id = 3, dist = 500, state = "fight" },
		{ id = 4, dist = 200, state = "retreat" },
		{ id = 5, dist = 6000, state = "ok" },
	}
	local obey, queue, ignore = R.PickResponders("push", cands, 3)
	T.eq(#obey, 3, "three free bots, the far one too")
	T.eq(obey[1], 2, "nearest first")
	T.eq(#queue, 0, "free bots first: the fighter is not needed")
	obey, queue = R.PickResponders("push", cands, 4)
	T.eq(queue[1], 3, "a fourth place: the fighter goes after its fight")
	T.eq(#ignore, 1, "the retreating bot")
	T.eq(ignore[1].why, "retreat", "why")
	obey = R.PickResponders("focus", cands, 5)
	T.eq(#obey, 2, "focus: only bots within 2000")
	T.eq(R.Verdict("go", 0, 1), "queue", "everyone fighting: after this fight")
	T.eq(R.Verdict("go", 0, 0), "refuse", "nobody")
	T.eq(R.Verdict("refuse", 3, 0), "refuse", "the check said no")
	T.eq(R.Verdict("go", 2, 0), "go", "go")
	T.eq(R.Need("push", { tier = 3, enemiesNear = 0 }), 5, "high ground: everyone")
	T.eq(R.Need("push", { tier = 1, enemiesNear = 0 }), 2, "T1: two")
	T.eq(R.Need("gank", { enemiesNear = 1 }), 2, "gank one: two")
end)

T.test("human orders: reply lines per language", function()
	T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	local Lines = require(GetScriptDirectory() .. "/lib/data/human_order_lines")
	T.eq(Lines.Get("en", "dead", "Leshrac", 12.7), "Dead, back in 12s", "dead line")
	T.eq(Lines.Get("en", "outnumbered", "Leshrac"), "They outnumber us there", "a short reason")
	T.eq(Lines.Get("xx", "too-early", "Leshrac"), "Too early", "unknown locale: English")
	T.eq(Lines.Get("en", "nonsense", "Leshrac"), "Can't now", "unknown key")
	T.eq(Lines.Get("en", "which_lane", "Leshrac"), "Leshrac, which lane? !push top / mid / bot", "a command reply")
	for _, locale in ipairs({ "en", "zh", "ru", "ja" }) do
		for key in pairs(Lines.en) do
			T.ok(Lines[locale][key] ~= nil, locale .. " has " .. key)
		end
	end
end)

T.test("human orders: the runtime loads and a tick without humans does nothing", function()
	T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	local Orders = require(GetScriptDirectory() .. "/lib/systems/human_orders")
	Orders.Tick(GetBot())
	T.eq(Orders.state.order, nil, "no order")
	T.eq(Orders.OnChat({ string = "gg", player_id = 10 }), false, "plain chat is not a command")
	T.eq(Orders.AssembleDesire(GetBot()), nil, "no assemble desire")
	T.eq(Orders.PushDesire(GetBot(), LANE_TOP), nil, "no push desire")
	T.eq(Orders.FocusTarget(GetBot(), 600), nil, "no focus target")
end)
