-- Shared bot system: chain disables (#228, "the next stun lands as the last one ends").
--
-- Two of our stuns on one enemy hero at once waste the second one: the stun times overlap instead of adding up.
-- The rule sits in the cast guard (global_overrides.lua GuardCast), so every hero file and the item code get it
-- without a change of their own:
--   * A listed disable (DISABLES below) ordered on an enemy hero who is stunned or hexed for longer than the new
--     disable needs to land (its cast point + delay + travel + walk into range + MARGIN) is refused. The bot
--     attacks that hero instead, and the hero file orders the disable again on a later think; it goes through
--     once the time left is down to what it needs.
--   * A unit-target disable that goes through (or a point one into a running stun) reserves the hero for the team
--     (Chain.claims) until it lands: a second bot whose own disable would land in that window holds it too. Bots
--     that ordered at the same moment used to stun together; now the second one waits for the first stun to end.
--   * Most hero files never order a disable on a hero Fu.IsDisabled already calls disabled (they wait for the
--     stun to end, then pay their own cast point). For a bot that holds a disable on a hero, Fu.IsDisabled
--     (general_utils/hero_state.lua) calls that hero free once the time left is down to the bot's need, so the
--     file orders the disable in time (Chain.ReleaseEarly). Only for that bot, that hero, while the hold lives.
-- No hold on a channelling hero (the stun ends the TP / channel), while the bot retreats or is below 30% HP, from
-- farther than HOLD_RANGE / attack range + ATTACK_BUFFER (the attack order would walk it in), or for longer than
-- HOLD_CAP. Only stuns and hexes count as disabled (roots, silences and slows leave the hero able
-- to act or blink), and only a time left read from a listed modifier counts: an unread time means no hold.
-- Cost: one GetName per targeted cast order; the rest only for a listed disable on an enemy hero. No scan of
-- nearby units; Fu.IsDisabled pays one compare (Chain.live) while no bot holds.
--
-- Logs: "[SHy-CHAIN] t= <bot> hold hero= spell= left= need= gap= dist= src=" (throttled), "... cast hero= spell=
-- left= need= gap= dist= held= real= why=" (a disable cast into a running disable, once per bot, spell and hero
-- every 3s; why=held after a hold, chain without one, blocked / far / cap when the rule did not wait),
-- "... unknown hero= spell= n= mods=" (stunned or hexed but no listed modifier: the list misses a name; n= counts
-- the unlisted names, disable-looking ones first, at most UNKNOWN_CAP shown), "... off"
-- (the time left did not count down: the rule switches itself off for the game), "... error" (once per game).
local Chain = {}

Chain.MARGIN = 0.25 -- s: turn to face the target plus order latency (the ability think runs every 1-3 frames)
Chain.MIN_HOLD = 0.15 -- s: a shorter wait is not worth an order
Chain.MAX_LEFT = 6 -- s: a longer read is not a stun we chain into (a misread or a permanent modifier)
Chain.HOLD_CAP = 4 -- s: one hold never lasts longer
Chain.CLAIM_GRACE = 0.3 -- s: a reservation counts this long past its landing time, then the modifier read rules
Chain.CLAIM_MAX = 2.5 -- s: a reservation never lasts longer (a cancelled cast)
Chain.LOW_HP = 0.3
-- No hold when the bot stands farther from the hero than this or its attack range + ATTACK_BUFFER: the hold's attack
-- order would walk it in from Fissure / Torrent / Ice Path range.
Chain.HOLD_RANGE = 700
Chain.ATTACK_BUFFER = 350
Chain.POINT_MATCH = 300 -- a point cast counts for the bot's target when it is this close to the point
Chain.LOG_GAP = 3

