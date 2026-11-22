-- Human trace (#111): what a human player on our team does on the map, to learn how a 7.42 outpost capture or
-- watcher activation looks from the bot API. Since 7.42 bots have no ability_capture / ability_lamp_use
-- ([OHA-OUTPOST] capture-off, [OHA-WATCHER] state lamp=nil); Valve's 7.42 notes call it an interaction.
--
-- Local diagnostic only: runs when Customize/general.lua sets Customize.Human_Trace = true (absent in the shipped
-- files). The first bot slot of a team that has a human runs it for every human hero on that team. Every engine
-- call on the human handle goes through pcall and prints n/a when it errors: the lines also show which calls work
-- on a human hero.
--
-- [OHA-HUMAN] lines (on change only, plus at most 1 state line per second inside a trace window):
--   on tracer= humans=                       who traces whom
--   abilities part= list=slot:name:h=hidden:c=castable:l=level   at the start and when the list changes
--   items list=slot:name                     at the start and when it changes
--   cb-install pid= ok=                      InstallCastCallback for the human's player id
--   cast <every field of the event table>    each cast the callback reports
--   state channel= active= atk= act= queued= anim= cycle= vel= speed= at= near=
--   mods add= del=                           modifiers gained / lost by the human
--   near kind=outpost|watcher|watcher-spot|other unit= dist= team= at=    / near-end
--   unit-mods unit= team= alive= add= del=   modifiers on the outpost / unit next to the human
--   unit-team unit= from= to=                that unit changed team
--   outposts n= list=                        the outposts found (at the first scan)
--   outpost-captured unit= from= to= by= after=
--   units add= del=                          non-hero, non-creep unit names that appear in / leave the unit lists
--   watcher-vision spot= vis= allyDist=      vision at a candidate watcher spot (an active watcher gives vision)
-- A trace window (10s) opens while the human channels, casts, has an active ability, is within 700 of an outpost,
-- a watcher spot or another map object (an outpost first, then the closest), or gains any modifier.
local H = {}

H.NEAR = 700
H.WINDOW = 10
H.LINE_EVERY = 1
H.NEAR_LINE_EVERY = 5
H.SAMPLE_EVERY = 0.25 -- outside a window; inside one every think
H.SCAN_EVERY = 1
H.OUTPOST_SCAN_EVERY = 10
H.ABILITY_EVERY = 2
H.REFRESH_EVERY = 5
H.CAPTURE_CREDIT = 900 -- outpost-captured by= names a human this close
H.VISION_EVERY = 5
H.ABILITY_SLOTS = 35
H.ITEM_SLOTS = 25

-- Watchers (npc_dota_lantern) are in no unit list in 7.42 (game 073 [OHA-WATCHER] unit-survey, lanterns=0), so the
-- trace also watches these points. Unverified: they are where Valve's own watcher mode held Lich and Ringmaster in
-- game 049 ([OHA-STUCK] mode=watcher moved=0), not positions read from the map. The human's at= on a channel line
-- gives the real ones.
H.WATCHER_SPOTS = { { 1091, -4300 }, { -1564, 3953 } }

-- Pure helpers (Tests/test_human_trace.lua).

-- Sorted names in new but not old, and in old but not new (sets: name -> true or a count).
function H.SetDiff(old, new)
	local added, removed = {}, {}
	for name, value in pairs(new) do
		if old[name] ~= value then
			if old[name] == nil or (type(value) == "number" and value > (old[name] or 0)) then
				added[#added + 1] = name
			else
				removed[#removed + 1] = name
			end
		end
	end
	for name in pairs(old) do
		if new[name] == nil then
			removed[#removed + 1] = name
		end
	end
	table.sort(added)
	table.sort(removed)
	return added, removed
end

-- "outpost" / "watcher" by unit name, else nil.
function H.Kind(name)
	local lower = string.lower(name or "")
	if string.find(lower, "outpost", 1, true) or string.find(lower, "watch_tower", 1, true) then
		return "outpost"
	end
	if string.find(lower, "lantern", 1, true) or string.find(lower, "watcher", 1, true) then
		return "watcher"
	end
	return nil
end

-- Units the near scan and the unit-list diff leave out: heroes, creeps, wards, couriers, thinkers, lane buildings.
local SKIP = {
	"npc_dota_hero_",
	"creep",
	"ward",
	"courier",
	"thinker",
	"wisp_spirit",
	"guys_",
	"halloffame",
	"illusion",
	"neutral",
	"roshan",
}
function H.Skip(name)
	if H.Kind(name) ~= nil then
		return false
	end
	local lower = string.lower(name or "")
	if lower == "dota_fountain" then
		return true
	end
	for _, part in ipairs(SKIP) do
		if string.find(lower, part, 1, true) then
			return true
		end
	end
	return false
end

-- Near-object choice: an outpost beats a watcher, a watcher spot and any other object (a closer neutral creep or
-- summon must not hide the outpost), then the closer one wins. a and b are { kind =, dist = } or nil.
local KIND_RANK = { outpost = 1, watcher = 2, ["watcher-spot"] = 3, other = 4 }
function H.Better(a, b)
	if a == nil then
		return false
	end
	if b == nil then
		return true
	end
	local rankA, rankB = KIND_RANK[a.kind] or 5, KIND_RANK[b.kind] or 5
	if rankA ~= rankB then
		return rankA < rankB
	end
	return a.dist < b.dist
end

-- First slot (1..5) whose flag is true, or nil.
function H.FirstBotSlot(isBot)
	for slot = 1, 5 do
		if isBot[slot] then
			return slot
		end
	end
	return nil
end

-- Change key of an ability list: slot, name and hidden (castable and level change all the time).
function H.AbilityKey(entries)
	local parts = {}
	for _, entry in ipairs(entries) do
		parts[#parts + 1] = string.format("%d:%s:%s", entry.slot, tostring(entry.name), tostring(entry.hidden))
	end
	return table.concat(parts, ",")
end

-- Short text for a value: nil -> "-", numbers rounded, vectors "x,y", units / abilities by name.
function H.Describe(value)
	local kind = type(value)
	if value == nil then
		return "-"
	elseif kind == "number" then
		if value == math.floor(value) then
			return string.format("%d", value)
		end
		return string.format("%.2f", value)
	elseif kind == "boolean" or kind == "string" then
		return tostring(value)
	end
	local okX, x = pcall(function()
		return value.x
	end)
	local okY, y = pcall(function()
		return value.y
	end)
	if okX and okY and type(x) == "number" and type(y) == "number" then
		return string.format("%.0f,%.0f", x, y)
	end
	local okUnit, unitName = pcall(function()
		return value:GetUnitName()
	end)
	if okUnit and type(unitName) == "string" then
		return unitName
	end
	local okName, abilityName = pcall(function()
		return value:GetName()
	end)
	if okName and type(abilityName) == "string" then
		return abilityName
	end
	if kind == "table" then
		local parts = {}
		for k, v in pairs(value) do
			if #parts >= 12 then
				break
			end
			parts[#parts + 1] = tostring(k) .. ":" .. (type(v) == "table" and "{}" or tostring(v))
		end
		return "{" .. table.concat(parts, ";") .. "}"
	end
	return tostring(value)
end

-- list split into strings of at most size entries joined by ","; at least one (empty) string.
function H.Chunks(list, size)
	local chunks, current = {}, {}
	for _, item in ipairs(list) do
		current[#current + 1] = item
		if #current >= size then
			chunks[#chunks + 1] = table.concat(current, ",")
			current = {}
		end
	end
	if #current > 0 or #chunks == 0 then
		chunks[#chunks + 1] = table.concat(current, ",")
	end
	return chunks
end

-- Runtime.

-- One state per team (the bots of both teams may share this module), set at the start of each Tick.
local enabled, errorLogged = nil, false
local states = {}
local state = nil
local function NewState()
	return {
		refreshAt = -999,
		tracer = nil,
		humans = {},
		traced = {},
		startKey = nil,
		outposts = {},
		outpostTeams = {},
		outpostScanAt = -999,
		outpostsLogged = false,
		unitNames = nil,
		unitScanAt = -999,
		spotVision = {},
		spotVisionAt = {},
		spotScanAt = -999,
	}
end

local function Try(object, method, ...)
	local args = { ... }
	local ok, value = pcall(function()
		return object[method](object, unpack(args))
	end)
	if ok then
		return value
	end
	return "n/a"
end

local function Short(name)
	return (string.gsub(tostring(name or "?"), "npc_dota_hero_", ""))
end

local function Log(hero, what)
	print(string.format("[OHA-HUMAN] t=%.0f %s %s", DotaTime(), hero, what))
end

local function Valid(unit)
	return unit ~= nil and unit ~= "n/a" and not unit:IsNull()
end

local function At(unit)
	local loc = Try(unit, "GetLocation")
	return H.Describe(loc ~= "n/a" and loc or nil)
end

local function Modifiers(unit)
	local set = {}
	local count = Try(unit, "NumModifiers")
	if type(count) ~= "number" then
		return set, false
	end
	for i = 0, math.min(count, 64) - 1 do
		local name = Try(unit, "GetModifierName", i)
		if type(name) == "string" then
			set[name] = true
		end
	end
	return set, true
end

local function Abilities(human)
	local entries = {}
	for slot = 0, H.ABILITY_SLOTS do
		local ability = Try(human, "GetAbilityInSlot", slot)
		if ability ~= nil and ability ~= "n/a" then
			entries[#entries + 1] = {
				slot = slot,
				name = Try(ability, "GetName"),
				hidden = Try(ability, "IsHidden"),
				castable = Try(ability, "IsFullyCastable"),
				level = Try(ability, "GetLevel"),
			}
		end
	end
	return entries
end

local function Items(human)
	local list = {}
	for slot = 0, H.ITEM_SLOTS do
		local item = Try(human, "GetItemInSlot", slot)
		if item ~= nil and item ~= "n/a" then
			list[#list + 1] = slot .. ":" .. H.Describe(Try(item, "GetName"))
		elseif item == "n/a" then
			list[#list + 1] = slot .. ":n/a"
		end
	end
	return list
end

local function OnCast(trace, event)
	trace.windowUntil = DotaTime() + H.WINDOW
	local parts = {}
	if type(event) == "table" then
		local keys = {}
		for key in pairs(event) do
			keys[#keys + 1] = tostring(key)
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local value = event[key]
			if value == nil then
				value = event[tonumber(key)]
			end
			parts[#parts + 1] = key .. "=" .. H.Describe(value)
		end
	else
		parts[1] = "event=" .. H.Describe(event)
	end
	Log(trace.name, "cast " .. table.concat(parts, " ") .. " at=" .. At(trace.unit))
end

-- Nearest outpost / watcher spot / other map object within H.NEAR of the human.
local function FindNear(human)
	local best = nil
	local ok, list = pcall(GetUnitList, UNIT_LIST_ALL)
	for _, unit in pairs(ok and list or {}) do
		if unit ~= nil and not unit:IsNull() then
			local name = unit:GetUnitName() or ""
			if not H.Skip(name) and unit ~= human then
				local dist = GetUnitToUnitDistance(human, unit)
				local candidate =
					{ kind = H.Kind(name) or "other", name = name ~= "" and name or "?", unit = unit, dist = dist }
				if dist <= H.NEAR and H.Better(candidate, best) then
					best = candidate
				end
			end
		end
	end
	for _, spot in ipairs(H.WATCHER_SPOTS) do
		local dist = GetUnitToLocationDistance(human, Vector(spot[1], spot[2], 0))
		local candidate = { kind = "watcher-spot", name = spot[1] .. "," .. spot[2], dist = dist }
		if dist <= H.NEAR and H.Better(candidate, best) then
			best = candidate
		end
	end
	return best
end

local function TraceNearUnit(trace, near)
	local unit = near.unit
	if not Valid(unit) then
		return
	end
	local key = tostring(unit)
	local mods = Modifiers(unit)
	local team = Try(unit, "GetTeam")
	local alive = Try(unit, "IsAlive")
	local before = trace.nearMods[key]
	if before == nil then
		trace.nearMods[key] = { mods = mods, team = team }
		local names = {}
		for name in pairs(mods) do
			names[#names + 1] = name
		end
		table.sort(names)
		Log(
			trace.name,
			string.format(
				"unit-mods unit=%s team=%s alive=%s first=%s",
				near.name,
				H.Describe(team),
				H.Describe(alive),
				table.concat(names, ",")
			)
		)
		return
	end
	local added, removed = H.SetDiff(before.mods, mods)
	if #added > 0 or #removed > 0 then
		Log(
			trace.name,
			string.format(
				"unit-mods unit=%s team=%s alive=%s add=%s del=%s",
				near.name,
				H.Describe(team),
				H.Describe(alive),
				table.concat(added, ","),
				table.concat(removed, ",")
			)
		)
	end
	if team ~= before.team then
		Log(
			trace.name,
			string.format("unit-team unit=%s from=%s to=%s", near.name, H.Describe(before.team), H.Describe(team))
		)
	end
	before.mods = mods
	before.team = team
end

local function TraceHuman(human, now)
	local key = tostring(Try(human, "GetPlayerID"))
	local trace = state.traced[key]
	if trace == nil then
		trace = {
			unit = human,
			name = Short(Try(human, "GetUnitName")),
			mods = nil,
			abilityKey = nil,
			itemKey = nil,
			abilityAt = -999,
			sampleAt = -999,
			lineAt = -999,
			scanAt = -999,
			windowUntil = -999,
			chanKey = nil,
			near = nil,
			nearKey = nil,
			nearSince = nil,
			nearMods = {},
			lastPos = nil,
			lastPosAt = nil,
		}
		state.traced[key] = trace
		local pid = Try(human, "GetPlayerID")
		local ok, err = pcall(InstallCastCallback, pid, function(event)
			local okCast, errCast = pcall(OnCast, trace, event)
			if not okCast then
				Log(trace.name, "cb-error " .. tostring(errCast))
			end
		end)
		Log(trace.name, string.format("cb-install pid=%s ok=%s err=%s", H.Describe(pid), tostring(ok), H.Describe(err)))
	end
	trace.unit = human
	local inWindow = now < trace.windowUntil
	if not inWindow and now - trace.sampleAt < H.SAMPLE_EVERY then
		return
	end
	trace.sampleAt = now
	if Try(human, "IsAlive") ~= true then
		return
	end

	if now - trace.abilityAt >= H.ABILITY_EVERY then
		trace.abilityAt = now
		local entries = Abilities(human)
		local abilityKey = H.AbilityKey(entries)
		if abilityKey ~= trace.abilityKey then
			trace.abilityKey = abilityKey
			local list = {}
			for _, entry in ipairs(entries) do
				list[#list + 1] = string.format(
					"%d:%s:h=%s:c=%s:l=%s",
					entry.slot,
					H.Describe(entry.name),
					H.Describe(entry.hidden),
					H.Describe(entry.castable),
					H.Describe(entry.level)
				)
			end
			local chunks = H.Chunks(list, 10)
			for i, chunk in ipairs(chunks) do
				Log(trace.name, string.format("abilities part=%d/%d n=%d list=%s", i, #chunks, #entries, chunk))
			end
		end
		local items = Items(human)
		local itemKey = table.concat(items, ",")
		if itemKey ~= trace.itemKey then
			trace.itemKey = itemKey
			Log(trace.name, "items list=" .. itemKey)
		end
	end

	-- Modifiers on the human.
	local mods, modsOk = Modifiers(human)
	local newModifier = false
	if modsOk then
		if trace.mods ~= nil then
			local added, removed = H.SetDiff(trace.mods, mods)
			if #added > 0 or #removed > 0 then
				-- Any new modifier opens the window: the capture one may have any name.
				newModifier = #added > 0
				Log(
					trace.name,
					string.format(
						"mods add=%s del=%s at=%s",
						table.concat(added, ","),
						table.concat(removed, ","),
						At(human)
					)
				)
			end
		end
		trace.mods = mods
	elseif trace.mods == nil then
		trace.mods = {}
		Log(trace.name, "mods n/a")
	end

	-- Objects next to the human.
	if now - trace.scanAt >= H.SCAN_EVERY then
		trace.scanAt = now
		local near = FindNear(human)
		local nearKey = near and (near.kind .. "|" .. near.name .. "|" .. tostring(near.unit)) or nil
		if nearKey ~= trace.nearKey then
			if trace.near ~= nil then
				Log(
					trace.name,
					string.format(
						"near-end kind=%s unit=%s stayed=%.0f",
						trace.near.kind,
						trace.near.name,
						now - (trace.nearSince or now)
					)
				)
			end
			trace.nearSince = near and now or nil
		end
		trace.near = near
		trace.nearKey = nearKey
		-- On a change, then every H.NEAR_LINE_EVERY while near (the state line carries near= every second).
		if
			near ~= nil
			and now - (trace.nearLineAt or -999) >= (nearKey ~= trace.nearKeyLogged and 0 or H.NEAR_LINE_EVERY)
		then
			trace.nearLineAt = now
			trace.nearKeyLogged = nearKey
			Log(
				trace.name,
				string.format(
					"near kind=%s unit=%s dist=%.0f team=%s at=%s",
					near.kind,
					near.name,
					near.dist,
					near.unit and H.Describe(Try(near.unit, "GetTeam")) or "-",
					At(human)
				)
			)
		end
	end
	if trace.near ~= nil then
		TraceNearUnit(trace, trace.near)
	end

	-- Channel / active ability / action.
	local channel = Try(human, "IsChanneling")
	local active = Try(human, "GetCurrentActiveAbility")
	local activeName = (active ~= nil and active ~= "n/a") and H.Describe(Try(active, "GetName")) or H.Describe(active)
	local chanKey = H.Describe(channel) .. "|" .. activeName
	if channel == true or (active ~= nil and active ~= "n/a") or trace.near ~= nil or newModifier then
		trace.windowUntil = now + H.WINDOW
	end
	inWindow = now < trace.windowUntil
	local due = inWindow and now - trace.lineAt >= H.LINE_EVERY
	if chanKey ~= trace.chanKey or due then
		trace.chanKey = chanKey
		trace.lineAt = now
		local pos = Try(human, "GetLocation")
		local speed = "-"
		if pos ~= "n/a" and pos ~= nil and trace.lastPos ~= nil and now > trace.lastPosAt then
			local dx, dy = pos.x - trace.lastPos.x, pos.y - trace.lastPos.y
			speed = string.format("%.0f", math.sqrt(dx * dx + dy * dy) / (now - trace.lastPosAt))
		end
		if pos ~= "n/a" and pos ~= nil then
			trace.lastPos = pos
			trace.lastPosAt = now
		end
		local velocity = Try(human, "GetVelocity")
		local vel = "n/a"
		if velocity ~= "n/a" and velocity ~= nil then
			local okLen, length = pcall(function()
				return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
			end)
			vel = okLen and string.format("%.0f", length) or "n/a"
		end
		local attack = Try(human, "GetAttackTarget")
		Log(
			trace.name,
			string.format(
				"state channel=%s active=%s atk=%s act=%s queued=%s anim=%s cycle=%s vel=%s speed=%s at=%s near=%s",
				H.Describe(channel),
				activeName,
				attack == "n/a" and "n/a" or H.Describe(Valid(attack) and Try(attack, "GetUnitName") or nil),
				H.Describe(Try(human, "GetCurrentActionType")),
				H.Describe(Try(human, "NumQueuedActions")),
				H.Describe(Try(human, "GetAnimActivity")),
				H.Describe(Try(human, "GetAnimCycle")),
				vel,
				speed,
				H.Describe(pos ~= "n/a" and pos or nil),
				trace.near and string.format("%s:%s:%.0f", trace.near.kind, trace.near.name, trace.near.dist) or "-"
			)
		)
	end
end

-- Outpost team changes, credited to a human within H.CAPTURE_CREDIT.
local function TraceOutposts(now)
	if now - state.outpostScanAt >= H.OUTPOST_SCAN_EVERY then
		state.outpostScanAt = now
		local found = {}
		local ok, list = pcall(GetUnitList, UNIT_LIST_ALL)
		for _, unit in pairs(ok and list or {}) do
			if unit ~= nil and not unit:IsNull() and H.Kind(unit:GetUnitName()) == "outpost" then
				found[#found + 1] = unit
			end
		end
		state.outposts = found
		if not state.outpostsLogged then
			state.outpostsLogged = true
			local names = {}
			for _, unit in ipairs(found) do
				names[#names + 1] =
					string.format("%s:team=%s:%s", unit:GetUnitName(), H.Describe(unit:GetTeam()), At(unit))
			end
			Log("-", string.format("outposts n=%d list=%s", #found, table.concat(names, ",")))
		end
	end
	for _, unit in ipairs(state.outposts) do
		if not unit:IsNull() then
			local key = tostring(unit)
			local team = unit:GetTeam()
			local before = state.outpostTeams[key]
			state.outpostTeams[key] = team
			if before ~= nil and before ~= team then
				local by, after = "-", "-"
				for _, trace in pairs(state.traced) do
					if Valid(trace.unit) and GetUnitToUnitDistance(trace.unit, unit) <= H.CAPTURE_CREDIT then
						by = trace.name
						after = trace.nearSince and string.format("%.1f", now - trace.nearSince) or "-"
					end
				end
				Log(
					"-",
					string.format(
						"outpost-captured unit=%s from=%s to=%s by=%s after=%s",
						unit:GetUnitName(),
						H.Describe(before),
						H.Describe(team),
						by,
						after
					)
				)
			end
		end
	end
end

-- Names of the non-hero, non-creep units in the unit lists: an activated watcher may only then appear as a unit.
local function TraceUnitNames(now, anyWindow)
	if now - state.unitScanAt < H.SCAN_EVERY then
		return
	end
	state.unitScanAt = now
	local counts = {}
	local ok, list = pcall(GetUnitList, UNIT_LIST_ALL)
	for _, unit in pairs(ok and list or {}) do
		if unit ~= nil and not unit:IsNull() then
			local name = unit:GetUnitName() or ""
			if not H.Skip(name) then
				name = name ~= "" and name or "?"
				counts[name] = (counts[name] or 0) + 1
			end
		end
	end
	if state.unitNames ~= nil then
		local added, removed = H.SetDiff(state.unitNames, counts)
		local hinted = false
		for _, name in ipairs(added) do
			hinted = hinted or H.Kind(name) ~= nil
		end
		if (#added > 0 or #removed > 0) and (anyWindow or hinted) then
			Log("-", string.format("units add=%s del=%s", table.concat(added, ","), table.concat(removed, ",")))
		end
	end
	state.unitNames = counts
end

-- Vision at the candidate watcher spots: an active watcher gives vision with no ally near.
local function TraceSpots(now)
	if now - state.spotScanAt < H.SCAN_EVERY then
		return
	end
	state.spotScanAt = now
	for i, spot in ipairs(H.WATCHER_SPOTS) do
		local loc = Vector(spot[1], spot[2], 0)
		local okVis, visible = pcall(IsLocationVisible, loc)
		if not okVis then
			visible = "n/a"
		end
		if visible ~= state.spotVision[i] and now - (state.spotVisionAt[i] or -999) >= H.VISION_EVERY then
			state.spotVision[i] = visible
			state.spotVisionAt[i] = now
			local allyDist = math.huge
			for slot = 1, 5 do
				local member = GetTeamMember(slot)
				if member ~= nil and not member:IsNull() and member:IsAlive() then
					allyDist = math.min(allyDist, GetUnitToLocationDistance(member, loc))
				end
			end
			Log(
				"-",
				string.format(
					"watcher-vision spot=%d,%d vis=%s allyDist=%s",
					spot[1],
					spot[2],
					H.Describe(visible),
					allyDist < math.huge and string.format("%.0f", allyDist) or "-"
				)
			)
		end
	end
end

local function Tick(bot)
	local now = DotaTime()
	if now - state.refreshAt >= H.REFRESH_EVERY then
		state.refreshAt = now
		local flags, members, raw = {}, {}, {}
		for slot = 1, 5 do
			local member = GetTeamMember(slot)
			members[slot] = member
			local isBot = nil
			if member ~= nil and not member:IsNull() then
				isBot = Try(member, "IsBot")
			end
			raw[#raw + 1] = slot .. ":" .. H.Describe(isBot)
			-- A human only when IsBot() says false (n/a counts as a bot, so a failing call traces nobody).
			flags[slot] = member ~= nil and not member:IsNull() and isBot ~= false
		end
		local slot = H.FirstBotSlot(flags)
		state.tracer = slot and members[slot] or nil
		local humans, names = {}, {}
		for i = 1, 5 do
			if members[i] ~= nil and not members[i]:IsNull() and not flags[i] then
				humans[#humans + 1] = members[i]
				names[#names + 1] = "slot" .. i .. ":" .. Short(Try(members[i], "GetUnitName"))
			end
		end
		state.humans = humans
		-- Once per team and whenever who traces whom changes, also with no human (the IsBot reads say why).
		local startKey = tostring(state.tracer) .. table.concat(names, ",")
		if startKey ~= state.startKey then
			state.startKey = startKey
			Log(
				state.tracer and Short(Try(state.tracer, "GetUnitName")) or "-",
				string.format(
					"on tracer=slot%d humans=%s team=%s isBot=%s",
					slot or 0,
					#names > 0 and table.concat(names, ",") or "none",
					H.Describe(Try(bot, "GetTeam")),
					table.concat(raw, ",")
				)
			)
		end
	end
	if bot ~= state.tracer or #state.humans == 0 then
		return
	end
	local anyWindow = false
	for _, human in ipairs(state.humans) do
		TraceHuman(human, now)
	end
	for _, trace in pairs(state.traced) do
		anyWindow = anyWindow or now < trace.windowUntil
	end
	TraceOutposts(now)
	TraceUnitNames(now, anyWindow)
	TraceSpots(now)
end

-- Called every think from CourierUsageThink (ability_item_usage_generic.lua) by every bot.
function H.Tick(bot)
	if enabled == false then
		return
	end
	if enabled == nil then
		local ok, settings = pcall(require, GetScriptDirectory() .. "/FuncLib/systems/custom_loader")
		enabled = ok and type(settings) == "table" and settings.Human_Trace == true
		if not enabled then
			return
		end
	end
	local ok, err = pcall(function()
		local team = bot:GetTeam()
		states[team] = states[team] or NewState()
		state = states[team]
		Tick(bot)
	end)
	if not ok and not errorLogged then
		errorLogged = true
		Log("-", "error " .. tostring(err))
	end
end

return H
