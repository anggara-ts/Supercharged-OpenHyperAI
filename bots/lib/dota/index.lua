-- Dota API names and constants: index.
local Exports = {}
do
	local Interfaces = require(GetScriptDirectory() .. "/lib/dota/interfaces")
	for key, value in pairs(Interfaces) do
		if key ~= "default" then
			Exports[key] = value
		end
	end
end
do
	local Enums = require(GetScriptDirectory() .. "/lib/dota/enums")
	for key, value in pairs(Enums) do
		if key ~= "default" then
			Exports[key] = value
		end
	end
end
return Exports