-- Disables the rule covers, from the 7.42 game files (pak01_dir.vpk scripts/npc/heroes/npc_dota_hero_<name>.txt and
-- scripts/npc/items.txt, read 2026-11-19). kind: the cast the guard sees (unit = entity order, point = location
-- order). speed / delay / duration: the ability's special-value keys, read from the caster's own handle; the
-- numbers after them are the game-file values, used when a read gives 0. No-target stuns (Hoof Stomp, Ravage,
-- Reverse Polarity) and channelled ones (Shackles, Fiend's Grip, Dismember) are left out on purpose.
Chain.DISABLES = {
	-- Unit target, projectile: bolt_speed 1000, bolt_stun_duration 1.0-1.75.
	sven_storm_bolt = { unit = true, speed = { "bolt_speed", 1000 }, duration = { "bolt_stun_duration", 1 } },
	-- magic_missile_speed 1350, magic_missile_stun 1.2-1.8.
	vengefulspirit_magic_missile = {
		unit = true,
		speed = { "magic_missile_speed", 1350 },
		duration = { "magic_missile_stun", 1.2 },
	},
	-- blast_speed 1200, blast_stun_duration 1.2-1.8.
	skeleton_king_hellfire_blast = {
		unit = true,
		speed = { "blast_speed", 1200 },
		duration = { "blast_stun_duration", 1.2 },
	},
	-- chaos_bolt_speed 900; the stun is random between stun_min and stun_max: the shorter one is reserved.
	chaos_knight_chaos_bolt = { unit = true, speed = { "chaos_bolt_speed", 900 }, duration = { "stun_min", 1.25 } },
	-- projectile_speed 1600 (Elder Dragon Form range), stun_duration 1.8-2.4.
	dragon_knight_dragon_tail = {
		unit = true,
		speed = { "projectile_speed", 1600 },
		duration = { "stun_duration", 1.8 },
	},
	-- Instant: stun_duration 1.2.
	ogre_magi_fireblast = { unit = true, duration = { "stun_duration", 1.2 } },
	ogre_magi_unrefined_fireblast = { unit = true, duration = { "stun_duration", 1.2 } },
	-- Instant hexes: duration 2-3.2 (Lion), 2-2.9 (Shadow Shaman), sheep_duration 2.8 (Scythe of Vyse).
	lion_voodoo = { unit = true, duration = { "duration", 2 } },
	shadow_shaman_voodoo = { unit = true, duration = { "duration", 2 } },
	item_sheepstick = { unit = true, duration = { "sheep_duration", 2.8 } },
	-- Instant: stun_duration 1.6 (Abyssal Blade active).
	item_abyssal_blade = { unit = true, duration = { "stun_duration", 1.6 } },
	-- Primal Roar: duration 3-4.
	beastmaster_primal_roar = { unit = true, duration = { "duration", 3 } },
	-- Point, delayed: light_strike_array_delay_time 0.5, light_strike_array_stun_duration 1.2-2.4.
	lina_light_strike_array = {
		point = true,
		delay = { "light_strike_array_delay_time", 0.5 },
		duration = { "light_strike_array_stun_duration", 1.2 },
	},
	-- delay 0.35, duration 1.7.
	leshrac_split_earth = { point = true, delay = { "delay", 0.35 }, duration = { "duration", 1.7 } },
	-- path_delay 0.2, stun_duration 1.25-2.
	jakiro_ice_path = { point = true, delay = { "path_delay", 0.2 }, duration = { "stun_duration", 1.25 } },
	-- No delay after the 0.69 cast point: stun_duration 1-1.6.
	earthshaker_fissure = { point = true, duration = { "stun_duration", 1 } },
	-- delay 1.6, stun_duration 1.4.
	kunkka_torrent = { point = true, delay = { "delay", 1.6 }, duration = { "stun_duration", 1.4 } },
	-- Lines: speed 2800 / duration 1.3-2.2 (Earth Spike, also unit target), speed 1600 / duration 1.25-2 (Impale),
	-- burrow_speed 2000 / burrow_duration 1.2-1.8 (Burrowstrike).
	lion_impale = { point = true, unit = true, speed = { "speed", 2800 }, duration = { "duration", 1.3 } },
	nyx_assassin_impale = { point = true, speed = { "speed", 1600 }, duration = { "duration", 1.25 } },
	sandking_burrowstrike = {
		point = true,
		speed = { "burrow_speed", 2000 },
		duration = { "burrow_duration", 1.2 },
	},
}

-- Modifiers whose time left is the time a hero stays stunned or hexed. Names from the game's localization
-- (resource/localization/abilities_english.txt: DOTA_Tooltip_<name>, tooltips "Stunned" / "Hexed"). Most stuns
-- use the shared modifier_stunned; the rest carry their own.
Chain.MODIFIERS = {
	modifier_stunned = true,
	modifier_bashed = true,
	modifier_hexxed = true,
	modifier_sheepstick_debuff = true,
	modifier_lion_voodoo = true,
	modifier_shadow_shaman_voodoo = true,
	modifier_item_princes_knife_hex = true,
	modifier_lion_impale = true,
	modifier_nyx_assassin_impale = true,
	modifier_sandking_impale = true,
	modifier_kunkka_torrent = true,
	modifier_jakiro_ice_path_stun = true,
	modifier_earthshaker_fissure_stun = true,
	modifier_tiny_avalanche_stun = true,
	modifier_tidehunter_ravage = true,
	modifier_magnataur_reverse_polarity_stun = true,
	modifier_mars_spear_stun = true,
	modifier_rubick_telekinesis_stun = true,
	modifier_monkey_king_boundless_strike_stun = true,
	modifier_pangolier_gyroshell_stunned = true,
	modifier_dawnbreaker_fire_wreath_smash_stun = true,
	modifier_dawnbreaker_solar_guardian_landing_stun = true,
	modifier_faceless_void_chronosphere_freeze = true,
	modifier_faceless_void_timelock_freeze = true,
	modifier_techies_stasis_trap_stunned = true,
	modifier_spirit_breaker_greater_bash = true,
	-- Dream Coil's break stun (game 088 [SHy-CHAIN] unknown lines; datafeed hero_id 13: coil_stun_duration 1.5-2.5).
	modifier_puck_coil_break_stun = true,
	-- Cold Embrace freezes the enemy Wyvern's ally solid for 4s (datafeed hero_id 112: duration 4): the engine
	-- calls him stunned (game 088 t=1445: Rubick inside it read as stunned with no listed modifier). A stun that
	-- lands inside it is wasted, so the next one waits for its end. The cocoon blocks physical damage: the hold
	-- walks to him instead of attacking (NO_ATTACK).
	modifier_winter_wyvern_cold_embrace = true,
}

-- Listed modifiers whose hero takes no physical damage: a hold on them moves to the hero instead of attacking.
Chain.NO_ATTACK = {
	modifier_winter_wyvern_cold_embrace = true,
}

-- The unknown line names at most UNKNOWN_CAP modifiers; names that look like a disable come first, so a long list
-- (auras, item buffs, trackers) does not cut the one the MODIFIERS list misses.
Chain.UNKNOWN_CAP = 16
Chain.DISABLE_WORDS = { "stun", "hex", "voodoo", "bash", "freeze", "frozen", "sleep", "embrace", "coil", "impale" }

Chain.enabled = true
Chain.live = 0 -- bots with a live hold stamp (Fu.IsDisabled's fast path)
Chain.claims = {} -- [team][hero name] = { caster =, landsAt =, endsAt = }
Chain.stamps = {} -- [bot] = { hero =, spell =, need =, startedAt =, untilAt = }
Chain.check = { pass = 0, fail = 0 } -- countdown self-check of the time-left read

-- Pure rules ---------------------------------------------------------------------------------------------------

-- Seconds from the order until the disable lands, plus MARGIN.
function Chain.Need(castPoint, delay, distance, speed, castRange, moveSpeed)
	local need = math.max(0, castPoint or 0) + math.max(0, delay or 0)
	if speed ~= nil and speed > 0 and distance ~= nil then
		need = need + math.min(distance, math.max(castRange or distance, 0)) / speed
	end
	if distance ~= nil and castRange ~= nil and castRange > 0 and distance > castRange then
		need = need + (distance - castRange) / math.max(100, moveSpeed or 300)
	end
	return need + Chain.MARGIN
end

-- A time left to trust: a number in (0, MAX_LEFT], else nil.
function Chain.SaneLeft(left)
	if type(left) ~= "number" or left ~= left or left <= 0 or left > Chain.MAX_LEFT then
		return nil
	end
	return left
end

-- "hold" while the running disable outlasts the new one's landing by more than MIN_HOLD, else "cast".
-- heldFor: how long this bot has held already (HOLD_CAP ends it). blocked: a reason not to hold at all.
function Chain.Decide(left, need, heldFor, blocked)
	if blocked or left == nil or need == nil then
		return "cast"
	end
	if (heldFor or 0) >= Chain.HOLD_CAP then
		return "cast"
	end
	if left - need > Chain.MIN_HOLD then
		return "hold"
	end
	return "cast"
end

-- The time left a teammate's reservation promises (nil when there is none, it is the caster's own, or it lapsed).
function Chain.ClaimLeft(claim, now, me)
	if claim == nil or claim.caster == me then
		return nil
	end
	if now > claim.landsAt + Chain.CLAIM_GRACE or now > claim.madeAt + Chain.CLAIM_MAX then
		return nil
	end
	return math.max(0, claim.endsAt - now)
end

-- Countdown self-check: two reads of one modifier dt apart should drop by dt. Returns "yes", "no" or nil (too
-- close together, or the time went up: a new stun refreshed it).
function Chain.Countdown(left1, t1, left2, t2)
	local dt = t2 - t1
	if dt < 0.3 or left1 == nil or left2 == nil or left2 > left1 + 0.05 then
		return nil
	end
	return math.abs((left1 - left2) - dt) <= 0.25 and "yes" or "no"
end

-- Off after two failed self-checks and no passed one: the read does not count down, so a hold could last forever.
function Chain.Record(verdict)
	if verdict == "yes" then
		Chain.check.pass = Chain.check.pass + 1
	elseif verdict == "no" then
		Chain.check.fail = Chain.check.fail + 1
	end
	if Chain.enabled and Chain.check.fail >= 2 and Chain.check.pass == 0 then
		Chain.enabled = false
		return true
	end
	return false
end

-- The unlisted modifier names for the unknown line: disable-looking names first (in their order), then the rest,
-- cut at cap. Returns the joined names and the total count.
function Chain.UnknownNames(names, cap)
	local first, rest = {}, {}
	for _, name in ipairs(names or {}) do
		local looks = false
		for _, word in ipairs(Chain.DISABLE_WORDS) do
			if string.find(name, word, 1, true) then
				looks = true
				break
			end
		end
		local into = looks and first or rest
		into[#into + 1] = name
	end
	for _, name in ipairs(rest) do
		first[#first + 1] = name
	end
	return table.concat(first, ",", 1, math.min(#first, cap or Chain.UNKNOWN_CAP)), #first
end

-- Game side ----------------------------------------------------------------------------------------------------

local function short(name)
	return (string.gsub(tostring(name), "^npc_dota_hero_", ""))
end

local function call(unit, method, ...)
	local fn = unit and unit[method]
	if fn == nil then
		return nil
	end
	local ok, value = pcall(fn, unit, ...)
	if ok then
		return value
	end
	return nil
end

-- The stun or hex time left on hero (the longest listed modifier), its modifier name, and the unlisted modifier
-- names when the engine says stunned / hexed but none is listed. nil when the hero is neither.
function Chain.ReadLeft(hero)
	if not call(hero, "IsStunned") and not call(hero, "IsHexed") then
		return nil
	end
	local count = call(hero, "NumModifiers")
	if type(count) ~= "number" then
		return nil
	end
	local best, bestName, others = nil, nil, nil
	for i = 0, count - 1 do
		local name = call(hero, "GetModifierName", i)
		if name ~= nil and Chain.MODIFIERS[name] then
			local left = Chain.SaneLeft(call(hero, "GetModifierRemainingDuration", i))
			if left ~= nil and (best == nil or left > best) then
				best, bestName = left, name
			end
		elseif name ~= nil and name ~= "" then
			others = others or {}
			others[#others + 1] = name
		end
	end
	return best, bestName, best == nil and others or nil
end

local function special(ability, spec)
	if spec == nil then
		return 0
	end
	local value = call(ability, "GetSpecialValueFloat", spec[1])
	if type(value) ~= "number" or value <= 0 then
		return spec[2]
	end
	return value
end

local function TeamClaims(team)
	Chain.claims[team] = Chain.claims[team] or {}
	return Chain.claims[team]
end

local function SetStamp(bot, stamp)
	if Chain.stamps[bot] == nil then
		Chain.live = Chain.live + 1
	end
	Chain.stamps[bot] = stamp
end

local function ClearStamp(bot)
	if Chain.stamps[bot] ~= nil then
		Chain.stamps[bot] = nil
		Chain.live = math.max(0, Chain.live - 1)
	end
end

local lineAt = {}
local function Throttled(key, now, gap)
	if now < (lineAt[key] or -math.huge) then
		return false
	end
	lineAt[key] = now + (gap or Chain.LOG_GAP)
	return true
end

local function Fmt(value)
	return type(value) == "number" and string.format("%.2f", value) or "?"
end

-- Countdown self-check on a hold's modifier reads: the first read, then one 0.3s+ later. Returns true when the
-- check switched the rule off.
local function CheckCountdown(stamp, left, now, botName)
	if left == nil or stamp.checked ~= nil then
		return false
	end
	if stamp.firstLeft == nil then
		stamp.firstLeft, stamp.firstAt = left, now
		return false
	end
	local verdict = Chain.Countdown(stamp.firstLeft, stamp.firstAt, left, now)
	if verdict == nil then
		return false
	end
	stamp.checked = verdict
	if Chain.Record(verdict) then
		print(
			string.format(
				"[SHy-CHAIN] t=%.0f %s off reason=no-countdown pass=%d fail=%d",
				now,
				short(botName),
				Chain.check.pass,
				Chain.check.fail
			)
		)
		return true
	end
	return false
end

-- The enemy hero a cast is aimed at: the unit of an entity order, or the bot's target at a point order's spot.
local function AimedHero(bot, target, kind)
	local hero = target
	if kind == "location" then
		hero = call(bot, "GetTarget")
		if hero == nil then
			return nil
		end
		local okD, dist = pcall(GetUnitToLocationDistance, hero, target)
		if not okD or type(dist) ~= "number" or dist > Chain.POINT_MATCH then
			return nil
		end
	end
	if hero == nil or call(hero, "IsNull") or not call(hero, "IsHero") or call(hero, "IsIllusion") then
		return nil
	end
	if call(hero, "GetTeam") == call(bot, "GetTeam") or not call(hero, "IsAlive") then
		return nil
	end
	return hero
end

-- From the cast guard (global_overrides.lua GuardCast, entity and location orders): true = refuse this order.
function Chain.OnCast(bot, ability, target, kind)
	if not Chain.enabled or ability == nil or target == nil then
		return false
	end
	local spellName = call(ability, "GetName")
	local spec = spellName and Chain.DISABLES[spellName]
	if spec == nil or (kind == "entity" and not spec.unit) or (kind == "location" and not spec.point) then
		return false
	end
	local hero = AimedHero(bot, target, kind)
	if hero == nil then
		return false
	end
	local now = DotaTime()
	local heroName = call(hero, "GetUnitName") or "?"
	local botName = call(bot, "GetUnitName") or "?"
	local claims = TeamClaims(call(bot, "GetTeam"))
	local maxHp = call(bot, "GetMaxHealth") or 1
	local blocked = call(hero, "IsChanneling")
		or call(bot, "GetActiveMode") == BOT_MODE_RETREAT
		or (call(bot, "GetHealth") or 0) < Chain.LOW_HP * math.max(1, maxHp)
	-- The running disable: the engine's modifier, or a teammate's disable that is on its way.
	local left, modName, unlisted = Chain.ReadLeft(hero)
	local modLeft = left
	local src = left and "modifier" or nil
	local claimLeft = Chain.ClaimLeft(claims[heroName], now, botName)
	if claimLeft ~= nil and (left == nil or claimLeft > left) then
		left, src = claimLeft, "claim"
	end
	if unlisted ~= nil and left == nil and Throttled(botName .. "|unknown", now, 30) then
		local mods, count = Chain.UnknownNames(unlisted)
		print(
			string.format(
				"[SHy-CHAIN] t=%.0f %s unknown hero=%s spell=%s n=%d mods=%s",
				now,
				short(botName),
				short(heroName),
				spellName,
				count,
				mods
			)
		)
	end
	local distance = nil
	if kind == "location" then
		local okD, d = pcall(GetUnitToLocationDistance, bot, target)
		distance = okD and d or nil
	else
		local okD, d = pcall(GetUnitToUnitDistance, bot, hero)
		distance = okD and d or nil
	end
	-- GetCastRange is a heavy wrapper (items, talents): only when a hold is possible.
	local castRange = left ~= nil and call(ability, "GetCastRange") or nil
	local need = Chain.Need(
		call(ability, "GetCastPoint") or 0,
		special(ability, spec.delay),
		distance,
		spec.speed and special(ability, spec.speed) or nil,
		castRange,
		call(bot, "GetCurrentMovementSpeed")
	)
	local stamp = Chain.stamps[bot]
	if stamp ~= nil and (stamp.hero ~= heroName or stamp.spell ~= spellName or now > stamp.untilAt) then
		ClearStamp(bot)
		stamp = nil
	end
	if stamp ~= nil and src == "modifier" and CheckCountdown(stamp, modLeft, now, botName) then
		ClearStamp(bot)
		return false
	end
	local heldFor = (stamp ~= nil and stamp.passedAt == nil) and (now - stamp.startedAt) or 0
	local far = false
	if left ~= nil and distance ~= nil then
		local attackRange = call(bot, "GetAttackRange") or 0
		far = distance > math.max(Chain.HOLD_RANGE, attackRange + Chain.ATTACK_BUFFER)
	end
	if Chain.Decide(left, need, heldFor, blocked or far) == "hold" then
		if stamp == nil or stamp.passedAt ~= nil then
			-- A new hold (a stamp that already let its disable through ends here).
			ClearStamp(bot)
			stamp = { hero = heroName, spell = spellName, startedAt = now }
			SetStamp(bot, stamp)
			if src == "modifier" then
				stamp.firstLeft, stamp.firstAt = modLeft, now
			end
		end
		stamp.need = need
		stamp.untilAt = now + math.min(Chain.HOLD_CAP - heldFor, left - need) + 1
		if Throttled(botName .. "|hold|" .. spellName, now) then
			print(
				string.format(
					"[SHy-CHAIN] t=%.0f %s hold hero=%s spell=%s left=%s need=%s gap=%s dist=%.0f src=%s mod=%s",
					now,
					short(botName),
					short(heroName),
					spellName,
					Fmt(left),
					Fmt(need),
					Fmt(left - need),
					distance or -1,
					src,
					tostring(modName or "-")
				)
			)
		end
		-- The hero file may have cleared the queue (Fu.SetQueuePtToINT) and queued Soul Ring / a Treads switch:
		-- one plain attack order on the disabled hero replaces them, so the bot hits him instead of standing.
		-- A hero who takes no physical damage (Cold Embrace): walk to him instead.
		if src == "modifier" and Chain.NO_ATTACK[modName] then
			pcall(bot.Action_MoveToUnit, bot, hero)
		else
			pcall(bot.Action_AttackUnit, bot, hero, false)
		end
		return true
	end
	-- The order goes through. A cast into a running disable is a chain: log it. why=held after a hold of this bot,
	-- chain without one; blocked / far / cap: a cast the rule let through without waiting.
	if left ~= nil and Throttled(botName .. "|cast|" .. spellName .. "|" .. heroName, now) then
		local why = "chain"
		if blocked then
			why = "blocked"
		elseif far then
			why = "far"
		elseif heldFor >= Chain.HOLD_CAP then
			why = "cap"
		elseif heldFor > 0 then
			why = "held"
		end
		print(
			string.format(
				"[SHy-CHAIN] t=%.0f %s cast hero=%s spell=%s left=%s need=%s gap=%s dist=%.0f held=%s real=%s src=%s why=%s",
				now,
				short(botName),
				short(heroName),
				spellName,
				Fmt(left),
				Fmt(need),
				Fmt(left - need),
				distance or -1,
				Fmt(heldFor),
				stamp and stamp.checked or "?",
				tostring(src),
				why
			)
		)
	end
	-- A stamp that let its disable through stays until the disable has landed, so Fu.IsDisabled keeps calling the
	-- hero free for this bot and the re-issued order (every think until the cast starts) is not replaced.
	if stamp ~= nil and stamp.passedAt == nil then
		stamp.passedAt = now
		stamp.untilAt = now + need + 0.5
	end
	-- Reserve the hero until this disable lands (the caster's own order re-issued every think keeps its first one).
	-- Unit-target orders only, or a point order into a running stun: a skillshot on a free hero can miss, and its
	-- reservation (up to 2.3s for Torrent) would hold a teammate's sure Hex for nothing.
	local claim = claims[heroName]
	local reserves = kind == "entity" or modLeft ~= nil
	if reserves and (claim == nil or claim.caster ~= botName or now > claim.landsAt + Chain.CLAIM_GRACE) then
		local landsAt = now + need - Chain.MARGIN
		claims[heroName] = {
			caster = botName,
			madeAt = now,
			landsAt = landsAt,
			endsAt = landsAt + special(ability, spec.duration),
		}
	end
	return false
end

-- From Fu.IsDisabled (enemy heroes) while Chain.live > 0: true = call hero free for this bot, because the bot
-- holds a disable on him and his time left is down to what the disable needs to land.
function Chain.ReleaseEarly(bot, hero)
	local stamp = bot and Chain.stamps[bot]
	if stamp == nil then
		return false
	end
	local now = DotaTime()
	if now > stamp.untilAt or not Chain.enabled then
		ClearStamp(bot)
		return false
	end
	if call(hero, "GetUnitName") ~= stamp.hero then
		return false
	end
	-- One read per frame: Fu.IsDisabled is asked many times per think.
	local frame = GameTime()
	if stamp.readFrame ~= frame then
		stamp.readFrame = frame
		stamp.readLeft = Chain.ReadLeft(hero)
		if stamp.passedAt == nil and CheckCountdown(stamp, stamp.readLeft, now, call(bot, "GetUnitName")) then
			ClearStamp(bot)
			return false
		end
	end
	return stamp.readLeft ~= nil and stamp.readLeft <= stamp.need + Chain.MIN_HOLD
end

-- Tests: a clean state.
function Chain.Reset()
	Chain.enabled = true
	Chain.live = 0
	Chain.claims = {}
	Chain.stamps = {}
	Chain.check = { pass = 0, fail = 0 }
	lineAt = {}
end

return Chain
