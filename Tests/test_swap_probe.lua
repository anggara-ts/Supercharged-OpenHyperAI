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
	local before = { a = "item_clarity", b = "item_faerie_fire" }
	local traded = { a = "item_faerie_fire", b = "item_clarity" }
	T.eq(P.Classify(before, traded, traded), "moved", "traded at 0.5s and 3s")
	T.eq(P.Classify(before, before, traded), "moved-late", "traded only by 3s")
	T.eq(P.Classify(before, traded, before), "reverted", "traded, then back")
	T.eq(P.Classify(before, before, before), "noop", "never changed")
	T.eq(P.Classify(before, before, { a = "-", b = "item_clarity" }), "other", "changed some other way")
	-- Into an empty slot.
	local intoEmpty = { a = "item_clarity", b = "-" }
	T.eq(P.Classify(intoEmpty, { a = "-", b = "item_clarity" }, { a = "-", b = "item_clarity" }), "moved", "moved")
	T.eq(P.Classify({ a = "-", b = "-" }, { a = "-", b = "-" }, { a = "-", b = "-" }), "same", "nothing to swap")
end)

T.test("swap probe: role slots", function()
	local P = load()
	local F, C = "item_faerie_fire", "item_clarity"
	-- The layout after setup: 4 main items, 2 in the backpack.
	local roles = P.PickRoles(slots({ C, F, F, F, "-", "-", F, F, "-" }))
	T.ok(roles ~= nil, "roles found")
	T.eq(roles.b1, 6, "backpack item")
	T.eq(roles.b2, 8, "empty backpack slot")
	T.eq(roles.m2, 4, "empty main slot")
	T.eq(roles.m1, 0, "main item named unlike the backpack item")
	-- Clarity in the backpack: the main item can be any filler.
	roles = P.PickRoles(slots({ F, F, F, F, "-", "-", C, F, "-" }))
	T.eq(roles.m1, 0, "a filler against the Clarity")
	-- No backpack item, a full backpack, a full main inventory, or only same names: no set.
	T.eq(P.PickRoles(slots({ C, F, F, F, F, "-", "-", "-", "-" })), nil, "empty backpack")
	T.eq(P.PickRoles(slots({ C, F, F, "-", "-", "-", F, F, F })), nil, "full backpack")
	T.eq(P.PickRoles(slots({ C, F, F, F, F, F, F, "-", "-" })), nil, "full main inventory")
	T.eq(P.PickRoles(slots({ F, F, F, "-", "-", "-", F, "-", "-" })), nil, "only fillers")
end)

T.test("swap probe: setup from an empty inventory", function()
	local P = load()
	local F, C = "item_faerie_fire", "item_clarity"
	local list = { "-", "-", "-", "-", "-", "-", "-", "-", "-" }
	local gold, buys = 600, 0
	-- Simulate the engine: a buy takes the first empty main slot, else the first empty backpack slot.
	local function place(item)
		for i = 1, 9 do
			if list[i] == "-" then
				list[i] = item
				return
			end
		end
	end
	local sold = 0
	for _ = 1, 20 do
		local action, arg = P.SetupStep(slots(list), gold, buys)
		if action == "buy" then
			buys = buys + 1
			gold = gold - (arg == C and 60 or 65)
			place(arg)
		elseif action == "sell" then
			sold = sold + 1
			list[arg + 1] = "-"
		else
			T.eq(action, "ready", "setup ends ready")
			break
		end
	end
	T.eq(buys, 8, "Clarity + 7 Faerie Fires")
	T.eq(sold, 2, "two main fillers sold")
	T.eq(table.concat(list, ","), table.concat({ C, F, F, F, "-", "-", F, F, "-" }, ","), "layout")
	T.ok(P.PickRoles(slots(list)) ~= nil, "every case can run")
	-- Out of gold, or too many buys: stop.
	T.eq((P.SetupStep(slots({ "-", "-", "-", "-", "-", "-", "-", "-", "-" }), 10, 0)), "abort", "no gold")
	T.eq((P.SetupStep(slots({ C, "-", "-", "-", "-", "-", "-", "-", "-" }), 600, P.MAX_BUYS)), "abort", "buy cap")
end)

T.test("swap probe: restore after a backpack item moved in", function()
	local P = load()
	local F, C = "item_faerie_fire", "item_clarity"
	-- Case 4 moved one Fire into the main slots: main 5, backpack 1. Buy one more (main full -> backpack), sell one.
	local names = slots({ C, F, F, F, F, "-", F, "-", "-" })
	T.eq(P.SetupStep(names, 400, 8), "buy", "buy a filler")
	names = slots({ C, F, F, F, F, F, F, "-", "-" })
	T.eq(P.SetupStep(names, 400, 9), "buy", "full main: the next one lands in the backpack")
	names = slots({ C, F, F, F, F, F, F, F, "-" })
	local action, slot = P.SetupStep(names, 400, 10)
	T.eq(action, "sell", "sell a main filler")
	T.eq(slot, 5, "the highest main filler")
end)
