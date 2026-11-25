-- bots/heroes/hero_sniper.lua: how an Assassinate kill shot ended (#48, [SHy-SNIPER] assassinate-result).
local T = ...
local Stub = T.stub

local function sniper()
	Stub.reset({ hero = "npc_dota_hero_sniper", slot = 1 })
	local ok, result = Stub.load("bots/heroes/hero_sniper")
	if not ok then
		error(tostring(result), 0)
	end
	return result
end

T.test("sniper: assassinate-result died= and when=", function()
	local X = sniper()
	-- diedAt, hitAt, seenAt, now
	local died, when = X.AssassinateDeath(100.2, 100.0, 99.9, 103.0)
	T.eq(died, "yes", "died right at the hit")
	T.eq(when, "hit")
	died, when = X.AssassinateDeath(99.0, 100.0, 98.9, 103.0)
	T.eq(died, "yes", "died before the shot landed")
	T.eq(when, "before", "someone else killed it")
	T.eq(select(2, X.AssassinateDeath(99.8, 100.0, 99.7, 103.0)), "hit", "the hit time can run a think late")
	T.eq(select(2, X.AssassinateDeath(101.5, 100.0, 101.4, 103.0)), "later", "lived through the hit, died later")
	T.eq(X.AssassinateDeath(104.0, 100.0, 103.0, 103.0), "no", "a death after the 3s window does not count")
	T.eq(X.AssassinateDeath(nil, 100.0, 103.0, 103.0), "no", "seen alive at the end")
	died, when = X.AssassinateDeath(nil, 100.0, 101.0, 103.0)
	T.eq(died, "fog", "not seen at the end: unknown")
	T.eq(when, "-")
end)
