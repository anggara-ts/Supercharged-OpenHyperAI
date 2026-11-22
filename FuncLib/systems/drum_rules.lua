-- Pure rules for the Drum of Endurance / Boots of Bearing active (#9): plain values in, so Tests/test_drum_rules.lua
-- can check them without the bot API.
--
-- 7.42 game data (scripts/npc/items.txt in pak01_dir.vpk, read 2026-11-21):
--   item_ancient_janggo: no target, radius 1200, bonus_attack_speed_pct 35, bonus_movement_speed_pct 13,
--     duration 6, AbilityCooldown 45, AbilitySharedCooldown "janggo"; "ItemRequiresCharges" is commented out
--     (charges_tooltip 8 is only a tooltip), so the active has no charges to spend.
--   item_boots_of_bearing: no target, radius 1200, bonus_attack_speed_pct 50, bonus_movement_speed_pct 15,
--     duration 6, AbilityCooldown 30, same shared cooldown "janggo".
local DrumRules = {}

DrumRules.RADIUS = 1200
-- A chase counts when the target is this close: further away the 6s buff runs out before the bot gets there.
DrumRules.CHASE_RANGE = 900
-- Escape: hit by a hero this recently (seconds).
DrumRules.HIT_WITHIN = 2
-- Allied heroes in the radius, the bot counted, for a fight or a push cast.
DrumRules.MIN_ALLIES = 2

-- s: {
--   vendetta, invisible   - the bot is in Nyx's Vendetta / invisible: a cast would break it
--   retreating, hitByHero - the bot retreats and a hero hit it in the last HIT_WITHIN seconds
--   inFight               - a fight is on around the bot (allies attacking, enemy heroes near)
--   allies                - allied heroes within RADIUS, the bot counted
--   enemies               - enemy heroes near (fight)
--   goingOn               - the bot is going on a hero (attack / roam modes)
--   targetDist            - distance to that hero (nil: no hero target)
--   attackRange           - the bot's attack range
--   targetMovingAway      - the target's predicted spot is further from the bot than it is now
--   alliesOnBuilding      - allied heroes within RADIUS (the bot counted) hitting an enemy tower / barracks / Ancient
-- }
-- Returns why ("escape" / "fight" / "chase" / "push") or nil. Order by value: escape > fight > chase > push.
function DrumRules.Why(s)
	if s.vendetta or s.invisible then
		return nil
	end
	if s.retreating and s.hitByHero then
		return "escape"
	end
	local allies = s.allies or 0
	if s.inFight and allies >= DrumRules.MIN_ALLIES and (s.enemies or 0) >= 1 then
		return "fight"
	end
	if
		s.goingOn
		and s.targetDist ~= nil
		and s.targetDist <= DrumRules.CHASE_RANGE
		and (s.targetMovingAway or s.targetDist > (s.attackRange or 0))
	then
		return "chase"
	end
	if (s.alliesOnBuilding or 0) >= DrumRules.MIN_ALLIES then
		return "push"
	end
	return nil
end

return DrumRules
