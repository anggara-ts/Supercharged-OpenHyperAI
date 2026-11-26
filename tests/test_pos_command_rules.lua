-- bots/lib/systems/pos_command_rules.lua (#210): parsing `!pos` / `!pos Y` / `!Xpos Y`, the two-way swap of two
-- positions, the position names and the `!pos` answer throttle.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lion" })
	return require(GetScriptDirectory() .. "/lib/systems/pos_command_rules")
end

T.test("pos rules: parse the three commands", function()
	local PosRules = rules()
	T.eq(PosRules.Parse("!pos").kind, "list")
	T.eq(PosRules.Parse("  !POS  ").kind, "list")
	local take = PosRules.Parse("!pos 2")
	T.eq(take.kind, "take")
	T.eq(take.pos, 2)
	local swap = PosRules.Parse("!3pos 5")
	T.eq(swap.kind, "swap")
	T.eq(swap.from, 3)
	T.eq(swap.pos, 5)
	-- Whole numbers outside 1..5 parse, and PlanSwap refuses them as "missing" ("no pos 6").
	T.eq(PosRules.Parse("!pos 6").pos, 6)
	T.eq(PosRules.Parse("!0pos 1").from, 0)
	T.eq(PosRules.Parse("!pos two").kind, "bad")
	T.eq(PosRules.Parse("!pos 2.5").kind, "bad")
	T.eq(PosRules.Parse("!3pos").kind, "bad")
	T.eq(PosRules.Parse("!pick lion"), nil)
	T.eq(PosRules.Parse("!position").kind, "bad")
	T.eq(PosRules.Parse("hello"), nil)
	T.eq(PosRules.Parse(nil), nil)
end)

-- Slot 1 human at pos 5; bots: slot 2 pos 1, slot 3 pos 2, slot 4 pos 3, slot 5 pos 4.
local function team()
	return { 5, 1, 2, 3, 4 }, { [1] = true }
end

T.test("pos rules: !pos Y swaps the human with the holder only", function()
	local PosRules = rules()
	local roles, humans = team()
	-- `!pos 2` from the human: PlanSwap(<his position 5>, 2).
	local plan = PosRules.PlanSwap(roles, humans, {}, 5, 2, 1)
	T.eq(plan.result, "ok")
	T.eq(plan.mover, 1)
	T.eq(plan.holder, 3)
	T.eq(plan.from, 5)
	T.eq(plan.holderTo, 5)
	T.ok(PosRules.Apply(roles, plan))
	T.eq(PosRules.RolesText(roles), "2,1,5,3,4")
end)

T.test("pos rules: a core bot is not pushed onto the human's old 4/5", function()
	local PosRules = rules()
	local roles, humans = team()
	local plan = PosRules.PlanSwap(roles, humans, { [2] = true }, 5, 1, 1)
	T.eq(plan.result, "core-holder")
	T.ok(not PosRules.Apply(roles, plan))
	T.eq(PosRules.RolesText(roles), "5,1,2,3,4")
	-- A non-core holder takes the 5.
	local roles2, humans2 = team()
	T.eq(PosRules.PlanSwap(roles2, humans2, { [2] = true }, 5, 3, 1).result, "ok")
end)

T.test("pos rules: !Xpos Y swaps the holders of positions X and Y, a repeat undoes it", function()
	local PosRules = rules()
	local roles, humans = team()
	-- `!3pos 2` from the human: slot 4 (pos 3) and slot 3 (pos 2) swap.
	local plan = PosRules.PlanSwap(roles, humans, {}, 3, 2, 1)
	T.eq(plan.result, "ok")
	T.eq(plan.mover, 4)
	T.eq(plan.holder, 3)
	PosRules.Apply(roles, plan)
	T.eq(PosRules.RolesText(roles), "5,1,3,2,4")
	-- The same command again restores the roles.
	T.ok(PosRules.Apply(roles, PosRules.PlanSwap(roles, humans, {}, 3, 2, 1)))
	T.eq(PosRules.RolesText(roles), "5,1,2,3,4")
	-- `!2pos 3` is the same swap as `!3pos 2`.
	PosRules.Apply(roles, PosRules.PlanSwap(roles, humans, {}, 2, 3, 1))
	T.eq(PosRules.RolesText(roles), "5,1,3,2,4")
end)

-- Game 087 (Dire, team order Zeus, Marci, Dark Willow, Ringmaster, Winter Wyvern; the maintainer is Marci, slot 2).
-- After `!pos 1` and `!5pos 2` the roles were 5,1,3,4,2. `!2pos 1` answered "you're already pos 1" because X was the
-- team-list index (Marci, already pos 1); X is a position now, so pos 2 (Wyvern) and pos 1 (Marci) swap.
T.test("pos rules: game 087 !2pos 1 swaps pos 2 and pos 1, the sender may be one of them", function()
	local PosRules = rules()
	local roles, humans = { 5, 1, 3, 4, 2 }, { [2] = true }
	local plan = PosRules.PlanSwap(roles, humans, {}, 2, 1, 2)
	T.eq(plan.result, "ok")
	T.eq(plan.mover, 5)
	T.eq(plan.holder, 2)
	PosRules.Apply(roles, plan)
	T.eq(PosRules.RolesText(roles), "5,2,3,4,1")
	-- The sender as the mover side: `!2pos 3` from Marci (now pos 2).
	plan = PosRules.PlanSwap(roles, humans, {}, 2, 3, 2)
	T.eq(plan.result, "ok")
	T.eq(plan.mover, 2)
end)

T.test("pos rules: another human's position is refused on either side", function()
	local PosRules = rules()
	local roles = { 5, 1, 2, 3, 4 }
	local humans = { [1] = true, [3] = true }
	-- `!pos 2` from slot 1: pos 2 is the human in slot 3.
	local plan = PosRules.PlanSwap(roles, humans, {}, 5, 2, 1)
	T.eq(plan.result, "human")
	T.eq(plan.humanSlot, 3)
	T.eq(plan.humanPos, 2)
	-- `!2pos 4` from slot 1: pos 2 (X) is the other human.
	plan = PosRules.PlanSwap(roles, humans, {}, 2, 4, 1)
	T.eq(plan.result, "human")
	T.eq(plan.humanSlot, 3)
	T.eq(plan.humanPos, 2)
	-- `!3pos 2` from slot 1: pos 2 (Y) is the other human.
	plan = PosRules.PlanSwap(roles, humans, {}, 3, 2, 1)
	T.eq(plan.result, "human")
	T.eq(plan.humanPos, 2)
	T.ok(not PosRules.Apply(roles, plan))
	-- Two bots: any player may swap them.
	T.eq(PosRules.PlanSwap(roles, humans, {}, 1, 3, 1).result, "ok")
	T.eq(PosRules.PlanSwap(roles, humans, {}, 1, 3, 3).result, "ok")
end)

T.test("pos rules: a core bot is refused on 4/5 in both directions", function()
	local PosRules = rules()
	local humans = { [1] = true }
	-- `!1pos 4`: the core on pos 1 (slot 2) would take 4.
	T.eq(PosRules.PlanSwap({ 5, 1, 2, 3, 4 }, humans, { [2] = true }, 1, 4, 1).result, "core")
	-- `!4pos 1`: the same swap named the other way; the core holder would get 4.
	T.eq(PosRules.PlanSwap({ 5, 1, 2, 3, 4 }, humans, { [2] = true }, 4, 1, 1).result, "core-holder")
	-- A core bot already on 4 can be swapped off it; the repeat that would put it back is refused.
	local roles = { 5, 2, 1, 3, 4 }
	T.ok(PosRules.Apply(roles, PosRules.PlanSwap(roles, humans, { [5] = true }, 4, 1, 1)))
	T.eq(PosRules.RolesText(roles), "5,2,4,3,1")
	T.eq(PosRules.PlanSwap(roles, humans, { [5] = true }, 4, 1, 1).result, "core-holder")
end)

T.test("pos rules: same position, missing and out-of-range positions", function()
	local PosRules = rules()
	local roles, humans = team()
	T.eq(PosRules.PlanSwap(roles, humans, {}, 3, 3, 1).result, "same")
	local plan = PosRules.PlanSwap(roles, humans, {}, 7, 2, 1)
	T.eq(plan.result, "missing")
	T.eq(plan.missingPos, 7)
	plan = PosRules.PlanSwap(roles, humans, {}, 2, 0, 1)
	T.eq(plan.result, "missing")
	T.eq(plan.missingPos, 0)
	-- Nobody holds pos 5 in a team of four.
	plan = PosRules.PlanSwap({ 1, 2, 3, 4 }, {}, {}, 5, 1, nil)
	T.eq(plan.result, "missing")
	T.eq(plan.missingPos, 5)
	-- Nobody holds Y: X moves there alone.
	roles = { 1, 2, 3, 4 }
	T.ok(PosRules.Apply(roles, PosRules.PlanSwap(roles, {}, {}, 4, 5, nil)))
	T.eq(PosRules.RolesText(roles), "1,2,3,5,-")
	T.eq(PosRules.Apply(roles, nil), false)
end)

T.test("pos rules: position names and lines", function()
	local PosRules = rules()
	T.eq(PosRules.Line(1), "Pos 1 Safelane")
	T.eq(PosRules.Line(2), "Pos 2 Mid")
	T.eq(PosRules.Line(3), "Pos 3 Offlane")
	T.eq(PosRules.Line(4), "Pos 4 Offlane Support")
	T.eq(PosRules.Line(5), "Pos 5 Hard Support")
	T.eq(PosRules.Line(5, { "a", "b", "c", "d", "e" }, "P"), "P 5 e")
	-- Every locale has the five names, or falls back to English.
	local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
	local names = Localization.Get("pos_names")
	T.eq(#names, 5)
	T.ok(type(Localization.Get("say_pos_prefix")) == "string", "no say_pos_prefix")
end)

T.test("pos rules: one answer per bot, in position order, throttled", function()
	local PosRules = rules()
	-- Request at t=100: pos 1 answers from 100.6, pos 5 from 103.
	T.eq(PosRules.AnswerState(nil, nil, nil, 100, 1), "none")
	T.eq(PosRules.AnswerState(100, nil, nil, 100.2, 1), "wait")
	T.eq(PosRules.AnswerState(100, nil, nil, 100.7, 1), "answer")
	T.eq(PosRules.AnswerState(100, nil, nil, 102.5, 5), "wait")
	T.eq(PosRules.AnswerState(100, nil, nil, 103.1, 5), "answer")
	-- Handled: nothing new.
	T.eq(PosRules.AnswerState(100, 100, 100.7, 101, 1), "none")
	-- A second request 2s later (or the other chat callback) is dropped.
	T.eq(PosRules.AnswerState(102, 100, 100.7, 103, 1), "drop")
	-- 20s later it is still dropped (the chat guard would swallow the same line), 35s later it is answered.
	T.eq(PosRules.AnswerState(120, 100, 100.7, 121, 1), "drop")
	T.eq(PosRules.AnswerState(135, 120, 100.7, 136, 1), "answer")
	-- A request typed in the draft, 60s before the bot spawned.
	T.eq(PosRules.AnswerState(40, nil, nil, 100, 3), "drop")
end)

-- Game 082 (t=-74): the maintainer as Nature's Prophet (slot 5, pos 5) typed `!pos 2`; the holder Puck (slot 2) is a
-- core bot and would get pos 5, so the swap was refused (core-holder) and nobody said why. Every refusal now has a
-- line, said by the mover if it is a bot, else the team's first bot.
local HEROES = { "Alchemist", "Puck", "Spirit Breaker", "Largo", "Nature's Prophet" }
local function heroOf(slot)
	return HEROES[slot] or "?"
end
local ENGLISH = {
	say_pos_refused_core = "{hero} can't play pos {pos}",
	say_pos_refused_human = "pos {pos} is {hero}'s",
	say_pos_refused_same = "you're already pos {pos}",
	say_pos_refused_same_self = "I'm already pos {pos}",
	say_pos_refused_same_other = "{hero} is already pos {pos}",
	say_pos_refused_missing = "no pos {pos}",
}
local function replyLine(PosRules, plan)
	local key, fields = PosRules.Reply(plan, heroOf)
	if key == nil then
		return nil
	end
	return PosRules.FillReply(ENGLISH[key], fields)
end

T.test("pos rules: game 082 core-holder refusal names Puck and pos 5", function()
	local PosRules = rules()
	local roles = { 1, 2, 3, 4, 5 }
	-- `!pos 2` from Nature's Prophet (pos 5).
	local plan = PosRules.PlanSwap(roles, { [5] = true }, { [1] = true, [2] = true }, 5, 2, 5)
	T.eq(plan.result, "core-holder")
	T.eq(replyLine(PosRules, plan), "Puck can't play pos 5")
	-- The mover is the human: the team's first bot says it.
	local players = { 10, 11, 12, 13, 14 }
	local isBot = function(playerId)
		return playerId ~= 14
	end
	T.eq(PosRules.ReplySpeaker(players, plan.mover, isBot), 10)
end)

T.test("pos rules: every refused result has its own reply", function()
	local PosRules = rules()
	-- core: bot Alchemist (pos 1, core) told to take pos 5 (`!1pos 5`).
	local plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, {}, { [1] = true }, 1, 5, nil)
	T.eq(plan.result, "core")
	T.eq(replyLine(PosRules, plan), "Alchemist can't play pos 5")
	-- human: pos 5 belongs to the human in slot 5, `!4pos 5` from the human in slot 1.
	plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, { [1] = true, [5] = true }, {}, 4, 5, 1)
	T.eq(plan.result, "human")
	T.eq(replyLine(PosRules, plan), "pos 5 is Nature's Prophet's")
	-- human on the X side: `!5pos 2` from the human in slot 1.
	plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, { [1] = true, [5] = true }, {}, 5, 2, 1)
	T.eq(plan.result, "human")
	T.eq(replyLine(PosRules, plan), "pos 5 is Nature's Prophet's")
	-- same, the sender's own position (`!pos 5` or `!5pos 5` from slot 5).
	plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, { [5] = true }, {}, 5, 5, 5)
	T.eq(plan.result, "same")
	T.eq(replyLine(PosRules, plan), "you're already pos 5")
	-- missing: a team of four, `!5pos 1`; and `!pos 7`.
	plan = PosRules.PlanSwap({ 1, 2, 3, 4 }, {}, {}, 5, 1, nil)
	T.eq(plan.result, "missing")
	T.eq(replyLine(PosRules, plan), "no pos 5")
	T.eq(replyLine(PosRules, PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, {}, {}, 1, 7, 1)), "no pos 7")
	-- ok has no reply.
	plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, {}, {}, 4, 5, nil)
	T.eq(plan.result, "ok")
	T.eq(PosRules.Reply(plan, heroOf), nil)
	T.eq(PosRules.FillReply(nil, {}), nil)
	T.eq(PosRules.FillReply("{hero} x", {}), "? x")
