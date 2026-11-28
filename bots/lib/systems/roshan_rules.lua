-- Shared bot system: pure Roshan-take rules (no bot API calls), so they can be tested with real numbers.
-- Used by mode_roshan_generic.lua (#12).
local RoshanRules = {}

-- Roshan's Slam: 70 magical damage every 10s to heroes within 350 (7.42 npc_abilities "roshan_slam": damage 70,
-- damage_growth 10, AbilityCooldown 10.0, radius 350; read from pak01_dir.vpk). Counted for every member (ranged
-- heroes usually stand outside 350, so this errs on the safe side); the growth is not counted.
RoshanRules.SLAM_DPS = 7
-- Roshan's attack on one hero per second when his handle can't be read. Measured, not game data: the
-- `[SHy-ROSH] step-out ... roshDmg3s=` lines (Roshan's GetEstimatedDamageToTarget over 3s on the hero he hits) read
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
-- The time to half HP comes from the group's right-click damage (spells and items are not counted) through his armor,
-- times the share of it that lands (HIT_SHARE), minus his regeneration (RoshanRules.HitDps). The tanking pool has to
-- last HALF_CREDIT times the modelled time to half.
-- Until game 091 the time to half used a flat half of the right-click and no regeneration, and HALF_CREDIT was 1.0.
-- Game 091 (31 min) Dire committed 5/5 at fit=group(tank=21,half=14) and 4/5 at (tank=17,half=17), all at full HP and
-- no enemy near: Roshan was at 76% after 16s and 67% after 26s, while four of them left under 45% (t=1901-1916), so his
-- time to half was about 33s, not 14-17. Game 089's three Dire commits (tank=17,half=17 / 18,14 / 18,17) left him at
-- 75-94% after 15-20s, and game 088's t=1297 took about 28s to half where the model said 19. Every commit with fit=
-- numbers on its commit line (games 088-091, seven of them) passed the check and failed. Their time to half was 1.8 to
-- 2.4 times the model's; HIT_SHARE is set from them (the right-click they implied against the HP Roshan lost, plus
-- his regeneration: 0.20-0.38 of the raw right-click, about 0.25 = ARMOR_THROUGH x 0.7). With it the seven commits
-- read tank/half 0.33-0.67, and HALF_CREDIT 0.75 drops them all. The older kills (games 074-087) had only call-line
-- fits, often a minute stale or more: seven of them still pass (tank/half 0.78-2.27), seven drop (0.44-0.72: a slower
-- group, 480-1040 right-click per second; tests/test_roshan_rules.lua lists both): a judgement call for the
-- maintainer. The tank side is unchanged: in game 091 the heroes left 16-26s after the commit against tank=21.
-- Before that: 0.75, from one take (game 068 Dire, 5 of 5, killed in about 20s where the model said about 27s). Game 088
-- (maintainer decision D7, 2026-11-27: one more game of fit= numbers, then retune) committed two takes that passed at
-- 0.75 and failed: Radiant t=1297 commit fit=group(tank=16,half=19) left Roshan at 34% (he took about 28s to reach
-- half, not 19), Dire t=1681 fit=group(tank=14,half=18) left him at 18%. At 1.0 both drop (16 < 19, 14 < 18). The
-- takes that killed him in games 074-085 had tank/half 1.0-4.8 at the call (082 t=1917 12/12, 081 t=1981 14/11,
-- 082 t=809 18/16, 078 t=1457 17/13, 084 t=2050 22/16, ...; tests/test_roshan_rules.lua lists them), so they still
-- pass. Takes that failed with tank/half above 1.0 (087 t=1337 22/10, t=1535 17/10) failed for other reasons
-- than the tank model: no credit drops them without dropping the kills.
RoshanRules.HALF_CREDIT = 0.75
-- Roshan's armor: 7.42 npc_units "npc_dota_roshan" ArmorPhysical 30 (pak01_dir.vpk, read 2026-11-28; the 7.33 patch
-- notes: "Roshan's Base Armor increased from 20 to 30"). His armor also grows with game time ("a scaling armor bonus
-- that increases as time goes on", abilities_english.txt roshan_devotion), by an amount that is in neither the game
-- files nor the patch notes (unverified): it is not modelled, the commit line logs his armor (armor=) to measure it.
RoshanRules.BASE_ARMOR = 30
-- Health regeneration: npc_units "npc_dota_roshan" StatusHealthRegen 20.
RoshanRules.REGEN = 20
-- The share of the group's right-click (after armor) that comes off his HP. Measured, not game data (games 088-091,
-- above): heroes walking in and out, his Bash stuns (roshan_bash: 15% chance, 1.65s), Slam's 50% slow and the members
-- not all hitting at once.
RoshanRules.HIT_SHARE = 0.7

-- Physical damage multiplier of an armor value (the Dota armor formula 1 - 0.06a / (1 + 0.06|a|)): 0.357 at 30.
function RoshanRules.ArmorThrough(armor)
	local a = armor or RoshanRules.BASE_ARMOR
	return 1 - 0.06 * a / (1 + 0.06 * math.abs(a))
end
RoshanRules.ARMOR_THROUGH = RoshanRules.ArmorThrough(RoshanRules.BASE_ARMOR)

