-- Interaction probe (#111, #53): does a bot get, and can it use, the 7.42 map interaction abilities: the watcher's
-- ability_lamp_use, the Twin Gate's twin_gate_portal_warp and the outpost's ability_capture?
--
-- Game 074 (human trace, #220): a human hero's ability list grew ability_lamp_use (t=3, ~500 from the watcher at
-- 1032,-4260), twin_gate_portal_warp (t=1241, ~613 from the top gate) and ability_capture (t=1427, far from every
-- outpost, 12s after the Dire top tier-2 fell); each stayed in the list for the rest of the game. The human then
-- cast ability_lamp_use on the watchers at 1032,-4260 and 2718,-657 (~1s channel from ~200), the gate warp (a 4s
-- channel, then he stood at the other gate) and ability_capture on the north outpost 3392,-448 from ~400 (a 6s
-- channel; the outpost carried modifier_watch_tower_capturing, and it had lost modifier_watch_tower_invulnerable at
-- t=1471). Every "bots have no such ability" line so far came from bots that never stood at a watcher or a gate.
--
-- Off unless the local setting Customize.Interact_Probe == true (absent in the shipped Customize/general.lua, so a
-- Workshop copy never runs it). One bot per team: the pos 5 bot, else pos 3, else pos 4; never a human, and on
-- Radiant never the item swap probe's bot (#219: the highest-position Radiant bot) while Customize.Swap_Probe is on.
--   watcher  walk to the nearest verified watcher (STEPS from 1500 down to 100, standing at each), then orders on
--            any unit found at the spot (move-to-unit, attack, use-shrine), then a ring around the spot. When
--            ability_lamp_use shows up: cast it (on the location, on the unit, no target) and log the channel.
--   gate     the same at the nearest Twin Gate (npc_dota_unit_twin_gate, in UNIT_LIST_ALL); a cast is judged by
--            where the bot stands after the channel (at the other gate or not).
--   outpost  after 10:00: every 10s the ability list is checked for ability_capture (logged when it changes, with
--            whether an enemy tier-2 is down). With the ability and an outpost of the other team that lacks
--            modifier_watch_tower_invulnerable: walk to ~350 and cast it (location, unit, location), log the
--            channel, the capturing modifier and the outpost's team. Within 600 of any outpost the full ability
--            list is logged too.
-- The watcher and gate tries run after the horn until 4:00, and again 10:00-25:00 if needed; outpost tries until
-- 60:00. Each kind gets up to 3 tries; a try stops (and is retried 45s later) on an enemy hero within 1200, HP
-- under 60% or death, and the bot's normal modes take over.
-- Hook: mode_outpost_generic.lua GetDesire returns M.Desire while a try runs, and its Think hands over to M.Think.
-- Logs: [OHA-PROBE] t= <hero> interact kind=watcher|gate|outpost step=start|abilities|approach|units|poke|found|
-- cast|result|abort|summary|scan ...; then a team chat line "Interaction test done: watcher=.. gate=.. outpost=..".
local M = {}

M.DESIRE = 1.5 -- above every normal mode; the probe gives up (returns nil) on danger, so retreat still wins
M.STEPS = { 1500, 1200, 900, 700, 500, 400, 250, 150, 100 }
M.DWELL = 1.5 -- seconds standing at a step
M.LONG_DWELL = { [400] = 4, [150] = 4 }
M.STEP_SLACK = 50
M.RING_RADIUS = 350
M.RING_POINTS = 6
M.RING_FOR = 4 -- seconds per ring point at most
M.POKES = { "move-to-unit", "attack", "use-shrine" }
M.POKE_FOR = 2.5
M.SAMPLE_EVERY = 0.5
M.MAX_TRIES = 3
M.TRY_TIMEOUT = 180
M.RETRY_AFTER = 45
M.DANGER_RANGE = 1200
M.HP_MIN = 0.6
M.CAST_WAIT = 3 -- seconds after a cast order before it is judged (longer while the bot walks into range)
M.CAST_WALK_MAX = 8
M.GATE_SETTLE = 2 -- seconds after the warp channel ends before the position is read
M.GATE_ARRIVED = 1500 -- within this of the other gate counts as arrived
M.CAPTURE_DIST = 350 -- game 074: the human cast ability_capture from ~395-400
-- How close the bot walks before the first cast once the ability is there (the abilities stay once given, so a retry
-- can start with one thousands away). Lamp: cast range 200 (game files, mode_watcher_generic.lua). Warp: unverified
-- (the human got it ~613 from the gate). Capture: the human cast it from ~395-400 (game 074).
M.CAST_FROM = { watcher = 150, gate = 300, outpost = M.CAPTURE_DIST }
M.CAPTURE_SETTLE = 1.5
M.SCAN_EVERY = 10
M.SCAN_HEARTBEAT = 120
M.PASSIVE_RANGE = 600
M.STUCK_MOVE = 30
M.STUCK_FOR = 3
M.KINDS = { "watcher", "gate", "outpost" }
M.ABILITY = { watcher = "ability_lamp_use", gate = "twin_gate_portal_warp", outpost = "ability_capture" }
M.SHORT = { ability_lamp_use = "lamp", twin_gate_portal_warp = "warp", ability_capture = "capture" }
M.NAMES = { "ability_lamp_use", "twin_gate_portal_warp", "ability_capture" }
M.CAST_PLAN = {
	watcher = { "location", "entity", "none" },
	gate = { "entity", "location", "none" },
	outpost = { "location", "entity", "location" },
}
-- Game seconds in which a try may start.
M.WINDOWS = {
	watcher = { { 0, 240 }, { 600, 1500 } },
	gate = { { 0, 240 }, { 600, 1500 } },
	outpost = { { 600, 3600 } },
}
M.END = 3600
-- Watchers are in no unit list in 7.42 ([OHA-WATCHER] lanterns=0, games 073-074), so the spots are fixed. Both are
-- the location of a human's ability_lamp_use cast in game 074 (verified). Not used, unverified: -1564,3953 (where
-- Valve's watcher mode held Lich in game 049) and the mirrors of the two through the map centre (-1032,4260 and
-- -2718,657): a "no" at a guessed spot would prove nothing.
M.WATCHER_SPOTS = { { 1032, -4260 }, { 2718, -657 } }
M.PARTS_SIZE = 12 -- ability entries per log line (console lines get cut)

