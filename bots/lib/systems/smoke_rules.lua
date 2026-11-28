-- Shared bot system: pure rules for Smoke of Deceit (#12). No bot API calls, so they are tested with plain numbers
-- (tests/test_smoke_rules.lua). The use rule itself is in bots/ability_item_usage_generic.lua (SmokeDesireRaw).
local SmokeRules = {}

-- A push Smoke is for a rotation: the group walks to a lane it is not on yet. Game 091 (maintainer: "they often use
-- smoke but then continue pushing same lane ... team-roam when walking to switch lane is better"): `push-group` fired
-- when the group already stood on the lane and walked from the fallen T1 to the T2 (t=930 Rubick, mid, 4496 from the
-- tower; t=1210 Winter Wyvern, top). On its own lane the group is already seen and meets the wave, so the Smoke buys
-- little. Game 089: 10 of 12 Smokes were `push-group`.
-- How far from the lane's path (GetAmountAlongLane(lane, location).distance) a bot still counts as on that lane: about
-- the width of a lane plus its jungle edge (a map-scale judgement value).
SmokeRules.ON_LANE_DIST = 2000
-- laneDist: the bot's distance from the push lane's path (nil: unknown). Returns ok, why.
function SmokeRules.PushSmokeOk(laneDist)
	if laneDist ~= nil and laneDist < SmokeRules.ON_LANE_DIST then
		return false, "same-lane"
	end
	return true, "rotation"
end

return SmokeRules
