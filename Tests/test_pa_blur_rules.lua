-- FuncLib/systems/pa_blur_rules.lua (#48): Phantom Assassin's Blur escape, chase-approach, enemy-area hide and the
-- dodge result.
local T = ...

-- "ok why" as one string: T.eq compares plain values.
local function pair(ok, why)
	return tostring(ok) .. " " .. tostring(why)
end

local function load()
	T.stub.reset({ hero = "npc_dota_hero_phantom_assassin" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/pa_blur_rules")
end

T.test("pa blur: escape is no longer blocked by a hero or a tower near", function()
	local R = load()
	local function escape(over)
		local o = { retreating = true, hitByHero = true, level = 10, hp = 0.5, heroesNear = 0, towerNear = false }
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		return R.Escape(o)
	end
	T.eq(pair(escape()), "true clear", "nobody near")
	T.eq(pair(escape({ heroesNear = 2 })), "true hero-near", "game 069: a hero within 740 stopped it")
	T.eq(pair(escape({ towerNear = true })), "true tower-near", "game 069: a tower within 878 stopped it")
	T.eq(pair(escape({ heroesNear = 1, towerNear = true })), "true hero-tower-near", "both")
	T.eq(escape({ retreating = false }), false, "not retreating")
	T.eq(escape({ hitByHero = false }), false, "no hero hit her")
	T.eq(escape({ level = 4, hp = 0.5 }), false, "before level 6 only when low")
	T.eq(escape({ level = 4, hp = 0.25 }), true, "low before level 6")
end)

T.test("pa blur: chase-approach only on a lone hero far enough", function()
	local R = load()
	local function approach(over)
		local o = {
			hunting = true,
			dist = 1400,
			othersNearTarget = 0,
			towerNearTarget = false,
			attackingOther = false,
			hp = 0.8,
			strikeReach = 0,
			manaAfter = 200,
			strikeCost = 50,
		}
		for k, v in pairs(over or {}) do
			o[k] = v
		end
		return R.Approach(o)
	end
	T.eq(pair(approach()), "true approach", "lone hero 1400 away")
	T.eq(pair(approach({ hunting = false })), "false not-hunting", "not going on someone")
	T.eq(pair(approach({ dist = 899 })), "false close", "under 900")
	T.eq(approach({ dist = 900 }), true, "900 counts")
	T.eq(pair(approach({ dist = 2600 })), "false far", "too far to be a chase")
	T.eq(pair(approach({ othersNearTarget = 1 })), "false not-alone", "another enemy near the target")
	T.eq(pair(approach({ towerNearTarget = true })), "false tower", "a tower near the target reveals her")
	T.eq(pair(approach({ attackingOther = true })), "false attacking", "an attack on the way breaks Blur")
	T.eq(pair(approach({ hp = 0.3 })), "false low-hp", "keep it for the escape")
	-- Datafeed hero 44: Phantom Strike cast range 650/750/850/950.
	T.eq(pair(approach({ dist = 940, strikeReach = 950 })), "false strike", "Phantom Strike reaches")
	T.eq(approach({ dist = 1200, strikeReach = 950 }), true, "Phantom Strike does not reach")
	T.eq(pair(approach({ manaAfter = 30, strikeCost = 50 })), "false mana", "keep the mana for the jump")
end)

T.test("pa blur: the enemy-area rule reads two hero ranges", function()
	local R = load()
	T.eq(R.AreaHide({ heroesClose = 0, heroesSeen = 0, towers = 0 }), true, "nobody near")
	T.eq(R.AreaHide({ heroesClose = 0, heroesSeen = 2, towers = 0 }), true, "two seen farther than 900")
	T.eq(R.AreaHide({ heroesClose = 0, heroesSeen = 3, towers = 0 }), false, "three seen")
	T.eq(R.AreaHide({ heroesClose = 1, heroesSeen = 1, towers = 0 }), false, "one within 900")
	T.eq(R.AreaHide({ heroesClose = 0, heroesSeen = 0, towers = 1 }), false, "a tower")
end)

T.test("pa blur: dodge result after 1s", function()
	local R = load()
	T.eq(R.DodgeResult({ at = 100, stunned = false }, 100.5), nil, "window open")
	T.eq(R.DodgeResult({ at = 100, stunned = false }, 101), "no", "no stun in 1s")
	T.eq(R.DodgeResult({ at = 100, stunned = true }, 101.2), "yes", "stun latched in the window")
	T.eq(R.DodgeResult({ at = 100, stunned = false }, 104), "unknown", "checked too late")
	T.eq(R.DodgeResult({ at = 100, stunned = true }, 104), "yes", "a latched stun stays yes")
end)
