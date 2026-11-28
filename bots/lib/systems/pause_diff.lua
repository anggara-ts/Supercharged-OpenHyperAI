-- Shared bot system: what a game pause changes in a bot's items and gold (#15). Games 089 and 091: after every pause
-- bots took stash items that no [SHy-BUY] line bought, replaying their early purchases in order (Zeus: Mantle, then
-- Circlet, then the Null Talisman recipe; Lion: Boots, Ring of Regen, Wind Lace). No script line prints during a pause,
-- so the change is read on the first think after it: the items and gold of the last think before the pause against
-- the ones now, once at the resume and once PAUSE_SETTLE seconds later (the copies may arrive a moment after).
-- Log: [SHy-BUY] pause-diff when=resume|settled paused= gold=before->after new= gone=.
local PauseDiff = {}

-- A think gap with this much more real time than game time is a pause (game time stops while paused).
PauseDiff.PAUSE_GAP = 2
PauseDiff.PAUSE_SETTLE = 3
-- Every slot that holds an item: inventory and backpack 0-8, stash 9-14, TP 15, neutral 16.
PauseDiff.LAST_SLOT = 16

-- realGap / gameGap: seconds of RealTime() and DotaTime() between two thinks.
function PauseDiff.IsPause(realGap, gameGap)
	return realGap ~= nil and gameGap ~= nil and realGap - gameGap >= PauseDiff.PAUSE_GAP
end

-- Items in `after` that `before` did not have, and the other way round, counted as multisets (two Boots after one is
-- one new Boots). before / after: lists of item names. Returns two sorted lists.
function PauseDiff.Changes(before, after)
	local count = {}
	for _, name in ipairs(before or {}) do
		count[name] = (count[name] or 0) + 1
	end
	local added = {}
	for _, name in ipairs(after or {}) do
		if (count[name] or 0) > 0 then
			count[name] = count[name] - 1
		else
			added[#added + 1] = name
		end
	end
	local gone = {}
	for name, n in pairs(count) do
		for _ = 1, n do
			gone[#gone + 1] = name
		end
	end
	table.sort(added)
	table.sort(gone)
	return added, gone
end

local function Snapshot(bot)
	local items = {}
	for slot = 0, PauseDiff.LAST_SLOT do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil and not item:IsNull() then
			items[#items + 1] = (string.gsub(item:GetName(), "^item_", ""))
		end
	end
	return { t = DotaTime(), real = RealTime(), gold = bot:GetGold(), items = items }
end

local function Report(bot, when, before, now, paused)
	local added, gone = PauseDiff.Changes(before.items, now.items)
	print(
		string.format(
			"[SHy-BUY] t=%.0f %s pause-diff when=%s paused=%.0f gold=%d->%d new=%s gone=%s",
			DotaTime(),
			(string.gsub(bot:GetUnitName(), "npc_dota_hero_", "")),
			when,
			paused,
			before.gold,
			now.gold,
			#added > 0 and table.concat(added, ",") or "-",
			#gone > 0 and table.concat(gone, ",") or "-"
		)
	)
end

-- Call once per think (ItemPurchaseThink). Cheap: one snapshot of 17 slots per think.
function PauseDiff.Watch(bot)
	if bot == nil or not bot:IsHero() or bot:IsIllusion() then
		return
	end
	local now = Snapshot(bot)
	local last = bot._pauseDiffLast
	bot._pauseDiffLast = now
	local pending = bot._pauseDiffPending
	if pending ~= nil and now.t >= pending.at then
		bot._pauseDiffPending = nil
		pcall(Report, bot, "settled", pending.before, now, pending.paused)
	end
	if last ~= nil and PauseDiff.IsPause(now.real - last.real, now.t - last.t) then
		local paused = (now.real - last.real) - (now.t - last.t)
		pcall(Report, bot, "resume", last, now, paused)
		bot._pauseDiffPending = { before = last, at = now.t + PauseDiff.PAUSE_SETTLE, paused = paused }
	end
end

return PauseDiff
