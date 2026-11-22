-- FuncLib/systems/curse_log.lua ([OHA-CURSE]): hits on enemies under Winter's Curse. Log only: the throttle, the
-- counts per curse, the end of a curse and who counts.
local T = ...

local CURSE = "modifier_winter_wyvern_winters_curse"

-- No Rubick or Winter Wyvern unless a test adds her (the stub's default Radiant has a Rubick).
local ALLIES = {
	"npc_dota_hero_lion",
	"npc_dota_hero_lina",
	"npc_dota_hero_tidehunter",
	"npc_dota_hero_sven",
	"npc_dota_hero_zuus",
}
local ENEMIES = {
	"npc_dota_hero_axe",
	"npc_dota_hero_earthshaker",
	"npc_dota_hero_crystal_maiden",
	"npc_dota_hero_lich",
	"npc_dota_hero_pudge",
}
local WITH_WYVERN = {
	"npc_dota_hero_winter_wyvern",
	"npc_dota_hero_axe",
	"npc_dota_hero_earthshaker",
	"npc_dota_hero_lich",
	"npc_dota_hero_pudge",
}

local function load(enemies)
	T.stub.reset({ hero = "npc_dota_hero_lion", allies = ALLIES, enemies = enemies or ENEMIES })
	return require(GetScriptDirectory() .. "/FuncLib/systems/curse_log")
end

local function printedCurse()
	local lines = {}
	for _, line in ipairs(T.stub.printed) do
		if string.find(line, "[OHA-CURSE]", 1, true) == 1 then
			lines[#lines + 1] = line
		end
	end
	return lines
end

local function curse(unit, left)
	unit.HasModifier = function(_, name)
		return name == CURSE
	end
	unit.GetModifierByName = function(_, name)
		return name == CURSE and 3 or -1
	end
	unit.GetModifierRemainingDuration = function()
		return left
	end
end

local function fakeAbility(name)
	return {
		GetName = function()
			return name
		end,
		GetDamageType = function()
			return 2
		end,
		GetAbilityDamage = function()
			return 600
		end,
	}
end

T.test("curse log: one hit line per kind every 2s", function()
	local C = load()
	local state = C.NewState()
	T.eq(C.Hit(state, 10, "attack", 3, "swing"), true, "first attack prints")
	T.eq(C.Hit(state, 11, "attack", 2, "swing"), false, "1s later: throttled")
	T.eq(C.Hit(state, 11, "spell", 2, "lion_finger_of_death"), true, "a spell has its own throttle")
	T.eq(C.Hit(state, 12, "attack", 1, nil), true, "2s later prints again")
	T.eq(state.attacks, 2, "two swings counted")
	T.eq(state.spells, 1, "one spell")
end)

T.test("curse log: a spell counts once per ability per curse", function()
	local C = load()
	local state = C.NewState()
	for i = 0, 5 do
		C.Hit(state, 10 + i * 0.1, "spell", 2, "lion_finger_of_death")
	end
	C.Hit(state, 10.6, "spell", 2, "item_dagon")
	T.eq(state.spells, 2, "re-issued order is one cast")
	T.eq(state.gameSpells, 2, "game total")
end)

T.test("curse log: the curse ends after its last known end, the game totals stay", function()
	local C = load()
	local state = C.NewState()
	C.Hit(state, 10, "attack", 3, "swing")
	C.Hit(state, 11, "attack", 1, "swing") -- ends at 12, earlier than 13: keeps 13
	T.eq(C.Ended(state, 13), nil, "still running at 13")
	T.eq(C.Ended(state, 13.4), nil, "within the grace")
	local attacks, spells = C.Ended(state, 13.6)
	T.eq(attacks, 2, "attacks of the curse")
	T.eq(spells, 0, "no spells")
	T.eq(C.Ended(state, 20), nil, "reported once")
	C.Hit(state, 30, "attack", nil, "swing") -- unknown time left: base 2s
	T.eq(C.Ended(state, 32.4), nil, "base duration")
	attacks = C.Ended(state, 32.6)
	T.eq(attacks, 1, "second curse counts from 0")
	T.eq(state.gameAttacks, 3, "game total")
	T.eq(C.ClampLeft(99), 6, "capped at max_duration")
	T.eq(C.ClampLeft(-1), 2, "bad read: base duration")
end)

T.test("curse log: line formats", function()
	local C = load()
	T.eq(
		C.HitLine(612.4, "npc_dota_hero_lion", "spell", "npc_dota_hero_axe", "lion_finger_of_death", 2.25, " dmgType=2"),
		"[OHA-CURSE] t=612 lion hit kind=spell hero=lion target=axe ability=lion_finger_of_death curseLeft=2.2 dmgType=2",
		"spell hit"
	)
	T.eq(
		C.HitLine(612, "npc_dota_hero_lion", "attack", "npc_dota_hero_axe", nil, nil),
		"[OHA-CURSE] t=612 lion hit kind=attack hero=lion target=axe ability=attack curseLeft=?",
		"attack hit, unknown time"
	)
	local state = C.NewState()
	state.gameAttacks, state.gameSpells = 7, 1
	T.eq(
		C.SummaryLine(615, "npc_dota_hero_lion", state, 4, 1),
		"[OHA-CURSE] t=615 lion summary hero=lion attacks=4 spells=1 gameAttacks=7 gameSpells=1",
		"summary"
	)
end)

T.test("curse log: a unit-target cast on a cursed enemy prints, Winter Wyvern and allies do not count", function()
	local C = load(WITH_WYVERN)
	local bot = GetBot()
	local enemy = T.stub.teams[TEAM_DIRE][2]
	local ally = T.stub.teams[TEAM_RADIANT][2]
	curse(enemy, 2.5)
	curse(ally, 2.5)
	C.OnCast(bot, fakeAbility("lion_finger_of_death"), ally)
	T.eq(#printedCurse(), 0, "an ally under the curse (a cursed bot's frozen ally) is not logged")
	C.OnCast(bot, fakeAbility("lion_finger_of_death"), enemy)
	local lines = printedCurse()
	T.eq(#lines, 1, "cursed enemy logged")
	T.ok(string.find(lines[1] or "", "kind=spell hero=lion", 1, true) ~= nil, "kind and hero: " .. tostring(lines[1]))
	T.ok(string.find(lines[1] or "", "dmgType=2 dmg=600", 1, true) ~= nil, "damage fields")
	local wyvern = T.stub.teams[TEAM_DIRE][1]
	curse(bot, 2.5)
	C.OnCast(wyvern, fakeAbility("winter_wyvern_splinter_blast"), bot)
	T.eq(#printedCurse(), 1, "Winter Wyvern's own casts are not logged")
end)

T.test("curse log: no curse caster in the game, nothing is read", function()
	local C = load()
	local enemy = T.stub.teams[TEAM_DIRE][2]
	curse(enemy, 2.5)
	C.OnCast(GetBot(), fakeAbility("lion_finger_of_death"), enemy)
	T.eq(#printedCurse(), 0, "no Winter Wyvern or Rubick")
end)

T.test("curse log: Watch counts swings at a cursed enemy and prints the summary when the curse ends", function()
	local C = load(WITH_WYVERN)
	local bot = GetBot()
	local enemy = T.stub.teams[TEAM_DIRE][2]
	curse(enemy, 2)
	local lastAttack = 0
	bot.GetAttackTarget = function()
		return enemy
	end
	bot.GetLastAttackTime = function()
		return lastAttack
	end
	T.stub.time = 100
	C.Watch(bot) -- first look: the old last-attack time is not a new swing
	lastAttack = 100.2
	T.stub.time = 100.3
	C.Watch(bot)
	lastAttack = 101
	T.stub.time = 101.1
	C.Watch(bot)
	bot.GetAttackTarget = function()
		return nil
	end
	T.stub.time = 104
	C.Watch(bot)
	local lines = printedCurse()
	T.eq(#lines, 2, "one hit line (throttled) and one summary: " .. table.concat(lines, " | "))
	T.ok(string.find(lines[2] or "", "summary hero=lion attacks=2 spells=0", 1, true) ~= nil, tostring(lines[2]))
end)
