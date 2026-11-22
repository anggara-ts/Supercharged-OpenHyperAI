-- Loads bots/customize/general.lua so settings override the script defaults.
local cachedSettings = nil
function LoadCustomize()
	if cachedSettings then
		return cachedSettings
	end
	-- The player's copy in vscripts/game/customize. Before #221 that folder name was capitalised, and Linux and macOS
	-- file systems are case-sensitive, so the old name is tried second.
	local settings = nil
	-- Handler only keeps the message (see init_debug: logging inside it errored).
	local loadErr = nil
	local loadOk = false
	for _, modulePath in ipairs({ "game/customize/general", "game/Customize/general" }) do -- restructure:keep
		loadOk = xpcall(function()
			settings = require(modulePath)
		end, function(err)
			loadErr = loadErr or err
			return err
		end)
		if loadOk and settings then
			break
		end
	end
	if not (loadOk and settings) and loadErr ~= nil and log then
		pcall(log, "[WARN] When loading customized file: %s", tostring(loadErr))
	end
	if loadOk and settings then
		cachedSettings = settings
	else
		if GetScriptDirectory() == "bots" then
			cachedSettings = require("bots.customize.general")
		else
			cachedSettings = require(GetScriptDirectory() .. "/customize/general")
		end
	end
	return cachedSettings
end
return LoadCustomize()
