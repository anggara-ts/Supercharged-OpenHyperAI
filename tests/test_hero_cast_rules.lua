-- bots/lib/systems/hero_cast_rules.lua: casts that were never made (#47): Chen Hand of God, Huskar's Shard
-- Berserker's Blood, Pugna Life Drain on an ally, Tiny Toss onto an ally, Keeper's Spirit Form heal, Phoenix's
-- Icarus Dive Stop.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_chen" })
	return require(GetScriptDirectory() .. "/lib/systems/hero_cast_rules")
end

T.test("hand of god: supports count, lower than cores", function()
	local R = rules()
	T.eq(R.HandOfGodWorth(0.45, true, true), true, "core at 45% in danger")
	T.eq(R.HandOfGodWorth(0.45, false, true), false, "support at 45%: not yet")
	T.eq(R.HandOfGodWorth(0.30, false, true), true, "support at 30% in danger")
	T.eq(R.HandOfGodWorth(0.10, false, false), false, "nobody on them: keep the ultimate")
end)

T.test("huskar cauterize: only to drop a root or a DoT in a fight, never too low", function()
	local R = rules()
	T.eq(R.HuskarCauterize(0.6, true, false, true, 1), true, "rooted, hit, enemy near")
	T.eq(R.HuskarCauterize(0.6, false, true, true, 2), true, "burning, hit, enemies near")
	T.eq(R.HuskarCauterize(0.6, false, false, true, 2), false, "nothing to dispel")
	T.eq(R.HuskarCauterize(0.2, true, true, true, 2), false, "HP too low to pay 30%")
	T.eq(R.HuskarCauterize(0.6, true, false, false, 1), false, "not being hit by a hero")
	T.eq(R.HuskarCauterize(0.6, true, false, true, 0), false, "no enemy hero near")
end)

T.test("pugna life drain on an ally: start and stop", function()
	local R = rules()
	T.eq(R.LifeDrainAllyWorth(0.3, 0.8, true, 1), true, "low ally under attack, Pugna healthy")
	T.eq(R.LifeDrainAllyWorth(0.3, 0.4, true, 1), false, "Pugna too low to pay")
	T.eq(R.LifeDrainAllyWorth(0.6, 0.9, true, 2), false, "ally not low")
	T.eq(R.LifeDrainAllyWorth(0.3, 0.9, false, 0), false, "ally not under attack")
	T.eq(R.LifeDrainAllyStop(0.95, 0.8), true, "ally healed")
	T.eq(R.LifeDrainAllyStop(0.5, 0.2), true, "Pugna low")
	T.eq(R.LifeDrainAllyStop(0.5, 0.7), false, "keep draining")
end)

T.test("tiny toss: nearest ally 400+ from the tossed unit, in cast range", function()
	local R = rules()
	local candidates = {
		{ ok = true, spotDist = 250, tinyDist = 300 }, -- too close to the tossed unit
		{ ok = true, spotDist = 700, tinyDist = 650 },
		{ ok = true, spotDist = 500, tinyDist = 1300 }, -- out of cast range
		{ ok = true, spotDist = 600, tinyDist = 800 },
	}
	T.eq(R.PickTossAlly(candidates, 1000, R.TOSS_ALLY_MIN_DIST), 4, "nearest valid ally")
	T.eq(R.PickTossAlly({ { ok = true, spotDist = 300, tinyDist = 200 } }, 1000, 400), nil, "nobody far enough")
	T.eq(R.PickTossAlly({}, 1000, 400), nil, "no allies")
end)

T.test("keeper spirit-form heal: only in Spirit Form, for a hurt ally under attack", function()
	local R = rules()
	T.eq(R.SpiritIlluminateHealWorth(0.4, true, true), true, "hurt ally hit, in Spirit Form")
	T.eq(R.SpiritIlluminateHealWorth(0.4, true, false), false, "not in Spirit Form")
	T.eq(R.SpiritIlluminateHealWorth(0.8, true, true), false, "ally healthy")
	T.eq(R.SpiritIlluminateHealWorth(0.4, false, true), false, "ally not under attack")
end)

local function dive(over)
	local d = {
		kind = "engage",
		elapsed = 0.5,
		duration = 2,
		fromStart = 500,
		fromStartMax = 500,
		dashLength = 1100,
		targetDist = 400,
		targetDistMin = 400,
		hitRadius = 200,
		dashWidth = 500,
	}
	for k, v in pairs(over or {}) do
		d[k] = v
	end
	return d
end

T.test("icarus dive stop: kill / engage stop at the target, not by time", function()
	local R = rules()
	T.eq(R.IcarusDiveStop(dive({ targetDist = 150, targetDistMin = 150 })), true, "within hit_radius: reached")
	local stop, why = R.IcarusDiveStop(dive({ targetDist = 330, targetDistMin = 240 }))
	T.eq(stop, true, "came within 250+200 and now moving away: passed")
	T.eq(why, "passed")
	T.eq(R.IcarusDiveStop(dive({ targetDist = 260, targetDistMin = 240 })), false, "still about level with it")
	T.eq(R.IcarusDiveStop(dive({ targetDist = 700, targetDistMin = 600 })), false, "target left the path: no stop")
	T.eq(R.IcarusDiveStop(dive({ elapsed = 1.9, targetDist = 700, targetDistMin = 600 })), false, "no time cap")
	T.eq(R.IcarusDiveStop(dive({ kind = "kill", targetDist = nil, targetDistMin = nil })), false, "no target")
	T.eq(R.IcarusDiveStop(dive({ elapsed = -0.1, targetDist = 100, targetDistMin = 100 })), false, "not started")
end)

T.test("icarus dive stop: retreat stops at the far end of the arc", function()
	local R = rules()
	local retreat = { kind = "retreat", targetDist = nil, targetDistMin = nil }
	local function at(over)
		local d = dive(retreat)
		for k, v in pairs(over) do
			d[k] = v
		end
		return d
	end
	T.eq(R.IcarusDiveStop(at({ elapsed = 0.6, fromStart = 800, fromStartMax = 800 })), false, "still going out")
	local stop, why = R.IcarusDiveStop(at({ elapsed = 0.9, fromStart = 1040, fromStartMax = 1095 }))
	T.eq(stop, true, "turned back after half the dash")
	T.eq(why, "far-end")
	T.eq(R.IcarusDiveStop(at({ elapsed = 0.5, fromStart = 200, fromStartMax = 260 })), false, "a wobble near the start")
	stop, why = R.IcarusDiveStop(at({ elapsed = 1.0, fromStart = 900, fromStartMax = 900 }))
	T.eq(stop, true, "half the dive duration is the cap")
	T.eq(why, "half")
	T.eq(
		R.IcarusDiveStop(at({ kind = "stuck", elapsed = 1.05, fromStart = 950, fromStartMax = 950 })),
		true,
		"stuck too"
	)
end)
