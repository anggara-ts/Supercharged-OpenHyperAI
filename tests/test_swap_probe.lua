-- #218: the item swap probe's pure rules (bots/lib/systems/swap_probe.lua).
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_lion" })
	return require(GetScriptDirectory() .. "/lib/systems/swap_probe")
end

-- names[0..8] from a list of 9 names ("-" = empty).
local function slots(list)
	local names = {}
	for slot = 0, 8 do
		names[slot] = list[slot + 1]
	end
	return names
end

T.test("swap probe: result of one swap", function()
	local P = load()
	local before = { a = "item_enchanted_mango", b = "item_faerie_fire" }
	local traded = { a = "item_faerie_fire", b = "item_enchanted_mango" }
	T.eq(P.Classify(before, traded, traded), "moved", "traded at 0.5s and 3s")
	T.eq(P.Classify(before, before, traded), "moved-late", "traded only by 3s")
	T.eq(P.Classify(before, traded, before), "reverted", "traded, then back")
	T.eq(P.Classify(before, before, before), "noop", "never changed")
	T.eq(P.Classify(before, before, { a = "-", b = "item_enchanted_mango" }), "other", "changed some other way")
	-- Into an empty slot.
	local intoEmpty = { a = "item_faerie_fire", b = "-" }
	local moved = { a = "-", b = "item_faerie_fire" }
	T.eq(P.Classify(intoEmpty, moved, moved), "moved", "moved")
	T.eq(P.Classify({ a = "-", b = "-" }, { a = "-", b = "-" }, { a = "-", b = "-" }), "same", "nothing to swap")
end)

T.test("swap probe: role slots", function()
	local P = load()
	local F, M = "item_branches", "item_faerie_fire"
	-- The layout after setup: 4 main items, 2 in the backpack.
	local roles = P.PickRoles(slots({ M, F, F, F, "-", "-", F, F, "-" }))
	T.eq(roles.b1, 6, "backpack item")
	T.eq(roles.b2, 8, "empty backpack slot")
	T.eq(roles.m2, 4, "empty main slot")
	T.eq(roles.m1, 0, "main item named unlike the backpack item")
	for i, caseDef in ipairs(P.CASES) do
		T.ok(P.CaseReady(roles, caseDef), "case " .. i .. " can run")
	end
	-- The marker in the backpack: the main item can be any filler.
	roles = P.PickRoles(slots({ F, F, F, F, "-", "-", M, F, "-" }))
	T.eq(roles.m1, 0, "a filler against the marker")
	-- Missing slots: only the cases that need them wait.
	roles = P.PickRoles(slots({ M, F, F, F, F, F, "-", "-", "-" }))
	T.eq(P.CaseReady(roles, P.CASES[1]), false, "no backpack item")
	roles = P.PickRoles(slots({ M, F, F, "-", "-", "-", F, F, F }))
	T.eq(P.CaseReady(roles, P.CASES[1]), true, "full backpack: main <-> backpack still runs")
	T.eq(P.CaseReady(roles, P.CASES[3]), false, "full backpack: no empty backpack slot")
	roles = P.PickRoles(slots({ M, F, F, F, F, F, F, "-", "-" }))
	T.eq(P.CaseReady(roles, P.CASES[4]), false, "full main inventory")
	roles = P.PickRoles(slots({ F, F, F, "-", "-", "-", F, "-", "-" }))
	T.eq(P.CaseReady(roles, P.CASES[1]), false, "only fillers: a swap would not show")
end)

T.test("swap probe: role pairs and missing roles", function()
	local P = load()
	local F, M = "item_branches", "item_faerie_fire"
	-- A filler in the first backpack slot pairs with nothing; the marker in slot 7 pairs with a main filler.
	local roles = P.PickRoles(slots({ F, F, F, F, F, F, F, M, "-" }))
	T.eq(roles.b1, 7, "the backpack item that has a pair")
	T.eq(roles.m1, 0, "its main partner")
	T.eq(table.concat(P.MissingRoles(roles, P.CASES[4]), ","), "m2", "case 4 lacks only an empty main slot")
	roles = P.PickRoles(slots({ M, F, "-", "-", "-", "-", "-", "-", "-" }))
	T.eq(roles.m1, 0, "no backpack item: any main item")
	T.eq(table.concat(P.MissingRoles(roles, P.CASES[1]), ","), "b1", "case 1 lacks a backpack item")
end)

