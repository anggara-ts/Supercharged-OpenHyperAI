-- Spirit Breaker's charge lock (#208, bots/heroes/hero_spirit_breaker.lua): while Charge of Darkness is up, move,
-- attack and stop orders on him from other code are dropped (one of them ends the charge), except in the retreat
-- mode when the charge is not the escape; the hero file's own cancel uses the class method and passes.
local T = ...
local Stub = T.stub

local CHARGE = "modifier_spirit_breaker_charge_of_darkness"

-- Loads the hero file, counts the class-level move orders, and runs fn(bot, X, count); restores the class method.
local function withHero(fn)
	Stub.reset({ hero = "npc_dota_hero_spirit_breaker" })
	local ok, X = Stub.load("bots/heroes/hero_spirit_breaker")
	if not ok then
		error(tostring(X), 0)
	end
	local bot = GetBot()
	local original = CDOTA_Bot_Script.Action_MoveToLocation
	local calls = 0
	CDOTA_Bot_Script.Action_MoveToLocation = function()
		calls = calls + 1
	end
	local okRun, err = pcall(fn, bot, X, function()
		return calls
	end)
	CDOTA_Bot_Script.Action_MoveToLocation = original
	if not okRun then
		error(err, 0)
	end
end

T.test("spirit breaker: no charge, orders go through", function()
	withHero(function(bot, _, count)
		bot:Action_MoveToLocation(Vector(0, 0, 0))
		T.eq(count(), 1, "the move reaches the class method")
	end)
end)

T.test("spirit breaker: charging, another mode's move is dropped", function()
	withHero(function(bot, _, count)
		bot.HasModifier = function(_, name)
			return name == CHARGE
		end
		bot.GetActiveMode = function()
			return BOT_MODE_LANING
		end
		bot:Action_MoveToLocation(Vector(0, 0, 0))
		T.eq(count(), 0, "a laning move during the charge is dropped")
		CDOTA_Bot_Script.Action_MoveToLocation(bot, Vector(0, 0, 0))
		T.eq(count(), 1, "the hero file's own order (class method) passes")
	end)
end)

T.test("spirit breaker: charging, the retreat mode can still stop a charge that is not the escape", function()
	withHero(function(bot, _, count)
		bot.HasModifier = function(_, name)
			return name == CHARGE
		end
		bot.GetActiveMode = function()
			return BOT_MODE_RETREAT
		end
		bot.chargeRetreat = false
		bot:Action_MoveToLocation(Vector(0, 0, 0))
		T.eq(count(), 1, "retreat move goes through")
		bot.chargeRetreat = true
		bot:Action_MoveToLocation(Vector(0, 0, 0))
		T.eq(count(), 1, "the escape charge itself is kept")
	end)
end)

T.test("spirit breaker: the charge-lock count resets when the charge ends", function()
	withHero(function(bot, X)
		local charging = true
		bot.HasModifier = function(_, name)
			return charging and name == CHARGE
		end
		bot.GetActiveMode = function()
			return BOT_MODE_FARM
		end
		bot:Action_AttackUnit(bot, true)
		charging = false
		X.ChargeLockTick()
		X.ChargeLockTick()
	end)
end)
