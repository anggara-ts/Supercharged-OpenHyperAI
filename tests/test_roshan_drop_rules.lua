-- #15: bots/lib/systems/roshan_drop_rules.lua (who takes the Aegis by KDA, which item it puts aside).
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_alchemist" })
	return require(GetScriptDirectory() .. "/lib/systems/roshan_drop_rules")
end

local function cand(id, kda, pos, dist, extra)
	local c = { id = id, kda = kda, pos = pos, dist = dist, alive = true, canTake = true, human = false }
	for key, value in pairs(extra or {}) do
		c[key] = value
	end
	return c
end

T.test("aegis rules: KDA is (kills + assists) / max(1, deaths)", function()
	local R = rules()
	T.near(R.Kda(4, 2, 6), 5, 1e-9, "10 / 2")
	T.near(R.Kda(3, 0, 1), 4, 1e-9, "no deaths counts as one")
	T.near(R.Kda(nil, nil, nil), 0, 1e-9, "nothing known")
end)

T.test("aegis rules: the best KDA near takes it, cores before supports on a tie", function()
	local R = rules()
	-- Maintainer, 2026-11-23: a core with a full bag left it to a support; the top performer takes it now.
	local support = cand(14, 6, 5, 300)
	local carry = cand(10, 3, 1, 2900)
	T.eq(R.AegisClaimer({ support, carry }).id, 14, "a support with the best KDA takes it")
	local tiedCore = cand(11, 6, 2, 700)
	local pick, why = R.AegisClaimer({ support, carry, tiedCore })
	T.eq(pick.id, 11, "same KDA: the core first")
	T.eq(why, "best-kda", "why")
	T.eq(R.AegisClaimer({ cand(12, 2, 3, 500), cand(10, 2, 1, 700) }).id, 10, "same KDA, both cores: pos 1")
	T.eq(R.AegisClaimer({ cand(13, 2, 4, 500), cand(12, 2, 4, 700) }).id, 12, "all the same: lower player ID")
end)

T.test("aegis rules: one claimer is kept until it is released", function()
	local R = rules()
	local first = cand(14, 2, 5, 800)
	local better = cand(10, 9, 1, 300)
	local pick, why = R.AegisClaimer({ first, better }, { current = 14 })
	T.eq(pick.id, 14, "a better KDA arriving does not take the claim over")
	T.eq(why, "kept", "why")
	pick = R.AegisClaimer({ cand(14, 2, 5, 800, { alive = false }), better }, { current = 14 })
	T.eq(pick.id, 10, "the claimer died: the next best")
	pick = R.AegisClaimer({ first, better }, { current = 14, excluded = { [14] = true } })
	T.eq(pick.id, 10, "a released claimer is skipped")
	pick = R.AegisClaimer({ cand(14, 2, 5, 7000), better }, { current = 14 })
	T.eq(pick.id, 10, "a claimer that walked out of range")
end)

T.test("aegis rules: nobody near that can take it, the next best by KDA does", function()
	local R = rules()
	local full = cand(10, 9, 1, 400, { canTake = false })
	local farAway = cand(11, 4, 2, 5200)
	local farther = cand(12, 1, 3, 4800)
	local pick, why = R.AegisClaimer({ full, farAway, farther })
	T.eq(pick.id, 11, "best KDA of the rest")
	T.eq(why, "far", "why")
	T.eq(R.AegisClaimer({ full, cand(13, 9, 1, 6500) }), nil, "nobody within 6000 either")
	local none, noneWhy = R.AegisClaimer({ full })
	T.eq(none, nil, "nobody at all")
	T.eq(noneWhy, "nobody", "why")
end)

T.test("aegis rules: a hero that can't stay at the pit is skipped when one that can is there", function()
	local R = rules()
	-- Game 084, 35:00: Lina (KDA 13) at 23% HP, retreating, 1091 from the Aegis; Lone Druid (KDA 10) 207 from it.
	local lina = cand(11, 13, 2, 1091, { hp = 0.23, retreating = true })
	local loneDruid = cand(12, 10, 1, 207, { hp = 0.96 })
	local pick, why = R.AegisClaimer({ lina, loneDruid })
	T.eq(pick.id, 12, "Lone Druid, who stands at it")
	T.eq(why, "best-kda", "why")
	T.eq(R.AegisClaimer({ cand(11, 13, 2, 300, { hp = 0.3 }), loneDruid }).id, 12, "under 35% HP")
	T.eq(R.AegisClaimer({ cand(11, 13, 2, 300, { retreating = true }), loneDruid }).id, 12, "retreating")
	T.eq(R.AegisClaimer({ cand(11, 13, 2, 1000), loneDruid }).id, 12, "further than 800")
	T.eq(R.AegisClaimer({ cand(11, 13, 2, 790, { hp = 0.35 }), loneDruid }).id, 11, "fit: the best KDA again")
end)

