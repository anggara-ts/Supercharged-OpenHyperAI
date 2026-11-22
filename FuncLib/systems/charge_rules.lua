-- Pure rules for Spirit Breaker's long Charge of Darkness (#47): save an ally ganked in another lane, or join a
-- teamfight far away. No bot API calls, so Tests/test_charge_rules.lua drives them with plain numbers;
-- BotsLib/hero_spirit_breaker.lua (X.ConsiderChargeOfDarkness) gathers the numbers and calls them.
--
-- Game data (Valve datafeed herodata hero_id=71, 2026-11-22): spirit_breaker_charge_of_darkness
--   movement_speed 275/325/375/425  bonus move speed on top of his own
--   windup_time 1.5, min_movespeed_bonus_pct 25  the charge starts at 25% of the bonus and reaches all of it after 1.5s
--   AbilityCastPoint 0.1, global (cast range 0), cooldown 22/19/16/13, mana 80/90/100/110
--   target team enemy, does not pierce debuff immunity (immunity 4); if the target dies he retargets the nearest enemy
--   unit to that spot. The datafeed says nothing about cancelling the charge or about the move speed cap.
-- Tower attack range 700: scripts/npc/units.txt (npc_dota_goodguys_tower1_top AttackRange, 7.42 pak01_dir.vpk).
local Rules = {}

-- A target this close is the near rules' job (channel interrupt, engage, an ally's target at 600-1900).
Rules.FAR_DIST = 1600
-- Unverified: whether the charge ignores the 550 move speed cap. Capping makes the ETA longer (the safer side for
-- the save's "does the ally live until he lands" check). The [OHA-HUNT] start dist= / end lasted= lines measure it.
Rules.MAX_SPEED = 550
-- A teamfight charge that lands later than this is likely too late (fights end; no duration estimate exists).
Rules.MAX_FIGHT_ETA = 7
-- Spirit Breaker himself below this HP ratio does not charge into a fight or a gank.
Rules.SELF_HP_MIN = 0.4
Rules.TOWER_RANGE = 700
-- HP-loss samples: kept for KEEP seconds; the rate is read from a sample MIN_AGE..MAX_AGE seconds old.
Rules.SAMPLE_KEEP = 2.0
Rules.SAMPLE_MIN_AGE = 0.5
Rules.SAMPLE_MAX_AGE = 1.5

-- Seconds from the cast to the arrival over dist. moveSpeed = his move speed now, bonus = movement_speed at his
-- level. The windup is assumed linear (from minPct% of the bonus to all of it over windup seconds): unverified.
function Rules.ChargeEta(dist, moveSpeed, bonus, windup, minPct, castPoint, maxSpeed)
	windup = windup or 1.5
	minPct = minPct or 25
	castPoint = castPoint or 0.1
	local top = moveSpeed + bonus
	local start = moveSpeed + bonus * minPct / 100
	if maxSpeed ~= nil then
		top = math.min(top, maxSpeed)
		start = math.min(start, maxSpeed)
	end
	if top <= 0 then
		return math.huge
	end
	local windupDist = (start + top) / 2 * windup
	if dist <= windupDist then
		local accel = windup > 0 and (top - start) / windup or 0
		if accel <= 0 then
			return castPoint + dist / math.max(start, 1)
		end
		-- dist = start * t + accel * t^2 / 2
		return castPoint + (-start + math.sqrt(start * start + 2 * accel * dist)) / accel
	end
	return castPoint + windup + (dist - windupDist) / top
end

-- HP history of one hero: an array of { t = seconds, hp = health }, oldest first.
function Rules.PushSample(samples, now, hp)
	samples[#samples + 1] = { t = now, hp = hp }
	while #samples > 1 and now - samples[1].t > Rules.SAMPLE_KEEP do
		table.remove(samples, 1)
	end
end

-- HP lost per second, from the oldest sample that is SAMPLE_MIN_AGE..SAMPLE_MAX_AGE old to hpNow (0 when healing).
-- nil when no sample is old enough (the hero was not sampled long enough: the caller must not guess).
function Rules.LossRate(samples, now, hpNow)
	for _, sample in ipairs(samples) do
		local age = now - sample.t
		if age <= Rules.SAMPLE_MAX_AGE and age >= Rules.SAMPLE_MIN_AGE then
			return math.max(0, (sample.hp - hpNow) / age)
		end
	end
	return nil
end

-- Seconds until an ally at hp dies at rate HP/s (math.huge when it is not losing HP).
function Rules.TimeToDie(hp, rate)
	if rate == nil or rate <= 0 then
		return math.huge
	end
	return hp / rate
end

-- Why Spirit Breaker does not charge, or nil to charge. s:
--   kind        "save" (an ally ganked in another lane) or "fight" (a teamfight far away)
--   selfHp      his HP ratio; retreating: his mode is retreat; busy: an enemy hero hit him in the last ~1.5s
--   dist, eta   to the charge target (ChargeEta)
--   allies      our heroes at the spot without him (the ganked ally counts); enemies: enemy heroes there
--   hitBy       (save) enemy heroes that hit the ally recently
--   allyHp, lossRate   (save) the ally's health and HP lost per second (LossRate; nil = no sample yet)
--   tower       the target stands in a standing enemy tower's range
function Rules.ChargeSkipWhy(s)
	if s.selfHp < Rules.SELF_HP_MIN then
		return "low-hp"
	end
	if s.retreating then
		return "retreat"
	end
	if s.busy then
		return "busy"
	end
	if s.dist <= Rules.FAR_DIST then
		return "near"
	end
	if s.kind == "save" then
		-- ganked: 2+ heroes on it, or 1+ hitting it while their side outnumbers ours there
		local ganked = s.hitBy >= 2 or s.hitBy >= 1 and s.enemies > s.allies
		if not ganked then
			return "no-gank"
		end
		if s.lossRate == nil then
			return "no-sample"
		end
		if Rules.TimeToDie(s.allyHp, s.lossRate) <= s.eta then
			return "too-late"
		end
	elseif s.eta > Rules.MAX_FIGHT_ETA then
		return "too-far"
	end
	-- after he lands: him + the allies there, at most one down
	if s.allies + 1 < s.enemies - 1 then
		return "outnumbered"
	end
	-- a tower in range of the landing spot: only when our side already wins there without him
	if s.tower and s.allies <= s.enemies then
		return "tower"
	end
	return nil
end

-- Which enemy hero to charge (higher is better). t:
--   hp          HP ratio; core: a core (pos 1-3)
--   hitsAlly    (save) it attacks / recently damaged the ganked ally
--   distToSpot  to the ally (save) or the fight centre (fight)
function Rules.TargetScore(t)
	local score = (1 - t.hp) * 100 - (t.distToSpot or 0) / 20
	if t.core then
		score = score + 30
	end
	if t.hitsAlly then
		score = score + 1000
	end
	return score
end

return Rules
