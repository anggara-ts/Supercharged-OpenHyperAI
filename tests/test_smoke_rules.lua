-- bots/lib/systems/smoke_rules.lua (#12): a push Smoke only for a rotation to another lane.
local T = ...

local function load()
	T.stub.reset({ hero = "npc_dota_hero_rubick" })
	return require(GetScriptDirectory() .. "/lib/systems/smoke_rules")
end

T.test("smoke: no push Smoke on the lane the group already stands on", function()
	local R = load()
	-- Game 091, t=930: Rubick on the mid lane walking from the fallen T1 to the T2.
	local ok, why = R.PushSmokeOk(350)
	T.eq(ok, false, "on the lane")
	T.eq(why, "same-lane")
	ok, why = R.PushSmokeOk(3200)
	T.eq(ok, true, "coming from another lane or the jungle")
	T.eq(why, "rotation")
	T.eq((R.PushSmokeOk(nil)), true, "unknown distance: the old rule")
	T.eq((R.PushSmokeOk(R.ON_LANE_DIST)), true, "the boundary counts as off the lane")
end)