-- ---------------------------------------------------------------- pure rules (Tests/test_interact_probe.lua)

function M.InWindow(kind, now)
	for _, window in ipairs(M.WINDOWS[kind] or {}) do
		if now >= window[1] and now < window[2] then
			return true
		end
	end
	return false
end

-- Why the bot must stop now, or nil.
function M.Danger(alive, hpRatio, enemies)
	if not alive then
		return "dead"
	end
	if hpRatio < M.HP_MIN then
		return "hp"
	end
	if enemies > 0 then
		return "enemy"
	end
	return nil
end

-- kinds = { watcher = { tries =, result = }, ... }. The first kind (in M.KINDS order) still open whose window is on.
function M.NextKind(kinds, now)
	for _, kind in ipairs(M.KINDS) do
		local entry = kinds[kind]
		if entry.result == nil and entry.tries < M.MAX_TRIES and M.InWindow(kind, now) then
			return kind
		end
	end
	return nil
end

-- A kind is closed once it has a result, used up its tries or its last window is over.
function M.Closed(kind, entry, now)
	if entry.result ~= nil or entry.tries >= M.MAX_TRIES then
		return true
	end
	local windows = M.WINDOWS[kind]
	return now >= windows[#windows][2]
end

-- yes = a cast worked, ability = the ability came but no cast worked, no = it never came, untested = never got there.
function M.Verdict(entry)
	return entry.result or "untested"
end

function M.ChatLine(kinds, now)
	local parts = {}
	for _, kind in ipairs(M.KINDS) do
		local entry = kinds[kind]
		local verdict = M.Verdict(entry)
		if entry.result == nil and not M.Closed(kind, entry, now) then
			verdict = kind == "outpost" and "waiting(enemy tier-2)" or "waiting"
		end
		parts[#parts + 1] = kind .. "=" .. verdict
	end
	return "Interaction test done: " .. table.concat(parts, " ")
end

-- The point dist away from target on the line to from (from itself when it is at the target).
function M.ApproachPoint(tx, ty, fx, fy, dist)
	local dx, dy = fx - tx, fy - ty
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then
		return tx + dist, ty
	end
	return tx + dx / len * dist, ty + dy / len * dist
end

function M.RingPoint(cx, cy, i)
	local angle = (i - 1) * 2 * math.pi / M.RING_POINTS
	return cx + math.cos(angle) * M.RING_RADIUS, cy + math.sin(angle) * M.RING_RADIUS
end

-- The first step index still ahead of a bot dist away (steps it is already inside are skipped).
function M.FirstStep(dist)
	for i, step in ipairs(M.STEPS) do
		if step < dist + M.STEP_SLACK then
			return i
		end
	end
	return #M.STEPS
end

function M.Dwell(step)
	return M.LONG_DWELL[step] or M.DWELL
end

-- spots = { {x, y}, ... }: index of the nearest to (x, y).
function M.Nearest(spots, x, y)
	local best, bestD = nil, math.huge
	for i, spot in ipairs(spots) do
		local dx, dy = spot[1] - x, spot[2] - y
		local d = dx * dx + dy * dy
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

function M.SlotEntry(slot, name, hidden, castable, level)
	return string.format("%d:%s:h=%s:c=%s:l=%d", slot, name, tostring(hidden), tostring(castable), level)
end

-- entries -> log line bodies of at most M.PARTS_SIZE entries ("part=i/n n=N list=...").
function M.Parts(entries)
	local count = math.max(1, math.ceil(#entries / M.PARTS_SIZE))
	local parts = {}
	for part = 1, count do
		local chunk = {}
		for i = (part - 1) * M.PARTS_SIZE + 1, math.min(#entries, part * M.PARTS_SIZE) do
			chunk[#chunk + 1] = entries[i]
		end
		parts[part] = string.format("part=%d/%d n=%d list=%s", part, count, #entries, table.concat(chunk, ","))
	end
	return parts
end

-- members = { [slot] = { pos =, isBot = } }: the slot the item swap probe takes (#219: the highest position among
-- the Radiant bots, a later slot winning a tie).
function M.SwapProbeSlot(members)
	local best, bestPos = nil, nil
	for slot = 1, 5 do
		local member = members[slot]
		if member ~= nil and member.isBot and (bestPos == nil or member.pos >= bestPos) then
			best, bestPos = slot, member.pos
		end
	end
	return best
end

-- The probe slot: a bot at pos 5, else 3, else 4, never the excluded slot.
function M.PickProbe(members, excludeSlot)
	for _, wanted in ipairs({ 5, 3, 4 }) do
		for slot = 1, 5 do
			local member = members[slot]
			if member ~= nil and member.isBot and member.pos == wanted and slot ~= excludeSlot then
				return slot
			end
		end
	end
	return nil
end

-- The outpost try's start: the capture ability is there and an outpost of the other team, one without
-- modifier_watch_tower_invulnerable first. Game 074 cannot say whether that modifier goes before the capture or
-- because of it (the human trace saw it gone at t=1471, while the human already walked in to cast), so an
-- invulnerable one is tried too.
function M.CanCapture(hasCapture, outposts, ourTeam)
	if not hasCapture then
		return nil
	end
	local fallback = nil
	for i, outpost in ipairs(outposts) do
		if outpost.team ~= ourTeam then
			if not outpost.invulnerable then
				return i
			end
			fallback = fallback or i
		end
	end
	return fallback
end

-- ---------------------------------------------------------------- game side

local states = {}
local settingsRead, enabled, swapProbeOn = false, false, false

local function Enabled()
	if not settingsRead then
		settingsRead = true
		local ok, settings = pcall(require, GetScriptDirectory() .. "/FuncLib/systems/custom_loader")
		enabled = ok and type(settings) == "table" and settings.Interact_Probe == true
		swapProbeOn = ok and type(settings) == "table" and settings.Swap_Probe == true
	end
	return enabled
end

local function TeamState()
	local team = GetTeam()
	local s = states[team]
	if s == nil then
		s = { decided = false }
		states[team] = s
	end
	return s
end

local function HeroName(bot)
	return (string.gsub(bot:GetUnitName(), "npc_dota_hero_", ""))
end

local function Log(fmt, ...)
	pcall(print, string.format(fmt, ...))
end

local function Pt(loc)
	return loc ~= nil and string.format("%d,%d", math.floor(loc.x), math.floor(loc.y)) or "-"
end

local function Line(bot, kind, step, fmt, ...)
	local rest = fmt ~= nil and string.format(fmt, ...) or ""
	Log("[OHA-PROBE] t=%.0f %s interact kind=%s step=%s %s", DotaTime(), HeroName(bot), kind, step, rest)
end

local function Decide(s)
	if not Enabled() then
		s.decided = true
		return true
	end
	if DotaTime() < -80 then
		return false
	end
	local okFu, Fu = pcall(require, GetScriptDirectory() .. "/FuncLib/func_utils")
	local members, handles = {}, {}
	for slot = 1, 5 do
		local member = GetTeamMember(slot)
		if member == nil and DotaTime() < -60 then
			return false
		end
		if member ~= nil then
			local okP, pos = false, nil
			if okFu and Fu ~= nil and Fu.GetPosition ~= nil then
				okP, pos = pcall(Fu.GetPosition, member)
			end
			members[slot] = { pos = okP and tonumber(pos) or slot, isBot = member:IsBot() }
			handles[slot] = member
		end
	end
	s.decided = true
	local exclude = nil
	if swapProbeOn and GetTeam() == TEAM_RADIANT then
		exclude = M.SwapProbeSlot(members)
	end
	local slot = M.PickProbe(members, exclude)
	if slot == nil then
		Log(
			"[OHA-PROBE] t=%.0f team=%d interact no-bot (no pos 5/3/4 bot) swapSlot=%s",
			DotaTime(),
			GetTeam(),
			tostring(exclude)
		)
		return true
	end
	s.bot = handles[slot]
	s.kinds = {}
	for _, kind in ipairs(M.KINDS) do
		s.kinds[kind] = { tries = 0 }
	end
	s.nextTryAt = -999
	s.scan = { at = -999, key = nil, loggedAt = -999 }
	s.passive = { at = -999, sig = nil }
	Log(
		"[OHA-PROBE] t=%.0f %s interact probe-start team=%d slot=%d pos=%s swapSlot=%s",
		DotaTime(),
		HeroName(s.bot),
		GetTeam(),
		slot,
		tostring(members[slot].pos),
		tostring(exclude)
	)
	return true
end

-- The bot's full ability list (slots 0-63) as log entries, plus the handle of each interaction ability (by name,
-- else by slot) and how it was found.
local function ReadAbilities(bot)
	local entries, bySlot = {}, {}
	for slot = 0, 63 do
		local ability = bot:GetAbilityInSlot(slot)
		if ability ~= nil and not ability:IsNull() then
			local name = ability:GetName()
			entries[#entries + 1] =
				M.SlotEntry(slot, name, ability:IsHidden(), ability:IsFullyCastable(), ability:GetLevel())
			if M.SHORT[name] ~= nil and bySlot[name] == nil then
				bySlot[name] = { ability = ability, how = "slot" .. slot }
			end
		end
	end
	local found = {}
	for _, name in ipairs(M.NAMES) do
		local ability = bot:GetAbilityByName(name)
		if ability ~= nil and not ability:IsNull() then
			found[name] = { ability = ability, how = "name" }
		else
			found[name] = bySlot[name]
		end
	end
	return entries, found
end

-- "lamp=nil warp=name:h=true:c=true:l=1 capture=nil"
local function NamedState(found)
	local parts = {}
	for _, name in ipairs(M.NAMES) do
		local entry = found[name]
		if entry == nil then
			parts[#parts + 1] = M.SHORT[name] .. "=nil"
		else
			local ability = entry.ability
			parts[#parts + 1] = string.format(
				"%s=%s:h=%s:c=%s:l=%d:cd=%.1f",
				M.SHORT[name],
				entry.how,
				tostring(ability:IsHidden()),
				tostring(ability:IsFullyCastable()),
				ability:GetLevel(),
				ability:GetCooldownTimeRemaining()
			)
		end
	end
	return table.concat(parts, " ")
end

-- Reads the list (at most every SAMPLE_EVERY unless forced), logs it when it changed since holder.sig.
local function Sample(bot, holder, kind, dist, now, force, extra)
	if not force and now - (holder.sampleAt or -999) < M.SAMPLE_EVERY then
		return holder.found or {}
	end
	holder.sampleAt = now
	local entries, found = ReadAbilities(bot)
	holder.found = found
	local sig = table.concat(entries, ",")
	if sig ~= holder.sig then
		holder.sig = sig
		for _, part in ipairs(M.Parts(entries)) do
			Line(bot, kind, "abilities", "dist=%d %s%s", math.floor(dist), extra or "", part)
		end
	end
	return found
end

local function Outposts(s)
	if s.outposts == nil or #s.outposts == 0 then
		s.outposts = {}
		for _, unit in pairs(GetUnitList(UNIT_LIST_ALL) or {}) do
			if unit ~= nil and not unit:IsNull() then
				local name = string.lower(unit:GetUnitName() or "")
				if string.find(name, "watch_tower", 1, true) or string.find(name, "outpost", 1, true) then
					s.outposts[#s.outposts + 1] = unit
				end
			end
		end
	end
	return s.outposts
end

local function Gates(s)
	if s.gates == nil or #s.gates < 2 then
		s.gates = {}
		for _, unit in pairs(GetUnitList(UNIT_LIST_ALL) or {}) do
			if unit ~= nil and not unit:IsNull() and unit:GetUnitName() == "npc_dota_unit_twin_gate" then
				s.gates[#s.gates + 1] = unit
			end
		end
	end
	return s.gates
end

local function OutpostInfo(s)
	local list = {}
	for _, unit in ipairs(Outposts(s)) do
		if not unit:IsNull() then
			list[#list + 1] = {
				unit = unit,
				team = unit:GetTeam(),
				invulnerable = unit:HasModifier("modifier_watch_tower_invulnerable"),
			}
		end
	end
	return list
end

-- A tier-2 of the enemy is gone (with that lane's tier-1: a nil tower list at the start does not count).
local function EnemyTier2Down()
	local enemy = GetOpposingTeam()
	local lanes = { { TOWER_TOP_1, TOWER_TOP_2 }, { TOWER_MID_1, TOWER_MID_2 }, { TOWER_BOT_1, TOWER_BOT_2 } }
	local standing, down = 0, false
	for _, lane in ipairs(lanes) do
		local t1, t2 = GetTower(enemy, lane[1]) ~= nil, GetTower(enemy, lane[2]) ~= nil
		standing = standing + (t1 and 1 or 0) + (t2 and 1 or 0)
		down = down or (not t1 and not t2)
	end
	return standing > 0 and down
end

-- Outpost watch (after 10:00, every SCAN_EVERY): ability_capture present or not, logged on change.
local function Scan(s, bot, now)
	if now < 600 or now - s.scan.at < M.SCAN_EVERY then
		return
	end
	s.scan.at = now
	local _, found = ReadAbilities(bot)
	local capture = found.ability_capture
	local info = OutpostInfo(s)
	local outpostStates = {}
	for _, outpost in ipairs(info) do
		outpostStates[#outpostStates + 1] = string.format(
			"%s:team=%d:inv=%s",
			Pt(outpost.unit:GetLocation()),
			outpost.team,
			tostring(outpost.invulnerable)
		)
	end
	local t2 = EnemyTier2Down()
	local key = string.format(
		"capture=%s t2down=%s outposts=%s",
		capture ~= nil and ("present:" .. capture.how) or "absent",
		tostring(t2),
		table.concat(outpostStates, ",")
	)
	if key ~= s.scan.key or now - s.scan.loggedAt >= M.SCAN_HEARTBEAT then
		s.scan.key, s.scan.loggedAt = key, now
		Line(bot, "outpost", "scan", "%s", key)
	end
	s.scan.capture = capture
	s.scan.info = info
end

-- The full list within PASSIVE_RANGE of any outpost (outside an outpost try), on change.
local function Passive(s, bot, now)
	if now - s.passive.at < 1 then
		return
	end
	s.passive.at = now
	for _, unit in ipairs(Outposts(s)) do
		if not unit:IsNull() then
			local dist = GetUnitToUnitDistance(bot, unit)
			if dist <= M.PASSIVE_RANGE then
				Sample(bot, s.passive, "outpost", dist, now, true, "passive=true team=" .. unit:GetTeam() .. " ")
				return
			end
		end
	end
end

local function Summary(s, bot, kind, why)
	local entry = s.kinds[kind]
	Line(
		bot,
		kind,
		"summary",
		"result=%s why=%s seenDist=%s cast=%s channel=%s tries=%d",
		M.Verdict(entry),
		why or "-",
		entry.seenDist ~= nil and tostring(math.floor(entry.seenDist)) or "-",
		entry.castMethod or "-",
		tostring(entry.channelSeen == true),
		entry.tries
	)
end

local function Close(s, bot, result, why)
	local try = s.cur
	s.kinds[try.kind].result = result
	Summary(s, bot, try.kind, why)
	s.cur = nil
	s.nextTryAt = DotaTime() + 3
end

local function Abort(s, bot, why)
	local try = s.cur
	-- An enemy at the other gate right after the warp: the warp still counts.
	if
		try.kind == "gate"
		and try.phase == "castwait"
		and try.far ~= nil
		and not try.far:IsNull()
		and GetUnitToUnitDistance(bot, try.far) <= M.GATE_ARRIVED
	then
		s.kinds.gate.castMethod = try.method
		Line(
			bot,
			"gate",
			"result",
			"method=%s channel=%s arrived=true at=%s abort=%s",
			try.method,
			tostring(try.sawChannel),
			Pt(bot:GetLocation()),
			why
		)
		Close(s, bot, "yes", "arrived")
		return
	end
	Line(bot, try.kind, "abort", "why=%s phase=%s try=%d", why, try.phase, s.kinds[try.kind].tries)
	s.cur = nil
	s.nextTryAt = DotaTime() + M.RETRY_AFTER
	local entry = s.kinds[try.kind]
	if entry.tries >= M.MAX_TRIES and entry.result == nil then
		-- The ability came on an earlier step of a try that never got a cast through.
		entry.result = entry.seenDist ~= nil and "ability" or nil
		Summary(s, bot, try.kind, "tries-used")
	end
end

local function Start(s, bot, kind, now)
	local entry = s.kinds[kind]
	local here = bot:GetLocation()
	local try = { kind = kind, startedAt = now, phase = "walk", lastPos = here, lastMoveAt = now }
	if kind == "watcher" then
		local spot = M.WATCHER_SPOTS[M.Nearest(M.WATCHER_SPOTS, here.x, here.y)]
		try.loc = Vector(spot[1], spot[2], 0)
		try.name = spot[1] .. "," .. spot[2]
	elseif kind == "gate" then
		local gates = Gates(s)
		if #gates < 2 then
			entry.tries = entry.tries + 1
			Log("[OHA-PROBE] t=%.0f %s interact kind=gate step=abort why=no-gate gates=%d", now, HeroName(bot), #gates)
			s.nextTryAt = now + M.RETRY_AFTER
			return
		end
		local near, far = gates[1], gates[2]
		if GetUnitToUnitDistance(bot, far) < GetUnitToUnitDistance(bot, near) then
			near, far = far, near
		end
		try.unit, try.far = near, far
		try.loc = near:GetLocation()
		try.name = "gate@" .. Pt(try.loc)
	else
		local index = M.CanCapture(s.scan.capture ~= nil, s.scan.info or {}, GetTeam())
		if index == nil then
			return
		end
		local outpost = s.scan.info[index]
		try.unit = outpost.unit
		try.loc = outpost.unit:GetLocation()
		try.name = "outpost@" .. Pt(try.loc)
		try.team = outpost.team
		try.found = true
		try.steps = { M.CAPTURE_DIST }
	end
	try.steps = try.steps or M.STEPS
	entry.tries = entry.tries + 1
	local dist = GetUnitToLocationDistance(bot, try.loc)
	try.stepIdx = kind == "outpost" and 1 or M.FirstStep(dist)
	s.cur = try
	Line(bot, kind, "start", "target=%s at=%s dist=%d try=%d", try.name, Pt(here), math.floor(dist), entry.tries)
	-- The baseline list (far from the object), always printed once per try.
	Sample(bot, try, kind, dist, now, true)
end

local function MoveTo(bot, try, x, y, now)
	if now - (try.orderAt or -999) >= 0.3 then
		try.orderAt = now
		bot:Action_MoveToLocation(Vector(x, y, 0))
	end
end

-- True when the bot has not moved STUCK_MOVE in STUCK_FOR seconds.
local function Stuck(bot, try, now)
	local here = bot:GetLocation()
	local dx, dy = here.x - try.lastPos.x, here.y - try.lastPos.y
	if dx * dx + dy * dy > M.STUCK_MOVE * M.STUCK_MOVE then
		try.lastPos, try.lastMoveAt = here, now
		return false
	end
	return now - try.lastMoveAt >= M.STUCK_FOR
end

local function UnitsNear(bot, loc)
	local found, seen = {}, {}
	local function add(list)
		for _, unit in pairs(list or {}) do
			if
				unit ~= nil
				and not unit:IsNull()
				and not seen[unit]
				and unit ~= bot
				and not unit:IsHero()
				and GetUnitToLocationDistance(unit, loc) <= 500
			then
				seen[unit] = true
				found[#found + 1] = unit
			end
		end
	end
	add(GetUnitList(UNIT_LIST_ALL))
	add(bot:GetNearbyCreeps(1000, true))
	add(bot:GetNearbyCreeps(1000, false))
	add(bot:GetNearbyNeutralCreeps(1000))
	return found
end

local function Pick(try, units)
	for _, unit in ipairs(units) do
		local name = string.lower(unit:GetUnitName() or "")
		if string.find(name, "lantern", 1, true) or string.find(name, "watcher", 1, true) then
			try.unit = unit
			return
		end
	end
end

local function Cast(bot, try, ability, method)
	if method == "location" then
		bot:Action_UseAbilityOnLocation(ability, try.loc)
	elseif method == "entity" then
		bot:Action_UseAbilityOnEntity(ability, try.unit)
	else
		bot:Action_UseAbility(ability)
	end
end

local function Poke(bot, try, order)
	if order == "move-to-unit" then
		bot:Action_MoveToUnit(try.unit)
		return "ok"
	elseif order == "attack" then
		bot:Action_AttackUnit(try.unit, true)
		return "ok"
	end
	local ok, err = pcall(bot.Action_UseShrine, bot, try.unit)
	return ok and "ok" or ("error:" .. tostring(err))
end

-- After the ability showed: the next cast method, or the kind's result when all were tried.
local function NextCast(s, bot, try, now)
	local plan = M.CAST_PLAN[try.kind]
	while true do
		try.castIdx = (try.castIdx or 0) + 1
		local method = plan[try.castIdx]
		if method == nil then
			-- Against an outpost that still had its invulnerability: not an answer, retried later.
			if try.kind == "outpost" and try.invAtCast and not try.anyChannel then
				Abort(s, bot, "invulnerable")
				return
			end
			Close(s, bot, "ability", "no-cast-worked")
			return
		end
		local entry = try.foundAbility
		if method == "entity" and (try.unit == nil or try.unit:IsNull()) then
			Line(bot, try.kind, "cast", "method=entity target=none skipped=true")
		elseif entry ~= nil then
			try.method, try.castAt, try.sawChannel, try.sawActive, try.sawCapturing = method, now, false, false, false
			try.phase = "castwait"
			Line(
				bot,
				try.kind,
				"cast",
				"method=%s target=%s dist=%d castable=%s cd=%.1f channelTime=%.1f",
				method,
				try.name,
				math.floor(GetUnitToLocationDistance(bot, try.loc)),
				tostring(entry:IsFullyCastable()),
				entry:GetCooldownTimeRemaining(),
				entry:GetChannelTime()
			)
			if try.kind == "outpost" and try.unit ~= nil and not try.unit:IsNull() then
				try.invAtCast = try.invAtCast or try.unit:HasModifier("modifier_watch_tower_invulnerable")
			end
			local okCast, castErr = pcall(Cast, bot, try, entry, method)
			if okCast then
				return
			end
			Line(bot, try.kind, "cast", "method=%s error=%s", method, tostring(castErr))
		else
			Close(s, bot, "ability", "handle-lost")
			return
		end
	end
end

local function Found(s, bot, try, ability, how, dist)
	try.found = true
	try.foundAbility = ability
	local entry = s.kinds[try.kind]
	entry.seenDist = entry.seenDist or dist
	Line(
		bot,
		try.kind,
		"found",
		"ability=%s by=%s dist=%d phase=%s",
		M.ABILITY[try.kind],
		how,
		math.floor(dist),
		try.phase
	)
end

local function Judge(s, bot, try, now)
	local entry = s.kinds[try.kind]
	entry.channelSeen = entry.channelSeen or try.sawChannel
	try.anyChannel = try.anyChannel or try.sawChannel
	local ability = try.foundAbility
	local cd = ability ~= nil and not ability:IsNull() and ability:GetCooldownTimeRemaining() or -1
	if try.kind == "gate" then
		local farDist = try.far ~= nil and not try.far:IsNull() and GetUnitToUnitDistance(bot, try.far) or -1
		local arrived = farDist >= 0 and farDist <= M.GATE_ARRIVED
		Line(
			bot,
			"gate",
			"result",
			"method=%s channel=%s active=%s arrived=%s at=%s farDist=%d cd=%.1f",
			try.method,
			tostring(try.sawChannel),
			tostring(try.sawActive),
			tostring(arrived),
			Pt(bot:GetLocation()),
			math.floor(farDist),
			cd
		)
		if arrived then
			entry.castMethod = try.method
			Close(s, bot, "yes", "arrived")
			return
		end
	elseif try.kind == "outpost" then
		local team = try.unit ~= nil and not try.unit:IsNull() and try.unit:GetTeam() or -1
		-- Only the probe bot's own channel counts: once a bot has the ability, ConsiderOutpostCapture lets any bot cast it.
		local captured = team == GetTeam() and try.sawChannel
		Line(
			bot,
			"outpost",
			"result",
			"method=%s channel=%s active=%s capturing=%s team=%d->%d captured=%s inv=%s cd=%.1f",
			try.method,
			tostring(try.sawChannel),
			tostring(try.sawActive),
			tostring(try.sawCapturing),
			try.team,
			team,
			tostring(captured),
			tostring(try.invAtCast == true),
			cd
		)
		if team == GetTeam() and not captured then
			Close(s, bot, "ability", "taken-by-another")
			return
		end
		if captured then
			entry.castMethod = try.method
			Close(s, bot, "yes", "captured")
			return
		end
	else
		local worked = try.sawChannel or cd > 0
		Line(
			bot,
			"watcher",
			"result",
			"method=%s channel=%s active=%s worked=%s cd=%.1f",
			try.method,
			tostring(try.sawChannel),
			tostring(try.sawActive),
			tostring(worked),
			cd
		)
		if worked then
			entry.castMethod = try.method
			Close(s, bot, "yes", "channel")
			return
		end
	end
	NextCast(s, bot, try, now)
end

local function Step(s, bot, now)
	local try = s.cur
	local dist = GetUnitToLocationDistance(bot, try.loc)
	local found = Sample(bot, try, try.kind, dist, now, false)
	local want = found[M.ABILITY[try.kind]]
	if try.phase == "castwait" then
		if bot:IsChanneling() then
			try.sawChannel = true
			try.channelEndAt = nil
		elseif try.sawChannel and try.channelEndAt == nil then
			try.channelEndAt = now
		end
		local active = bot:GetCurrentActiveAbility()
		if active ~= nil and not active:IsNull() and active:GetName() == M.ABILITY[try.kind] then
			try.sawActive = true
		end
		if try.kind == "outpost" and try.unit ~= nil and not try.unit:IsNull() then
			try.sawCapturing = try.sawCapturing
				or try.unit:HasModifier("modifier_watch_tower_capturing")
				or bot:HasModifier("modifier_watch_tower_capturing")
		end
		-- No order at all while the channel runs (a new order would break it).
		if bot:IsChanneling() then
			return
		end
		local settle = try.kind == "gate" and M.GATE_SETTLE or (try.kind == "outpost" and M.CAPTURE_SETTLE or 0)
		if try.sawChannel then
			if now - try.channelEndAt >= settle then
				Judge(s, bot, try, now)
			end
			return
		end
		local wait = try.sawActive and M.CAST_WALK_MAX or M.CAST_WAIT
		if now - try.castAt >= wait then
			Judge(s, bot, try, now)
		end
		return
	end
	if want ~= nil and not try.cast then
		if not try.foundLogged then
			try.foundLogged = true
			Found(s, bot, try, want.ability, want.how, dist)
		end
		try.foundAbility = want.ability
		-- Walk in to the cast distance first (straight, no more stops); a blocked walk casts from where it is.
		local castFrom = M.CAST_FROM[try.kind]
		if not try.closeIn then
			try.closeIn = true
			try.lastPos, try.lastMoveAt = bot:GetLocation(), now
		end
		if dist > castFrom + M.STEP_SLACK and not Stuck(bot, try, now) then
			local here = bot:GetLocation()
			local x, y = M.ApproachPoint(try.loc.x, try.loc.y, here.x, here.y, castFrom)
			MoveTo(bot, try, x, y, now)
			return
		end
		try.cast = true
		NextCast(s, bot, try, now)
		return
	end
	if try.phase == "walk" then
		local step = try.steps[try.stepIdx]
		local stuck = Stuck(bot, try, now)
		if dist <= step + M.STEP_SLACK or stuck then
			try.phase, try.dwellUntil, try.blocked = "dwell", now + M.Dwell(step), stuck
			bot:Action_ClearActions(true)
			return
		end
		local here = bot:GetLocation()
		local x, y = M.ApproachPoint(try.loc.x, try.loc.y, here.x, here.y, step)
		MoveTo(bot, try, x, y, now)
		return
	end
	if try.phase == "dwell" then
		if now < try.dwellUntil then
			return
		end
		Line(
			bot,
			try.kind,
			"approach",
			"dist=%d want=%d blocked=%s %s",
			math.floor(dist),
			try.steps[try.stepIdx],
			tostring(try.blocked),
			NamedState(found)
		)
		try.stepIdx = try.stepIdx + 1
		try.lastPos, try.lastMoveAt = bot:GetLocation(), now
		if try.stepIdx <= #try.steps then
			try.phase = "walk"
			return
		end
		if try.kind == "outpost" then
			-- At the capture spot with the ability: cast (want is nil only when the ability went away).
			if want == nil then
				Close(s, bot, "no", "capture-gone")
				return
			end
			try.cast = true
			NextCast(s, bot, try, now)
			return
		end
		local units = UnitsNear(bot, try.loc)
		local names = {}
		for i = 1, math.min(8, #units) do
			names[#names + 1] = string.format(
				"%s:%d:team=%d",
				units[i]:GetUnitName(),
				math.floor(GetUnitToLocationDistance(units[i], try.loc)),
				units[i]:GetTeam()
			)
		end
		Line(bot, try.kind, "units", "n=%d list=%s", #units, table.concat(names, ","))
		if try.kind == "watcher" then
			Pick(try, units)
		end
		try.phase, try.pokeIdx = "poke", 0
		try.pokeUntil = -999
		return
	end
	if try.phase == "poke" then
		if now < try.pokeUntil then
			return
		end
		try.pokeIdx = try.pokeIdx + 1
		local order = M.POKES[try.pokeIdx]
		if order == nil or try.unit == nil or try.unit:IsNull() then
			if order ~= nil then
				Line(bot, try.kind, "poke", "order=all target=none")
			end
			if try.kind == "watcher" then
				try.phase, try.ringIdx, try.ringUntil = "ring", 0, -999
				return
			end
			Close(s, bot, "no", "never-came")
			return
		end
		local result = Poke(bot, try, order)
		try.pokeUntil = now + M.POKE_FOR
		Line(
			bot,
			try.kind,
			"poke",
			"order=%s target=%s dist=%d result=%s",
			order,
			try.unit:GetUnitName(),
			math.floor(GetUnitToUnitDistance(bot, try.unit)),
			result
		)
		return
	end
	if try.phase == "ring" then
		local x, y
		if try.ringIdx > 0 then
			x, y = M.RingPoint(try.loc.x, try.loc.y, try.ringIdx)
		end
		local reached = x ~= nil and GetUnitToLocationDistance(bot, Vector(x, y, 0)) <= M.STEP_SLACK
		if try.ringIdx == 0 or reached or now >= try.ringUntil then
			if try.ringIdx > 0 then
				Line(bot, try.kind, "approach", "ring=%d dist=%d %s", try.ringIdx, math.floor(dist), NamedState(found))
			end
			try.ringIdx = try.ringIdx + 1
			if try.ringIdx > M.RING_POINTS then
				Close(s, bot, "no", "never-came")
				return
			end
			try.ringUntil = now + M.RING_FOR
			x, y = M.RingPoint(try.loc.x, try.loc.y, try.ringIdx)
		end
		MoveTo(bot, try, x, y, now)
	end
end

local function Finish(s, bot, now, final)
	local line = M.ChatLine(s.kinds, now)
	if line == s.chatLine then
		return
	end
	s.chatLine = line
	Log("[OHA-PROBE] t=%.0f %s interact done final=%s %s", now, HeroName(bot), tostring(final), line)
	pcall(bot.ActionImmediate_Chat, bot, line, false)
end

-- mode_outpost_generic.lua GetDesire, for every bot every frame: M.DESIRE while this bot runs a try, else nil.
function M.Desire(bot)
	local s = TeamState()
	if not s.decided and not Decide(s) then
		return nil
	end
	if s.bot == nil or s.done or bot ~= s.bot then
		return nil
	end
	local now = DotaTime()
	if now >= 0 and bot:IsAlive() then
		Scan(s, bot, now)
		if s.cur == nil or s.cur.kind ~= "outpost" then
			Passive(s, bot, now)
		end
	end
	local open = false
	for _, kind in ipairs(M.KINDS) do
		open = open or not M.Closed(kind, s.kinds[kind], now)
	end
	-- One chat line once watcher and gate are settled, another when the outpost is (or the time is up).
	if
		s.cur == nil
		and now - (s.finishAt or -999) >= 1
		and M.Closed("watcher", s.kinds.watcher, now)
		and M.Closed("gate", s.kinds.gate, now)
	then
		s.finishAt = now
		Finish(s, bot, now, not open)
	end
	if not open and s.cur == nil then
		Finish(s, bot, now, true)
		s.done = true
		return nil
	end
	local enemies = bot:GetNearbyHeroes(M.DANGER_RANGE, true, BOT_MODE_NONE) or {}
	local maxHealth = bot:GetMaxHealth()
	local hpRatio = maxHealth > 0 and bot:GetHealth() / maxHealth or 0
	local why = M.Danger(bot:IsAlive(), hpRatio, #enemies)
	if s.cur == nil then
		if now < s.nextTryAt or why ~= nil or bot:IsChanneling() then
			return nil
		end
		local kind = M.NextKind(s.kinds, now)
		if kind == nil then
			return nil
		end
		Start(s, bot, kind, now)
		if s.cur == nil then
			return nil
		end
	end
	if why == nil and now - s.cur.startedAt > M.TRY_TIMEOUT then
		why = "timeout"
	end
	if why ~= nil then
		Abort(s, bot, why)
		return nil
	end
	bot._noTpUntil = now + 1
	s.desireAt = now
	return M.DESIRE
end

-- mode_outpost_generic.lua Think: true when the probe gave this bot its orders.
function M.Think(bot)
	local s = states[GetTeam()]
	if s == nil or s.cur == nil or bot ~= s.bot or DotaTime() - (s.desireAt or -999) > 0.5 then
		return false
	end
	local ok, err = pcall(Step, s, bot, DotaTime())
	if not ok and s.cur ~= nil then
		Line(bot, s.cur.kind, "error", "err=%s", tostring(err))
		Abort(s, bot, "error")
	end
	return true
end

return M
