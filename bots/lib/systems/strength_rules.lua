-- Shared bot system: pure rules of the strength push (#12, no bot API calls, tested with plain numbers in
-- tests/test_strength_rules.lua). bots/lib/systems/strength_push.lua reads the game and calls these.
--
-- Game 074 (45:30-47:00): Radiant's bots farmed jungle camps with Dire's mid T3 and mid ranged barracks down; a push
-- only started after kills / Aegis, a pushed wave or a ping. The strength push compares the teams (levels, net worth
-- as far as it is readable, our ultimates, alive counts, Aegis) and, when clearly ahead with nothing to defend,
-- sends the group to one lane for a window of ~40s. Game 074 itself was NOT such a case: Radiant was behind
-- (avg level 17 vs 19.6, bot net worth 50.4k + a human vs 69.1k), so the rule must hold back there.
local StrengthRules = {}

-- Thresholds. The lead thresholds (nwLeadPct, lvlLead*) are multiplied by the scale (StrengthRules.SetScale), the
-- knob a difficulty profile can turn: under 1 pushes on a smaller lead, over 1 needs a bigger one.
-- Conservative on purpose (maintainer, 2026-11-23: a human can order a push with !push, #225; "need more data"):
-- only a clear lead fires, and the strength-skip / strength-compare lines give the numbers to tune these.
StrengthRules.DEFAULTS = {
	nwLeadPct = 0.2, -- net worth lead (our - their) / their
	lvlLeadAlone = 2.5, -- average level lead that is enough on its own (net worth not behind)
	lvlLeadWithNw = 1.0, -- average level lead needed next to a net worth lead (net worth reads are a lower bound)
	nwBehindPct = -0.05, -- net worth this far behind blocks the level route
	lvlBehind = -1.0, -- average level this far behind: always skip
	aegisFactor = 0.6, -- with the Aegis the lead thresholds are this much of normal
	endFactor = 0.5, -- during a window the lead may drop to this much of the start threshold
	minAlive = 4, -- our alive heroes at least
	defendDesire = 0.4, -- any GetDefendLaneDesire at or above this: defend first
	holdSeconds = 40, -- window length from the arrival at the lane front (the card asks ~30-45s)
	gatherSeconds = 45, -- no 2+ allies at the lane front this long after the start: end
	extendSeconds = 20, -- extra hold while the target is still losing HP
	cooldown = 20, -- seconds after an end before a new window
	cooldownAfterFall = 5, -- after the target fell (chain to the next building)
	maxNwAge = 120, -- an enemy net worth read older than this counts as unknown
}
local scale = 1
function StrengthRules.SetScale(value)
	value = tonumber(value) or 1
	scale = math.max(0.5, math.min(2, value))
	return scale
end
function StrengthRules.GetScale()
	return scale
end
local D = StrengthRules.DEFAULTS

-- Team net worth from per-player reads. reads = { [pid] = { value=, at= } } for every player of the team, a missing
-- or stale (older than maxAge) entry makes the total unknown (nil): an unread hero must not count as 0.
function StrengthRules.TeamTotal(playerIds, reads, now, maxAge)
	local total = 0
	for _, pid in ipairs(playerIds or {}) do
		local read = reads and reads[pid]
		if read == nil or read.value == nil or read.value <= 0 then
			return nil
		end
		if maxAge ~= nil and now ~= nil and now - (read.at or -math.huge) > maxAge then
			return nil
		end
		total = total + read.value
	end
	return total
end

-- The lead. i = { ourNw, theirNw (nil = unknown), ourLvl, theirLvl, aegis, factor (1 = start, endFactor = in a
-- window) }. Returns ok, lead ("nw" | "lvl"), why (when not ok), nwPct (nil when unknown), lvlLead.
function StrengthRules.Lead(i)
	local factor = (i.factor or 1) * scale
	if i.aegis then
		factor = factor * D.aegisFactor
	end
	local lvlLead = (i.ourLvl or 0) - (i.theirLvl or 0)
	local nwPct = nil
	if i.ourNw ~= nil and i.theirNw ~= nil and i.theirNw > 0 then
		nwPct = (i.ourNw - i.theirNw) / i.theirNw
	end
	if lvlLead <= D.lvlBehind then
		return false, nil, "behind-lvl", nwPct, lvlLead
	end
	if nwPct ~= nil and nwPct <= D.nwBehindPct then
		return false, nil, "behind-nw", nwPct, lvlLead
	end
	if nwPct ~= nil and nwPct >= D.nwLeadPct * factor and lvlLead >= D.lvlLeadWithNw * factor then
		return true, "nw", nil, nwPct, lvlLead
	end
	if lvlLead >= D.lvlLeadAlone * factor then
		return true, "lvl", nil, nwPct, lvlLead
	end
	return false, nil, nwPct == nil and "no-lead-nw-unknown" or "no-lead", nwPct, lvlLead
end

-- Whether the team may start (or keep) a strength push. i = the Lead inputs plus
--   laning (bool), baseThreat (bool: enemy heroes or creeps at our base), defendDesire (max over lanes),
--   defendPing (bool), aliveUs, aliveThem, ultsReady, ultsTotal (our cores with a learned ultimate).
-- Returns ok, why (the skip reason, or the lead kind when ok), nwPct, lvlLead.
function StrengthRules.Decide(i)
	if i.laning then
		return false, "laning"
	end
	if i.baseThreat then
		return false, "base"
	end
	if i.defendPing then
		return false, "defend-ping"
	end
	if (i.defendDesire or 0) >= D.defendDesire then
		return false, "defend"
	end
	local aliveUs, aliveThem = i.aliveUs or 0, i.aliveThem or 0
	if aliveUs < D.minAlive or aliveUs < aliveThem then
		return false, "alive"
	end
	local ok, lead, why, nwPct, lvlLead = StrengthRules.Lead(i)
	if not ok then
		return false, why, nwPct, lvlLead
	end
	-- Our core ultimates: at least half of the learned ones ready (passives count as ready). The enemy's are unknown.
	local total = i.ultsTotal or 0
	if total > 0 and (i.ultsReady or 0) * 2 < total then
		return false, "ults", nwPct, lvlLead
	end
	return true, lead, nwPct, lvlLead
end

-- The lane to push. lanes = list of { lane=, tier= (1-3 tower, 4 barracks / T4 / Ancient), hp= (target HP ratio),
-- allyDist= (average distance of our alive cores to the lane front) }; entries without a target are left out by the
-- caller. An open enemy high ground (T3 down) comes first, then the weakest outer building (lowest tier, then lowest
-- HP), and the lane closest to our cores breaks ties: cost = allyDist + 3000 * hp + 1500 * (tier - 1), minus 6000
-- for an open high ground. Returns the chosen entry (nil without lanes).
function StrengthRules.LaneCost(entry)
	local tier = entry.tier or 1
	local cost = (entry.allyDist or 0) + 3000 * (entry.hp or 1)
	if tier >= 4 then
		cost = cost - 6000
	else
		cost = cost + 1500 * (tier - 1)
	end
	return cost
end
function StrengthRules.PickLane(lanes)
	local best, bestCost = nil, math.huge
	for _, entry in ipairs(lanes or {}) do
		local cost = StrengthRules.LaneCost(entry)
		if cost < bestCost then
			best, bestCost = entry, cost
		end
	end
	return best
end

-- Whether a running window ends. state = { startedAt, aliveAtStart, arrivedAt (nil until 2+ allies reached the lane
-- front) }, i = the Decide inputs at the end threshold (factor = endFactor) plus targetAlive (bool), targetDropping
-- (the target lost HP since the last tick), enemiesAtFront, alliesAtFront (visible heroes near the lane front).
-- The hold clock runs from the arrival, so the walk does not eat the window; gatherSeconds without an arrival ends
-- it, and a target still losing HP at the end of the hold gets up to extendSeconds more. Our ultimates are not
-- checked here: they are cast in the fight the push starts. Returns the end reason or nil.
function StrengthRules.EndWhy(state, now, i)
	if not i.targetAlive then
		return "building-down"
	end
	if state.arrivedAt == nil then
		if now - (state.startedAt or now) >= D.gatherSeconds then
			return "no-gather"
		end
	else
		local held = now - state.arrivedAt
		if held >= D.holdSeconds and not (i.targetDropping and held < D.holdSeconds + D.extendSeconds) then
			return "timeout"
		end
	end
	local aliveUs, aliveThem = i.aliveUs or 0, i.aliveThem or 0
	if aliveUs < (state.aliveAtStart or 0) - 1 or aliveUs < aliveThem or aliveUs < D.minAlive then
		return "deaths"
	end
	if (i.enemiesAtFront or 0) >= 2 and (i.enemiesAtFront or 0) > (i.alliesAtFront or 0) then
		return "outnumbered"
	end
	if i.baseThreat then
		return "base"
	end
	if i.defendPing then
		return "defend-ping"
	end
	if (i.defendDesire or 0) >= D.defendDesire then
		return "defend"
	end
	local ok, _, why = StrengthRules.Lead(i)
	-- An enemy not seen for a while makes net worth unknown; that alone does not end a running window.
	if not ok and why ~= "no-lead-nw-unknown" then
		return why
	end
	return nil
end

-- Seconds to wait after an end before a new window.
function StrengthRules.Cooldown(endWhy)
	if endWhy == "roshan-first" then
		return 0
	end
	return endWhy == "building-down" and D.cooldownAfterFall or D.cooldown
end

-- Roshan first (maintainer: "would they take aegis first when available?"; on #87: "Aegis first rather than forcing a
-- 5v5 high-ground push"). When a strength window would open (or is open) and Roshan is up and takeable by our side,
-- the push waits for the Aegis; with the Aegis it starts at once (the Aegis thresholds apply).
-- "Takeable" is the Roshan mode's own verdict (mode_roshan_generic.lua, bot._roshWhy): these reasons are returned
-- only after its safety checks passed (numbers edge, pit not contested, enough damage).
StrengthRules.ROSH_PAST_SAFETY = {
	["team-call"] = true,
	["timer"] = true,
	["kill-window"] = true,
	["finishing"] = true,
	["ping"] = true,
	["too-early-no-kill"] = true,
	["human-invite"] = true,
	["human-invite-expired"] = true,
	["human-cooldown"] = true,
}
-- Of those, the ones where the Roshan mode would not call the take itself (or only at a low desire): the strength
-- push raises the Roshan desire of its bots for these (StrengthPush.RoshanDesire).
StrengthRules.ROSH_BOOSTABLE = {
	["timer"] = true,
	["too-early-no-kill"] = true,
	["human-invite"] = true,
	["human-invite-expired"] = true,
	["human-cooldown"] = true,
}
D.roshGiveUpIdle = 90 -- no ally in Roshan mode this long after Roshan first started: give up
D.roshGiveUpMax = 150 -- give up after this long whatever happens (unless finishing)
D.roshBlockSeconds = 180 -- after giving up, no Roshan first for this long
D.roshKeepTargetHp = 0.4 -- a running window whose building is under this HP finishes it first

-- r = { aegis (we hold it), roshAlive, contested (2+ enemies seen at the pit), whys (list of our alive bots'
-- Roshan reasons), blockedUntil, now }. Returns on, why.
function StrengthRules.RoshanFirst(r)
	if r.aegis then
		return false, "have-aegis"
	end
	if not r.roshAlive then
		return false, "rosh-dead"
	end
	if (r.now or 0) < (r.blockedUntil or -math.huge) then
		return false, "gave-up"
	end
	if r.contested then
		return false, "contested"
	end
	local whys = r.whys or {}
	local past, refusal = 0, nil
	for _, why in ipairs(whys) do
		if StrengthRules.ROSH_PAST_SAFETY[why] then
			past = past + 1
		elseif refusal == nil then
			refusal = why
		end
	end
	if past >= 2 or past >= 1 and #whys == 1 then
		return true, "rosh-ok"
	end
	return false, "rosh-" .. tostring(refusal or "no-bots")
end

-- Whether a running Roshan first is given up: since = when it started, inRoshan = our bots in Roshan mode now,
-- finishing = one of them is finishing Roshan.
function StrengthRules.RoshanGiveUp(since, now, inRoshan, finishing)
	if finishing then
		return false
	end
	local waited = now - since
	return waited >= D.roshGiveUpMax or waited >= D.roshGiveUpIdle and (inRoshan or 0) == 0
end

return StrengthRules
