-- bots/lib/systems/channel_save_rules.lua (#47, game 077): a save that disables an ally (Cold Embrace, Disruption,
-- Astral Imprisonment) goes on a channelling ally only when the enemies are expected to kill it before the channel
-- ends.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_winter_wyvern" })
	return require(GetScriptDirectory() .. "/lib/systems/channel_save_rules")
end

T.test("channel save: time left from the modifier, else the channel time minus the time seen", function()
	local R = load()
	local left, src = R.ChannelLeft(2.8, 3.0, 0.2)
	T.near(left, 2.8, 1e-9)
	T.eq(src, "modifier")
	left, src = R.ChannelLeft(0, 3.0, 1.0)
	T.near(left, 2.0, 1e-9)
	T.eq(src, "ability")
	left, src = R.ChannelLeft(nil, 3.0, 5.0)
	T.near(left, 0, 1e-9, "never below 0")
	left, src = R.ChannelLeft(nil, 0, 1.0)
	T.near(left, R.UNKNOWN_LEFT, 1e-9)
	T.eq(src, "unknown")
end)

T.test("channel save: the damage window adds the cast point", function()
	local R = load()
	T.near(R.DamageWindow(2.8, 0.3), 3.1, 1e-9)
	T.near(R.DamageWindow(-1, 0.3), 0.3, 1e-9)
end)

T.test("channel save: only a lethal estimate allows the save (game 077: Undying's TP at 0.21 HP)", function()
	local R = load()
	T.ok(not R.SaveAllowed(150, 300), "the TP finishes: 150 damage on 300 HP")
	T.ok(R.SaveAllowed(300, 300), "lethal: save")
	T.ok(R.SaveAllowed(450, 300))
	T.ok(not R.SaveAllowed(100, 0), "no HP read: no save")
	T.ok(not R.SaveAllowed(nil, 300))
	T.near(R.Ratio(150, 300), 0.5, 1e-9)
	T.eq(R.Ratio(150, 0), 0)
end)
