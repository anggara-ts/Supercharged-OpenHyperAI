-- Shared bot system: the spot the ward mode walks to, for the `[SHy-WARD] goal` line (#15, game 087: Dark Willow
-- went back and forth near the secret shop in ward mode and no line said where to). Pure rules (plain values in, no
-- bot API), so tests/test_ward_goal.lua can run them; bots/mode_ward_generic.lua calls Step on every ward think and
-- prints the line when Step says so.
local WardGoal = {}

-- Target changes are counted over this many seconds (the line's `changed=`).
WardGoal.WINDOW = 10
-- At most one line per bot in this many seconds.
WardGoal.THROTTLE = 2
-- No ward think for this long: the next one is a new pick (a line), not a change.
WardGoal.GAP = 1

-- A spot by its point, rounded: some spot lists build new tables on every call, so the table itself can't be compared.
function WardGoal.Key(x, y)
	return string.format("%d,%d", math.floor(x + 0.5), math.floor(y + 0.5))
end

-- One ward think. state: the bot's own table (starts empty), key: Key() of the spot walked to, now: DotaTime().
-- A target that differs from the last think's counts as a change. Every change and every new pick (the first think,
-- or the first after GAP without one) owes a line; it goes out once THROTTLE has passed since the last one, so a
-- spot that flips A -> B -> A within 2s still prints, with changed=2. Returns true when the line is due, and the
-- number of changes in the last WINDOW seconds.
function WardGoal.Step(state, key, now)
	local changes = state.changes
	if changes == nil then
		changes = {}
		state.changes = changes
	end
	if state.key == nil or now - (state.lastAt or now) > WardGoal.GAP then
		state.pending = true
	elseif state.key ~= key then
		changes[#changes + 1] = now
		state.pending = true
	end
	state.key = key
	state.lastAt = now
	while changes[1] ~= nil and now - changes[1] > WardGoal.WINDOW do
		table.remove(changes, 1)
	end
	if state.pending and now - (state.printedAt or -math.huge) >= WardGoal.THROTTLE then
		state.pending = false
		state.printedAt = now
		return true, #changes
	end
	return false, #changes
end

return WardGoal
