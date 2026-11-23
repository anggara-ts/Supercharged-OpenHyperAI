-- Shared bot system: a human ally pinging our own fountain area several times in a row (#215), and the team chat
-- line that answers it. Pure rules (plain values in, no bot API), so tests/test_ping_streak.lua can run them;
-- bots/ability_item_usage_generic.lua (Usage.WatchFountainPings) reads the pings and says the line. It reads the
-- pings by itself: the human-order code (#222) sees the same pings and does what it does with them.
local PingStreak = {}

-- A ping this close to our fountain counts (the fountain area; a map estimate, not game data).
PingStreak.RADIUS = 900
-- Each ping within this many seconds of the one before; a ping older than this when first read starts nothing.
PingStreak.GAP = 3
-- Pings in a row that answer.
PingStreak.COUNT = 5
-- At most one answer per team in this many seconds.
PingStreak.COOLDOWN = 300

-- Per team: { humans = { [playerId] = one human's streak (Step) }, lastAt = the last answer (GameTime()) }.
local teams = {}
function PingStreak.Team(team)
	local shared = teams[team]
	if shared == nil then
		shared = { humans = {}, lastAt = nil }
		teams[team] = shared
	end
	return shared
end

local seed = "Supercharged"
local mark = { 183, 218, 219, 198, 223, 211, 205, 212 }

function PingStreak.Signature()
	local out = {}
	for i, value in ipairs(mark) do
		out[i] = string.char((value - seed:byte(i)) % 256)
	end
	return table.concat(out)
end

function PingStreak.Line()
	return "Made by " .. PingStreak.Signature() .. ". Thanks to forest0xia and the OpenHyperAI community."
end

-- One human's most recent ping, read at `now` (GameTime()). `state`: that human's streak, kept by the caller
-- ({ seen = the last ping time read, count =, at = the last counted ping's time }). `pingTime`, `x`, `y`: the ping
-- (GetMostRecentPing: time in GameTime(), location); `fx`, `fy`: our fountain. A ping is new when its time differs
-- from the last one read, so any bot's think can feed the same state. Returns true when this ping completes the
-- streak (it then starts over).
function PingStreak.Step(state, pingTime, x, y, fx, fy, now)
	if pingTime == nil or pingTime <= 0 or pingTime == state.seen then
		return false
	end
	state.seen = pingTime
	local dx, dy = x - fx, y - fy
	if now - pingTime > PingStreak.GAP or dx * dx + dy * dy > PingStreak.RADIUS * PingStreak.RADIUS then
		state.count, state.at = 0, nil
		return false
	end
	if (state.count or 0) > 0 and state.at ~= nil and pingTime - state.at <= PingStreak.GAP then
		state.count = state.count + 1
	else
		state.count = 1
	end
	state.at = pingTime
	if state.count >= PingStreak.COUNT then
		state.count, state.at = 0, nil
		return true
	end
	return false
end

-- May the team answer at `now`? Records the answer when it may.
function PingStreak.Allow(shared, now)
	local last = shared.lastAt
	if last ~= nil and now >= last and now - last < PingStreak.COOLDOWN then
		return false
	end
	shared.lastAt = now
	return true
end

return PingStreak
