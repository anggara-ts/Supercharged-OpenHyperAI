-- Chat lines for human orders (#222, FuncLib/systems/human_orders.lua), per language (the `!sp` locales). Kept
-- here, not in FuncLib/systems/localization.lua, so this feature does not touch the file other chat PRs edit.
-- One bot says one line per order: when it goes, the assemble mode's "On my way!" (say_assemble in
-- localization.lua; maintainer, 2026-11-23: "on my way is good"), otherwise the reason below. {name} is the human's
-- hero, {s} the seconds until a dead bot respawns.
local Lines = {
	en = {
		queue = "{name}, after this fight",
		which_lane = "{name}, which lane? !push top / mid / bot",
		cancelled = "OK {name}, cancelled",
		["too-early"] = "{name}, too early, still laning. Ping again to insist",
		outnumbered = "{name}, they have more heroes there. Ping again to insist",
		["base-under-attack"] = "{name}, base under attack",
		["too-few-alive"] = "{name}, too few of us alive. Ping again to insist",
		["no-creeps"] = "{name}, no creeps of ours there. Ping again to insist",
		["roshan-dead"] = "{name}, Roshan is dead",
		dead = "{name}, dead, back in {s}s",
		["low-hp"] = "{name}, low HP, after I heal",
		retreat = "{name}, low HP, after I heal",
		base = "{name}, base under attack",
		busy = "{name}, can't now",
	},
	zh = {
		queue = "{name}，打完这波就去",
		which_lane = "{name}，哪一路？!push top / mid / bot",
		cancelled = "好的{name}，取消",
		["too-early"] = "{name}，太早了，还在对线。再标记一次就去",
		outnumbered = "{name}，那边敌人更多。再标记一次就去",
		["base-under-attack"] = "{name}，基地被攻击",
		["too-few-alive"] = "{name}，我们活着的人太少。再标记一次就去",
		["no-creeps"] = "{name}，那边没有我们的兵线。再标记一次就去",
		["roshan-dead"] = "{name}，肉山已经死了",
		dead = "{name}，我死了，{s}秒后复活",
		["low-hp"] = "{name}，血量太低，回复后就去",
		retreat = "{name}，血量太低，回复后就去",
		base = "{name}，基地被攻击",
		busy = "{name}，现在去不了",
	},
	ru = {
		queue = "{name}, после этой драки",
		which_lane = "{name}, какая линия? !push top / mid / bot",
		cancelled = "Ок {name}, отмена",
		["too-early"] = "{name}, слишком рано, ещё стоим на линии. Пингани ещё раз, и пойдём",
		outnumbered = "{name}, там их больше. Пингани ещё раз, и пойдём",
		["base-under-attack"] = "{name}, база под атакой",
		["too-few-alive"] = "{name}, нас слишком мало в живых. Пингани ещё раз, и пойдём",
		["no-creeps"] = "{name}, там нет наших крипов. Пингани ещё раз, и пойдём",
		["roshan-dead"] = "{name}, Рошан мёртв",
		dead = "{name}, я мёртв, вернусь через {s} с",
		["low-hp"] = "{name}, мало HP, приду после хила",
		retreat = "{name}, мало HP, приду после хила",
		base = "{name}, база под атакой",
		busy = "{name}, сейчас не могу",
	},
	ja = {
		queue = "{name}、この戦闘の後で",
		which_lane = "{name}、どのレーン？ !push top / mid / bot",
		cancelled = "了解{name}、中止",
		["too-early"] = "{name}、まだ早い、レーン中。もう一度ピンで行く",
		outnumbered = "{name}、向こうの方が多い。もう一度ピンで行く",
		["base-under-attack"] = "{name}、本拠地が攻撃されている",
		["too-few-alive"] = "{name}、生存者が少なすぎる。もう一度ピンで行く",
		["no-creeps"] = "{name}、味方のクリープがいない。もう一度ピンで行く",
		["roshan-dead"] = "{name}、ロシャンは死んでいる",
		dead = "{name}、死亡中、{s}秒後に復活",
		["low-hp"] = "{name}、HPが低い、回復したら行く",
		retreat = "{name}、HPが低い、回復したら行く",
		base = "{name}、本拠地が攻撃されている",
		busy = "{name}、今は無理",
	},
}

-- The line for `key` in `locale` (English when the locale or the key is missing), with {name} and {s} filled in.
function Lines.Get(locale, key, name, seconds)
	local set = Lines[locale]
	local line = type(set) == "table" and set[key] or nil
	if line == nil then
		line = Lines.en[key] or Lines.en.busy
	end
	line = string.gsub(line, "{name}", (string.gsub(name or "", "%%", "")))
	line = string.gsub(line, "{s}", tostring(math.floor(seconds or 0)))
	return line
end

return Lines
