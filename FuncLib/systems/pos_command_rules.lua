-- Pure rules for the position chat commands (#210): parsing `!pos`, `!pos Y` and `!Xpos Y`, the two-way swap,
-- the position names and the throttle for the bots' "Pos N <name>" answer. No bot API here, so Tests/ can load it.
local PosRules = {}

-- English names. Localization.Get("pos_names") can give a translated list; a missing entry falls back to these.
PosRules.Names = { "Carry", "Mid", "Offlane", "Offlane Support", "Hard Support" }

-- Seconds a bot waits before it answers `!pos` again (a second callback or a repeated `!pos` inside the window is
-- dropped), and the gap between the bots' lines (pos 1 speaks first, pos 5 last). 30s is the window of
-- FuncLib/systems/chat_guard.lua: a team says the same text at most once per 30s, so a faster repeat would be
-- swallowed there unseen.
PosRules.AnswerCooldown = 30
PosRules.AnswerStep = 0.6
-- A request older than this is dropped without an answer.
PosRules.AnswerMaxAge = 20

-- "!pos" -> { kind = "list" }; "!pos 2" -> { kind = "take", pos = 2 }; "!3pos 5" -> { kind = "swap", index = 3,
-- pos = 5 }. Anything else that starts with "!pos" / "!Npos" -> { kind = "bad" }; other text -> nil.
-- Positions outside 1..5 and indexes outside 1..5 are "bad" too.
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
		local pos = tonumber(takeArg)
		if pos ~= nil and pos >= 1 and pos <= 5 and pos == math.floor(pos) then
			return { kind = "take", pos = pos }
		end
		return { kind = "bad" }
	end
	local indexText, posText = command:match("^!(%d+)pos%s+(%S+)$")
	if indexText ~= nil then
		local index, pos = tonumber(indexText), tonumber(posText)
		if index >= 1 and index <= 5 and pos ~= nil and pos >= 1 and pos <= 5 and pos == math.floor(pos) then
			return { kind = "swap", index = index, pos = pos }
		end
		return { kind = "bad" }
	end
	if command:match("^!%d*pos") ~= nil then
		return { kind = "bad" }
	end
	return nil
end

-- One swap: slot `mover` takes `newPos`, the slot that held `newPos` takes the mover's old position, every other slot
-- keeps its position.
--   roles[slot]  = position (1..5) of team slot 1..5
--   humans[slot] = true for a human player
--   cores[slot]  = true for a bot whose hero is clearly a core (never put on 4/5)
--   sender       = the slot of the player who typed the command (nil when unknown)
-- Returns a plan { result = "ok" | "same" | "missing" | "human-mover" | "human" | "core" | "core-holder",
-- mover, from, to, holder, holderFrom, holderTo }. Nothing is changed; PosRules.Apply does that.
--   human-mover: `!Xpos Y` names another human (a human only moves himself, with `!pos Y`).
--   human:       Y belongs to another human.
--   core:        the mover is a core bot and Y is 4 or 5.
--   core-holder: the holder of Y is a core bot and would get the mover's old 4 or 5.
function PosRules.PlanSwap(roles, humans, cores, mover, newPos, sender)
	humans = humans or {}
	cores = cores or {}
	local plan = { mover = mover, to = newPos, from = roles[mover] }
	if plan.from == nil then
		plan.result = "missing"
		return plan
	end
	for slot = 1, 5 do
		if slot ~= mover and roles[slot] == newPos then
			plan.holder = slot
			break
		end
	end
	if plan.holder ~= nil then
		plan.holderFrom = newPos
		plan.holderTo = plan.from
	end
	if plan.from == newPos then
		plan.result = "same"
	elseif humans[mover] and mover ~= sender then
		plan.result = "human-mover"
	elseif plan.holder ~= nil and humans[plan.holder] then
		plan.result = "human"
	elseif not humans[mover] and cores[mover] and newPos >= 4 then
		plan.result = "core"
	elseif plan.holder ~= nil and not humans[plan.holder] and cores[plan.holder] and plan.from >= 4 then
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

-- "1,2,3,4,5": the positions of slots 1..5, for the [OHA-ROLE] lines.
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
