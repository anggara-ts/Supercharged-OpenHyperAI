-- Item swap probe (#218): can a bot move items between the main slots (0-5) and the backpack (6-8)?
-- Match logs so far: main item <-> backpack item swaps almost never take (15 of ~1640), main item -> empty backpack
-- slot 0 of 60, backpack item -> empty main slot 1 of 1. This probe tells what differs, for #119 (Aegis) and #15.
--
-- Off unless the local setting Customize.Swap_Probe == true (never set in the shipped bots/customize/general.lua, so a
-- Workshop copy never runs it). One Radiant bot (the highest position among the Radiant bots) runs it pre-game:
--   setup   before each case, from the slots as they are now: buy a marker item and fillers until the case's role
--           slots exist (a main item and a backpack item with different names, an empty backpack slot, an empty
--           main slot). Only at the fountain shop, one buy or sell per 0.3s, at most SETUP_SECONDS per case: a case
--           whose slots can't be made is skipped with the missing role as the reason (never the whole probe).
--           Game 075: an emptied main slot is refilled from the backpack within 0.3s (the sell -> buy -> sell loop
--           ran into the buy cap), so "4 main + 2 backpack" can't be held. Main full + 1 backpack item is enough
--           for cases 1-3; for 4-5 one sell is tried, and once a refill is seen they are skipped (main-refilled).
--           Only items without a stock limit (game 074: the Enchanted Mango was out of stock at t=-88, code 82). A
--           failed buy moves on to the next candidate. The swaps use the engine's own method (handed over by
--           global_overrides.lua), so our wrapper's rules (no branch into the backpack, #15's pull rule) don't apply.
--           Gold (600 at t=-88): a Faerie Fire and 6 branches (395).
--   cases   1 swap(main item, bag item)  2 swap(bag item, main item)  3 main item -> empty bag slot, then
--           bag item -> that main slot  4 bag item -> empty main slot, then main item -> that bag slot
--           5 case 4 with 7s between the steps (the backpack cooldown is 6s). Slots are re-read before each case.
--   conds   idle (held in place by mode_outpost's hold, Action_ClearActions once, then no order), busy (the same
--           hold with a move order every think), modes (no hold: the bot's modes run, e.g. the walk to lane).
-- While it runs, the probe bot's item usage and item purchase thinks are paused (no other code touches its slots).
-- Logs: [SHy-SWAP] probe (one line per step), probe-summary (per condition), probe-done; then one ALL chat line.
local M = {}

-- Candidates in order; 7.42 items.txt: ItemCost, and no ItemStockMax / ItemStockInitial (no stock limit).
M.MARKERS = {
	{ name = "item_faerie_fire", cost = 65 },
	{ name = "item_quelling_blade", cost = 100 },
	{ name = "item_gauntlets", cost = 140 },
}
M.FILLERS = {
	{ name = "item_branches", cost = 55 },
	{ name = "item_slippers", cost = 140 },
	{ name = "item_mantle", cost = 140 },
}
M.MAX_BUYS = 20 -- gold guard over the whole probe
M.SETUP_SECONDS = 8 -- per case: the setup gives up after this and the case is skipped with the missing role
M.REFILL_CHECK = 0.5 -- seconds after a sell before the slots are read again (game 075: refilled within 0.3s)
M.DEADLINE = 180 -- game seconds: whatever is not done by then is cut short
M.CONDITIONS = { "idle", "busy", "modes" }
-- Each step names two role slots (re-read before the case): m1 a main item, m2 an empty main slot, b1 a backpack
-- item, b2 an empty backpack slot.
M.CASES = {
	{ { "m1", "b1" } },
	{ { "b1", "m1" } },
	{ { "m1", "b2" }, { "b1", "m1" } },
	{ { "b1", "m2" }, { "m1", "b1" } },
	{ { "b1", "m2" }, { "m1", "b1" }, gap = 7 },
}

-- ---------------------------------------------------------------- pure rules (tests/test_swap_probe.lua)

-- What a swap of slots a and b did. before / after05 / after3 = { a = name, b = name } ("-" = empty).
-- moved: traded places by the 0.5s check and still so at 3s; moved-late: only at 3s; reverted: traded at 0.5s
-- but back at 3s; noop: unchanged at both checks; other: the slots changed some other way; same: nothing to swap.
function M.Classify(before, after05, after3)
	if before.a == before.b then
		return "same"
	end
	local function traded(after)
		return after.a == before.b and after.b == before.a
	end
	local function unchanged(after)
		return after.a == before.a and after.b == before.b
	end
	if traded(after3) then
		return traded(after05) and "moved" or "moved-late"
	end
	if unchanged(after3) then
		return traded(after05) and "reverted" or (unchanged(after05) and "noop" or "other")
	end
	return "other"
end

-- names[0..8] (item name or "-") -> { m1, m2, b1, b2 } slots (a field is nil when the layout has none).
-- m1 and b1 are a main item and a backpack item with different names, so a main <-> backpack swap is visible; with
-- an empty backpack m1 is any main item, and with no such pair b1 is the first backpack item and m1 is nil.
function M.PickRoles(names)
	local roles = {}
	for slot = 6, 8 do
		if names[slot] == "-" then
			roles.b2 = roles.b2 or slot
		end
	end
	for slot = 0, 5 do
		if names[slot] == "-" then
			roles.m2 = roles.m2 or slot
		end
	end
	for bag = 6, 8 do
		if names[bag] ~= "-" then
			roles.b1 = roles.b1 or bag
			for main = 0, 5 do
				if names[main] ~= "-" and names[main] ~= names[bag] then
					roles.b1, roles.m1 = bag, main
					return roles
				end
			end
		end
	end
	if roles.b1 == nil then
		for main = 0, 5 do
			if names[main] ~= "-" then
				roles.m1 = main
				break
			end
		end
	end
	return roles
end

-- The role names the case's steps need that the layout lacks, in a fixed order (m1, b1, b2, m2).
function M.MissingRoles(roles, caseDef)
	local wanted = {}
	for _, stepDef in ipairs(caseDef) do
		wanted[stepDef[1]], wanted[stepDef[2]] = true, true
	end
	local missing = {}
	for _, role in ipairs({ "m1", "b1", "b2", "m2" }) do
		if wanted[role] and roles[role] == nil then
			missing[#missing + 1] = role
		end
	end
	return missing
end

-- Every role slot the case's steps name is there.
function M.CaseReady(roles, caseDef)
	return #M.MissingRoles(roles, caseDef) == 0
end

local function InList(list, name)
	for _, entry in ipairs(list) do
		if entry.name == name then
			return true
		end
	end
	return false
end

-- The next setup action for caseDef from the slots as they are: "ready" | "buy", item, cost | "sell", slot |
-- "skip", reason. ctx = { buys = buys so far, failed = set of item names whose buy failed (the next candidate is
-- tried), refills = an emptied main slot was seen refilled from the backpack (game 075) }.
-- A buy lands in the first empty main slot, else in the first empty backpack slot.
function M.SetupStep(names, gold, caseDef, ctx)
	ctx = ctx or {}
	local failed = ctx.failed or {}
	local roles = M.PickRoles(names)
	local missing = M.MissingRoles(roles, caseDef)
	if #missing == 0 then
		return "ready"
	end
	local mainItems, marker, bagNames = 0, false, {}
	for slot = 0, 8 do
		if names[slot] ~= "-" then
			if slot <= 5 then
				mainItems = mainItems + 1
			else
				bagNames[names[slot]] = true
			end
			marker = marker or InList(M.MARKERS, names[slot])
		end
	end
	local function buy(lists, what)
		if (ctx.buys or 0) >= M.MAX_BUYS then
			return "skip", "buy-cap"
		end
		local short = false
		for _, list in ipairs(lists) do
			for _, entry in ipairs(list) do
				if not failed[entry.name] and not bagNames[entry.name] then
					if gold >= entry.cost then
						return "buy", entry.name, entry.cost
					end
					short = true
				end
			end
		end
		return "skip", short and "gold" or ("no-" .. what .. "-buyable")
	end
	local function sellFiller(from, to)
		for slot = from, to, -1 do
			if InList(M.FILLERS, names[slot]) then
				return "sell", slot
			end
		end
		return nil
	end
	local need = missing[1]
	if need == "m1" or need == "b1" then
		-- No main/backpack pair with different names. While the main slots have room a buy lands there (an item
		-- unlike the backpack's), once they are full it lands in the backpack. The marker first, so a pair exists.
		if need == "m1" and mainItems >= 6 then
			return "skip", "no-pair"
		end
		return buy(marker and { M.FILLERS, M.MARKERS } or { M.MARKERS, M.FILLERS }, need == "m1" and "main" or "filler")
	end
	if need == "b2" then
		-- The backpack is full: sell its highest filler.
		local action, slot = sellFiller(8, 6)
		if action ~= nil then
			return action, slot
		end
		return "skip", "bag-full"
	end
	-- need == "m2": the main slots are full. Game 075: a sold main slot was refilled from the backpack at once, so an
	-- empty main slot and a backpack item can't both be had; one sell is tried, then the case is skipped.
	if ctx.refills then
		return "skip", "main-refilled"
	end
	local action, slot = sellFiller(5, 0)
	if action ~= nil then
		return action, slot
	end
	return "skip", "no-main-filler"
end

-- After selling soldSlot: the backpack slot whose item moved into the sold main slot (game 075), else nil.
-- before / after = names[0..8].
function M.DetectRefill(before, after, soldSlot)
	local now = after[soldSlot]
	if now == nil or now == "-" then
		return nil
	end
	for slot = 6, 8 do
		if before[slot] == now and after[slot] == "-" then
			return slot
		end
	end
	return nil
end

-- ---------------------------------------------------------------- game side

-- The engine's own swap (global_overrides.lua hands it over before wrapping the method): the probe tests the bot
-- API, not our wrapper's rules (the branch rule, #15's pull rule, the pair gap). Set once.
local rawSwap
function M.SetRawSwap(fn)
	rawSwap = rawSwap or fn
end

-- Per team (GetTeam() is the team whose scripts run; kept apart in case both teams share one Lua state).
local states = {}
local state
local function UseTeamState()
	local team = GetTeam()
	states[team] = states[team] or { decided = false }
	state = states[team]
end

local function Short(name)
	return (string.gsub(name or "-", "^item_", ""))
end

local function HeroName(bot)
	return (string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""))
end

local function Names(bot)
	local names = {}
	for slot = 0, 8 do
		local item = bot:GetItemInSlot(slot)
		names[slot] = item ~= nil and item:GetName() or "-"
	end
	return names
end

local function Layout(names)
	local parts = {}
	for slot = 0, 8 do
		parts[#parts + 1] = slot .. ":" .. Short(names[slot])
	end
	return table.concat(parts, ",")
end

local function Log(fmt, ...)
	pcall(print, string.format(fmt, ...))
end

local function Enabled()
	local ok, settings = pcall(require, GetScriptDirectory() .. "/lib/systems/custom_loader")
	return ok and type(settings) == "table" and settings.Swap_Probe == true
end

-- Picks the probe bot once: the Radiant bot with the highest position. Returns false while undecided.
local function Decide()
	if state.decided then
		return true
	end
	if not Enabled() or GetTeam() ~= TEAM_RADIANT or DotaTime() > 60 then
		state.decided = true
		return true
	end
	local okFu, Fu = pcall(require, GetScriptDirectory() .. "/lib/func_utils")
	local best, bestPos
	for i = 1, 5 do
		local member = GetTeamMember(i)
		if member == nil and DotaTime() < -60 then
			return false
		end
		if member ~= nil and member:IsBot() then
			local okP, pos = false, nil
			if okFu and Fu ~= nil and Fu.GetPosition ~= nil then
				okP, pos = pcall(Fu.GetPosition, member)
			end
			pos = okP and tonumber(pos) or i
			if bestPos == nil or pos >= bestPos then
				best, bestPos = member, pos
			end
		end
	end
	state.decided = true
	if best ~= nil then
		state.pid = best:GetPlayerID()
		state.phase = "setup"
		state.cond, state.case, state.buys, state.failed = 1, 1, 0, {}
		state.counts = {}
		Log(
			"[SHy-SWAP] t=%.0f %s probe-start pos=%s swap=%s",
			DotaTime(),
			HeroName(best),
			tostring(bestPos),
			rawSwap ~= nil and "raw" or "wrapper"
		)
	end
	return true
end

local function IsProbeBot(bot)
	return state.pid ~= nil and bot ~= nil and bot:GetPlayerID() == state.pid
end

-- ItemPurchaseThink: true while this bot's purchases must wait (every Radiant bot until the probe bot is picked,
-- then the probe bot until the probe is done).
function M.Busy(bot)
	UseTeamState()
	if not Decide() then
		return true
	end
	return IsProbeBot(bot) and state.phase ~= "done"
end

local function Count(cond)
	state.counts[cond] = state.counts[cond] or { tries = 0, moved = 0, skipped = 0, blocked = 0 }
	return state.counts[cond]
end

local function Hold(bot, now)
	bot._swapProbeHoldUntil = now + 1
	bot._outpostHoldUntil = now + 0.5
end

local function Release(bot)
	-- Only the probe's own flag: _outpostHoldUntil may be a hero's own hold, and the probe's lapses in 0.5s.
	bot._swapProbeHoldUntil = nil
end

local function Finish(bot, why)
	local moved, tries = 0, 0
	for _, cond in ipairs(M.CONDITIONS) do
		local c = Count(cond)
		moved, tries = moved + c.moved, tries + c.tries
		Log(
			"[SHy-SWAP] t=%.0f %s probe-summary cond=%s moved=%d tries=%d skipped=%d blocked=%d",
			DotaTime(),
			HeroName(bot),
			cond,
			c.moved,
			c.tries,
			c.skipped,
			c.blocked
		)
	end
	if why == "complete" and tries == 0 then
		-- Every case was skipped: name the last reason (e.g. gold, no-pair, away-from-shop).
		why = "all-skipped-" .. tostring(state.lastSkip)
	end
	Log(
		"[SHy-SWAP] t=%.0f %s probe-done why=%s moved=%d tries=%d refills=%s",
		DotaTime(),
		HeroName(bot),
		why,
		moved,
		tries,
		tostring(state.refills)
	)
	state.phase = "done"
	state.doneAt = DotaTime()
	Release(bot)
	if tries == 0 then
		-- Game 074: "finished (0/0 moved)" was said after a setup that never bought anything.
		state.chat = nil
		pcall(bot.ActionImmediate_Chat, bot, string.format("Item swap test could not run (%s).", tostring(why)), true)
		return
	end
	state.chat = string.format(
		"Item swap test finished (%d/%d moved). Type !about if you haven't; then you can stop the game.",
		moved,
		tries
	)
	pcall(bot.ActionImmediate_Chat, bot, state.chat, true)
end

-- Returns false when the wrapper refused the swap (only without the raw swap; the wrapper records _swapCheck for
-- a swap it passed on).
local function Swap(bot, a, b)
	if rawSwap ~= nil then
		rawSwap(bot, a, b)
		return true
	end
	bot._swapCheck = nil
	bot._swapTryReverse = nil
	bot._swapDespiteEnemies = true
	bot._swapDespiteCooldown = true
	bot:ActionImmediate_SwapItems(a, b)
	local passed = bot._swapCheck ~= nil
	-- Not for VerifyLastSwap: its [SHy-ITEM] line would report the probe swap later.
	bot._swapCheck = nil
	return passed
end

local function SkipCase(bot, now, names, reason)
	local cond = M.CONDITIONS[state.cond]
	local c = Count(cond)
	c.skipped = c.skipped + #M.CASES[state.case]
	Log(
		"[SHy-SWAP] t=%.0f %s probe cond=%s case=%d result=skipped reason=%s layout=%s",
		DotaTime(),
		HeroName(bot),
		cond,
		state.case,
		tostring(reason),
		Layout(names)
	)
	state.lastSkip = reason
	state.case = state.case + 1
	state.setupAt = nil
	state.nextAt = now + 0.2
end

local function StartCase(bot, now, names)
	local cond = M.CONDITIONS[state.cond]
	local roles = M.PickRoles(names)
	Log(
		"[SHy-SWAP] t=%.0f %s probe cond=%s case=%d layout=%s",
		DotaTime(),
		HeroName(bot),
		cond,
		state.case,
		Layout(names)
	)
	state.setupAt = nil
	state.modesStarted = state.modesStarted or cond == "modes"
	state.roles = roles
	state.step = 1
	state.phase = "order"
	state.nextAt = now
end

local function Order(bot, now)
	local stepDef = M.CASES[state.case][state.step]
	local a, b = state.roles[stepDef[1]], state.roles[stepDef[2]]
	local names = Names(bot)
	local check = {
		a = a,
		b = b,
		before = { a = names[a], b = names[b] },
		at = now,
		mode = bot:GetActiveMode(),
		action = bot:GetCurrentActionType(),
	}
	check.passed = Swap(bot, a, b)
	state.check = check
	state.phase = "check"
end

local function CheckStep(bot, now)
	local check = state.check
	local names = Names(bot)
	if check.after05 == nil then
		if now < check.at + 0.5 then
			return
		end
		check.after05 = { a = names[check.a], b = names[check.b] }
	end
	if now < check.at + 3 then
		return
	end
	local after3 = { a = names[check.a], b = names[check.b] }
	local cond = M.CONDITIONS[state.cond]
	local c = Count(cond)
	local result
	if not check.passed then
		result = "blocked"
		c.blocked = c.blocked + 1
	else
		result = M.Classify(check.before, check.after05, after3)
		if result == "same" then
			c.skipped = c.skipped + 1
		else
			c.tries = c.tries + 1
		end
		if result == "moved" or result == "moved-late" then
			c.moved = c.moved + 1
		end
	end
	Log(
		"[SHy-SWAP] t=%.0f %s probe cond=%s case=%d step=%d order=%d->%d before=%s,%s after05=%s,%s after3=%s,%s result=%s mode=%s action=%s layout=%s",
		DotaTime(),
		HeroName(bot),
		cond,
		state.case,
		state.step,
		check.a,
		check.b,
		Short(check.before.a),
		Short(check.before.b),
		Short(check.after05.a),
		Short(check.after05.b),
		Short(after3.a),
		Short(after3.b),
		result,
		tostring(check.mode),
		tostring(check.action),
		Layout(names)
	)
	local caseDef = M.CASES[state.case]
	if state.step < #caseDef then
		state.step = state.step + 1
		state.phase = "order"
		state.nextAt = check.at + math.max(3.1, caseDef.gap or 0)
	else
		state.case = state.case + 1
		state.phase = "setup"
		state.nextAt = now + 0.2
	end
end

-- A purchase result code by its PURCHASE_ITEM_* name (the [SHy-API] dump lists the constants), else the number.
local PURCHASE_RESULTS = {
	"PURCHASE_ITEM_SUCCESS",
	"PURCHASE_ITEM_OUT_OF_STOCK",
	"PURCHASE_ITEM_DISALLOWED_ITEM",
	"PURCHASE_ITEM_INSUFFICIENT_GOLD",
	"PURCHASE_ITEM_NOT_AT_HOME_SHOP",
	"PURCHASE_ITEM_NOT_AT_SIDE_SHOP",
	"PURCHASE_ITEM_NOT_AT_SECRET_SHOP",
	"PURCHASE_ITEM_INVALID_ITEM_NAME",
}
local function PurchaseResultName(result)
	for _, name in ipairs(PURCHASE_RESULTS) do
		if result ~= nil and _G[name] == result then
			return (string.gsub(name, "^PURCHASE_ITEM_", "")) .. "(" .. tostring(result) .. ")"
		end
	end
	return tostring(result)
end

-- What the last sell did, read REFILL_CHECK later: the hole stayed, or a backpack item moved into it (game 075).
-- ourSwaps = swap orders our code gave this bot since the sell (global_overrides.lua counts them): 0 means the
-- engine moved the item, not our code.
local function CheckSell(bot, names)
	local sell = state.lastSell
	state.lastSell = nil
	local from = M.DetectRefill(sell.names, names, sell.slot)
	local what = from ~= nil and tostring(from) or (names[sell.slot] == "-" and "none" or "unsold")
	if from ~= nil then
		state.refills = true
	end
	Log(
		"[SHy-SWAP] t=%.0f %s probe setup sold=%d refill=%s ourSwaps=%d gold=%d layout=%s",
		DotaTime(),
		HeroName(bot),
		sell.slot,
		what,
		(bot._swapCalls or 0) - sell.swapCalls,
		bot:GetGold(),
		Layout(names)
	)
end

-- Setup before each case, from the slots as they are: one buy or sell per 0.3s, at the fountain shop only, at most
-- SETUP_SECONDS per case; a case that can't be set up is skipped with the reason.
local function Setup(bot, now, names)
	if state.lastSell ~= nil then
		CheckSell(bot, names)
	end
	if state.case > #M.CASES then
		state.cond = state.cond + 1
		state.case = 1
		if state.cond > #M.CONDITIONS then
			Finish(bot, "complete")
			return
		end
		state.nextAt = now + 0.2
		return
	end
	local caseDef = M.CASES[state.case]
	state.setupAt = state.setupAt or now
	local action, arg
	if M.CaseReady(M.PickRoles(names), caseDef) then
		action = "ready"
	elseif bot:DistanceFromFountain() >= 900 then
		action, arg = "skip", "away-from-shop"
	elseif now - state.setupAt > M.SETUP_SECONDS then
		action, arg = "skip", "setup-timeout-" .. table.concat(M.MissingRoles(M.PickRoles(names), caseDef), "+")
	else
		action, arg = M.SetupStep(
			names,
			bot:GetGold(),
			caseDef,
			{ buys = state.buys, failed = state.failed, refills = state.refills }
		)
	end
	if action == "buy" then
		local result = bot:ActionImmediate_PurchaseItem(arg)
		local ok = result == nil or result == (PURCHASE_ITEM_SUCCESS or -1)
		if ok then
			state.buys = state.buys + 1
		else
			-- Game 074: the same out-of-stock order repeated until the buy cap. Try the next candidate instead.
			state.failed[arg] = true
		end
		Log(
			"[SHy-SWAP] t=%.0f %s probe setup case=%d buy=%s result=%s gold=%d before=%s",
			DotaTime(),
			HeroName(bot),
			state.case,
			Short(arg),
			PurchaseResultName(result),
			bot:GetGold(),
			Layout(names)
		)
		state.nextAt = now + 0.3
		return
	end
	if action == "sell" then
		local item = bot:GetItemInSlot(arg)
		if item ~= nil then
			state.lastSell = { slot = arg, names = names, swapCalls = bot._swapCalls or 0 }
			bot:ActionImmediate_SellItem(item)
		end
		Log(
			"[SHy-SWAP] t=%.0f %s probe setup case=%d sell=%d gold=%d before=%s",
			DotaTime(),
			HeroName(bot),
			state.case,
			arg,
			bot:GetGold(),
			Layout(names)
		)
		state.nextAt = now + M.REFILL_CHECK
		return
	end
	if action == "skip" then
		SkipCase(bot, now, names, arg)
		return
	end
	if state.case == 1 and M.CONDITIONS[state.cond] == "idle" and not state.cleared then
		state.cleared = true
		bot:Action_ClearActions(true)
	end
	StartCase(bot, now, names)
end

local function Run(bot, now)
	if state.phase == "check" then
		CheckStep(bot, now)
		return
	end
	if now < (state.nextAt or -999) then
		return
	end
	if state.phase == "order" then
		Order(bot, now)
		return
	end
	-- setup (also between cases); StartCase moves on to "order".
	Setup(bot, now, Names(bot))
end

-- ItemUsageThink: runs the probe; true while it owns this bot (skip the rest of the item think).
function M.Tick(bot)
	if bot == nil then
		return false
	end
	UseTeamState()
	if not Decide() or not IsProbeBot(bot) then
		return false
	end
	local now = DotaTime()
	if state.phase == "done" then
		-- One reminder 60s later when nobody has typed !about yet (#217 notes the answer in Fu.Role).
		if state.chat ~= nil and now > state.doneAt + 60 then
			local okFu, Fu = pcall(require, GetScriptDirectory() .. "/lib/func_utils")
			local answered = okFu and Fu ~= nil and Fu.Role ~= nil and Fu.Role.AboutAnsweredAt ~= nil
			if not answered then
				pcall(bot.ActionImmediate_Chat, bot, state.chat, true)
			end
			state.chat = nil
		end
		return false
	end
	if not bot:IsAlive() or now > M.DEADLINE then
		Finish(bot, bot:IsAlive() and "deadline" or "dead")
		return false
	end
	local cond = M.CONDITIONS[state.cond]
	-- Held for idle and busy, and for the setup before "modes" (at the shop); never again once "modes" started.
	local held = cond ~= "modes" or not state.modesStarted
	if held then
		Hold(bot, now)
		if not state.firstClear then
			state.firstClear = true
			bot:Action_ClearActions(true)
		end
		if cond == "busy" then
			state.spot = state.spot or bot:GetLocation()
			local side = (math.floor(now / 1.5) % 2 == 0) and 100 or -100
			bot:Action_MoveToLocation(state.spot + Vector(side, 0, 0))
		end
	else
		Release(bot)
	end
	local ok, err = pcall(Run, bot, now)
	if not ok then
		Log("[SHy-SWAP] t=%.0f %s probe error=%s", DotaTime(), HeroName(bot), tostring(err))
		Finish(bot, "error")
		return false
	end
	return true
end

return M
