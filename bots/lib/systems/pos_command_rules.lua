-- Pure rules for the position chat commands (#210): parsing `!pos`, `!pos Y` and `!Xpos Y`, the two-way swap,
-- the position names and the throttle for the bots' "Pos N <name>" answer. No bot API here, so tests/ can load it.
local PosRules = {}

-- English names. Localization.Get("pos_names") can give a translated list; a missing entry falls back to these.
PosRules.Names = { "Safelane", "Mid", "Offlane", "Offlane Support", "Hard Support" }

-- Seconds a bot waits before it answers `!pos` again (a second callback or a repeated `!pos` inside the window is
-- dropped), and the gap between the bots' lines (pos 1 speaks first, pos 5 last). 30s is the window of
-- bots/lib/systems/chat_guard.lua: a team says the same text at most once per 30s, so a faster repeat would be
-- swallowed there unseen.
PosRules.AnswerCooldown = 30
PosRules.AnswerStep = 0.6
-- A request older than this is dropped without an answer.
PosRules.AnswerMaxAge = 20

-- "!pos" -> { kind = "list" }; "!pos 2" -> { kind = "take", pos = 2 }; "!3pos 5" -> { kind = "swap", from = 3,
-- pos = 5 } (swap positions 3 and 5). Whole numbers outside 1..5 still parse ("!pos 7", "!0pos 1"): PlanSwap refuses
-- them as "missing" so the player hears "no pos 7". Anything else that starts with "!pos" / "!Npos" ->
-- { kind = "bad" }; other text -> nil.
local function wholeNumber(text)
	local number = tonumber(text)
	if number ~= nil and number == math.floor(number) then
		return number
	end
	return nil
end
function PosRules.Parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local command = text:lower():match("^%s*(.-)%s*$")
	if command == "!pos" then
		return { kind = "list" }
	end
	local takeArg = command:match("^!pos%s+(%S+)$")
	if takeArg ~= nil then
		local pos = wholeNumber(takeArg)
		if pos ~= nil then
			return { kind = "take", pos = pos }
		end
		return { kind = "bad" }
	end
	local fromText, posText = command:match("^!(%d+)pos%s+(%S+)$")
	if fromText ~= nil then
		local from, pos = wholeNumber(fromText), wholeNumber(posText)
		if from ~= nil and pos ~= nil then
			return { kind = "swap", from = from, pos = pos }
		end
		return { kind = "bad" }
	end
	if command:match("^!%d*pos") ~= nil then
		return { kind = "bad" }
	end
	return nil
end

local function isPosition(pos)
	return type(pos) == "number" and pos >= 1 and pos <= 5
end

-- One two-way swap between the holders of position `fromPos` and position `toPos` (current positions, as `!pos`
-- lists them; maintainer, game 087: "yes make X and Y as the current position"). `!Xpos Y` is PlanSwap(X, Y); `!pos
-- Y` is PlanSwap(<the sender's position>, Y). Only the two holders move, and a swap is symmetric: `!3pos 2` twice
-- restores the roles, and `!3pos 2` is the same swap as `!2pos 3`.
--   roles[slot]  = position (1..5) of team slot 1..5
--   humans[slot] = true for a human player
--   cores[slot]  = true for a bot whose hero is clearly a core (never put on 4/5)
--   sender       = the slot of the player who typed the command (nil when unknown); any player may swap two bots
-- Returns a plan { result = "ok" | "same" | "missing" | "human" | "core" | "core-holder", from, to, mover, holder,
-- holderFrom, holderTo, sender, moverHuman, humanSlot, humanPos, missingPos }. mover is the slot that holds `fromPos`
-- (it moves to `toPos`), holder the slot that holds `toPos` (it moves to `fromPos`; nil when nobody holds it).
-- Nothing is changed; PosRules.Apply does that.
--   missing:     a position outside 1..5, or nobody holds `fromPos` (missingPos says which).
--   same:        fromPos == toPos.
--   human:       one of the two holders is a human other than the sender (humanSlot / humanPos: who and where).
--   core:        the mover is a core bot and `toPos` is 4 or 5.
--   core-holder: the holder is a core bot and would get `fromPos` 4 or 5.
-- A core bot already on 4/5 can be swapped off it, but the repeat that would put it back is refused (core rule).
function PosRules.PlanSwap(roles, humans, cores, fromPos, toPos, sender)
	humans = humans or {}
	cores = cores or {}
	local plan = { from = fromPos, to = toPos, sender = sender }
	if not isPosition(fromPos) or not isPosition(toPos) then
		plan.result = "missing"
		plan.missingPos = isPosition(fromPos) and toPos or fromPos
		return plan
	end
	for slot = 1, 5 do
		if roles[slot] == fromPos then
			plan.mover = slot
			break
		end
	end
	if plan.mover == nil then
		plan.result = "missing"
		plan.missingPos = fromPos
		return plan
	end
	local mover = plan.mover
	plan.moverHuman = humans[mover] == true
	for slot = 1, 5 do
		if slot ~= mover and roles[slot] == toPos then
			plan.holder = slot
			break
		end
	end
	local holder = plan.holder
	if holder ~= nil then
		plan.holderFrom = toPos
		plan.holderTo = fromPos
	end
	if fromPos == toPos then
		plan.result = "same"
	elseif humans[mover] and mover ~= sender then
		plan.result = "human"
		plan.humanSlot, plan.humanPos = mover, fromPos
	elseif holder ~= nil and humans[holder] and holder ~= sender then
		plan.result = "human"
		plan.humanSlot, plan.humanPos = holder, toPos
	elseif not humans[mover] and cores[mover] and toPos >= 4 then
		plan.result = "core"
	elseif holder ~= nil and not humans[holder] and cores[holder] and fromPos >= 4 then
		plan.result = "core-holder"
	else
		plan.result = "ok"
	end
	return plan
end

-- Writes an "ok" plan into roles. Returns true when it changed something.
function PosRules.Apply(roles, plan)
	if plan == nil or plan.result ~= "ok" then
		return false
	end
	roles[plan.mover] = plan.to
	if plan.holder ~= nil then
		roles[plan.holder] = plan.holderTo
	end
	return true
end

-- A refused swap gets one team-chat reply naming the reason (game 082: `!pos 2` from Nature's Prophet was refused as
-- core-holder before the horn and nobody saw why; maintainer 2026-11-24 "sure go"). The swap runs in
-- hero_selection.lua's chat callback, where a chat order is lost (#225), so the reply is queued on the shared Role
-- table and the speaker says it from its think. A reply nobody said within ReplyMaxAge seconds is dropped.
PosRules.ReplyMaxAge = 10

-- Localization key and fields for each refused result (nil for "ok" and unknown results).
--   heroOf(slot) -> the display name of that slot's hero
-- "same" names who already holds the position: "you're" only for the human who typed the command, "I'm" when the
-- holder is a bot (PosRules.ReplySpeaker makes that bot the speaker), "<hero> is" for another human (game 087: Dark
-- Willow, a bot, said "you're already pos 2" about itself).
local replyKeys = {
	["core-holder"] = "say_pos_refused_core",
	core = "say_pos_refused_core",
	human = "say_pos_refused_human",
	same = "say_pos_refused_same",
	missing = "say_pos_refused_missing",
}
function PosRules.Reply(plan, heroOf)
	local key = plan and replyKeys[plan.result]
	if key == nil then
		return nil
	end
	local result = plan.result
	local fields = {}
	if result == "core-holder" then
		-- The holder would get the mover's old 4 or 5: "Puck can't play pos 5".
		fields.hero, fields.pos = heroOf(plan.holder), plan.holderTo
	elseif result == "core" then
		fields.hero, fields.pos = heroOf(plan.mover), plan.to
	elseif result == "human" then
		fields.hero, fields.pos = heroOf(plan.humanSlot), plan.humanPos
	elseif result == "same" then
		fields.pos = plan.to
		if plan.mover ~= nil and plan.mover ~= plan.sender then
			if plan.moverHuman then
				key = "say_pos_refused_same_other"
				fields.hero = heroOf(plan.mover)
			else
				key = "say_pos_refused_same_self"
			end
		end
	else
		fields.pos = plan.missingPos
	end
	return key, fields
end

-- Fills "{hero}" and "{pos}" in a localized template.
function PosRules.FillReply(template, fields)
	if type(template) ~= "string" then
		return nil
	end
	fields = fields or {}
	return (
		template:gsub("{(%a+)}", function(name)
			return fields[name] ~= nil and tostring(fields[name]) or "?"
		end)
	)
end

-- Who says the reply: the mover's player if it is a bot, otherwise the team's first bot (nil when no bot).
function PosRules.ReplySpeaker(teamPlayers, mover, isBot)
	local moverId = mover ~= nil and teamPlayers[mover] or nil
	if moverId ~= nil and isBot(moverId) then
		return moverId
	end
	for slot = 1, 5 do
		local playerId = teamPlayers[slot]
		if playerId ~= nil and isBot(playerId) then
			return playerId
		end
	end
	return nil
end

-- "1,2,3,4,5": the positions of slots 1..5, for the [SHy-ROLE] lines.
function PosRules.RolesText(roles)
	local parts = {}
	for slot = 1, 5 do
		parts[slot] = tostring(roles and roles[slot] or "-")
	end
	return table.concat(parts, ",")
end

function PosRules.Name(pos, names)
	return names and names[pos] or PosRules.Names[pos] or "?"
end

-- "Pos 2 Mid". `prefix` is the localized "Pos" (nil = "Pos").
function PosRules.Line(pos, names, prefix)
	return string.format("%s %s %s", prefix or "Pos", tostring(pos), PosRules.Name(pos, names))
end

-- Whether a bot answers the latest `!pos` request now.
--   requestAt:   GameTime() of the latest request (nil = none)
--   handledAt:   the request time this bot last handled (answered or dropped)
--   answeredAt:  GameTime() of this bot's last answer
--   now, pos:    the clock and the bot's position (pos 1 answers first)
-- Returns "none" (nothing new), "wait" (its turn has not come), "answer" or "drop" (answered less than
-- AnswerCooldown seconds before the request, or the request is older than AnswerMaxAge: the request is marked
-- handled without a line).
function PosRules.AnswerState(requestAt, handledAt, answeredAt, now, pos)
	if requestAt == nil or handledAt ~= nil and requestAt <= handledAt then
		return "none"
	end
	-- A request typed during the draft, before this bot existed, is old news once it spawns.
	if now - requestAt > PosRules.AnswerMaxAge then
		return "drop"
	end
	if answeredAt ~= nil and requestAt - answeredAt < PosRules.AnswerCooldown then
		return "drop"
	end
	if now < requestAt + PosRules.AnswerStep * (pos or 1) then
		return "wait"
	end
	return "answer"
end

return PosRules
