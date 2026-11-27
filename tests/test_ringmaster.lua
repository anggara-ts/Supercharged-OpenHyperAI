-- bots/heroes/hero_ringmaster.lua: Tame the Beasts' channel curve and when the whip cracks early (#49, game 084).
local T = ...
local Stub = T.stub

local function ringmaster()
	Stub.reset({ hero = "npc_dota_hero_ringmaster", slot = 5 })
	local ok, result = Stub.load("bots/heroes/hero_ringmaster")
	if not ok then
		error(tostring(result), 0)
	end
	return result
end

T.test("ringmaster: whip damage, fear and radius over the channel", function()
	local X = ringmaster()
	-- Game file: "Real max damage is 4x damage min" (max_multiplier 4); level 4 damage_min 125.
	T.near(X.WhipDamage(0, 125, 4), 125, 0.01, "no channel: minimum damage")
	T.near(X.WhipDamage(1, 125, 4), 500, 0.01, "full channel: 4x the minimum")
	T.near(X.WhipDamage(0.5, 125, 4), 250, 0.01, "half the channel: 2x (exponential)")
	T.near(X.WhipDamage(2, 125, 4), 500, 0.01, "clamped at the full channel")
	-- Level 4 fear 0.4 .. 1.2.
	T.near(X.WhipFear(0, 0.4, 1.2, 4), 0.4, 0.001, "an instant crack gives the minimum fear")
	T.near(X.WhipFear(1, 0.4, 1.2, 4), 1.2, 0.001, "the full channel gives the maximum fear")
	T.ok(X.WhipFear(0.5, 0.4, 1.2, 4) < 0.8, "half the channel gives less than half the extra fear")
	T.near(X.WhipRadius(0, 450, 200), 450, 0.01, "start radius")
	T.near(X.WhipRadius(1, 450, 200), 200, 0.01, "end radius")
end)

T.test("ringmaster: when the whip cracks before the full channel", function()
	local X = ringmaster()
	local function decide(fields)
		local s = { why = "engage", nearestNow = 100, nearestLater = 120, radiusLater = 300, margin = 25 }
		for key, value in pairs(fields) do
			-- "none" stands for nil (pairs skips nil values)
			if value == "none" then
				s[key] = nil
			else
				s[key] = value
			end
		end
		return X.WhipCrackDecision(s)
	end
	T.eq(decide({}), nil, "engage: target deep inside, keep channelling")
	T.eq(decide({ nearestLater = 290 }), "radius", "engage: target about to leave the shrinking area")
	T.eq(decide({ nearestNow = "none", nearestLater = "none" }), "empty", "engage: nobody inside, nothing to hold for")
	T.eq(decide({ killNow = true }), "kill", "the damage now kills a hero")
	T.eq(decide({ lowHp = true }), "lowhp", "Ringmaster about to die")
	T.eq(decide({ why = "retreat", enemyOnTop = true }), "ontop", "retreat: an enemy on top of him")
	T.eq(decide({ why = "cancel" }), "cancel", "teleport cancel cracks at once")
	-- The combo whip keeps its full channel whatever happens: the fear has to drive them into the Wheel.
	T.eq(decide({ why = "combo", nearestLater = 400, killNow = true, lowHp = true }), nil, "combo: never early")
	-- Creep and objective whips: full channel unless Ringmaster is about to die.
	T.eq(decide({ why = "farm", nearestNow = "none", nearestLater = "none" }), nil, "farm: full channel")
	T.eq(decide({ why = "push", lowHp = true }), "lowhp", "push: low HP cracks")
end)

