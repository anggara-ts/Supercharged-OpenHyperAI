-- Shared bot system: pure rules that keep an even game moving (#12, no bot API calls, tested with plain numbers in
-- tests/test_tempo_rules.lua). Maintainer, 2026-11-25 (game 084): "the bot farms too long is the most users reported
-- and boring". The callers: bots/lib/systems/push.lua (lane-front gate), bots/mode_retreat_generic.lua (early-game
-- anti-dive), bots/lib/systems/roshan_window.lua (Roshan in the respawn window).
local TempoRules = {}

-- Lane-front push gate. Before: 2+ enemy heroes within 2200 of the lane front cancelled every push on that lane,
-- whatever our numbers (game 084, 43:52-43:59: Leshrac, Weaver and Ringmaster dropped a push on 2 enemies; 15
-- `push-gate lane=2 why=lane-front-enemies` from 40:00). Now it blocks only when they outnumber us there:
--   enemies  enemy heroes seen within 2200 of the lane front
--   allies   our heroes within 2200 of it, plus ours in that lane's push mode within 4000 (walking in)
--   aliveUs / aliveThem  heroes alive on each side
-- Blocks when enemies >= 2 and enemies >= allies + 1, or when we have fewer alive. Equal numbers keep pushing: the
-- same line the strength push ends a window on (StrengthRules.EndWhy "outnumbered": enemies > allies), so both push
-- systems agree; the defenders' tower is why a 3v2 stays blocked. Returns blocked, why ("outnumbered" / "fewer-alive"
-- when blocked, "outnumber" when 2+ enemies are there and we keep pushing, nil with under 2 enemies).
TempoRules.LANE_FRONT_MIN_ENEMIES = 2
function TempoRules.LaneFrontBlocks(enemies, allies, aliveUs, aliveThem)
	enemies, allies = enemies or 0, allies or 0
	if enemies < TempoRules.LANE_FRONT_MIN_ENEMIES then
		return false, nil
	end
	if (aliveUs or 0) < (aliveThem or 0) then
		return true, "fewer-alive"
	end
	if enemies >= allies + 1 then
		return true, "outnumbered"
	end
	return false, "outnumber"
end

-- Early-game anti-dive (mode_retreat_generic.lua, before 12:00). A dive into an enemy tower's range is let through
-- when the target dies to our ~3s damage (killable) or is under 25% HP while the tower is busy (lowTarget). Game 084,
-- 1:21-1:34: Underlord chased a 5% Spirit Bear under Dire's top T2 with the T1 up, was shot to 7% and died on the
-- way home. Maintainer, 2026-11-25: "there was ally (tusk) and chasing bear is plausible. just dont dive t2 early
-- game, the damage is too big". So the exceptions stay for a tier-1 tower only; tier 2+ always stops the dive.
-- tier: 1-4 (nil when unknown: treated as tier 1, the old rule). Returns allowed, why.
function TempoRules.EarlyDiveAllowed(tier, killable, lowTarget)
	if (tier or 1) >= 2 then
		return false, "tower-tier2"
	end
	if killable then
		return true, "killable"
	end
	if lowTarget then
		return true, "low-target"
	end
	return false, "tower"
end

-- A tower's tier from its unit name (npc_dota_goodguys_tower2_top, npc_dota_badguys_tower4): 1-4, nil if none.
function TempoRules.TowerTier(unitName)
	local tier = type(unitName) == "string" and unitName:match("tower(%d)") or nil
	return tier ~= nil and tonumber(tier) or nil
end

-- Roshan respawn window. Roshan respawns 8-11 minutes after his death (turbo: half; the commonly cited respawn time,
-- as in human_order_rules.lua ROSHAN_MIN_RESPAWN, not read from game data). Fu.IsRoshanAlive answers "alive" only
-- after 11 minutes or once one of our units sees him; nobody looked (game 084: killed 35:04, the first Dire call at
-- 49:12, desire 0.30).
TempoRules.ROSH_MIN_RESPAWN = 8 * 60
TempoRules.ROSH_MAX_RESPAWN = 11 * 60
-- Phase of the respawn: "never" (no kill yet), "dead" (surely dead), "window" (may be up), "up" (surely up).
function TempoRules.RoshanPhase(sinceKill, turbo)
	if sinceKill == nil then
		return "never"
	end
	local scale = turbo and 0.5 or 1
	if sinceKill < TempoRules.ROSH_MIN_RESPAWN * scale then
		return "dead"
	end
	if sinceKill < TempoRules.ROSH_MAX_RESPAWN * scale then
		return "window"
	end
	return "up"