T.test("swap probe: a sold main slot refilled from the backpack", function()
	local P = load()
	local F, M = "item_branches", "item_faerie_fire"
	local before = slots({ M, F, F, F, F, F, F, F, "-" })
	-- Game 075: sell=5, and 0.3s later slot 5 held slot 6's branch.
	T.eq(P.DetectRefill(before, slots({ M, F, F, F, F, F, "-", F, "-" }), 5), 6, "refilled from slot 6")
	T.eq(P.DetectRefill(before, slots({ M, F, F, F, F, "-", F, F, "-" }), 5), nil, "the hole stayed")
	T.eq(P.DetectRefill(before, before, 5), nil, "not sold yet")
end)

-- Game 075 (t=-86..-78): main full and two branches in the backpack; the old setup wanted 4 main + 2 backpack, so it
-- sold slot 5, the engine moved slot 6's branch into it, it bought a branch again, and so on until the buy cap.
T.test("swap probe: game 075 layout runs cases 1-3 without buying or selling", function()
	local P = load()
	local F, M = "item_branches", "item_faerie_fire"
	local names = slots({ M, F, F, F, F, F, "-", F, "-" })
	for i = 1, 3 do
		T.eq(P.SetupStep(names, 205, P.CASES[i], { buys = 20 }), "ready", "case " .. i .. " ready as it is")
	end
	-- Case 4 needs an empty main slot: one sell, then (refill seen) skipped, never a buy.
	local action, slot = P.SetupStep(names, 205, P.CASES[4], { buys = 20 })
	T.eq(action, "sell", "one sell to make a main hole")
	T.eq(slot, 5, "the highest main filler")
	local reason
	action, reason = P.SetupStep(names, 205, P.CASES[4], { buys = 20, refills = true })
	T.eq(action, "skip", "skipped once a refill was seen")
	T.eq(reason, "main-refilled", "reason")
end)

T.test("swap probe: a failed buy moves on to the next candidate", function()
	local P = load()
	local empty = slots({ "-", "-", "-", "-", "-", "-", "-", "-", "-" })
	local case1 = P.CASES[1]
	-- Game 074: the Enchanted Mango was out of stock (code 82) and the same order repeated until the buy cap.
	local action, item = P.SetupStep(empty, 600, case1, { failed = {} })
	T.eq(action, "buy", "buy")
	T.eq(item, P.MARKERS[1].name, "first marker")
	action, item = P.SetupStep(empty, 600, case1, { failed = { [P.MARKERS[1].name] = true } })
	T.eq(item, P.MARKERS[2].name, "next marker after a failed buy")
	local allFailed = {}
	for _, list in ipairs({ P.MARKERS, P.FILLERS }) do
		for _, entry in ipairs(list) do
			allFailed[entry.name] = true
		end
	end
	local reason
	action, reason = P.SetupStep(empty, 600, case1, { failed = allFailed })
	T.eq(action, "skip", "every candidate failed")
	T.eq(reason, "no-main-buyable", "reason")
	action, reason = P.SetupStep(empty, 10, case1, {})
	T.eq(reason, "gold", "gold")
	action, reason = P.SetupStep(empty, 600, case1, { buys = P.MAX_BUYS })
	T.eq(reason, "buy-cap", "buy cap")
	-- No candidate has a stock limit, and none is refused by #15's pull rule (7.42 items.txt).
	for _, entry in ipairs(P.MARKERS) do
		T.ok(entry.name ~= "item_enchanted_mango" and entry.name ~= "item_clarity", entry.name)
	end
end)

