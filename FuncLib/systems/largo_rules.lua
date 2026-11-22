-- Pure rules for Largo (#198): plain values in and out, so Tests/test_largo_rules.lua can check them without the
-- bot API. Game data (Valve datafeed hero_id=155 and the 7.42 npc_dota_hero_largo.txt in pak01_dir.vpk):
-- Amphibian Rhapsody is a toggle (cooldown 1.5, no mana) with rhythm_interval 1 (one beat a second),
-- rhythm_grace_period 0.4, max_stacks 5 of Groovin' (stack_duration 5: the stacks linger 5s after the song ends),
-- radius 800. The three songs cost 25/35/45 mana and share one 0.2s cooldown (AbilitySharedCooldown "largo_songs").
-- With Scepter (double_song 1) two songs can be strummed on one beat.
local LargoRules = {}

LargoRules.BEAT = 1
LargoRules.GRACE = 0.4
LargoRules.MAX_STACKS = 5
LargoRules.SONG_SHARED_COOLDOWN = 0.2
-- A strum goes out on the first think at or after the beat, never before it, and at most this late. Inside the
-- grace either way: the game data does not say whether the 0.4s grace lies before, after or around the beat.
LargoRules.LATE = 0.25
-- After a strum that gained no Groovin' stack (below the cap), the beat is assumed this far later: three misses walk
-- the phase through a whole beat, so a 0.4s window is found within a few beats wherever it lies.
LargoRules.REANCHOR_SHIFT = 0.3
-- Shifts with no hit at all before the stacks are taken to say nothing (3 x 0.3s: a whole beat swept).
LargoRules.MAX_REANCHORS = 3
-- The song ends after this many beats in a row with no song going out (blocked, or a cast that never happened),
-- and is not started again for NO_CAST_HOLD seconds: Largo is disarmed while it is on.
LargoRules.NO_CAST_BEATS = 3
LargoRules.NO_CAST_HOLD = 20
-- The song ends after this many seconds with no reason to sing (the stacks linger 5s anyway).
LargoRules.TOGGLE_OFF_AFTER = 3
-- Turn the song on only with mana for this many beats of the chosen songs.
LargoRules.TOGGLE_ON_BEATS = 3

-- The beat that is due now, or nil. anchor: a time that is a beat (the toggle-on time, moved by re-anchors);
-- lastBeat: the beat strummed last (the anchor itself at toggle-on, so the first strum is one beat later).
function LargoRules.BeatDue(now, anchor, lastBeat, beat, late)
	beat = beat or LargoRules.BEAT
	late = late or LargoRules.LATE
	if now < anchor then
		return nil
	end
	local index = math.floor((now - anchor) / beat + 1e-6)
	if index < 1 then
		return nil
	end
	local beatTime = anchor + index * beat
	if beatTime <= lastBeat + beat * 0.5 then
		return nil
	end
	if now - beatTime > late then
		return nil
	end
	return beatTime
end

-- What a strum did, from the Groovin' stacks before it and a moment after it:
--   "hit"  the stacks rose;
--   "max"  they were at the cap and stayed there (a hit can't show, and it is not a miss);
--   "miss" anything else.
function LargoRules.StrumResult(before, after, maxStacks)
	maxStacks = maxStacks or LargoRules.MAX_STACKS
	if after > before then
		return "hit"
	end
	if before >= maxStacks and after >= before then
		return "max"
	end
	return "miss"
end

-- The anchor after a strum's result: a miss of a strum that really went out moves the beat later; a hit or a strum
-- that never went out (no mana, a cast that failed) keeps it.
function LargoRules.Reanchor(anchor, result, castWentOut, shift)
	if result == "miss" and castWentOut then
		return anchor + (shift or LargoRules.REANCHOR_SHIFT)
	end
	return anchor
end

-- Whether a miss may move the beat. A beat that has hit (the stacks work) moves only after two on-time misses in a row
-- (game 071: one lost or late order moved a proven beat); before any hit, for MAX_REANCHORS shifts.
function LargoRules.MayReanchor(reanchors, hits, missStreak)
	if hits > 0 then
		return (missStreak or 0) >= 2
	end
	return reanchors < LargoRules.MAX_REANCHORS
end

-- A strum order that has not gone out yet is pushed again while the beat's window lasts (LATE + 0.1s after the beat,
-- inside the 0.4s grace), at most MAX_PUSHES times.
LargoRules.MAX_PUSHES = 6
function LargoRules.ShouldRepush(sinceBeat, attempts)
	return sinceBeat <= LargoRules.LATE + 0.1 and attempts < LargoRules.MAX_PUSHES
end

-- Whether a beat with no song out counts toward the no-cast toggle-off. Not while he runs (game 071: the song went off
-- in a retreat, when the run and heal songs mattered), not for a block by the shared cooldown (a song just went out).
function LargoRules.CountsAsNoCast(castWentOut, blockedWhy, escaping)
	if escaping or castWentOut then
		return false
	end
	return blockedWhy ~= "cooldown"
end

-- Heal thresholds (#198, maintainer game 071): under HEAL_URGENT the heal beats every song; outside a fight it tops
-- the group up while the lowest ally is under TOP_UP_HP or the group misses TOP_UP_STRUMS strums of healing, with
-- TOP_UP_MP mana or more.
LargoRules.HEAL_URGENT = 0.35
LargoRules.TOP_UP_HP = 0.8
LargoRules.TOP_UP_STRUMS = 3
LargoRules.TOP_UP_MP = 0.4

-- Which songs to play. s (all optional):
--   enemies     enemy heroes inside the song radius (800)
--   fighting    Largo or an ally inside the radius is fighting (going on someone, or a team fight)
--   hurtHp      the lowest HP ratio of a healable ally hero inside the radius (Largo included), 1 when none
--   escaping    Largo or an ally inside the radius runs from enemies that hit it
--   chasing     an ally inside the radius chases a target that is getting away
--   objective   allies inside the radius hit Roshan or a Tormentor
--   double      Scepter: two songs per beat
-- Returns first, second, why ("fight" | "vibes" | "time", second only with double), or nil when there is no reason.
--   Good Vibrations (heal): someone below 30% first of all, below 50% above a fight, below 75% in a fight.
--   Double Time (move speed, slow resistance): an escape, then a chase.
--   Fight Song (burst damage, spell amp, attack magic damage): enemies inside the radius and someone fighting, or
--   Roshan / a Tormentor.
function LargoRules.ChooseSongs(s)
	local scores = {}
	local reasons = {}
	local hurtHp = s.hurtHp or 1
	local enemies = s.enemies or 0
	local function offer(song, score, why)
		if scores[song] == nil or score > scores[song] then
			scores[song] = score
			reasons[song] = why
		end
	end
	-- Good Vibrations by the group's need (game 071 ~26:00: allies at 60-75% got no heal). strumsNeeded: strums to top
	-- the group up (missing HP / (heal per strum x heroes healed)).
	local perStrum = (s.healPerStrum or 0) * math.max(1, s.healCount or 0)
	local strumsNeeded = perStrum > 0 and (s.missing or 0) / perStrum or 0
	local inFight = enemies >= 1 and s.fighting or s.objective
	if hurtHp < LargoRules.HEAL_URGENT then
		-- Someone is about to die: beats the run song too.
		offer("vibes", 3, "hurt")
	elseif inFight then
		if hurtHp < 0.5 then
			offer("vibes", 2.2, "hurt")
		elseif (s.under65 or 0) >= 2 then
			offer("vibes", 2.1, "group-hurt")
		elseif hurtHp < 0.75 then
			offer("vibes", 1.8, "hurt")
		end
	elseif s.escaping then
		if hurtHp < 0.75 then
			offer("vibes", 1.8, "hurt")
		end
	elseif
		(s.mpRatio or 0) >= LargoRules.TOP_UP_MP
		and (hurtHp < LargoRules.TOP_UP_HP or strumsNeeded >= LargoRules.TOP_UP_STRUMS)
	then
		-- After a fight: top the group up while the mana lasts, stop when it is full.
		offer("vibes", 1.5, "top-up")
	end
	if s.escaping then
		offer("time", 2.5, "escape")
	elseif s.chasing then
		offer("time", 1.6, "chase")
	end
	if enemies >= 1 and s.fighting then
		offer("fight", 2, "fight")
	elseif s.objective then
		offer("fight", 1.5, "objective")
	end
	local order = { "vibes", "time", "fight" }
	local first, second
	for _, song in ipairs(order) do
		if scores[song] ~= nil and (first == nil or scores[song] > scores[first]) then
			first = song
		end
	end
	if first == nil then
		return nil, nil, nil
	end
	local why = reasons[first]
	if s.double then
		for _, song in ipairs(order) do
			if song ~= first and scores[song] ~= nil and (second == nil or scores[song] > scores[second]) then
				second = song
			end
		end
		if second ~= nil then
			why = why .. "+" .. reasons[second]
		end
	end
	return first, second, why
end

-- Whether to end the song now: "mana" (not enough mana for one song), "no-cast" (noCastBeats beats in a row with no
-- song going out), "idle" (no reason to sing for holdSeconds), or nil to keep singing.
-- silentFor: seconds he could strum and gave no song order (game 071 23:10: a song on for 6s with nothing played);
-- "silent" after SILENT_AFTER.
LargoRules.SILENT_AFTER = 1.6
function LargoRules.ToggleOffReason(now, lastReasonAt, canAffordSong, holdSeconds, noCastBeats, silentFor)
	if not canAffordSong then
		return "mana"
	end
	if (noCastBeats or 0) >= LargoRules.NO_CAST_BEATS then
		return "no-cast"
	end
	if (silentFor or 0) >= LargoRules.SILENT_AFTER then
		return "silent"
	end
	if now - lastReasonAt >= (holdSeconds or LargoRules.TOGGLE_OFF_AFTER) then
		return "idle"
	end
	return nil
end

-- Enough mana to turn the song on: `beats` beats of the chosen songs (songCost each, songsPerBeat per beat).
function LargoRules.CanStartSong(mana, songCost, songsPerBeat, beats)
	return mana >= songCost * (songsPerBeat or 1) * (beats or LargoRules.TOGGLE_ON_BEATS)
end

-- Croak of Genius: on whom (#198, maintainer 2026-11-22). Datafeed hero_id=155: mana_cost_reduction 15%, Croak costs
-- 40, duration 15/20/25/30 against a 25s cooldown (from level 3 the buff lasts the whole cooldown), damage_portion_pct
-- 25-40% reverberated over 5s, "Only applies to damage sources affected by spell amplification" (not attacks); an
-- ally's buff loses duration_reduction 0.5s per mana spend, Largo's own does not. Aghanim's Shard (on the innate
-- Encore: "HasShardUpgrade" "1" under largo_encore in the 7.42 npc_dota_hero_largo.txt; datafeed shard text):
-- "Whenever Largo applies a Unit Target buff to a friendly hero, he also gets the buff. If Largo targets himself, the
-- buff is also applied to the nearest allied hero within the cast range."
-- o: level; hasShard; allyFighting (an ally going on a hero); spellAlly (one of them deals spell damage,
-- IsSpellDamageAlly); selfHasBuff; selfWants (singing, about to sing, or a Lick + Frogstomp combo); alone.
-- Returns "ally" | "self" | nil and why:
--   shard-share  Shard and an ally fighting: the ally (spell damage first), Largo gets it too;
--   ally-nuker   a spell-damage ally going into a fight (never a physical core: the reverb skips attacks);
--   self-upkeep  from level 3, on Largo whenever it is ready (his songs, Lick and Frogstomp are magical);
--   self-mana    levels 1-2: on Largo when he sings, is about to, or starts a combo.
LargoRules.CROAK_UPKEEP_LEVEL = 3
function LargoRules.CroakTarget(o)
	if o.hasShard and o.allyFighting then
		return "ally", "shard-share"
	end
	if o.spellAlly and o.allyFighting then
		return "ally", "ally-nuker"
	end
	if o.selfHasBuff then
		return nil, nil
	end
	if (o.level or 0) >= LargoRules.CROAK_UPKEEP_LEVEL then
		return "self", "self-upkeep"
	end
	if o.selfWants then
		return "self", "self-mana"
	end
	return nil, nil
end

-- Whether an ally's damage is mostly spells (the part Croak's reverb takes): its 5s magic estimate against its
-- physical one (GetEstimatedDamageToTarget), or a kit of 2+ magical / pure spells with at least half as much magic.
function LargoRules.IsSpellDamageAlly(magicDamage, physicalDamage, spellKitCount)
	if magicDamage <= 0 then
		return false
	end
	if magicDamage >= physicalDamage then
		return true
	end
	return (spellKitCount or 0) >= 2 and magicDamage >= physicalDamage * 0.5
end

-- Frogstomp as lane harass (#198, game 071). o: mpRatio, manaAfterOk (after the cast still the mana for Lick and
-- Croak, Fu.GetManaThreshold), inEnemyTowerRange (Largo), enemiesNear / alliesNear (heroes within 1200, Largo
-- counted), retreating. Returns ok and, when not ok, the first gate that stops it.
LargoRules.HARASS_MP = 0.8
function LargoRules.LaneStompOk(o)
	if o.retreating then
		return false, "retreating"
	end
	if o.mpRatio < LargoRules.HARASS_MP then
		return false, "mana"
	end
	if not o.manaAfterOk then
		return false, "reserve"
	end
	if o.inEnemyTowerRange then
		return false, "tower"
	end
	if o.enemiesNear > o.alliesNear then
		return false, "outnumbered"
	end
	return true, nil
end

-- Whether a Catchy Lick or Frogstomp is worth ending the song for (game 071, maintainer: "he could turn off ulti and
-- use lick when needed"). reason: the spell rule's why; stacks: Groovin' now (they linger stack_duration 5s after the
-- song, and the toggle has a 1.5s cooldown); count: heroes a stomp catches; alliesNear: other ally heroes within 900.
--   Always: a kill, an ally save, an ally dispel, a channel stopped, a stomp on 3+ heroes.
--   Below BREAK_STACKS stacks only (little to lose): a stomp on 2 heroes, a pull of the enemy into our fight (Largo's
--   chase lick with an ally near, or an engage lick).
LargoRules.BREAK_STACKS = 3
-- songHasReason false: no song is worth playing now (no one hurt, no enemy in the radius, no escape), so any play
-- beats the idle song (game 071 23:10).
function LargoRules.BreakSongFor(reason, stacks, count, alliesNear, songHasReason)
	if reason == nil then
		return false
	end
	if songHasReason == false then
		return true
	end
	if reason == "kill" or reason == "ally-save" or reason == "channel" or string.find(reason, "^ally%-dispel") then
		return true
	end
	local cheap = stacks < LargoRules.BREAK_STACKS
	if reason == "fight-aoe" then
		return (count or 0) >= 3 or (count or 0) >= 2 and cheap
	end
	if reason == "ally-engage" or reason == "chase" and (alliesNear or 0) >= 1 then
		return cheap
	end
	return false
end

-- Catchy Lick pulls an ally pullDistance (375) toward Largo. A dispel lick on an ally that is fighting in range of its
-- target would drag it out of range: only when the debuff already stops it fighting (sleep, stun) or it is not
-- in range of its target anyway. distToTarget nil: no target.
function LargoRules.DispelPullOk(allyFighting, distToTarget, attackRange, pullDistance, debuffStopsFighting)
	if debuffStopsFighting or not allyFighting or distToTarget == nil then
		return true
	end
	-- In range now and out of it after the pull (pulled straight away from the target, the worst case).
	if distToTarget <= attackRange + 100 and distToTarget + pullDistance > attackRange + 100 then
		return false
	end
	return true
end

return LargoRules