T.test("ringmaster: last-will Wheel before he dies", function()
	local X = ringmaster()
	-- hp ratio, hit by a hero in the last 2s, damage the enemies deal in 2s, his health, enemy heroes in the Wheel
	T.eq(X.LastWillDue(0.2, true, 100, 300, 2), true, "under 25% and being hit")
	T.eq(X.LastWillDue(0.2, false, 100, 300, 2), false, "under 25% but nobody is hitting him")
	T.eq(X.LastWillDue(0.4, true, 900, 800, 1), true, "the burst kills him within 2s")
	T.eq(X.LastWillDue(0.4, true, 300, 800, 2), false, "healthy enough")
	T.eq(X.LastWillDue(0.1, true, 900, 100, 0), false, "no enemy hero where the Wheel stops")
end)

T.test("ringmaster: why no last-will Wheel went out", function()
	local X = ringmaster()
	local function why(fields)
		local s = {
			learned = true,
			cooldown = 0,
			manaOk = true,
			castable = true,
			enemiesNear = 2,
			enemiesInWheel = 1,
		}
		for key, value in pairs(fields) do
			if value == "none" then
				s[key] = nil
			else
				s[key] = value
			end
		end
		return X.LastWillSkipWhy(s)
	end
	T.eq(why({}), nil, "nothing stops it")
	T.eq(why({ learned = false, cooldown = 30 }), "unlearned", "not learned yet")
	-- Game 085: 7 of 14 deaths came 6-56s after a Wheel (cooldown 90/80/70).
	T.eq(why({ cooldown = 40, blocked = "disabled" }), "cd", "the cooldown is named before a block")
	T.eq(why({ blocked = "whip" }), "whip", "the whip is channelling")
	T.eq(why({ blocked = "disabled", manaOk = false }), "disabled", "stunned")
	T.eq(why({ manaOk = false }), "mana", "no mana")
	T.eq(why({ castable = false }), "uncastable", "the API says it can't be cast")
	T.eq(why({ enemiesNear = 0, enemiesInWheel = 0 }), "no-enemy", "no enemy hero in range")
	T.eq(why({ enemiesInWheel = 0 }), "empty", "no enemy hero where the Wheel stops")
end)

T.test("ringmaster: the outpost hold comes before a cast in Valve's modes", function()
	local X = ringmaster()
	-- A held order (decided in Valve's attack or retreat mode) waits for the hold, at most 0.4s.
	T.eq(X.HoldStep(false, 0.1, 0.4), "wait", "asked 0.1s ago, Valve's mode still on")
	T.eq(X.HoldStep(true, 0.1, 0.4), "cast", "the outpost hold is on: cast now")
	T.eq(X.HoldStep(false, 0.45, 0.4), "cast", "waited long enough: cast anyway")
	T.eq(X.HoldStep(true, 0.8, 0.4), "drop", "too old (the ticks stopped): dropped")
	-- The hold is shared by name between the hero file and the outpost mode.
	local hero = T.read("bots/heroes/hero_ringmaster.lua")
	local outpost = T.read("bots/mode_outpost_generic.lua")
	T.ok(hero:find("_ringmasterHoldWantAt", 1, true) ~= nil, "the hero file asks for the hold")
	T.ok(outpost:find("bot._ringmasterHoldWantAt", 1, true) ~= nil, "the outpost mode reads the ask")
	T.ok(outpost:find("bot._castHoldUntil", 1, true) ~= nil, "the outpost mode holds while the cast hold is on")
end)

T.test("ringmaster: a whip order may walk into range before it counts as not started", function()
	local X = ringmaster()
	-- Game 085: 11 whips ordered 843-1453 away (cast range 700) timed out at 0.8s mid-walk.
	T.near(X.WhipStartLimit(500, 700, 300), 0.8, 0.001, "in range: only the turn")
	T.near(X.WhipStartLimit(1000, 700, 300), 1.8, 0.001, "300 to walk at 300 speed: 1s more")
	T.near(X.WhipStartLimit(1453, 700, 300), 3.0, 0.001, "capped at 3s")
	T.near(X.WhipStartLimit(900, 700, 0), 1.8, 0.001, "an unknown speed counts as 200")
end)
