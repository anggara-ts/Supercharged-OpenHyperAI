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
	for name in pairs(R.EITHER_WAY) do
		T.ok(seen[name], "either-way jump not in SPELLS: " .. name)
	end
	T.ok(R.EITHER_WAY.item_blink and not R.EITHER_WAY.dark_willow_shadow_realm, "Blink goes either way, the realm not")
end)

T.test("ally escape: the sample from before a jump", function()
	local R = load()
	local samples = { { t = 2090, dist = 1197 }, { t = 2090.25, dist = 1150 }, { t = 2090.5, dist = 150 } }
	T.eq(R.SampleBefore(samples, 2091, 0.8).dist, 1197, "cast at 2090.2: the newest sample before it")
	T.eq(R.SampleBefore(samples, 2091, 0.6).dist, 1150, "cast at 2090.4")
	T.eq(R.SampleBefore(samples, 2091, 1.5), nil, "cast before every sample")
	T.eq(R.SampleBefore(nil, 2091, 0.8), nil, "no samples")
	T.eq(R.SampleBefore(samples, 2091, nil), nil, "in its cast point: no time")
end)

T.test("ally escape: a jump onto the enemy is not an escape (game 091, 34:51: Dark Willow's Blink onto Axe)", function()
	local R = load()
	local counts, why = R.JumpIsEscape({ t = 2090, dist = 1197 }, 150, false)
	T.eq(counts, false, "1197 before, 150 after: an initiation")
	T.eq(why, "initiation")
	T.eq(R.JumpIsEscape({ t = 2090, dist = 1197 }, 1250, false), false, "within the margin: not away")
	counts, why = R.JumpIsEscape({ t = 2090, dist = 1197 }, 1400, false)
	T.ok(counts and why == "away", "the nearest enemy 200 further: away")
	counts, why = R.JumpIsEscape({ t = 2090, dist = 600 }, nil, false)
	T.ok(counts and why == "away", "no enemy in range after it: away")
	counts, why = R.JumpIsEscape({ t = 2090, dist = 1197 }, 150, true)
	T.ok(counts and why == "retreat", "in retreat mode: counts")
	counts, why = R.JumpIsEscape(nil, 150, false)
	T.ok(not counts and why == "unknown", "no sample before (or in its cast point): only retreat mode counts")
	counts, why = R.JumpIsEscape({ t = 2090, dist = nil }, 150, false)
	T.ok(not counts and why == "unknown", "no enemy before")
	T.ok(R.JumpIsEscape(nil, 150, true), "no sample, retreat mode: counts")
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

T.test("winter wyvern: no embrace on a Dark Willow whose script just ordered an escape realm", function()
	local _, X, willow = wyvern()
	willow._dwRealm = { why = "attack" }
	T.ok(X.EmbraceAlly(willow, "low-hp"), "an attack realm is not an escape")
	willow._dwRealm = { why = "retreat" }
	Stub.time = 2692
	T.eq(X.EmbraceAlly(willow, "low-hp"), false, "an escape realm ordered: no embrace")
	local line = printedWith("embrace-skip why=escaping")
	T.ok(line ~= nil and string.find(line, "spell=dark_willow_shadow_realm ago=order", 1, true) ~= nil, tostring(line))
end)

T.test("winter wyvern: a Blink onto an enemy is not an escape, a Blink away is (game 091, 34:51)", function()
	local bot, X, willow = wyvern()
	local enemy = Stub.teams[bot:GetTeam() == TEAM_RADIANT and TEAM_DIRE or TEAM_RADIANT][1]
	enemy._loc = willow._loc + Vector(1197, 0, 0)
	Stub.time = 2690
	X.SampleAllyEnemyDist()
	-- 0.8s ago (cast at 2090.2 of 2091 in the game) she blinked next to the enemy.
	local blink = Stub.newAbility("item_blink", willow)
	blink.GetCooldown = function()
		return 15
	end
	blink.GetCooldownTimeRemaining = function()
		return 14.2
	end
	blink.IsInAbilityPhase = function()
		return false
	end
	willow._items[0] = blink
	willow.FindItemSlot = function(_, name)
		return name == "item_blink" and 0 or -1
	end
	willow._loc = enemy._loc + Vector(150, 0, 0)
	Stub.time = 2691
	T.ok(X.EmbraceAlly(willow, "fight-core"), "a Blink onto the enemy: the save goes")
	local line = printedWith("escape-not-counted why=initiation ally=dark_willow spell=item_blink")
	T.ok(line ~= nil and string.find(line, "ago=0.80 before=1197 now=150", 1, true) ~= nil, tostring(line))
	T.eq(printedWith("embrace-skip why=escaping"), nil, "no escaping skip")
	-- The same Blink with her in retreat mode counts.
	willow.GetActiveMode = function()
		return BOT_MODE_RETREAT
	end
	Stub.time = 2691.1
	T.eq(X.EmbraceAlly(willow, "fight-core"), false, "retreat mode: an escape")
	line = printedWith("embrace-skip why=escaping")
	T.ok(line ~= nil and string.find(line, "spell=item_blink ago=0.80 jump=retreat", 1, true) ~= nil, tostring(line))
	-- Out of retreat mode, a Blink that took her 1400 from the enemy counts too.
	willow.GetActiveMode = function()
		return BOT_MODE_NONE
	end
	willow._loc = enemy._loc + Vector(1400, 0, 0)
	Stub.printed = {}
	bot._wwLogAt = nil
	Stub.time = 2691.2
	T.eq(X.EmbraceAlly(willow, "fight-core"), false, "blinked away: an escape")
	line = printedWith("embrace-skip why=escaping")
	T.ok(line ~= nil and string.find(line, "jump=away", 1, true) ~= nil, tostring(line))
end)
