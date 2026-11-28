-- Chat lines for human orders (#222, bots/lib/systems/human_orders.lua), per language (the `!sp` locales). Kept
-- here, not in bots/lib/systems/localization.lua, so this feature does not touch the file other chat PRs edit.
-- A bot that goes says what it does, once (maintainer, 2026-11-23: "response 'on my way' only when acknowledging. no
-- reply for 'cant do'"; game 077: "instead of generic 'on my way', change to 'pushing bot', 'on my way' (when checking
-- fog), 'attacking medusa'"): the key comes from human_order_rules.lua Rules.AckKey. Only when nobody goes does one
-- bot say one short reason from this file (at most once per 30s per team); a bot busy with a team call gives that
-- call's words (busy-roshan / busy-push / busy-defend, game 078). {name} is the human's hero (the replies to
-- a command), {s} the seconds until a dead bot respawns, {lane} the lane (lane_top / lane_mid / lane_bot of the same
-- language), {target} the enemy hero's display name, {cmd} the command word the human typed (which_lane: `!def` for
-- a defend, `!push` when none is given).
local Lines = {
	en = {
		which_lane = "{name}, which lane? {cmd} top / mid / bot",
		cancelled = "OK {name}, cancelled",
		["on-my-way"] = "On my way",
		pushing = "Pushing {lane}",
		defending = "Defending {lane}",
		attacking = "Attacking {target}",
		["clearing-camp"] = "Clearing the camp",
		["going-roshan"] = "Going Roshan",
		grouping = "Grouping up",
		lane_top = "top",
		lane_mid = "mid",
		lane_bot = "bot",
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
		["busy-roshan"] = "Going Roshan",
		["busy-push"] = "Pushing {lane}",
		["busy-defend"] = "Defending {lane}",
	},
	zh = {
		which_lane = "{name}，哪一路？{cmd} top / mid / bot",
		cancelled = "好的{name}，取消",
		["on-my-way"] = "我来了",
		pushing = "去推{lane}",
		defending = "去守{lane}",
		attacking = "去打{target}",
		["clearing-camp"] = "去清野",
		["going-roshan"] = "去打肉山",
		grouping = "集合",
		lane_top = "上路",
		lane_mid = "中路",
		lane_bot = "下路",
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
		["busy-roshan"] = "去打肉山",
		["busy-push"] = "去推{lane}",
		["busy-defend"] = "去守{lane}",
	},
	ru = {
		which_lane = "{name}, какая линия? {cmd} top / mid / bot",
		cancelled = "Ок {name}, отмена",
		["on-my-way"] = "Иду",
		pushing = "Пушу {lane}",
		defending = "Защищаю {lane}",
		attacking = "Атакую {target}",
		["clearing-camp"] = "Зачищаю лагерь",
		["going-roshan"] = "Иду на Рошана",
		grouping = "Собираемся",
		lane_top = "топ",
		lane_mid = "мид",
		lane_bot = "бот",
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
		["busy-roshan"] = "Иду на Рошана",
		["busy-push"] = "Пушу {lane}",
		["busy-defend"] = "Защищаю {lane}",
	},
	ja = {
		which_lane = "{name}、どのレーン？ {cmd} top / mid / bot",
		cancelled = "了解{name}、中止",
		["on-my-way"] = "向かってる",
		pushing = "{lane}をプッシュ",
		defending = "{lane}を防衛",
		attacking = "{target}を攻撃",
		["clearing-camp"] = "キャンプを処理",
		["going-roshan"] = "ロシャンに行く",
		grouping = "集合",
		lane_top = "トップ",
		lane_mid = "ミッド",
		lane_bot = "ボット",
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
		["busy-roshan"] = "ロシャンに行く",
		["busy-push"] = "{lane}をプッシュ",
		["busy-defend"] = "{lane}を防衛",
	},
	id = {
		which_lane = "{name}, jalur mana? {cmd} top / mid / bot",
		cancelled = "Oke {name}, batal",
		["on-my-way"] = "Otw",
		pushing = "Dorong {lane}",
		defending = "Jaga {lane}",
		attacking = "Serang {target}",
		["clearing-camp"] = "Bersihkan camp",
		["going-roshan"] = "Menuju Roshan",
		grouping = "Kumpul",
		lane_top = "atas",
		lane_mid = "mid",
		lane_bot = "bawah",
		["too-early"] = "Masih terlalu awal",
		outnumbered = "Mereka lebih banyak di sana",
		["base-under-attack"] = "Base diserang",
		["too-few-alive"] = "Kita terlalu sedikit yang hidup",
		["no-creeps"] = "Tidak ada creep kita di sana",
		["roshan-dead"] = "Roshan sudah mati",
		dead = "Mati, hidup lagi {s} detik",
		["low-hp"] = "HP rendah",
		retreat = "HP rendah",
		base = "Base diserang",
		busy = "Tidak bisa sekarang",
		["busy-roshan"] = "Menuju Roshan",
		["busy-push"] = "Dorong {lane}",
		["busy-defend"] = "Jaga {lane}",
	},
}

-- A gsub replacement with "%" removed (a "%" in a replacement string is a capture reference).
local function Plain(text)
	return (string.gsub(text or "", "%%", ""))
end

-- The line for `key` in `locale` (English when the locale or the key is missing), with {name}, {s}, {lane},
-- {target} and {cmd} filled in. `extra`: { lane = "top" / "mid" / "bot", target = the enemy hero's display name,
-- cmd = the command word } or nil.
function Lines.Get(locale, key, name, seconds, extra)
	local set = type(Lines[locale]) == "table" and Lines[locale] or Lines.en
	local line = set[key]
	if line == nil then
		line = Lines.en[key] or Lines.en.busy
	end
	extra = extra or {}
	local laneWord = extra.lane ~= nil and (set["lane_" .. extra.lane] or Lines.en["lane_" .. extra.lane]) or ""
	line = string.gsub(line, "{name}", Plain(name))
	line = string.gsub(line, "{s}", tostring(math.floor(seconds or 0)))
	line = string.gsub(line, "{lane}", Plain(laneWord))
	line = string.gsub(line, "{target}", Plain(extra.target))
	line = string.gsub(line, "{cmd}", Plain(extra.cmd or "!push"))
	return line
end

return Lines