-- A small engine: a buy takes the first empty main slot, else the first empty backpack slot; a sell refunds the
-- cost (within 10s, game 075: 150 -> 205 for a branch). refill = an emptied main slot takes the first backpack item
-- at once (game 075). A swap moves only a backpack item into an EMPTY main slot (match logs).
local function newInventory(P, gold, refill)
	local inv = { list = { "-", "-", "-", "-", "-", "-", "-", "-", "-" }, gold = gold, buys = 0, cost = {} }
	inv.refills = false
	function inv.names()
		return slots(inv.list)
	end
	-- Setup for one case as Setup() runs it; returns "ready" or "skip", reason.
	function inv.setup(caseDef)
		for _ = 1, 30 do
			local action, arg, cost = P.SetupStep(inv.names(), inv.gold, caseDef, {
				buys = inv.buys,
				refills = inv.refills,
			})
			if action == "buy" then
				inv.buys = inv.buys + 1
				inv.gold = inv.gold - cost
				inv.cost[arg] = cost
				for i = 1, 9 do
					if inv.list[i] == "-" then
						inv.list[i] = arg
						break
					end
				end
			elseif action == "sell" then
				local before = inv.names()
				inv.gold = inv.gold + inv.cost[inv.list[arg + 1]]
				inv.list[arg + 1] = "-"
				if refill then
					for bag = 7, 9 do
						if inv.list[bag] ~= "-" then
							inv.list[arg + 1], inv.list[bag] = inv.list[bag], "-"
							break
						end
					end
				end
				inv.refills = inv.refills or P.DetectRefill(before, inv.names(), arg) ~= nil
			else
				return action, arg
			end
		end
		return "skip", "loop"
	end
	function inv.swap(a, b)
		local list = inv.list
		local nameA, nameB = list[a + 1], list[b + 1]
		if
			(a >= 6 and b <= 5 and nameB == "-" and nameA ~= "-")
			or (b >= 6 and a <= 5 and nameA == "-" and nameB ~= "-")
		then
			list[a + 1], list[b + 1] = nameB, nameA
		end
	end
	-- Three conditions at the shop; returns ran, skip reasons.
	function inv.run()
		local ran, reasons = 0, {}
		for _ = 1, 3 do
			for i, caseDef in ipairs(P.CASES) do
				local action, reason = inv.setup(caseDef)
				if action == "ready" then
					ran = ran + 1
					local roles = P.PickRoles(inv.names())
					for _, stepDef in ipairs(caseDef) do
						inv.swap(roles[stepDef[1]], roles[stepDef[2]])
					end
				else
					reasons[#reasons + 1] = i .. ":" .. tostring(reason)
				end
			end
		end
		return ran, reasons
	end
	return inv
end

T.test("swap probe: setup from an empty inventory when a sold main slot stays empty", function()
	local P = load()
	local inv = newInventory(P, 600, false)
	local ran, reasons = inv.run()
	T.eq(table.concat(reasons, ","), "", "no case skipped")
	T.eq(ran, 15, "every case in every condition ran")
	T.ok(inv.buys < P.MAX_BUYS, "buys: " .. inv.buys)
	T.ok(inv.gold >= 0, "gold left: " .. inv.gold)
end)

T.test("swap probe: setup when a sold main slot is refilled from the backpack (game 075)", function()
	local P = load()
	local inv = newInventory(P, 600, true)
	local ran, reasons = inv.run()
	-- Cases 1-3 run in all three conditions; 4 and 5 are skipped with the reason, never by the buy cap.
	T.eq(ran, 9, "cases 1-3 ran three times")
	T.eq(#reasons, 6, "cases 4-5 skipped")
	for _, reason in ipairs(reasons) do
		T.ok(reason:find("main%-refilled") ~= nil, "skip reason " .. reason)
	end
	T.ok(inv.buys <= 8, "a marker and a few fillers, not the buy cap: " .. inv.buys)
	T.ok(inv.gold >= 0, "gold left: " .. inv.gold)
end)
