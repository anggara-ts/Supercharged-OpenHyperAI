-- bots/mode_outpost_generic.lua ThinkGeneralRoaming (#13): in Wraith Delay (or Helm of the Undying) with no proper
-- target and nothing the range+350 search accepts, the old code indexed a nil target (game 085, 49:34:
-- "mode_outpost_generic.lua:1107: attempt to index local 'target' (a nil value)"; Wraith King stood still).
local T = ...
local Stub = T.stub

-- A Wraith King bot in Wraith Delay; enemyDist puts the first Dire hero that far east of him (nil: none near).
local function setup(enemyDist)
	local bot = Stub.reset({ hero = "npc_dota_hero_skeleton_king", time = 2974 })
	bot.HasModifier = function(_, name)
		return name == "modifier_skeleton_king_reincarnation_scepter_active"
	end
	local enemy = Stub.teams[TEAM_DIRE][1]
	if enemyDist ~= nil then
		enemy._loc = bot:GetLocation() + Vector(enemyDist, 0, 0)
	end
	-- Attack-immune: the weakest-unit search skips it, as it found nothing in game 085.
	enemy.IsAttackImmune = function()
		return true
	end
	local orders = {}
	bot.Action_MoveToLocation = function(_, loc)
		orders[#orders + 1] = { "move", loc }
	end
	bot.Action_AttackMove = function(_, loc)
		orders[#orders + 1] = { "attack-move", loc }
	end
	bot.Action_AttackUnit = function(_, unit)
		orders[#orders + 1] = { "attack", unit }
	end
	local ok, err = Stub.load("mode_outpost_generic")
	if not ok then
		error(tostring(err), 0)
	end
	return bot, enemy, orders
end

local function printed(pattern)
	for _, line in ipairs(Stub.printed) do
		if string.find(tostring(line), pattern, 1, true) then
			return true
		end
	end
	return false
end

T.test("death delay: no target, an enemy hero within 1200 -> attack-move toward it", function()
	local _, enemy, orders = setup(900)
	T.eq(ThinkGeneralRoaming(), true, "the block gave the order")
	T.eq(#orders, 1, "one order")
	T.eq(orders[1][1], "attack-move", "attack-move")
	T.ok((orders[1][2] - enemy:GetLocation()):Length2D() < 1, "toward the enemy")
	T.ok(printed("death-delay src=nearest target=sven"), "[SHy-ROAM] death-delay src=nearest printed")
end)

T.test("death delay: the unit GetDesire picked this second is reused", function()
	local bot, enemy, orders = setup(900)
	bot._deathDelayTarget, bot._deathDelayTargetAt = enemy, DotaTime()
	T.eq(ThinkGeneralRoaming(), true, "the block gave the order")
	T.eq(#orders, 1, "one order")
	T.eq(orders[1][1], "move", "walks to it (out of attack range)")
	T.ok(printed("death-delay src=desire target=sven"), "[SHy-ROAM] death-delay src=desire printed")
end)

T.test("death delay: no enemy near -> no error, the rest of the roaming think runs", function()
	setup(nil)
	local ok, err = pcall(ThinkGeneralRoaming)
	T.ok(ok, tostring(err))
	T.ok(printed("death-delay src=none target=-"), "[SHy-ROAM] death-delay src=none printed")
end)
