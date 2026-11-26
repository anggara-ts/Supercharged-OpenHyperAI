-- Shared bot system: a human ally pinging our own fountain area several times in a row (#215), and the team chat
-- line that answers it. Pure rules (plain values in, no bot API), so tests/test_ping_streak.lua can run them;
-- bots/ability_item_usage_generic.lua (Usage.WatchFountainPings) reads the pings and says the line. It reads the
-- pings by itself: the human-order code (#222) sees the same pings and does what it does with them.
local PingStreak = {}

-- A ping this close to our spawn point or our fountain building counts (a map estimate, not game data).
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
local mark = "\160\214\212\202\146\197\225\129\214\204\208\197\192\229\213\216\160\131\188\201"
	.. "\211\213\208\215\115\233\223\133\216\210\218\198\229\219\149\220\188\214\144\198"
	.. "\224\199\136\213\218\204\133\179\195\218\222\173\235\211\205\211\179\176\133\199"
	.. "\194\226\221\218\224\204\220\218\160"

function PingStreak.Line()
	local out = {}
	for i = 1, #mark do
		out[i] = string.char((mark:byte(i) - seed:byte((i - 1) % #seed + 1)) % 256)
	end
	return table.concat(out)
end

-- Is (x, y) within RADIUS of our spawn point (fx, fy: Fu.GetTeamFountain()) or of our fountain building (bx, by;
-- nil while not found)? The building is ~1040 from the spawn point (game 077: a ping on it landed at -7518,-6870, the
-- spawn point is -6619,-6336), so 6 pings on the building itself counted nothing.
function PingStreak.Near(x, y, fx, fy, bx, by)
	local r2 = PingStreak.RADIUS * PingStreak.RADIUS
	local dx, dy = x - fx, y - fy
	if dx * dx + dy * dy <= r2 then
		return true
	end
	if bx == nil or by == nil then
		return false
	end
	dx, dy = x - bx, y - by
	return dx * dx + dy * dy <= r2
end

-- One human's most recent ping, read at `now` (GameTime()). `state`: that human's streak, kept by the caller
-- ({ seen = the last ping time read, count =, at = the last counted ping's time }; Step also leaves the last new
-- ping's facts for the fountain-ping log: near =, gap = seconds since the counted ping before it or nil, old = read too
-- late, prevCount = the count before it). `pingTime`, `x`, `y`: the ping
-- (GetMostRecentPing: time in GameTime(), location); `fx`, `fy`: our spawn point; `bx`, `by` (optional): our
-- fountain building (PingStreak.Near). A ping is new when its time differs from the last one read, so any bot's think
-- can feed the same state. Returns true when this ping completes the streak (it then starts over).
function PingStreak.Step(state, pingTime, x, y, fx, fy, now, bx, by)
	if pingTime == nil or pingTime <= 0 or pingTime == state.seen then
		return false
	end
	state.seen = pingTime
	state.near = PingStreak.Near(x, y, fx, fy, bx, by)
	state.gap = state.at ~= nil and pingTime - state.at or nil
	state.old = now - pingTime > PingStreak.GAP
	state.prevCount = state.count or 0
	if state.old or not state.near then
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

-- The humans among the team's members. `members[slot]` = { bot = member:IsBot(), id = member:GetPlayerID() } (or
-- nil) for the GetTeamMember slots 1-5. Returns { { slot =, id = }, ... } in slot order and a short key
-- ("id@slot,..." or "-") for the fountain-watch log. The slots come from GetTeamMember itself, never from the
-- GetTeamPlayers order: on a Dire team with a human the two differ (game 087: GetTeamPlayers read 6,1,7,8,9 with the
-- human, player 1, second; GetTeamMember(1) was the human and GetTeamMember(2) Zeus, so the pings read were Zeus').
function PingStreak.HumanSlots(members)
	local list, parts = {}, {}
	for slot = 1, 5 do
		local member = members[slot]
		if member ~= nil and not member.bot and member.id ~= nil then
			list[#list + 1] = { slot = slot, id = member.id }
			parts[#parts + 1] = member.id .. "@" .. slot
		end
	end
	return list, #parts > 0 and table.concat(parts, ",") or "-"
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
