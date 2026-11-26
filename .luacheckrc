-- luacheck settings for the Dota 2 bot scripts (run by .github/workflows/lua-check.yml).
-- The game runs LuaJIT, and the bot API puts hundreds of functions and constants in the
-- global scope (GetBot, DotaTime, BOT_MODE_*, ...), so global checks are off.
std = "luajit"
allow_defined = true
allow_defined_top = true
global = false
unused_args = false
max_line_length = false
-- Ignored: 1xx globals (the bot API), 211/212/213 unused locals/args/loop vars,
-- 311 unused assigned values, 411/412/421/422/423/431/432 shadowing and redefinition,
-- 542 empty if branches. Still reported: unreachable code (511), a loop that can run
-- at most once (512), an empty do block (541), and any code not listed here.
ignore = { "1..", "211", "212", "213", "311", "411", "412", "421", "422", "423", "431", "432", "542" }
exclude_files = { ".git/**", "tools/**" }
