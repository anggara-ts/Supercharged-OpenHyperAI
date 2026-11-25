-- bots/lib/systems/ally_escape_rules.lua and Winter Wyvern's use of it (#238, game 083 44:51): no Cold Embrace on an
-- ally that is escaping (Shadow Realm, Phase Shift, a blink...), and an embrace in its cast point is stopped when the
-- ally starts escaping.
local T = ...
local Stub = T.stub

local ALLIES = {
	"npc_dota_hero_winter_wyvern",
	"npc_dota_hero_dark_willow",
	"npc_dota_hero_lina",
	"npc_dota_hero_sven",
	"npc_dota_hero_zuus",
}

local function load()
	Stub.reset({ hero = "npc_dota_hero_winter_wyvern" })
	return require(GetScriptDirectory() .. "/lib/systems/ally_escape_rules")
end

T.test("ally escape: cast in the last second, from the cooldown", function()
	local R = load()
	local just, ago = R.JustCast(15, 14.8)
	T.ok(just, "0.2s ago")
	T.near(ago, 0.2, 1e-9)
	T.ok(not R.JustCast(15, 12), "3s ago")
	T.ok(not R.JustCast(15, 0), "ready: not on cooldown")
	T.ok(not R.JustCast(0, 3), "no cooldown read")
	T.ok(not R.JustCast(nil, 3), "nil cooldown")
	T.ok(not R.JustCast(15, 20), "time left above the cooldown: not trusted")
	T.ok(R.JustCast(15, 15.05), "a hair above: just cast")
	T.ok(R.JustCast(15, 13.6, 1.5), "a wider window")
end)

T.test("ally escape: the lists are game names, no repeats", function()
	local R = load()
	local seen = {}
	for _, name in ipairs(R.MODIFIERS) do
		T.ok(string.find(name, "^modifier_[a-z_]+$") ~= nil, name)
		T.ok(not seen[name], "repeated: " .. name)
		seen[name] = true
	end
	for _, name in ipairs(R.SPELLS) do
		T.ok(string.find(name, "^[a-z_]+$") ~= nil and string.find(name, "^modifier_") == nil, name)
		T.ok(not seen[name], "repeated: " .. name)
		seen[name] = true
	end
	T.ok(seen.modifier_dark_willow_shadow_realm_buff and seen.dark_willow_shadow_realm, "game 083: Shadow Realm")
end)

local function wyvern()
	local bot = Stub.reset({ hero = "npc_dota_hero_winter_wyvern", allies = ALLIES, slot = 1, time = 2691 })
	local ok, X = Stub.load("bots/heroes/hero_winter_wyvern")
	T.ok(ok, "hero_winter_wyvern loads: " .. tostring(X))
	local willow
	for _, hero in ipairs(Stub.heroes) do
		if hero._name == "npc_dota_hero_dark_willow" then
			willow = hero
		end
	end
	willow._loc = bot._loc + Vector(500, 0, 0)
	willow._hp = willow._maxHp * 0.17
	return bot, X, willow
end

local function printedWith(text)
	for _, line in ipairs(Stub.printed) do
		if string.find(line, text, 1, true) then
			return line
		end
	end
	return nil
end

T.test("winter wyvern: no embrace on an ally in Shadow Realm (game 083, 44:51)", function()
	local _, X, willow = wyvern()
	T.ok(X.EmbraceAlly(willow, "fight-support"), "not escaping: the save goes")
	willow.HasModifier = function(_, name)
		return name == "modifier_dark_willow_shadow_realm_buff"
	end
	Stub.time = 2692
	T.eq(X.EmbraceAlly(willow, "fight-support"), false, "in the realm: no embrace")
	local line = printedWith("embrace-skip why=escaping")
	T.ok(
		line ~= nil and string.find(line, "mod=modifier_dark_willow_shadow_realm_buff", 1, true) ~= nil,
		tostring(line)
	)
end)

T.test("winter wyvern: no embrace on an ally that cast an escape 0.2s ago", function()
	local _, X, willow = wyvern()
	local realm = willow:GetAbilityByName("dark_willow_shadow_realm")
	realm.GetCooldown = function()
		return 15
	end
	realm.GetCooldownTimeRemaining = function()
		return 14.8
	end
	T.eq(X.EmbraceAlly(willow, "low-hp"), false, "the realm is fading in: no embrace")
	local line = printedWith("embrace-skip why=escaping")
	T.ok(line ~= nil and string.find(line, "spell=dark_willow_shadow_realm ago=0.20", 1, true) ~= nil, tostring(line))
end)

T.test("winter wyvern: an embrace in its cast point stops when the ally starts escaping", function()
	local bot, X, willow = wyvern()
	local embrace = bot:GetAbilityByName("winter_wyvern_cold_embrace")
	local cleared = 0
	bot.Action_ClearActions = function()
		cleared = cleared + 1
	end
	bot._wwEmbrace = { ally = willow, at = 2691 }
	embrace.IsInAbilityPhase = function()
		return true
	end
	Stub.time = 2691.05
	X.EmbraceCastCheck()
	T.eq(cleared, 0, "not escaping: the cast goes on")
	willow.HasModifier = function(_, name)
		return name == "modifier_dark_willow_shadow_realm_fade_time"
	end
	Stub.time = 2691.1
	X.EmbraceCastCheck()
	T.eq(cleared, 1, "the realm fades in: the cast is stopped")
	T.ok(printedWith("embrace-cancel why=escaping ally=dark_willow") ~= nil, "the cancel line")
	embrace.IsInAbilityPhase = function()
		return false
	end
	Stub.time = 2691.7
	X.EmbraceCastCheck()
	T.ok(printedWith("embrace-cancel-result ally=dark_willow cast=no") ~= nil, "the result line")
	T.eq(bot._wwEmbrace, nil, "done")
end)
