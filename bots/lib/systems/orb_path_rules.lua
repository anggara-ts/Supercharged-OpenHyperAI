-- Illusory Orb path probe (#36, Puck): how far the Orb strays from the straight line she aimed along. Plain numbers
-- in, so tests/test_orb_path_rules.lua can check them without the bot API.
-- Game files (puck_illusory_orb; read from the hero definitions, not re-checked in the 7.42 VPK): POINT | ALT_CASTABLE,
-- curve_orb 1, curve_strength 0.6. Datafeed: alt-cast launches the Orb straight ahead. Bots can't alt-cast
-- (docs/BOT_API_RUNTIME.md, discussion #50 item 2); this measures it.
local OrbPath = {}

-- Signed lateral offset of (px, py) from the line that starts at (sx, sy) and points at (ax, ay): positive on the left
-- of the aim direction, negative on the right. The second value is the distance along that line. nil when the aim
-- point is on the start (no direction).
function OrbPath.Offset(sx, sy, ax, ay, px, py)
	local dx, dy = ax - sx, ay - sy
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then
		return nil
	end
	dx, dy = dx / len, dy / len
	local rx, ry = px - sx, py - sy
	return dx * ry - dy * rx, dx * rx + dy * ry
end

-- A new path record for one cast: start (sx, sy) and the ordered aim point (ax, ay).
function OrbPath.New(sx, sy, ax, ay)
	return { sx = sx, sy = sy, ax = ax, ay = ay, n = 0, dev = 0, devAlong = 0, last = 0, lastAlong = 0 }
end

-- Adds one Orb position to the record: counts it, keeps the largest offset (with its sign and where along the line it
-- was) and the last offset. Returns false when the record has no direction.
function OrbPath.Add(path, px, py)
	local lateral, along = OrbPath.Offset(path.sx, path.sy, path.ax, path.ay, px, py)
	if lateral == nil then
		return false
	end
	path.n = path.n + 1
	if math.abs(lateral) > math.abs(path.dev) then
		path.dev = lateral
		path.devAlong = along
	end
	path.last = lateral
	path.lastAlong = along
	return true
end

-- Ethereal Jaunt seen from her position (#191, game 091: all 92 orb-path lines said jaunt=no, also right after a
-- Jaunt). The old test read a jump in the Jaunt's cooldown, but puck_ethereal_jaunt has no AbilityCooldown at all
-- (game files, scripts/npc/heroes/npc_dota_hero_puck.txt, 7.42 VPK; the datafeed does not list the Jaunt), so it
-- never fired. The Jaunt puts her on the Orb: she moved farther since the last sample (dt seconds ago) than a walk at
-- moveSpeed allows (+ JAUNT_WALK_MARGIN, at least JAUNT_MIN_JUMP), and she now stands near the Orb: within
-- JAUNT_LAND_TOL + the Orb's flight in dt (orb_speed 750, datafeed hero 13) of its current position (orbX, orbY) or
-- of where it was last seen (lastX, lastY; it may be gone in the same sample). A Rift or a Blink away from the Orb
-- is no Jaunt.
OrbPath.JAUNT_WALK_MARGIN = 100
OrbPath.JAUNT_MIN_JUMP = 150
OrbPath.JAUNT_LAND_TOL = 150
OrbPath.ORB_SPEED = 750
function OrbPath.JauntSeen(px, py, nx, ny, orbX, orbY, lastX, lastY, dt, moveSpeed)
	if px == nil or nx == nil or dt == nil or dt < 0 then
		return false
	end
	local jump = math.sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
	local walk = (moveSpeed or 550) * dt + OrbPath.JAUNT_WALK_MARGIN
	if jump <= math.max(walk, OrbPath.JAUNT_MIN_JUMP) then
		return false
	end
	local tol = OrbPath.JAUNT_LAND_TOL + OrbPath.ORB_SPEED * dt
	for _, orb in ipairs({ { orbX, orbY }, { lastX, lastY } }) do
		if orb[1] ~= nil and orb[2] ~= nil and math.sqrt((nx - orb[1]) ^ 2 + (ny - orb[2]) ^ 2) <= tol then
			return true
		end
	end
	return false
end

return OrbPath