end)

-- Game 087 (t=-31): the maintainer typed `!3pos 2` a second time and Dark Willow, a bot already on pos 2, said
-- "you're already pos 2" about itself. "you're" is only for the human who typed the command.
T.test("pos rules: a bot that already holds the position does not say you're", function()
	local PosRules = rules()
	local humans = { [5] = true }
	-- `!3pos 3` from the human in slot 5: the holder of pos 3 is the bot Spirit Breaker, and it is the speaker.
	local plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, humans, {}, 3, 3, 5)
	T.eq(plan.result, "same")
	local line = replyLine(PosRules, plan)
	T.eq(line, "I'm already pos 3")
	T.ok(line:find("you're", 1, true) == nil, line)
	local players = { 10, 11, 12, 13, 14 }
	T.eq(
		PosRules.ReplySpeaker(players, plan.mover, function(playerId)
			return playerId ~= 14
		end),
		12
	)
	-- Another human already on pos 1 (`!1pos 1` from slot 5).
	plan = PosRules.PlanSwap({ 1, 2, 3, 4, 5 }, { [1] = true, [5] = true }, {}, 1, 1, 5)
	T.eq(replyLine(PosRules, plan), "Alchemist is already pos 1")
end)

T.test("pos rules: the reply speaker is the mover bot, else the first bot", function()
	local PosRules = rules()
	local players = { 10, 11, 12, 13, 14 }
	local humanSlot1 = function(playerId)
		return playerId ~= 10
	end
	T.eq(PosRules.ReplySpeaker(players, 3, humanSlot1), 12, "the mover is a bot")
	T.eq(PosRules.ReplySpeaker(players, 1, humanSlot1), 11, "the mover is the human")
	T.eq(PosRules.ReplySpeaker(players, nil, humanSlot1), 11, "no mover")
	T.eq(PosRules.ReplySpeaker(players, 6, humanSlot1), 11, "missing slot")
	T.eq(
		PosRules.ReplySpeaker(players, 2, function()
			return false
		end),
		nil,
		"no bot"
	)
end)

T.test("pos rules: every locale has the refusal lines with their fields", function()
	rules()
	local Localization = require(GetScriptDirectory() .. "/lib/systems/localization")
	-- The same module name localization.lua uses when GetScriptDirectory() is "bots".
	local CustomLoader = require("bots.lib.systems.custom_loader")
	local saved = CustomLoader.Localization
	for _, locale in ipairs({ "en", "zh", "ru", "ja" }) do
		CustomLoader.Localization = locale
		for key, english in pairs(ENGLISH) do
			local template = Localization.Get(key)
			T.ok(type(template) == "string", locale .. ": no " .. key)
			for field in english:gmatch("{%a+}") do
				T.ok(template:find(field, 1, true) ~= nil, locale .. ": " .. key .. " lacks " .. field)
			end
		end
	end
	CustomLoader.Localization = saved
	T.eq(Localization.Get("say_pos_refused_core"), ENGLISH.say_pos_refused_core)
end)
