-- bots/lib/systems/pause_diff.lua (#15): what a pause changes in a bot's items.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_zuus" })
	return require(GetScriptDirectory() .. "/lib/systems/pause_diff")
end

T.test("pause diff: a pause is a think gap with much more real time than game time", function()
	local R = load()
	T.eq(R.IsPause(39, 0.03), true, "game 091: a 39 s pause")
	T.eq(R.IsPause(0.4, 0.4), false, "a normal think")
	T.eq(R.IsPause(1.2, 0.1), false, "a short hitch")
	T.eq(R.IsPause(nil, 0), false)
end)

T.test("pause diff: new and gone items are counted as multisets", function()
	local R = load()
	-- Game 091, about 14:30: Zeus got a Mantle and a Mango in the stash with no buy.
	local added, gone = R.Changes({ "boots", "magic_wand", "null_talisman" }, {
		"boots",
		"magic_wand",
		"null_talisman",
		"mantle",
		"enchanted_mango",
	})
	T.eq(table.concat(added, ","), "enchanted_mango,mantle")
	T.eq(#gone, 0)
	-- A second pair of boots is new even though he had boots.
	added = R.Changes({ "boots" }, { "boots", "boots" })
	T.eq(table.concat(added, ","), "boots")
	-- An item used up during the pause shows as gone.
	local _, gone2 = R.Changes({ "tango", "clarity" }, { "tango" })
	T.eq(table.concat(gone2, ","), "clarity")
end)
