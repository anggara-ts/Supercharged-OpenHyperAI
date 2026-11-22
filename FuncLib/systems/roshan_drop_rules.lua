-- Who takes the Aegis, and which item it puts aside for it (#15). Pure, no bot API calls, so
-- Tests/test_roshan_drop_rules.lua can load it. FuncLib/systems/item.lua feeds it the team and the bag.
--
-- 7.42 game file (scripts/npc/items.txt, item_aegis): AllowedInBackpack 0, SpeciallyBannedFromNeutralSlot 1,
-- ItemDroppable 0, disappear_time 300. So the Aegis goes into a main slot only: with the six main slots full
-- the pick-up fails ("Can't pick up item, no room in inventory", game 070 at 31:09), and once taken it can't be
-- passed on. Maintainer (2026-11-23): the team's top performer by KDA takes it, even if that means putting a
-- high-value item aside (boots, a passive like Octarine Core), and the item put aside is never sold.
local RoshanDropRules = {}

-- Allies within this range of the Aegis count as near (the walking range the claim already used).
RoshanDropRules.NEAR = 4000
-- A claimer keeps the claim while within this range; a new pick only happens when it is released.
RoshanDropRules.KEEP = 6000

-- 7.42 game file: ItemDroppable 0. These can't be put on the ground, so they are never the item put aside.
RoshanDropRules.UNDROPPABLE = {
	item_aegis = true,
	item_eldwurms_edda = true,
	item_black_grimoire = true,
	item_grisgris = true,
}

function RoshanDropRules.Kda(kills, deaths, assists)
	return ((kills or 0) + (assists or 0)) / math.max(1, deaths or 0)
end

local function IsCore(c)
	return (c.pos or 3) <= 3
end

-- a goes before b: higher KDA; on a tie a core (pos 1-3) before a support, then the lower position, then
-- the lower player ID, so every bot of the team computes the same order.
function RoshanDropRules.Before(a, b)
	if math.abs((a.kda or 0) - (b.kda or 0)) > 1e-6 then
		return (a.kda or 0) > (b.kda or 0)
	end
	if IsCore(a) ~= IsCore(b) then
		return IsCore(a)
	end
	if (a.pos or 3) ~= (b.pos or 3) then
		return (a.pos or 3) < (b.pos or 3)
	end
	return (a.id or 99) < (b.id or 99)
end

local function Best(cands, accept)
	local best = nil
	for _, c in ipairs(cands) do
		if accept(c) and (best == nil or RoshanDropRules.Before(c, best)) then
			best = c
		end
	end
	return best
end

-- cands: one entry per allied hero: { id, kda, pos, dist (to the Aegis), alive, human, canTake (a free main
-- slot or an item it can put aside) }. o: { current = id of the claimer so far, excluded = { [id] = true }
-- released claimers, humanWait = true while a human near still gets the first go }.
-- Returns the claimer's entry (nil: nobody) and why:
--   kept       the claimer so far, still alive, able and within KEEP
--   human      a human ally is near and still gets the first go (bots leave it to the player)
--   best-kda   the best KDA of the allies near that can take it
--   far        nobody near can take it: the best KDA of the rest
function RoshanDropRules.AegisClaimer(cands, o)
	o = o or {}
	local excluded = o.excluded or {}
	local function able(c)
		return c.alive and c.canTake and not excluded[c.id]
	end
	if o.current ~= nil then
		for _, c in ipairs(cands) do
			if
				c.id == o.current
				and able(c)
				and (c.dist or math.huge) <= RoshanDropRules.KEEP
				and (not c.human or o.humanWait)
			then
				return c, "kept"
			end
		end
	end
	if o.humanWait then
		local human = Best(cands, function(c)
			return c.human and c.alive and not excluded[c.id] and (c.dist or math.huge) <= RoshanDropRules.NEAR
		end)
		if human ~= nil then
			return human, "human"
		end
	end
	local near = Best(cands, function(c)
		return not c.human and able(c) and (c.dist or math.huge) <= RoshanDropRules.NEAR
	end)
	if near ~= nil then
		return near, "best-kda"
	end
	local far = Best(cands, function(c)
		return not c.human and able(c)
	end)
	if far ~= nil then
		return far, "far"
	end
	return nil, "nobody"
end

-- items: the six main slots, { slot, name, cost, keep } for each filled one (keep: an item the bag code never
-- moves out, e.g. Black King Bar, Gem, wards, Divine Rapier). Returns the entry to put aside so the Aegis fits:
-- the cheapest that is not a keep item, else the cheapest keep item; never one that can't be dropped. nil when
-- a main slot is free (nothing to put aside) or every item is undroppable.
function RoshanDropRules.AsideItem(items)
	local filled = 0
	local best = nil
	for _, it in ipairs(items) do
		filled = filled + 1
		if not RoshanDropRules.UNDROPPABLE[it.name] then
			local itKeep, bestKeep = it.keep == true, best ~= nil and best.keep == true
			local cost, bestCost = it.cost or 0, best ~= nil and (best.cost or 0) or 0
			if
				best == nil
				or (bestKeep and not itKeep)
				or (bestKeep == itKeep and (cost < bestCost or (cost == bestCost and it.slot < best.slot)))
			then
				best = it
			end
		end
	end
	if filled < 6 then
		return nil
	end
	return best
end

return RoshanDropRules
