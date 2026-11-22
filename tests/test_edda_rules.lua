-- bots/lib/systems/edda_rules.lua and the consume path in ability_item_usage_generic.lua (#47): Winter Wyvern's
-- Eldwurm's Edda.
local T = ...
local Stub = T.stub

local function load()
	Stub.reset({ hero = "npc_dota_hero_winter_wyvern" })
	return require(GetScriptDirectory() .. "/lib/systems/edda_rules")
end

local function levels(a, b, c, maxB)
	return {
		{ name = "winter_wyvern_arctic_burn", level = a, max = 4 },
		{ name = "winter_wyvern_splinter_blast", level = b, max = maxB or 4 },
		{ name = "winter_wyvern_cold_embrace", level = c, max = 4 },
	}
end

T.test("edda: consumed once off cooldown, out of danger, with a long retry gap", function()
	local R = load()
	local base = { cooldown = 0, tries = 0, canAct = true, inDanger = false }
	local function why(over)
		local s = {}
		for k, v in pairs(base) do
			s[k] = v
		end
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return R.ConsumeWhy(s)
	end
	T.eq(why(), "ready", "off cooldown")
	T.eq(select(2, why({ cooldown = 120 })), "cooldown", "on cooldown")
	T.eq(select(2, why({ canAct = false })), "cannot-act", "stunned or muted")
	T.eq(select(2, why({ inDanger = true })), "danger", "hit by a hero")
	T.eq(select(2, why({ tries = 1, sinceTry = 10 })), "retry-gap", "a retry waits")
	T.eq(why({ tries = 1, sinceTry = R.RETRY_GAP }), "retry", "a retry after the gap")
	T.eq(select(2, why({ tries = R.MAX_TRIES, sinceTry = 999 })), "gave-up", "stops after MAX_TRIES")
end)

T.test("edda: int bonus is 25% of base int (datafeed 26 + 3.6 per level)", function()
	local R = load()
	T.near(R.BaseInt(1), 26, 0.01, "level 1")
	T.near(R.BaseInt(9), 54.8, 0.01, "level 9")
	T.near(R.IntBonus(R.BaseInt(9), 25), 13.7, 0.01, "bonus at level 9")
	T.near(R.IntBonus(R.BaseInt(25), 25), 28.1, 0.01, "bonus at level 25")
end)

T.test("edda: outcome of the consume probe", function()
	local R = load()
	local before = { levels = levels(1, 4, 1), points = 0, itemPresent = true }
	T.eq(
		R.Outcome(before, { levels = levels(1, 4, 1), points = 0, itemPresent = true }),
		"not-consumed",
		"item still there"
	)
	local outcome, changed = R.Outcome(before, { levels = levels(1, 5, 1, 5), points = 0, itemPresent = false })
	T.eq(outcome, "level", "a level landed")
	T.eq(changed, "winter_wyvern_splinter_blast", "on Splinter Blast")
	T.eq(
		R.Outcome(before, { levels = levels(1, 4, 1), points = 1, itemPresent = false }),
		"pending",
		"a point appeared"
	)
	T.eq(R.Outcome(before, { levels = levels(1, 4, 1), points = 0, itemPresent = false }), "no-level", "nothing")
	T.eq(R.LevelsText(levels(1, 4, 0)), "arctic_burn:1/4,splinter_blast:4/4,cold_embrace:0/4", "levels text")
end)

T.test("edda: the choice call never spends a normal skill point", function()
	local R = load()
	T.ok(R.ShouldTryChoice({ points = 1 }, "pending"), "the consume's own point")
	T.ok(R.ShouldTryChoice({ points = 0 }, "no-level"), "no point to spend")
	T.ok(not R.ShouldTryChoice({ points = 1 }, "no-level"), "a normal point is left to the build")
	T.ok(not R.ShouldTryChoice({ points = 0 }, "level"), "a level landed")
	T.ok(not R.ShouldTryChoice({ points = 0 }, "not-consumed"), "not consumed")
end)

T.test("edda: innate slot items are not neutral items; the Edda is never swapped", function()
	local R = load()
	T.ok(R.IsInnateSlotItem("item_eldwurms_edda"), "Edda")
	T.ok(R.IsInnateSlotItem("item_grisgris"), "Gris-Gris")
	T.ok(not R.IsInnateSlotItem("item_polliwog_charm"), "a real neutral")
	local Item = require(GetScriptDirectory() .. "/lib/systems/item")
	T.ok(Item.IsCanNotSwitchItem("item_eldwurms_edda"), "Edda is not a swap target")
end)

local function printed(pattern)
	for _, line in ipairs(Stub.printed) do
		if string.find(line, pattern) then
			return line
		end
	end
	return nil
end

T.test("edda: Winter Wyvern consumes it from the neutral slot and probes the result", function()
	Stub.reset({ hero = "npc_dota_hero_winter_wyvern", time = 600 })
	local ok, Usage = Stub.load("ability_item_usage_generic")
	if not ok then
		error(tostring(Usage), 0)
	end
	local bot = Stub.bot
	bot._alive = true
	bot.IsAlive = function()
		return true
	end
	local edda = Stub.newAbility("item_eldwurms_edda", bot)
	local cooldown = 30
	edda.GetCooldownTimeRemaining = function()
		return cooldown
	end
	bot._items[16] = edda
	local ordered = nil
	bot.Action_UseAbility = function(_, item)
		ordered = item
	end
	T.ok(not Usage.TryConsumeEdda(), "waits for the cooldown")
	T.ok(printed("edda%-state when=first slot=16") ~= nil, "state line")
	cooldown = 0
	Stub.time = 601
	T.ok(Usage.TryConsumeEdda(), "consumes once ready")
	T.eq(ordered, edda, "Action_UseAbility on the item")
	T.ok(printed("edda%-consume why=ready try=1 ability=splinter_blast") ~= nil, "consume line")
	T.ok(printed("edda%-state when=ready") ~= nil, "ready line")
	bot._items[16] = nil
	Stub.time = 602.5
	T.ok(not Usage.TryConsumeEdda(), "no second order")
	T.ok(printed("edda%-result after=1%.5 try=1 outcome=no%-level") ~= nil, "result line")
	T.ok(printed("edda%-choice try=LevelAbility") ~= nil, "the choice call is tried once")
end)

T.test("edda: other heroes never touch it", function()
	Stub.reset({ hero = "npc_dota_hero_witch_doctor", time = 900 })
	local ok, Usage = Stub.load("ability_item_usage_generic")
	if not ok then
		error(tostring(Usage), 0)
	end
	T.ok(not Usage.TryConsumeEdda(), "not Winter Wyvern")
end)