end

-- A peek trip: someone walks to see the pit (or wards it) while Roshan may be up and nobody has seen him, at most one
-- trip every PEEK_INTERVAL seconds. p = { phase, seen (Roshan seen alive since the kill), pitVisible (our team sees
-- the pit now: a ward or a hero there), tripActive, lastTripEnd, now, siege (nil, or why the team is busy at the enemy
-- base: "strength", "advantage" or "their-hg") }. Returns due, why.
-- No peek during a siege (#12, game 087 35:27: Ringmaster, pos 1, was sent 7251 away from the Dire base push and the
-- trip timed out after 44s).
TempoRules.PEEK_INTERVAL = 60
function TempoRules.PeekDue(p)
	if p.phase ~= "window" then
		return false, "phase-" .. tostring(p.phase)
	end
	if p.siege ~= nil then
		return false, "siege-" .. tostring(p.siege)
	end
	if p.seen then
		return false, "seen"
	end
	if p.tripActive then
		return false, "trip-active"
	end
	if p.pitVisible then
		return false, "pit-visible"
	end
	if (p.now or 0) - (p.lastTripEnd or -math.huge) < TempoRules.PEEK_INTERVAL then
		return false, "interval"
	end
	return true, "due"
end

-- Who peeks: candidates = list of { id, support (bool), dist (to the pit), ok (alive bot, HP 60%+, not hit by a
-- hero, not defending or at Roshan) }. The nearest healthy support, else the nearest healthy bot. Returns the
-- candidate or nil.
function TempoRules.PickPeeker(candidates)
	local bestSupport, bestAny = nil, nil
	for _, c in ipairs(candidates or {}) do
		if c.ok then
			if c.support and (bestSupport == nil or c.dist < bestSupport.dist) then
				bestSupport = c
			end
			if bestAny == nil or c.dist < bestAny.dist then
				bestAny = c
			end
		end
	end
	return bestSupport or bestAny
end

-- The team's Roshan window call: Roshan up (seen, or past the longest respawn), the late game, all of us alive, nothing
-- to defend and no lead push running (the game is even: a team that leads pushes with the strength push instead).
-- c = { roshAlive, now, aliveUs, teamSize, aliveThem, defendDesire, defendPing, baseThreat, leadPush, active (the
-- call is already on) }. A running call keeps going with 4+ alive and at least their number (one death in the pit
-- fight doesn't drop it). Returns ok, why.
TempoRules.CALL_TIME = 30 * 60
TempoRules.CALL_DEFEND = 0.4
function TempoRules.RoshanCallOk(c)
	if not c.roshAlive then
		return false, "rosh-dead"
	end
	if (c.now or 0) < TempoRules.CALL_TIME then
		return false, "early"
	end
	if c.baseThreat then
		return false, "base"
	end
	if c.defendPing or (c.defendDesire or 0) >= TempoRules.CALL_DEFEND then
		return false, "defend"
	end
	if c.leadPush then
		return false, "lead-push"
	end
	local aliveUs, aliveThem = c.aliveUs or 0, c.aliveThem or 0
	if c.active then
		if aliveUs < 4 or aliveUs < aliveThem then
			return false, "alive"
		end
	elseif aliveUs < (c.teamSize or 5) then
		return false, "alive"
	end
	return true, "ok"
end
-- A call that hasn't killed Roshan after CALL_MAX seconds gives up for CALL_BLOCK seconds.
TempoRules.CALL_MAX = 150
TempoRules.CALL_BLOCK = 180

return TempoRules