T.test("aegis rules: nobody fit, the one that can stay walks in, else the one that has to leave", function()
	local R = rules()
	local walking = cand(11, 2, 1, 1500)
	local leaving = cand(12, 9, 2, 200, { retreating = true })
	local pick, why = R.AegisClaimer({ walking, leaving })
	T.eq(pick.id, 11, "healthy and on the way beats retreating at the pit")
	T.eq(why, "walk", "why")
	pick, why = R.AegisClaimer({ leaving, cand(13, 3, 3, 400, { hp = 0.2 }) })
	T.eq(pick.id, 12, "only heroes that have to leave: still the best KDA, better than nobody")
	T.eq(why, "weak", "why")
end)

T.test("aegis rules: a claimer that has to leave hands over to a fit ally at once", function()
	local R = rules()
	local loneDruid = cand(12, 10, 1, 207, { hp = 0.96 })
	local pick, why, leaving = R.AegisClaimer(
		{ cand(11, 13, 2, 600, { retreating = true }), loneDruid, cand(13, 1, 5, 2000) },
		{ current = 11 }
	)
	T.eq(pick.id, 12, "the fit ally takes over")
	T.eq(why, "handover", "why")
	T.eq(leaving, "retreat", "the reason")
	pick, why, leaving = R.AegisClaimer({ cand(11, 13, 2, 600, { hp = 0.2 }), loneDruid }, { current = 11 })
	T.eq(pick.id, 12, "low HP")
	T.eq(why, "handover", "why")
	T.eq(leaving, "low-hp", "the reason")
	pick, why = R.AegisClaimer({ cand(11, 13, 2, 600, { hp = 0.3 }), loneDruid }, { current = 11 })
	T.eq(pick.id, 11, "hit once at the pit (30%, above 25%): kept, no flip")
	T.eq(why, "kept", "why")
	pick, why = R.AegisClaimer({ cand(11, 13, 2, 600, { retreating = true }), cand(13, 1, 5, 2000) }, { current = 11 })
	T.eq(pick.id, 11, "nobody fit to take over: kept")
	T.eq(why, "kept", "why")
	pick = R.AegisClaimer({ cand(11, 13, 2, 1500), loneDruid }, { current = 11 })
	T.eq(pick.id, 11, "a healthy claimer walking in keeps it, even with a fit ally closer")
	pick = R.AegisClaimer({ cand(11, 13, 2, 600, { retreating = true }), loneDruid }, {
		current = 11,
		excluded = { [12] = true },
	})
	T.eq(pick.id, 11, "a released ally is no successor")
end)

T.test("aegis rules: a human near gets the first go, then the bots", function()
	local R = rules()
	local human = cand(10, 1, 1, 500, { human = true })
	local bot = cand(11, 5, 2, 400)
	local pick, why = R.AegisClaimer({ human, bot }, { humanWait = true })
	T.eq(pick.id, 10, "the player first")
	T.eq(why, "human", "why")
	pick = R.AegisClaimer({ human, bot }, { humanWait = false, current = 10 })
	T.eq(pick.id, 11, "the wait is over: a bot takes it, the human claim is not kept")
end)

T.test("aegis rules: the item put aside is the cheapest it can spare, a keep item only if it must", function()
	local R = rules()
	local function bag(list)
		local items = {}
		for slot, entry in ipairs(list) do
			items[#items + 1] = { slot = slot - 1, name = entry[1], cost = entry[2], keep = entry[3] }
		end
		return items
	end
	-- Maintainer: "they had cheap item like wraith band".
	local aside = R.AsideItem(bag({
		{ "item_power_treads", 1400 },
		{ "item_wraith_band", 505 },
		{ "item_black_king_bar", 4050, true },
		{ "item_octarine_core", 4800 },
		{ "item_desolator", 3500 },
		{ "item_satanic", 5050 },
	}))
	T.eq(aside.name, "item_wraith_band", "the cheapest")
	aside = R.AsideItem(bag({
		{ "item_power_treads", 1400 },
		{ "item_octarine_core", 4800 },
		{ "item_black_king_bar", 4050, true },
		{ "item_desolator", 3500 },
		{ "item_satanic", 5050 },
		{ "item_butterfly", 5450 },
	}))
	T.eq(aside.name, "item_power_treads", "even the boots")
	aside = R.AsideItem(bag({
		{ "item_eldwurms_edda", 0 },
		{ "item_black_king_bar", 4050, true },
		{ "item_gem", 900, true },
		{ "item_ward_observer", 0, true },
		{ "item_grisgris", 0 },
		{ "item_black_grimoire", 0 },
	}))
	T.eq(aside.name, "item_ward_observer", "only keep items left: the cheapest one, never an undroppable one")
	T.eq(
		R.AsideItem(bag({ { "item_eldwurms_edda", 0 }, { "item_grisgris", 0 } })),
		nil,
		"a free main slot: nothing to put aside"
	)
end)
