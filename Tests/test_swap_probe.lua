-- #218: the item swap probe's pure rules (FuncLib/systems/swap_probe.lua).
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_lion" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/swap_probe")
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
	local F, M = "item_faerie_fire", "item_enchanted_mango"
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

-- A small engine: a buy takes the first empty main slot, else the first empty backpack slot; a sell refunds half.
local function newInventory(P, gold)
	local inv = { list = { "-", "-", "-", "-", "-", "-", "-", "-", "-" }, gold = gold, buys = 0 }
	function inv.names()
		return slots(inv.list)
	end
	-- Runs setup steps until ready or abort; returns the final action.
	function inv.setup(restore)
		for _ = 1, 20 do
			local action, arg = P.SetupStep(inv.names(), inv.gold, inv.buys, restore)
			if action == "buy" then
				inv.buys = inv.buys + 1
				inv.gold = inv.gold - 65
				for i = 1, 9 do
					if inv.list[i] == "-" then
						inv.list[i] = arg
						break
					end
				end
			elseif action == "sell" then
				inv.list[arg + 1] = "-"
				inv.gold = inv.gold + 32
			else
				return action, arg
			end
		end
	end
	return inv
end

T.test("swap probe: first setup from an empty inventory", function()
	local P = load()
	local F, M = "item_faerie_fire", "item_enchanted_mango"
	local inv = newInventory(P, 600)
	T.eq(inv.setup(false), "ready", "setup ends ready")
	T.eq(inv.buys, 8, "a mango and 7 Faerie Fires")
	T.eq(table.concat(inv.list, ","), table.concat({ M, F, F, F, "-", "-", F, F, "-" }, ","), "layout")
	-- Out of gold, or too many buys: stop.
	T.eq((P.SetupStep(slots({ "-", "-", "-", "-", "-", "-", "-", "-", "-" }), 10, 0, false)), "abort", "no gold")
	T.eq((P.SetupStep(slots({ M, "-", "-", "-", "-", "-", "-", "-", "-" }), 600, P.MAX_BUYS, false)), "abort", "cap")
end)

T.test("swap probe: restore after a backpack item moved in", function()
	local P = load()
	local F, M = "item_faerie_fire", "item_enchanted_mango"
	-- Case 5 moved the last Fire into the main slots: main full, backpack empty. One buy (lands in the backpack)
	-- and one sell are enough.
	local action, slot = P.SetupStep(slots({ M, F, F, F, F, F, "-", "-", "-" }), 300, 8, true)
	T.eq(action, "buy", "buy a filler")
	T.eq(slot, F, "a Fire")
	action, slot = P.SetupStep(slots({ M, F, F, F, F, F, F, "-", "-" }), 235, 9, true)
	T.eq(action, "sell", "sell a main filler")
	T.eq(slot, 5, "the highest main filler")
	T.eq(P.SetupStep(slots({ M, F, F, F, F, "-", F, "-", "-" }), 267, 9, true), "ready", "one of each is enough")
end)

-- The likely game: only a backpack item into an EMPTY main slot moves (match logs). Half refunds, 600 gold.
T.test("swap probe: three conditions at the shop never run out of slots or gold", function()
	local P = load()
	local inv = newInventory(P, 600)
	T.eq(inv.setup(false), "ready", "first setup")
	local function engineSwap(a, b)
		local list = inv.list
		local nameA, nameB = list[a + 1], list[b + 1]
		local bagToEmptyMain = (a >= 6 and b <= 5 and nameB == "-" and nameA ~= "-")
			or (b >= 6 and a <= 5 and nameA == "-" and nameB ~= "-")
		if bagToEmptyMain then
			list[a + 1], list[b + 1] = nameB, nameA
		end
	end
	local skipped, ran = 0, 0
	for _ = 1, 2 do -- idle and busy (at the shop); "modes" starts with the same restore
		for _, caseDef in ipairs(P.CASES) do
			if not P.CaseReady(P.PickRoles(inv.names()), caseDef) then
				inv.setup(true)
			end
			local roles = P.PickRoles(inv.names())
			if P.CaseReady(roles, caseDef) then
				ran = ran + 1
				for _, stepDef in ipairs(caseDef) do
					engineSwap(roles[stepDef[1]], roles[stepDef[2]])
				end
			else
				skipped = skipped + 1
			end
		end
	end
	T.eq(skipped, 0, "no case skipped at the shop")
	T.eq(ran, 10, "ten cases ran")
	-- The restore before "modes".
	if not P.CaseReady(P.PickRoles(inv.names()), P.CASES[1]) then
		inv.setup(true)
	end
	T.ok(P.CaseReady(P.PickRoles(inv.names()), P.CASES[1]), "modes can start")
	T.ok(inv.gold >= 0, "gold left: " .. inv.gold)
end)
