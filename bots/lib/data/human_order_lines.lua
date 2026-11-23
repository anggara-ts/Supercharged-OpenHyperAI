-- Chat lines for human orders (#222, bots/lib/systems/human_orders.lua), per language (the `!sp` locales). Kept
-- here, not in bots/lib/systems/localization.lua, so this feature does not touch the file other chat PRs edit.
-- A bot that goes says the assemble mode's "On my way!" (say_assemble in localization.lua; maintainer, 2026-11-23:
-- "response 'on my way' only when acknowledging. no reply for 'cant do'"). Only when nobody goes does one bot say
-- one short reason from this file (at most once per 30s per team). {name} is the human's hero (the replies to a
-- command), {s} the seconds until a dead bot respawns.
local Lines = {
	en = {
		which_lane = "{name}, which lane? !push top / mid / bot",
		cancelled = "OK {name}, cancelled",
		["too-early"] = "Too early",
		outnumbered = "They outnumber us there",
		["base-under-attack"] = "Base under attack",
		["too-few-alive"] = "Too few of us alive",
		["no-creeps"] = "No creeps of ours there",
		["roshan-dead"] = "Roshan is dead",
		dead = "Dead, back in {s}s",
		["low-hp"] = "Low HP",
		retreat = "Low HP",
		base = "Base under attack",
		busy = "Can't now",
	},
	zh = {
		which_lane = "{name}，哪一路？!push top / mid / bot",
		cancelled = "好的{name}，取消",
		["too-early"] = "太早了",
		outnumbered = "那边敌人更多",
		["base-under-attack"] = "基地被攻击",
		["too-few-alive"] = "我们活着的人太少",
		["no-creeps"] = "那边没有我们的兵线",
		["roshan-dead"] = "肉山已经死了",
		dead = "我死了，{s}秒后复活",
		["low-hp"] = "血量太低",
		retreat = "血量太低",
		base = "基地被攻击",
		busy = "现在去不了",
	},
	ru = {
		which_lane = "{name}, какая линия? !push top / mid / bot",
		cancelled = "Ок {name}, отмена",
		["too-early"] = "Слишком рано",
		outnumbered = "Там их больше",
		["base-under-attack"] = "База под атакой",
		["too-few-alive"] = "Нас слишком мало в живых",
		["no-creeps"] = "Там нет наших крипов",
		["roshan-dead"] = "Рошан мёртв",
		dead = "Я мёртв, вернусь через {s} с",
		["low-hp"] = "Мало HP",
		retreat = "Мало HP",
		base = "База под атакой",
		busy = "Сейчас не могу",
	},
	ja = {
		which_lane = "{name}、どのレーン？ !push top / mid / bot",
		cancelled = "了解{name}、中止",
		["too-early"] = "まだ早い",
		outnumbered = "向こうの方が多い",
		["base-under-attack"] = "本拠地が攻撃されている",
		["too-few-alive"] = "生存者が少なすぎる",
		["no-creeps"] = "味方のクリープがいない",
		["roshan-dead"] = "ロシャンは死んでいる",
		dead = "死亡中、{s}秒後に復活",
		["low-hp"] = "HPが低い",
		retreat = "HPが低い",
		base = "本拠地が攻撃されている",
		busy = "今は無理",
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
