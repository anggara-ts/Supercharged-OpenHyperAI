-- Custom build version.
-- A git clone has bots/customize/build_info.lua (git-ignored, written by tools/build-info.js from the git hooks):
-- the number is then "<commit date YYYY.MM.DD>-<short sha>", plus "+dirty" when tracked files other than
-- bots/customize/general.lua had local changes. Without it (Workshop copies) the static release number below is used.
-- Release format: YYYY.MM.DD-NNN; `release` is that release's tag. The /release skill sets both. The start-of-game
-- welcome shows "<release> (<date of the number>)" in a Workshop copy, "dev <number>" in a git build
-- (bots/lib/systems/chat_rules.lua WelcomeVersion).
local Version = {
	number = "2026.11.26-250",
	release = "v0.8",
}
Version.releaseNumber = Version.number

local infoOk, info = pcall(require, GetScriptDirectory() .. "/customize/build_info")
if infoOk and type(info) == "table" and type(info.version) == "string" then
	Version.number = info.version .. (info.dirty and "+dirty" or "")
	Version.commit = info.commit
	Version.branch = info.branch
	Version.dirty = info.dirty == true
end

return Version
