-- Shared helper: saves that disable an ally (Cold Embrace, Disruption, Astral Imprisonment) and the ally's channel
-- (#47). Its own file so it doesn't share lines with combat.lua's other changes.
local ChannelSaveRules = require(GetScriptDirectory() .. "/lib/systems/channel_save_rules")
-- When each unit was first seen channelling, for channels without a modifier time (Fu.ChannelSaveCheck).
local channelSeenAt = setmetatable({}, { __mode = "k" })
local function installChannelSave(Fu)
	-- A save that disables the ally (Cold Embrace, Disruption, Astral Imprisonment) cancels its channel (#47, game 077:
	-- Winter Wyvern's Cold Embrace cancelled Undying's Town Portal). channelling = false: the ally isn't channelling,
	-- save as before. Otherwise allowed only when the enemy heroes attacking the ally (their estimated damage over the
	-- channel's time left plus the save's cast point, plus attacks already in flight) are expected to kill it before
	-- the channel ends (bots/lib/systems/channel_save_rules.lua). info: kind (tp or the ability name), left, src, dmg,
	-- hp, ratio, attackers.
	function Fu.ChannelSaveCheck(ally, castPoint)
		if not Fu.IsValidHero(ally) then
			return false, true, nil
		end
		local teleporting = ally:HasModifier("modifier_teleporting")
		if not teleporting and not ally:IsChanneling() then
			channelSeenAt[ally] = nil
			return false, true, nil
		end
		local now = DotaTime()
		channelSeenAt[ally] = channelSeenAt[ally] or now
		local kind = teleporting and "tp" or "channel"
		local modLeft = teleporting and Fu.GetModifierTime(ally, "modifier_teleporting") or nil
		local channelTime = nil
		if modLeft == nil or modLeft <= 0 then
			local okA, active = pcall(function()
				return ally:GetCurrentActiveAbility()
			end)
			if okA and active ~= nil and not active:IsNull() then
				kind = (string.gsub(active:GetName(), "^item_", ""))
				channelTime = active:GetChannelTime()
			end
		end
		local left, src = ChannelSaveRules.ChannelLeft(modLeft, channelTime, now - channelSeenAt[ally])
		local window = ChannelSaveRules.DamageWindow(left, castPoint)
		local dmg, attackers = 0, 0
		for _, enemy in pairs(Fu.GetNearbyHeroes(ally, 1600, true, BOT_MODE_NONE) or {}) do
			if Fu.IsValidHero(enemy) and not Fu.IsSuspiciousIllusion(enemy) and enemy:GetAttackTarget() == ally then
				attackers = attackers + 1
				dmg = dmg + enemy:GetEstimatedDamageToTarget(true, ally, window, DAMAGE_TYPE_ALL)
			end
		end
		dmg = dmg + Fu.GetAttackProjectileDamageByRange(ally, 1200)
		local hp = ally:GetHealth()
		return true,
			ChannelSaveRules.SaveAllowed(dmg, hp),
			{
				kind = kind,
				left = left,
				src = src,
				dmg = dmg,
				hp = hp,
				ratio = ChannelSaveRules.Ratio(dmg, hp),
				attackers = attackers,
			}
	end
	-- Fu.ChannelSaveCheck plus one log line when the ally is channelling, at most once per 5s per bot and line:
	--   [SHy-<tag>] t= <spell>-save|<spell>-skip why=channel ally= kind= left= src= dmg= health= ratio= attackers=
	-- Returns whether the save may go.
	function Fu.ChannelSaveGate(ally, castPoint, tag, spell)
		local channelling, allowed, info = Fu.ChannelSaveCheck(ally, castPoint)
		if not channelling then
			return true
		end
		local bot = GetBot()
		local what = spell .. (allowed and "-save" or "-skip")
		bot._channelSaveLogAt = bot._channelSaveLogAt or {}
		if DotaTime() >= (bot._channelSaveLogAt[what] or -999) then
			bot._channelSaveLogAt[what] = DotaTime() + 5
			pcall(
				print,
				string.format(
					"[SHy-%s] t=%.0f %s why=channel ally=%s kind=%s left=%.1f src=%s dmg=%.0f health=%.0f ratio=%.2f attackers=%d",
					tag,
					DotaTime(),
					what,
					(string.gsub(ally:GetUnitName(), "npc_dota_hero_", "")),
					info.kind,
					info.left,
					info.src,
					info.dmg,
					info.hp,
					info.ratio,
					info.attackers
				)
			)
		end
		return allowed
	end
end
return installChannelSave