-- HP per second the group's right-click (groupDps, before armor) takes off Roshan, after his regeneration (0 or more).
function RoshanRules.HitDps(groupDps)
	return math.max(0, (groupDps or 0) * RoshanRules.ARMOR_THROUGH * RoshanRules.HIT_SHARE - RoshanRules.REGEN)
end

-- Seconds until Roshan is down to STAY_BELOW of his HP (0 when he is there already).
function RoshanRules.HalfTime(roshHp, roshMax, groupDps)
	local max = math.max(1, roshMax or roshHp or 1)
	return math.max(0, (roshHp or max) - RoshanRules.STAY_BELOW * max) / math.max(1, RoshanRules.HitDps(groupDps))
end
-- Finishing a low Roshan with nobody contesting (#12, game 088: Dire had him at 18-20% and Radiant at 34-35% with
-- foes=0 near the pit; heroes he had focused stepped out a little, the few-hitters and finish-unsafe checks dropped
-- the take and he regenerated). Under FINISH_CLEAR_BELOW of his HP with no enemy hero seen within 1600 of the pit, the
-- allies within FINISH_HITTER_RANGE of him count as hitters and as the group in the pit (not only those within 900 of
-- him and 1600 of the pit), and one ally in the pit with no foe there is safe enough to finish. The range is wider than
-- the pit's 1600 because the heroes that had stepped out stood 1618-2014 from it (game 088: Puck 1618 at t=1352,
-- Winter Wyvern 1993 at t=1727, Underlord 2014 at t=1347).
RoshanRules.FINISH_CLEAR_BELOW = 0.36
RoshanRules.FINISH_HITTER_RANGE = 2200

-- Is the finish clear? roshRatio: his HP ratio (seen, or last seen; nil when unknown), foesNearPit: enemy heroes seen
-- within 1600 of the pit.
function RoshanRules.FinishClear(roshRatio, foesNearPit)
	return type(roshRatio) == "number" and roshRatio < RoshanRules.FINISH_CLEAR_BELOW and (foesNearPit or 0) == 0
end

-- The tank check alone: does a tanking time of `tank` seconds cover `half` seconds to half HP?
function RoshanRules.TankCovers(tank, half)
	return (tank or 0) >= (half or 0) * RoshanRules.HALF_CREDIT
end

-- Can the group that is coming take Roshan before its HP runs out? (#12, game 068: 3 of 4 committed tries failed;
-- the kill time ignored Roshan's damage on the group.)
--   s.members: { { hp = HP, maxHp = max HP, roshDps = Roshan's damage per second on this hero }, ... } (the heroes
--     the take time counts)
--   s.roshHp, s.roshMax: Roshan's HP; s.groupDps: the members' right-click damage per second before his armor
--     (RoshanRules.HitDps turns it into the HP he loses)
-- The members' HP above the leave line is the group's tanking pool: Roshan hits one hero at a time (the average of
-- roshDps) and his Slam hits everyone. The pool must last until Roshan is at half HP, after which nobody leaves.
-- Returns ok, why, numbers { avg, tank, half, low, hit }.
function RoshanRules.GroupFit(s)
	local members = s.members or {}
	local n = #members
	if n == 0 then
		return false, "no-members", { avg = 0, tank = 0, half = 0, hit = 0 }
	end
	local leave = s.leaveHp or RoshanRules.LEAVE_HP
	local ratioSum, pool, dpsSum = 0, 0, 0
	-- low: seconds the weakest member lasts to the leave line while Roshan hits him (and his Slam), for the log: the
	-- per-member data a later model needs (game 088 Dire t=1686: Rubick left at 42% five seconds after the commit).
	local low = nil
	for _, member in ipairs(members) do
		local maxHp = math.max(1, member.maxHp or 1)
		local hp = math.max(0, member.hp or 0)
		local roshDps = member.roshDps or RoshanRules.FALLBACK_DPS
		local margin = math.max(0, hp - leave * maxHp)
		ratioSum = ratioSum + hp / maxHp
		pool = pool + margin
		dpsSum = dpsSum + roshDps
		local lasts = margin / math.max(1, roshDps + RoshanRules.SLAM_DPS)
		if low == nil or lasts < low then
			low = lasts
		end
	end
	local avg = ratioSum / n
	local drain = dpsSum / n + RoshanRules.SLAM_DPS * n
	local tank = pool / math.max(1, drain)
	local toHalf = RoshanRules.HalfTime(s.roshHp, s.roshMax, s.groupDps)
	local hit = RoshanRules.HitDps(s.groupDps)
	local numbers = { avg = avg, tank = tank, half = toHalf, low = low or 0, hit = hit }
	if avg < (s.minAvg or RoshanRules.MIN_AVG_HP) then
		return false, string.format("group-hurt(avg=%.2f,n=%d)", avg, n), numbers
	end
	if not RoshanRules.TankCovers(tank, toHalf) then
		return false,
			string.format(
				"tank-short(tank=%.0f,half=%.0f,avg=%.2f,n=%d,low=%.0f,dps=%.0f,hit=%.0f)",
				tank,
				toHalf,
				avg,
				n,
				low or 0,
				s.groupDps or 0,
				hit
			),
			numbers
	end
	return true,
		string.format(
			"group(tank=%.0f,half=%.0f,avg=%.2f,n=%d,low=%.0f,dps=%.0f,hit=%.0f)",
			tank,
			toHalf,
			avg,
			n,
			low or 0,
			s.groupDps or 0,
			hit
		),
		numbers
end

return RoshanRules
