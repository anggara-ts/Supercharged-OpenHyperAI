-- Pure rules for mode_rune_generic.lua (#32): plain numbers in, so tests/test_rune_rules.lua can check them without
-- the bot API.
local RuneRules = {}

-- Passing-by grab (#32): does this bot leave a rune to an ally closer to it? The old rule left it to any closer ally,
-- whether or not that ally went for it. Game 066, 78:01: an invisibility rune (type 3) lay 357 from Elder Titan and
-- 382 from Earthshaker while they chased Omniknight, both said `powerrune-near-skip`, and nobody took it.
-- A closer human always has it. A closer bot has it while its active mode is the rune mode, and for the first
-- PASS_WAIT seconds this bot sees it closer (its rune mode needs a think to win). After that, a closer bot that still
-- isn't in the rune mode has given it up, and this bot takes it. waited: seconds this bot has seen that ally closer.
RuneRules.PASS_WAIT = 1.0
-- Seconds a bot that took a rune over stays its picker (renewed every think the passing grab still wants it).
RuneRules.PASS_TAKE_FOR = 3
function RuneRules.PassingYield(allyCloser, allyIsHuman, allyInRuneMode, waited)
	if not allyCloser then
		return false
	end
	if allyIsHuman or allyInRuneMode then
		return true
	end
	return waited < RuneRules.PASS_WAIT
end
-- The passing grab's desire with no enemy hero within 1200 (above a walking push or defend at 0.95, #99), and for a
-- power rune within PASS_POWER_STEP even with enemy heroes near, unless one hit the bot in the last 1.5s.
RuneRules.PASS_DESIRE = 0.97
RuneRules.PASS_POWER_STEP = 400

-- Leftover rune: a spot (river or jungle) whose status reads available while GetRuneType says -1 (no type), with
-- the spot in our vision, after the first 10s of its spawn cycle (the type reads -1 just after a spawn too: game
-- 017, the horn). Game 063: the bottom river bounty from 0:00 was never taken and read `type=-1` all game; bots
-- ordered the pick-up 14-20 times per visit at distance 0 (`blind-pickup` ... `pickup-failed tries=19`, Clinkz
-- 30:29-30:49 under creep fire), and Shadow Fiend at 15:00 left a jungle bounty reading the same (`no-rune rune=3`).
-- Game 062 (Valve's item mode in place): every one of the 9 `blind-pickup` orders on such a spot took the rune within
-- 1.6s from 70-130 away (`pickup-result taken=yes`, no `stale-status`), so a type -1 spot can hold a real rune the
-- order takes. So: one pick-up order, then stand on the spot without orders for HOLD_FOR seconds so Valve's item mode
-- can take it, then give up for this spawn cycle.
RuneRules.FRESH_SPAWN = 10
RuneRules.TRY_WAIT = 1.5
RuneRules.HOLD_FOR = 3
RuneRules.ON_SPOT = 60
RuneRules.GIVE_UP = 10

function RuneRules.IsLeftover(available, runeType, invalidType, visible, sinceSpawn)
	local untyped = runeType == -1 or (invalidType ~= nil and runeType == invalidType)
	return available == true and untyped and visible == true and sinceSpawn >= RuneRules.FRESH_SPAWN
end

-- One step of a leftover hold. hold = { t0 = start }; the step keeps hold.onSpotAt. dist: bot to the spot; up: the
-- raw status still reads available; typed: GetRuneType now names a rune; contested: enemy heroes hold the spot or
-- one hits the bot. Returns the phase ("try" / "walk" / "hold") or "end" plus why ("taken" / "typed" / "fight" /
-- "held" / "timeout").
function RuneRules.LeftoverStep(hold, now, dist, up, typed, contested)
	if not up then
		return "end", "taken"
	end
	if typed then
		return "end", "typed"
	end
	if contested then
		return "end", "fight"
	end
	if now - hold.t0 > RuneRules.GIVE_UP then
		return "end", "timeout"
	end
	if now < hold.t0 + RuneRules.TRY_WAIT then
		return "try"
	end
	if dist > RuneRules.ON_SPOT then
		hold.onSpotAt = nil
		return "walk"
	end
	hold.onSpotAt = hold.onSpotAt or now
	if now - hold.onSpotAt >= RuneRules.HOLD_FOR then
		return "end", "held"
	end
	return "hold"
end

-- Seconds stood on the spot so far.
function RuneRules.HeldFor(hold, now)
	return hold.onSpotAt ~= nil and now - hold.onSpotAt or 0
end

-- The pick-up retry loop for a rune with a known type: at most PICKUP_TRIES orders, PICKUP_GAP seconds apart (the
-- old loop counted thinks: 19 orders in 3s). try = { n = orders so far, last = time of the last order }.
-- "order": give one now; "wait": no new order; "fail": tries used up and the last one had its time.
RuneRules.PICKUP_TRIES = 3
RuneRules.PICKUP_GAP = 1.0
function RuneRules.PickupStep(try, now)
	local due = try.last == nil or now - try.last >= RuneRules.PICKUP_GAP
	if try.n >= RuneRules.PICKUP_TRIES then
		return due and "fail" or "wait"
	end
	return due and "order" or "wait"
end

-- Spawn hold at a river spot (#32, game 064, 2:00): Puck was 475 from the top spot when the water rune spawned, the
-- after-spawn walk desire (0.35) lost to laning (0.54-0.56) and she walked back to mid; the bounty walk-back brought
-- her there 8s later (2:14). A bot of the water walk (spawns at 0:00, 2:00, 4:00) within SPAWN_HOLD_RADIUS of the
-- spot from SPAWN_HOLD_BEFORE seconds before the spawn to SPAWN_HOLD_FOR after it keeps SPAWN_HOLD_DESIRE (above
-- laning, as the 0.6 on-spot stay; below fights and retreat). sinceSpawn: seconds since the spawn (negative before).
RuneRules.SPAWN_HOLD_RADIUS = 600
RuneRules.SPAWN_HOLD_BEFORE = 2
RuneRules.SPAWN_HOLD_FOR = 3
RuneRules.SPAWN_HOLD_DESIRE = 0.6
function RuneRules.SpawnHold(sinceSpawn, dist)
	return sinceSpawn >= -RuneRules.SPAWN_HOLD_BEFORE
		and sinceSpawn <= RuneRules.SPAWN_HOLD_FOR
		and dist <= RuneRules.SPAWN_HOLD_RADIUS
end

-- Walk to a river spot for a water rune (#32, game 065): Puck (mid) walked to the top spot before the 2:00 and 4:00
-- spawns at 0.53 (BOT_MODE_DESIRE_HIGH, `why=water-walk` t=112.7 and t=232.3, 1846-2188 from the spot) and laning
-- (0.56) won, so she stayed in lane; after the spawn the walk was 0.35 (`river-item-walk`, 2211 away at t=120.3).
-- Death Prophet took both top water runes. Maintainer (2026-11-21): raise it only for heroes near the spot (the mid
-- laner or a support roaming to mid), by distance. So a bot whose distance to the spot is the smallest on its team
-- (rank 1), or within RIVER_WALK_NEAR of it, walks at RIVER_WALK_DESIRE (above laning, as the spawn hold; below
-- fights, retreat and Valve's item mode, which does the pickup); others keep oldDesire.
-- rank: 1 + the number of living team heroes closer to the spot than the bot.
RuneRules.RIVER_WALK_NEAR = 2000
RuneRules.RIVER_WALK_DESIRE = 0.6
function RuneRules.RiverWalkNear(dist, rank)
	return rank == 1 or dist <= RuneRules.RIVER_WALK_NEAR
end
function RuneRules.RiverWalkDesire(dist, rank, oldDesire)
	if RuneRules.RiverWalkNear(dist, rank) then
		return math.max(RuneRules.RIVER_WALK_DESIRE, oldDesire)
	end
	return oldDesire
end

-- Release after a failed pick-up order at a river spot (#32, game 080, 0:00-0:15): at the bottom spot the order never
-- worked (7 of 7 `river-pickup-try id=1 worked=no`, games 070-080), and then the 5s `water-stay` (0.60) and the
-- bounty return (0.60) kept Winter Wyvern and Io standing on the rune with Valve's item mode never starting
-- (`water-walk-end ... status=up type=5 itemMode=no`); the item mode took it at 0:21 (`mode=m21/0.90`). So after a
-- `worked=no` with the bot on the spot and the rune up, the rune mode lets go (desire 0, under every mode, the item
-- mode's 0.90 included) for RELEASE_FOR seconds and logs whether the rune went. A worked=unsure / yes keeps the stay.
-- Unverified why the item mode does not start there: the 0.60 stay was already under its 0.90, and in game 080 it did
-- not start under laning (0.27) either, so the release may not be enough on its own; the result line shows it.
RuneRules.RELEASE_FOR = 3
RuneRules.RELEASE_RADIUS = 300

-- Start a release? worked: the try's verdict ("no" / "unsure" / "yes"); dist: bot to the spot; up: the rune reads up.
function RuneRules.ReleaseStarts(worked, dist, up)
	return worked == "no" and up == true and (dist or math.huge) <= RuneRules.RELEASE_RADIUS
end

-- One step of a release (release = { t0 = start }): "hold" (keep the desire at 0) or "end" plus taken (true when the
-- rune is gone).
function RuneRules.ReleaseStep(release, now, up)
	if not up then
		return "end", true
	end
	if now - release.t0 >= RuneRules.RELEASE_FOR then
		return "end", false
	end
	return "hold"
end

-- Which river spot the water walk tries first (#32, game 078, 0:00): both teams tried the top spot (RUNE_POWERUP_1)
-- first, so both mids went top and nobody went bottom; Io (Dire) took the top spot 1981 away with the bottom one 1694
-- away (`river-walk-near spot=0 dist=1981`). Maintainer: "usually bots take top river horn bounty and dire bottom".
-- Radiant tries the top spot first, Dire the bottom one; then the other spot. top / bottom: the two rune ids.
function RuneRules.RiverSpotOrder(isDire, top, bottom)
	if isDire then
		return { bottom, top }
	end
	return { top, bottom }
end

-- A takeover claims the rune for the team (#32, game 069 40:18-40:22: during a Roshan take Vengeful Spirit took a rune
-- over from Puck, Puck took it back from her, then Zeus from her: each takeover lost to the Roshan mode, nobody picked it
-- up). Claims are shared by the team's bots (this module is one table per team VM), keyed by team and rune id: an
-- ally's live claim makes the others leave the rune (pass=claimed:<hero>). A claim lasts PASS_TAKE_FOR and is renewed
-- while its holder is in the rune mode, or within PASS_WAIT of taking it (its rune mode needs a think to win); a holder
-- that never switches to the rune mode loses it after PASS_TAKE_FOR.
RuneRules.passClaims = {}
-- The claim after this think: a new one (claim nil), or the old one renewed or kept. holder: any value naming the bot.
function RuneRules.NextClaim(claim, holder, now, inRuneMode)
	if claim == nil or claim.holder ~= holder or now >= claim.untilAt then
		return { holder = holder, at = now, untilAt = now + RuneRules.PASS_TAKE_FOR }
	end
	if inRuneMode or now - claim.at <= RuneRules.PASS_WAIT then
		claim.untilAt = now + RuneRules.PASS_TAKE_FOR
	end
	return claim
end
-- Another bot's live claim on the rune: true when this bot should leave it.
function RuneRules.ClaimedByOther(claim, holder, now)
	return claim ~= nil and claim.holder ~= holder and now < claim.untilAt
end

-- Wisdom shrine (#32). Game data (7.42 pak01 scripts/npc/npc_units.txt, npc_dota_xp_fountain): RingRadius 100, so a
-- hero can't walk closer than ~140 to the shrine's centre (game 068: Vengeful Spirit and Nyx stopped at 139-140 for
-- the whole window). npc_abilities.txt, ability_xp_fountain: radius 300, countdown_time 3: a hero inside 300 for 3s
-- takes the XP. The old stand rule waited for dist <= 100, which a hero never reaches, so no stand was ever timed and
-- no shrine claimed (games 064-068). Stand at 220: inside the 300 radius with 80 to spare, outside the ~140 the
-- shrine's ring allows.
RuneRules.WISDOM_RADIUS = 300
RuneRules.WISDOM_STAND = 220
-- Seconds on the shrine after the mark before a stand with no XP seen counts as covered (countdown_time 3 + 0.5).
RuneRules.WISDOM_COVER = 3.5
-- Seconds the shrine window stays open after the mark (the InMarkWindow stayAfter of the shrine trip).
RuneRules.WISDOM_STAY = 8

-- Can this shrine trip still make it? Returns "go" | "cant-arrive" | "window". etaW: seconds to the mark (negative
-- after it). A bot already on the shrine never reads cant-arrive, and a window with under 1s left reads "window":
-- game 068 t=428, Vengeful Spirit at dist=140 printed `cant-arrive travel=0 eta=-8` (travel 0.4s > 0s left).
function RuneRules.WisdomTrip(dist, travel, etaW)
	local left = etaW + RuneRules.WISDOM_STAY
	if dist <= RuneRules.WISDOM_STAND then
		if left <= 0 then
			return "window"
		end
		return "go"
	end
	if travel > left then
		if left <= 1 then
			return "window"
		end
		return "cant-arrive"
	end
	return "go"
end

-- The stand clock on the shrine starts at the mark: a stand from before the mark counts from the mark, so a bot that
-- arrived early does not read "covered" (and leave) the moment the mark passes, before the 3s countdown ran.
-- Returns the stand start to use.
function RuneRules.WisdomStandFrom(standSince, mark, now)
	if standSince == nil then
		return now
	end
	if now >= mark and standSince < mark then
		return mark
	end
	return standSince
end

-- XP gained between two reads of GetXPNeededToLevel() and GetLevel() (the bot handle has no GetCurrentXP, game 069).
-- Same level: the drop in XP still needed. A level up: at least the XP that was still needed then (the part into the
-- new level is not known without the level table). Returns gain, leveled.
function RuneRules.XpGain(prevNeeded, prevLevel, needed, level)
	if prevNeeded == nil or needed == nil then
		return 0, false
	end
	if (level or 0) > (prevLevel or 0) then
		return prevNeeded, true
	end
	return math.max(0, prevNeeded - needed), false
end

-- When a shrine stand is done (#32, live game 2026-11-23: `t=423 largo taken xp=+1 stood=0.3`, `t=428 winter_wyvern
-- taken xp=+1 stood=1.2`: a 1-XP rise, creep XP or rounding, read as the shrine paying out, and they left before its
-- countdown). The shrine pays a hero that stays inside its radius for countdown_time 3 (7.42 npc_abilities.txt
-- ability_xp_fountain), so a gain before that is not the shrine's: the stand always runs WISDOM_COVER (3 + 0.5) from
-- the mark or the arrival. How much the shrine gives is a runtime value (dota_en.txt "Shrine of Wisdom ({d:xp} XP)"),
-- not in the game files, so the label uses WISDOM_BIG_XP, a guess above a creep's share: "taken" with a gain of at
-- least that, else "covered". Returns done, label.
RuneRules.WISDOM_BIG_XP = 100
function RuneRules.WisdomStandDone(stood, gain, leveled)
	if stood < RuneRules.WISDOM_COVER then
		return false, nil
	end
	if leveled or (gain or 0) >= RuneRules.WISDOM_BIG_XP then
		return true, "taken"
	end
	return true, "covered"
end

-- Lotus pool (7.42 npc_abilities.txt ability_lotus_pool): radius 350, first_lotus_pickup_time 1.5,
-- pickup_time_reduction_pct 70, min_lotus_pickup_time 0.3: after the first lotus, each next one in the pool comes
-- 0.45s later. Live game 2026-11-23: a bot that took the lotus stood ~6s more (the pluck-stall clock restarted on the
-- new charge, `do=hold` ... `do=stalled`). Now a stand ends LOTUS_MORE_WAIT after the last lotus taken when no other
-- came. state: { base = lotus charges at the stand's start, lastRise, first } (kept per bot and mark).
-- Returns "wait" or "leave", and the seconds since the first lotus taken.
RuneRules.LOTUS_MORE_WAIT = 1.0
function RuneRules.LotusTakeStep(state, have, now)
	if have < state.base then
		-- Eaten or used while standing: count from here.
		state.base = have
	elseif have > state.base then
		state.base = have
		state.lastRise = now
		state.first = state.first or now
	end
	if state.lastRise ~= nil and now - state.lastRise >= RuneRules.LOTUS_MORE_WAIT then
		return "leave", now - state.first
	end
	return "wait", nil
end

-- Healing Lotus tiers (7.42 items_all.txt): item_famango (stacks to 3), item_great_famango (recipe: 3 item_famango,
-- stacks to 2), item_greater_famango (recipe: 2 item_great_famango, stacks to 3). The recipes consume the charges
-- (ItemRecipeConsumesCharges 1), so a third lotus picked up next to two turns into one Great Healing Lotus and the charge
-- total drops from 2 to 1. LotusValue counts every tier in Healing Lotuses (1 / 3 / 6), so a pickup, merged or not,
-- always raises it. items: list of { name =, charges = }.
RuneRules.LOTUS_TIER = { item_famango = 1, item_great_famango = 3, item_greater_famango = 6 }
function RuneRules.LotusValue(items)
	local value = 0
	for i = 1, #(items or {}) do
		local tier = RuneRules.LOTUS_TIER[items[i].name]
		if tier ~= nil then
			value = value + tier * math.max(1, items[i].charges or 1)
		end
	end
	return value
end

-- Lotus stand result (#32, game 074, maintainer 2026-11-23: "45 seconds is too long. can bot check if their inventory
-- change (added or upgraded lotus) after certain time in the area?"). The pool's lotus count can't be read
-- (LotusCountOnUnit), so the stand reads the bot's own lotuses: a rise in LotusValue is a lotus taken by us; standing
-- LOTUS_STAND_WAIT in the pluck ring after the spawn with no rise means the lotus is gone (someone else took it).
-- Game data (7.42 npc_abilities.txt ability_lotus_pool): radius 350, first_lotus_pickup_time 1.5 (a hero in the pool
-- gets its first lotus after 1.5s). Game 074, 6:00: Winter Wyvern stood from 357.5 and had the lotus at 361.4 (mark +1.4,
-- `taken-leave after=1.2` at 362.6). LOTUS_STAND_WAIT = 1.5 + 1s for think and walk-in lag. With an enemy hero in the
-- pool the wait is one second longer: whether a contesting hero delays the pickup is not in the game data (unverified).
-- LOTUS_AREA: the bot fights and casts without walking back while within it (inside the 350 radius). Stand time counts
-- only in the pluck ring (LOTUS_RING): the bot walks to 140 and a pickup is proven there (game 074: taken at 132; the
-- old comment in map_objectives says the pool's lip never granted one), so a bot fighting at 250 doesn't read "gone" on
-- a lotus that may still be there. LOTUS_HOLD_CAP: backstop, wall seconds from the bot's first think within LOTUS_NEAR
-- after the spawn (a pause for retreat counts too); it also ends a stand whose lotus was taken but whose take step never
-- ran.
RuneRules.LOTUS_AREA = 300
RuneRules.LOTUS_RING = 150
RuneRules.LOTUS_NEAR = 800
RuneRules.LOTUS_STAND_WAIT = 2.5
RuneRules.LOTUS_STAND_WAIT_CONTESTED = 3.5
RuneRules.LOTUS_HOLD_CAP = 10
-- A think gap longer than this (the rune mode lost, e.g. paused for retreat) counts as no time stood in the ring.
RuneRules.LOTUS_THINK_GAP = 0.5
function RuneRules.NewLotusStand(mark, value)
	return { mark = mark, base = value, stood = 0 }
end
-- Wall seconds since the stand began (its first think within LOTUS_NEAR after the spawn), 0 before that.
function RuneRules.LotusHeld(stand, now)
	return stand.since ~= nil and now - stand.since or 0
end
-- One think of a stand. mark: the spawn this stand is for; dist: bot to pool; contested: an enemy hero in the pool.
-- stood (in the ring) counts think time only, so a pause in another mode adds nothing; held is wall time (the cap).
-- Returns "wait" | "taken" | "gone" | "cap", stood and held. gone / cap stay; taken can still become cap.
function RuneRules.LotusStandStep(stand, now, value, dist, contested)
	if stand.result == "gone" or stand.result == "cap" then
		return stand.result, stand.stood, RuneRules.LotusHeld(stand, now)
	end
	if now < stand.mark then
		-- Waiting for the spawn: nothing to take yet.
		stand.lastAt = nil
		if value < stand.base then
			stand.base = value
		end
		if value > stand.base then
			-- A lotus left in the pool from before: taken.
			stand.result = "taken"
		end
		return stand.result or "wait", 0, 0
	end
	local dt = 0
	if stand.lastAt ~= nil then
		dt = now - stand.lastAt
		if dt > RuneRules.LOTUS_THINK_GAP or dt < 0 then
			dt = 0
		end
	end
	stand.lastAt = now
	if stand.since == nil and dist <= RuneRules.LOTUS_NEAR then
		stand.since = now
	end
	local held = RuneRules.LotusHeld(stand, now)
	if stand.result == "taken" then
		if held >= RuneRules.LOTUS_HOLD_CAP then
			stand.result = "cap"
		end
		return stand.result, stand.stood, held
	end
	if value > stand.base then
		stand.result = "taken"
		return "taken", stand.stood, held
	end
	if value < stand.base then
		-- Eaten or given away while standing: not a pickup, count from here.
		stand.base = value
	end
	if dist <= RuneRules.LOTUS_RING then
		stand.stood = stand.stood + dt
	end
	local wait = contested and RuneRules.LOTUS_STAND_WAIT_CONTESTED or RuneRules.LOTUS_STAND_WAIT
	if stand.stood >= wait then
		stand.result = "gone"
	elseif held >= RuneRules.LOTUS_HOLD_CAP then
		stand.result = "cap"
	end
	return stand.result or "wait", stand.stood, held
end

-- At the pool (#32, maintainer 2026-11-23: "being hit by hero/creep should apply same mechanism like being hit in
-- outside the area but they will try to maintain it unless retreat mode is active"). The hold desire (0.75) used to
-- beat retreat: game 074, 3:00-3:19, Winter Wyvern was hit 1v1 by Leshrac from 0.96 to 0.34 HP while retreat asked
-- 0.30-0.40 (0.61 at 0.42 HP) and lost to it. Now the hold gives way while retreat asks LOTUS_RETREAT_YIELD or more:
-- about the laning mode's 0.30, the level at which retreat took over from laning in that game
-- (`[SHy-FLIP] ... retreat:0.30@184>laning:0.30@186`, printed with %.2f, so a little under 0.30). Retreat's base formula
-- (mode_retreat_generic.lua, the line-533 return) stays well under that for a bot that isn't hit and isn't low: about
-- 0.18 for a healthy bot with an enemy near, minus 0.175 in the laning phase when not hit, so no hit gate is needed.
-- retreatDesire: retreat's last desire (nil when not fresh).
RuneRules.LOTUS_RETREAT_YIELD = 0.29
function RuneRules.LotusHoldYields(retreatDesire)
	return retreatDesire ~= nil and retreatDesire >= RuneRules.LOTUS_RETREAT_YIELD
end
-- A yielding bot pushed this far by retreat can still resume the hold (beside is 800 otherwise).
RuneRules.LOTUS_RESUME_DIST = 1600
-- The yield is a pause, not the end (coordinator, 2026-11-23): the hold returns 0 while retreat asks for it, and comes
-- back when retreat drops below the line while the spawn is still open (in its window, no taken / gone / cap). The spawn
-- is dropped only when it closes (window or cap) during a yield. state: { yielding } per bot and spawn. open: the
-- spawn's window still runs and it has no result; capped: the stand's wall-time cap ran out.
-- Returns "hold" | "yield-start" | "yield" | "resume" | "drop".
function RuneRules.LotusYieldStep(state, retreatDesire, open, capped)
	if state.yielding and (not open or capped) then
		state.yielding = false
		return "drop"
	end
	if RuneRules.LotusHoldYields(retreatDesire) then
		if state.yielding then
			return "yield"
		end
		state.yielding = true
		return "yield-start"
	end
	if state.yielding then
		state.yielding = false
		return "resume"
	end
	return "hold"
end

return RuneRules
