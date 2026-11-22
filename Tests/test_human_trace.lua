-- FuncLib/systems/human_trace.lua (#111): the pure parts of the human trace (change detection, names, formats).
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_lich" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/human_trace")
end

T.test("human trace: set diff for modifiers and unit counts", function()
	local H = load()
	local added, removed = H.SetDiff({ a = true, b = true }, { b = true, c = true, d = true })
	T.eq(table.concat(added, ","), "c,d", "added, sorted")
	T.eq(table.concat(removed, ","), "a", "removed")
	added, removed = H.SetDiff({ x = true }, { x = true })
	T.eq(#added + #removed, 0, "no change")
	added, removed = H.SetDiff({ lamp = 1, gate = 2 }, { lamp = 2, gate = 1 })
	T.eq(table.concat(added, ","), "lamp", "count up is added")
	T.eq(table.concat(removed, ","), "gate", "count down is removed")
	added, removed = H.SetDiff({}, {})
	T.eq(#added + #removed, 0, "empty")
end)

T.test("human trace: unit kinds and skipped units", function()
	local H = load()
	T.eq(H.Kind("#DOTA_OutpostName_South"), "outpost", "7.42 outpost name (game 073 unit survey)")
	T.eq(H.Kind("npc_dota_watch_tower"), "outpost", "old outpost name")
	T.eq(H.Kind("npc_dota_lantern"), "watcher", "watcher")
	T.eq(H.Kind("npc_dota_unit_twin_gate"), nil, "twin gate is other")
	T.ok(H.Skip("npc_dota_hero_lich"), "hero skipped")
	T.ok(H.Skip("npc_dota_creep_badguys_melee"), "creep skipped")
	T.ok(H.Skip("npc_dota_goodguys_tower1_mid"), "lane tower skipped")
	T.ok(H.Skip("dota_fountain"), "fountain skipped")
	T.ok(not H.Skip("npc_dota_watch_tower"), "outpost kept although it says tower")
	T.ok(not H.Skip("npc_dota_xp_fountain"), "wisdom shrine kept")
	T.ok(not H.Skip("npc_dota_unit_twin_gate"), "twin gate kept")
	T.ok(not H.Skip(""), "unnamed unit kept")
	T.ok(H.Skip("npc_dota_neutral_kobold"), "neutral creep skipped (camps sit next to outposts)")
	T.ok(H.Skip("npc_dota_roshan"), "roshan skipped")
end)

T.test("human trace: near choice puts an outpost first", function()
	local H = load()
	local outpost = { kind = "outpost", dist = 650 }
	local gate = { kind = "other", dist = 100 }
	local spot = { kind = "watcher-spot", dist = 300 }
	T.ok(H.Better(outpost, gate), "a far outpost beats a close other object")
	T.ok(not H.Better(gate, outpost), "and not the other way round")
	T.ok(H.Better(spot, gate), "a watcher spot beats other")
	T.ok(H.Better({ kind = "other", dist = 50 }, gate), "same kind: closer wins")
	T.ok(H.Better(gate, nil), "anything beats nothing")
	T.ok(not H.Better(nil, gate), "nothing beats nothing")
end)

T.test("human trace: first bot slot", function()
	local H = load()
	T.eq(H.FirstBotSlot({ true, true, true, true, false }), 1, "human in slot 5")
	T.eq(H.FirstBotSlot({ false, true, true, true, true }), 2, "human in slot 1")
	T.eq(H.FirstBotSlot({ false, false, false, false, false }), nil, "all human")
end)

T.test("human trace: ability key ignores castable and level", function()
	local H = load()
	local a = H.AbilityKey({
		{ slot = 0, name = "lich_frost_nova", hidden = false, castable = true, level = 1 },
		{ slot = 5, name = "ability_capture", hidden = true, castable = false, level = 1 },
	})
	local b = H.AbilityKey({
		{ slot = 0, name = "lich_frost_nova", hidden = false, castable = false, level = 2 },
		{ slot = 5, name = "ability_capture", hidden = true, castable = true, level = 1 },
	})
	T.eq(a, b, "same list")
	T.eq(a, "0:lich_frost_nova:false,5:ability_capture:true", "format")
	local c = H.AbilityKey({ { slot = 0, name = "lich_frost_nova", hidden = false } })
	T.ok(a ~= c, "a slot gone is a change")
end)

T.test("human trace: value text and chunks", function()
	local H = load()
	T.eq(H.Describe(nil), "-", "nil")
	T.eq(H.Describe(true), "true", "boolean")
	T.eq(H.Describe(3), "3", "integer")
	T.eq(H.Describe(0.256), "0.26", "fraction")
	T.eq(H.Describe("n/a"), "n/a", "string")
	T.eq(H.Describe({ x = 10.4, y = -20.6 }), "10,-21", "vector-like")
	T.eq(
		H.Describe({
			GetUnitName = function()
				return "npc_dota_lantern"
			end,
		}),
		"npc_dota_lantern",
		"unit"
	)
	T.eq(
		H.Describe({
			GetName = function()
				return "ability_lamp_use"
			end,
		}),
		"ability_lamp_use",
		"ability"
	)
	T.eq(table.concat(H.Chunks({ "a", "b", "c" }, 2), "|"), "a,b|c", "chunks")
	T.eq(#H.Chunks({}, 10), 1, "empty list is one empty chunk")
end)
