-- Shared bot system: may a save that disables an ally go on an ally who is channelling (#47)?
--
-- Cold Embrace freezes the ally, Disruption banishes it, Astral Imprisonment hides it ("invulnerable and disabled"),
-- and a disabled hero's channel ends: game 077, 6:02, Winter Wyvern embraced Undying 1s into a Town Portal out of the
-- bottom lane (`embrace-save ally=undying hp=0.21`), and Undying was still in the lane at 6:03 with the scroll spent.
-- Maintainer (game 077): "if enemy guaranteed to kill ally using attack hit, it is plausible". So a channelling ally
-- is saved only when the enemy heroes attacking it are expected to kill it before the channel ends; otherwise the
-- channel (the TP home) is the save. Pure rules here; the game reads are in Fu.ChannelSaveCheck
-- (bots/lib/general_utils/combat.lua).
local R = {}

-- Seconds left of a channel whose length can't be read at all (no modifier time, no ability channel time).
R.UNKNOWN_LEFT = 1.0

-- Time left of the channel. modLeft: the remaining time of the channel's modifier (a Town Portal:
-- modifier_teleporting; the enemy TP reads in game 077 went 3.00 then 2.80 0.2s later, so it counts down);
-- channelTime: the channelled ability's full channel time; seenFor: how long the ally has been seen channelling.
-- Returns left, source ("modifier" | "ability" | "unknown").
function R.ChannelLeft(modLeft, channelTime, seenFor)
	if type(modLeft) == "number" and modLeft > 0 then
		return modLeft, "modifier"
	end
	if type(channelTime) == "number" and channelTime > 0 then
		return math.max(0, channelTime - math.max(0, seenFor or 0)), "ability"
	end
	return R.UNKNOWN_LEFT, "unknown"
end

-- The window the damage is estimated over: the channel's time left plus the save's cast point (the ally keeps
-- channelling, and taking hits, until the save lands).
function R.DamageWindow(left, castPoint)
	return math.max(0, left or 0) + math.max(0, castPoint or 0)
end

-- dmg: the damage expected on the ally within the window; hp: its current health. A save on a channelling ally only
-- when that damage kills it.
function R.SaveAllowed(dmg, hp)
	if type(hp) ~= "number" or hp <= 0 then
		return false
	end
	return (dmg or 0) >= hp
end

-- dmg / hp for the log (>= 1: the enemies were expected to kill the ally).
function R.Ratio(dmg, hp)
	if type(hp) ~= "number" or hp <= 0 then
		return 0
	end
	return (dmg or 0) / hp
end

return R
