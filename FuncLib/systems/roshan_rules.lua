-- Shared bot system: pure Roshan-take rules (no bot API calls), so they can be tested with real numbers.
-- Used by mode_roshan_generic.lua (#12).
local RoshanRules = {}

-- Roshan's Slam: 70 magical damage every 10s to heroes within 350 (7.42 npc_abilities "roshan_slam": damage 70,
-- damage_growth 10, AbilityCooldown 10.0, radius 350; read from pak01_dir.vpk). Counted for every member (ranged
-- heroes usually stand outside 350, so this errs on the safe side); the growth is not counted.
RoshanRules.SLAM_DPS = 7
-- Roshan's attack on one hero per second when his handle can't be read. Measured, not game data: the
-- `[OHA-ROSH] step-out ... roshDmg3s=` lines (Roshan's GetEstimatedDamageToTarget over 3s on the hero he hits) read
-- 372-654 between 21:00 and 49:00 in games 05x-068, i.e. 124-218 per second after the hero's armor. 7.42
-- npc_units "npc_dota_roshan" has AttackDamage 75 and AttackRate 2.0 at spawn; his growth per minute is not in the
-- unit file (unverified), so the base values are not used.
RoshanRules.FALLBACK_DPS = 170
-- Fu.ShouldLeaveRoshanFight: a hero under 45% HP leaves while Roshan is above 50% HP (nobody leaves after that).
RoshanRules.LEAVE_HP = 0.45
RoshanRules.STAY_BELOW = 0.5
-- A fresh take needs the group's average HP at 70%+ (game 068: Radiant called at 26:06 and 37:27 right after
-- fights and left Roshan at 60% and 78%).
RoshanRules.MIN_AVG_HP = 0.7

-- Can the group that is coming take Roshan before its HP runs out? (#12, game 068: 3 of 4 committed tries failed;
-- the kill time ignored Roshan's damage on the group.)
--   s.members: { { hp = HP, maxHp = max HP, roshDps = Roshan's damage per second on this hero }, ... } (the heroes
--     the take time counts)
--   s.roshHp, s.roshMax: Roshan's HP; s.groupDps: the members' right-click damage per second (half goes through his
--     armor, as in the kill time)
-- The members' HP above the leave line is the group's tanking pool: Roshan hits one hero at a time (the average of
-- roshDps) and his Slam hits everyone. The pool must last until Roshan is at half HP, after which nobody leaves.
-- Returns ok, why, numbers { avg, tank, half }.
function RoshanRules.GroupFit(s)
	local members = s.members or {}
	local n = #members
	if n == 0 then
		return false, "no-members", { avg = 0, tank = 0, half = 0 }
	end
	local leave = s.leaveHp or RoshanRules.LEAVE_HP
	local ratioSum, pool, dpsSum = 0, 0, 0
	for _, member in ipairs(members) do
		local maxHp = math.max(1, member.maxHp or 1)
		local hp = math.max(0, member.hp or 0)
		ratioSum = ratioSum + hp / maxHp
		pool = pool + math.max(0, hp - leave * maxHp)
		dpsSum = dpsSum + (member.roshDps or RoshanRules.FALLBACK_DPS)
	end
	local avg = ratioSum / n
	local drain = dpsSum / n + RoshanRules.SLAM_DPS * n
	local tank = pool / math.max(1, drain)
	local roshMax = math.max(1, s.roshMax or s.roshHp or 1)
	local toHalf = math.max(0, (s.roshHp or roshMax) - RoshanRules.STAY_BELOW * roshMax)
		/ math.max(1, (s.groupDps or 0) * 0.5)
	local numbers = { avg = avg, tank = tank, half = toHalf }
	if avg < (s.minAvg or RoshanRules.MIN_AVG_HP) then
		return false, string.format("group-hurt(avg=%.2f,n=%d)", avg, n), numbers
	end
	if tank < toHalf then
		return false, string.format("tank-short(tank=%.0f,half=%.0f,avg=%.2f,n=%d)", tank, toHalf, avg, n), numbers
	end
	return true, string.format("group(tank=%.0f,half=%.0f,avg=%.2f,n=%d)", tank, toHalf, avg, n), numbers
end

return RoshanRules
