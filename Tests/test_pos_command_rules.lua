-- FuncLib/systems/pos_command_rules.lua (#210): parsing `!pos` / `!pos Y` / `!Xpos Y`, the two-way swap, the
-- position names and the `!pos` answer throttle.
local T = ...

local function rules()
	T.stub.reset({ hero = "npc_dota_hero_lion" })
	return require(GetScriptDirectory() .. "/FuncLib/systems/pos_command_rules")
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
	T.eq(swap.index, 3)
	T.eq(swap.pos, 5)
	T.eq(PosRules.Parse("!pos 6").kind, "bad")
	T.eq(PosRules.Parse("!pos two").kind, "bad")
	T.eq(PosRules.Parse("!0pos 1").kind, "bad")
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
	local plan = PosRules.PlanSwap(roles, humans, {}, 1, 2, 1)
	T.eq(plan.result, "ok")
	T.eq(plan.holder, 3)
	T.eq(plan.from, 5)
	T.eq(plan.holderTo, 5)
	T.ok(PosRules.Apply(roles, plan))
	T.eq(PosRules.RolesText(roles), "2,1,5,3,4")
end)

T.test("pos rules: a core bot is not pushed onto the human's old 4/5", function()
	local PosRules = rules()
	local roles, humans = team()
	local plan = PosRules.PlanSwap(roles, humans, { [2] = true }, 1, 1, 1)
	T.eq(plan.result, "core-holder")
	T.ok(not PosRules.Apply(roles, plan))
	T.eq(PosRules.RolesText(roles), "5,1,2,3,4")
	-- A non-core holder takes the 5.
	local roles2, humans2 = team()
	T.eq(PosRules.PlanSwap(roles2, humans2, { [2] = true }, 1, 3, 1).result, "ok")
end)

T.test("pos rules: another human's position is refused", function()
	local PosRules = rules()
	local roles = { 5, 1, 2, 3, 4 }
	local humans = { [1] = true, [3] = true }
	T.eq(PosRules.PlanSwap(roles, humans, {}, 1, 2, 1).result, "human")
	-- `!3pos 4` from slot 1: slot 3 is a human, only he moves himself.
	T.eq(PosRules.PlanSwap(roles, humans, {}, 3, 4, 1).result, "human-mover")
end)

T.test("pos rules: !Xpos Y swaps bot X and the holder of Y", function()
	local PosRules = rules()
	local roles, humans = team()
	local plan = PosRules.PlanSwap(roles, humans, {}, 4, 4, 1)
	T.eq(plan.result, "ok")
	T.eq(plan.holder, 5)
	PosRules.Apply(roles, plan)
	T.eq(PosRules.RolesText(roles), "5,1,2,4,3")
	-- Already there.
	T.eq(PosRules.PlanSwap(roles, humans, {}, 4, 4, 1).result, "same")
	-- A core bot asked to play 4/5.
	T.eq(PosRules.PlanSwap({ 5, 1, 2, 3, 4 }, humans, { [2] = true }, 2, 4, 1).result, "core")
	-- No such slot.
	T.eq(PosRules.PlanSwap({ 5, 1, 2 }, humans, {}, 5, 1, 1).result, "missing")
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
	local Localization = require(GetScriptDirectory() .. "/FuncLib/systems/localization")
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
