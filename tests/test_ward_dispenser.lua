-- #15: mode_ward_generic.lua logs a dispenser plant the ward think no longer watches (game 068: 3 of 48 casts
-- printed `dispenser planted`; the next spot was picked or another mode took over once the ward was down).
local T = ...

local function wardBot(obs, sen)
	local bot = T.stub.reset({ hero = "npc_dota_hero_zuus", slot = 5, time = 600 })
	local ok, err = T.stub.load("mode_ward_generic")
	T.ok(ok, "mode_ward_generic loads: " .. tostring(err))
	local dispenser = T.stub.newAbility("item_ward_dispenser", bot, false)
	dispenser._obs, dispenser._sen = obs, sen
	dispenser.GetCurrentCharges = function(self)
		return self._obs
	end
	dispenser.GetSecondaryCharges = function(self)
		return self._sen
	end
	bot._items[0] = dispenser
	return bot, dispenser
end

local function castTry(bot, spot)
	bot._dispTry = {
		at = T.stub.time,
		loc = spot.location,
		wantObs = true,
		obs = 2,
		sen = 1,
		toggled = false,
		castAt = T.stub.time,
		spot = spot,
		allObs = 2,
		allSen = 1,
	}
end

T.test("ward: a dispenser plant seen after the bot left the ward mode is logged and remembered", function()
	local bot, dispenser = wardBot(2, 1)
	local spot = { location = Vector(-4365, -1012, 0), role = "uber", label = "uber-radiant-top", plant_time_obs = 0 }
	castTry(bot, spot)
	T.stub.time = 600.5
	pcall(GetDesire)
	T.ok(bot._dispTry ~= nil, "no drop yet: still watched")
	-- A courier delivery raises the baseline; it is no plant.
	dispenser._obs = 3
	T.stub.time = 601
	pcall(GetDesire)
	T.ok(bot._dispTry ~= nil and bot._dispTry.allObs == 3, "courier delivery: baseline 3")
	dispenser._obs = 2
	T.stub.time = 601.5
	pcall(GetDesire)
	T.eq(bot._dispTry, nil, "planted: the try is done")
	T.eq(spot.plant_time_obs, 601.5, "the spot is marked planted")
	local found = nil
	for _, line in ipairs(T.stub.printed) do
		if string.find(line, "dispenser planted", 1, true) then
			found = line
		end
	end
	T.ok(found ~= nil, "a planted line")
	T.ok(string.find(found or "", "want=obs got=obs", 1, true) ~= nil, tostring(found))
	T.ok(string.find(found or "", "via=mode-left", 1, true) ~= nil, tostring(found))
	T.ok(string.find(found or "", "uber-radiant-top", 1, true) ~= nil, tostring(found))
end)

T.test("ward: a dispenser try with no drop is dropped after 6s", function()
	local bot = wardBot(2, 1)
	castTry(bot, { location = Vector(0, 0, 0), plant_time_obs = 0 })
	T.stub.time = 606.5
	pcall(GetDesire)
	T.eq(bot._dispTry, nil, "dropped")
end)
