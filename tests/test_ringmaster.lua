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
