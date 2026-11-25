#!/usr/bin/env node
// One command after a test game: splits the console log and writes a review skeleton for the newest game.
//
//   node tools/after-game.js [path\to\dota 2 beta\game\dota] [--game NNN] [--no-split] [--no-mark] [--force]
//
// 1. Runs tools/split-console.js into local/match-logs (skip with --no-split) and picks the newest game in
//    local/match-logs/index.txt (or --game NNN).
// 2. Build: the [SHy-BUILD] line (or the summary's version for old builds) mapped to a commit; old numeric
//    versions are found with `git log --all -S'"<version>"' -- bots/customize/version.lua`. Lists the PRs in the
//    test build from local/verify/test-build.json (tools/test-build.js) when it exists.
// 3. Tracker: `node tools/verify.js check <log> --game NNN` (its output, verbatim).
// 4. Script errors grouped by message, log spam (top [SHy-*] tags by peak lines per second), deaths and the
//    scoreboard from the summary.
// 4b. Mode flip-flops: tools/flip-report.js's summary of [SHy-FLIP], [SHy-ROAMSTAT] and [SHy-HUNT] (#165).
// 4c. Ping clicks: the server's click lines per burst against the pings the bot API saw (#222).
// 5. Maintainer comments on every tracked PR posted since the last review (`lastReviewAt` in
//    local/verify/tracker.json; set at the end unless --no-mark).
// 6. Writes local/match-logs/game-NNN_review.md (git-ignored) and prints its path. An existing review file is
//    kept unless --force.
"use strict";
const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const ROOT = path.join(__dirname, "..");
const { LOCAL_DIR, normTags } = require("./shared.js");
const LOGS = path.join(LOCAL_DIR, "match-logs");
const TRACKER = path.join(LOCAL_DIR, "verify", "tracker.json");
const TEST_BUILD = path.join(LOCAL_DIR, "verify", "test-build.json");
// customize/version.lua before and after the layout change of #221 (old builds name their version there).
const VERSION_FILES = ["bots/customize/version.lua", "Customize/version.lua"]; // restructure:keep
const DEFAULT_DOTA = "C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota";
const GH = process.env.GH || (process.platform === "win32" ? "C:\\Program Files\\GitHub CLI\\gh.exe" : "gh");
// "attempt to" is case-sensitive: Lua errors are lower case, the engine's "Attempt to set 'item' in slot" is noise.
const ERROR_LINE = /attempt to|stack traceback|\[SHy-ERROR\]|[Ss]cript (Runtime )?[Ee]rror/;
const TAG = /\[(SHy-[A-Z0-9_]+)\]/;

function parseArgs(argv) {
	const o = { dota: DEFAULT_DOTA, game: null, split: true, mark: true, force: false };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--game") o.game = String(argv[++i]).padStart(3, "0");
		else if (a === "--no-split") o.split = false;
		else if (a === "--no-mark") o.mark = false;
		else if (a === "--force") o.force = true;
		else o.dota = a;
	}
	return o;
}

function run(cmd, args) {
	const r = cp.spawnSync(cmd, args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
	return { ok: r.status === 0, out: (r.stdout || "") + (r.stderr || ""), error: r.error };
}
function git(args) {
	const r = run("git", args);
	return r.ok ? r.out.trim() : "";
}
function readJson(file, fallback) {
	try {
		return JSON.parse(fs.readFileSync(file, "utf8"));
	} catch (e) {
		return fallback;
	}
}
function field(text, name) {
	const m = text.match(new RegExp("\\b" + name + "=(\\S+)"));
	return m ? m[1] : null;
}
function body(line) {
	const at = line.indexOf("[VScript]");
	return at < 0 ? line.replace(/^\d+\/\d+ \d+:\d+:\d+ /, "") : line.slice(at + 9).trim();
}
function wallTime(line) {
	const m = line.match(/^(\d+\/\d+ \d+:\d+:\d+)/);
	return m ? m[1] : null;
}
function fmtClock(t) {
	if (t == null || Number.isNaN(t)) return "?";
	const abs = Math.abs(t);
	return (t < 0 ? "-" : "") + Math.floor(abs / 60) + ":" + String(Math.floor(abs % 60)).padStart(2, "0");
}
function fence(text) {
	return "```\n" + String(text).replace(/\s+$/, "") + "\n```";
}

// --- 1. split and pick the game --------------------------------------------------------------------------
function splitAndPick(o) {
	let splitOut = "(skipped: --no-split)";
	if (o.split) {
		const r = run(process.execPath, [path.join(__dirname, "split-console.js"), o.dota]);
		splitOut = r.out.trim();
		if (!r.ok) console.warn(`split-console.js failed, using the existing local/match-logs:\n${splitOut}`);
		else console.log(splitOut.split(/\r?\n/)[0]);
	}
	const rows = fs
		.readFileSync(path.join(LOGS, "index.txt"), "utf8")
		.split(/\r?\n/)
		.filter(Boolean)
		.map((l) => {
			const [file, ...rest] = l.split("\t");
			const f = Object.fromEntries(rest.map((kv) => [kv.slice(0, kv.indexOf("=")), kv.slice(kv.indexOf("=") + 1)]));
			return { file, num: file.match(/^game-(\d+)/)[1], ...f };
		});
	const game = o.game ? rows.find((r) => r.num === o.game) : rows[rows.length - 1];
	if (!game) throw new Error(`game ${o.game || "(newest)"} not in local/match-logs/index.txt`);
	return { game, splitOut };
}

// --- 2. build -> commit ----------------------------------------------------------------------------------
function describe(sha) {
	return git(["show", "-s", "--format=%h %cd %s", "--date=format:%Y-%m-%d %H:%M", sha]);
}
function buildSection(lines, summary) {
	const out = [];
	const builds = [...new Set(lines.filter((l) => l.includes("[SHy-BUILD]")).map((l) => body(l)))];
	let version = null;
	let sha = null;
	if (builds.length) {
		for (const b of builds) out.push(`- \`${b}\``);
		const b = builds[0];
		version = field(b, "version");
		const c = field(b, "commit");
		if (c && c !== "release") sha = c;
		if (builds.some((x) => field(x, "dirty") === "true")) {
			out.push("- **dirty**: the game ran local uncommitted changes on top of that commit.");
		}
	} else {
		const m = summary.match(/^version (\S+)/m);
		version = m ? m[1] : null;
		out.push(`- version \`${version || "?"}\` (no [SHy-BUILD] line: build before build info)`);
	}
	let commit = null;
	if (!sha && version) {
		const m = version.match(/-([0-9a-f]{7,40})(\+dirty)?$/);
		if (m) sha = m[1];
	}
	if (sha) {
		const full = git(["rev-parse", "--verify", "--quiet", sha + "^{commit}"]);
		commit = full || null;
		out.push(full ? `- commit: ${describe(full)}` : `- commit \`${sha}\` is not in this clone (git fetch?)`);
	} else if (version) {
		const hits = git(["log", "--all", "--format=%H", `-S"${version.replace(/\+dirty$/, "")}"`, "--", ...VERSION_FILES])
			.split(/\r?\n/)
			.filter(Boolean);
		if (hits.length) {
			commit = hits[hits.length - 1];
			out.push(`- commit (version introduced): ${describe(commit)}`);
			if (hits.length > 1) out.push(`- version replaced by: ${describe(hits[hits.length - 2])} (the build is in this range)`);
			else out.push("- not replaced yet: the build is this commit or a later one up to HEAD");
			for (const h of hits.slice(0, -2)) out.push(`- also touches this version: ${describe(h)}`);
		} else {
			out.push(`- no commit sets version \`${version}\` in ${VERSION_FILES.join(" or ")}`);
		}
	}
	const tb = readJson(TEST_BUILD, null);
	if (tb) {
		const tracker = readJson(TRACKER, { prs: {} });
		const name = (n) => `#${n}${tracker.prs && tracker.prs[n] ? " " + tracker.prs[n].title : ""}`;
		const match = commit && tb.head ? (commit.startsWith(tb.head) || tb.head.startsWith(commit) ? "yes" : "NO") : "?";
		out.push("", `Test build (local/verify/test-build.json, built ${tb.builtAt || "?"}): head \`${String(tb.head || "?").slice(0, 10)}\` on base \`${String(tb.base || "?").slice(0, 10)}\`; game ran this head: **${match}**`);
		for (const [key, label] of [["included", "in this build"], ["upToDate", "already in base"], ["conflicts", "CONFLICT, not in build"], ["missing", "branch missing"]]) {
			for (const n of tb[key] || []) out.push(`- ${name(n)} (${label})`);
		}
	} else {
		out.push("", "No local/verify/test-build.json (game not run from a test build).");
	}
	// Which tracked PRs were in this game, straight from git: a PR is in the build when its branch tip is an
	// ancestor of the commit the game printed in [SHy-BUILD]. Works for one PR branch and for a test/next build
	// with many PRs alike, and keeps working after test/next is rebuilt.
	gamePrs = null;
	if (commit) {
		const tracker = readJson(TRACKER, { prs: {} });
		const inBuild = [];
		const notIn = [];
		const isAncestor = (a) => cp.spawnSync("git", ["merge-base", "--is-ancestor", a, commit], { cwd: ROOT }).status === 0;
		for (const [n, p] of Object.entries(tracker.prs || {})) {
			if (!p.branch) continue;
			// The PR's own (non-merge) commits that change Lua must all be in the build. Merge commits are
			// ignored (a later "merge main into the PR" doesn't change what the PR contributes), and so are
			// commits that touch no Lua (CI, docs, tools): game 038 ran #6's code, but #6's CI-only commit
			// came later and the PR was counted as missing. A PR with no Lua commits uses all of them.
			const range = `origin/main..origin/${p.branch}`;
			const lines = (out) => out.split(/\r?\n/).filter(Boolean);
			const luaOwn = lines(git(["rev-list", "--no-merges", range, "--", "*.lua"]));
			const own = luaOwn.length ? luaOwn : lines(git(["rev-list", "--no-merges", range]));
			const ok = own.length ? own.every(isAncestor) : isAncestor(`origin/${p.branch}`);
			(ok ? inBuild : notIn).push(n);
		}
		gamePrs = inBuild;
		out.push("", `Tracked PRs in this game's build (all their own Lua commits are ancestors of the build commit): ${inBuild.map((n) => "#" + n).join(" ") || "none"}`);
		if (notIn.length) out.push(`Not in this build (their items are not checked): ${notIn.map((n) => "#" + n).join(" ")}`);
	}
	return out.join("\n");
}
let gamePrs = null;

// --- 4. errors, spam, deaths -----------------------------------------------------------------------------
function errorsSection(lines) {
	const groups = new Map();
	let clock = null;
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const b = body(line);
		const t = line.includes("[VScript]") ? b.match(/\bt=(-?\d+(?:\.\d+)?)/) : null;
		if (t) clock = Number(t[1]);
		if (!ERROR_LINE.test(line)) continue;
		let key = b.replace(/\bt=[-\d.]+ /, "").replace(/npc_dota_hero_\w+/g, "<hero>");
		if (/stack traceback/i.test(key) && lines[i + 1]) key += " " + body(lines[i + 1]).trim();
		key = key.slice(0, 200);
		const g = groups.get(key) || { n: 0, wall: wallTime(line), clock };
		g.n++;
		groups.set(key, g);
	}
	if (!groups.size) return "No script errors (lines with `attempt to`, `stack traceback`, `[SHy-ERROR]`, `script error`, `Script Runtime Error`).";
	const total = [...groups.values()].reduce((a, g) => a + g.n, 0);
	const rows = [...groups.entries()].sort((a, b) => b[1].n - a[1].n);
	return [`${total} error line(s), ${groups.size} distinct:`, "", "| count | first (game / wall) | message |", "|---:|---|---|"]
		.concat(rows.map(([k, g]) => `| ${g.n} | ${fmtClock(g.clock)} / ${g.wall || "?"} | \`${k.replace(/\|/g, "\\|").replace(/`/g, "'")}\` |`))
		.join("\n");
}

function spamSection(lines) {
	const tags = new Map();
	let clock = null;
	let first = null;
	let last = null;
	for (const line of lines) {
		if (!line.includes("[VScript]")) continue;
		const b = body(line);
		const t = b.match(/\bt=(-?\d+(?:\.\d+)?)/);
		if (t) clock = Number(t[1]);
		const m = b.match(TAG);
		const sec = wallTime(line);
		if (!m || !sec) continue;
		first = first || sec;
		last = sec;
		const s = tags.get(m[1]) || { total: 0, per: new Map(), peak: 0, at: null, clock: null };
		s.total++;
		const n = (s.per.get(sec) || 0) + 1;
		s.per.set(sec, n);
		if (n > s.peak) Object.assign(s, { peak: n, at: sec, clock });
		tags.set(m[1], s);
	}
	const span = first && last ? Math.max(60, (Date.parse("2000/" + last) - Date.parse("2000/" + first)) / 1000) : 0;
	const rows = [...tags.entries()].sort((a, b) => b[1].peak - a[1].peak || b[1].total - a[1].total).slice(0, 10);
	return ["Top 10 [SHy-*] tags by peak lines in one second (wall clock):", "", "| tag | peak/s | at (game / wall) | total | per min |", "|---|---:|---|---:|---:|"]
		.concat(
			rows.map(([tag, s]) => `| ${tag} | ${s.peak} | ${fmtClock(s.clock)} / ${s.at} | ${s.total} | ${span ? (s.total / (span / 60)).toFixed(1) : "?"} |`)
		)
		.join("\n");
}

function deathsSection(summary) {
	const lines = summary.split(/\r?\n/);
	const team = {};
	for (const side of ["radiant", "dire"]) {
		const m = summary.match(new RegExp(`^${side} (\\S+)`, "m"));
		for (const h of m ? m[1].split(",") : []) team[h] = side;
	}
	const out = [];
	const sb = lines.findIndex((l) => l.startsWith("scoreboard"));
	const board = [];
	if (sb >= 0) {
		for (let i = sb + 1; i < lines.length && /^\s+(radiant|dire)\s/.test(lines[i]); i++) board.push(lines[i]);
	}
	if (board.length) {
		const sum = { radiant: { k: 0, d: 0 }, dire: { k: 0, d: 0 } };
		for (const l of board) {
			const m = l.match(/^\s+(radiant|dire)\s+\S+\s+(\d+)\/\s*(\d+)\//);
			if (m) {
				sum[m[1]].k += Number(m[2]);
				sum[m[1]].d += Number(m[3]);
			}
		}
		out.push(`Scoreboard deaths: radiant ${sum.radiant.d} (kills ${sum.radiant.k}), dire ${sum.dire.d} (kills ${sum.dire.k})`);
	} else {
		out.push("No end-of-match scoreboard in this log.");
	}
	// [SHy-DEATH] list: Meepo clones repeat "meepo #N", so count each hero's death number once.
	const seen = new Set();
	const per = { radiant: {}, dire: {}, "?": {} };
	const dl = lines.findIndex((l) => /^deaths \d+/.test(l));
	for (let i = dl + 1; dl >= 0 && i < lines.length && /^\s+-?\d+:\d+\s+\S+ #\d+/.test(lines[i]); i++) {
		const m = lines[i].match(/^\s+-?\d+:\d+\s+(\S+) #(\d+)/);
		if (seen.has(m[1] + "#" + m[2])) continue;
		seen.add(m[1] + "#" + m[2]);
		const side = team[m[1]] || "?";
		per[side][m[1]] = (per[side][m[1]] || 0) + 1;
	}
	for (const side of ["radiant", "dire", "?"]) {
		const hs = Object.entries(per[side]);
		if (!hs.length) continue;
		const n = hs.reduce((a, [, c]) => a + c, 0);
		out.push(`[SHy-DEATH] ${side}: ${n}  (${hs.sort((a, b) => b[1] - a[1]).map(([h, c]) => `${h} ${c}`).join(", ")})`);
	}
	if (board.length) out.push("", fence(["scoreboard"].concat(board).join("\n")));
	return out.join("\n");
}

// --- 4b. mode flip-flops (#165) ----------------------------------------------------------------------------
function flipsSection(lines) {
	try {
		return require("./flip-report").summary(lines);
	} catch (err) {
		return `flip-report.js failed: ${err.message || err}`;
	}
}

// --- 5. maintainer comments ------------------------------------------------------------------------------
function commentsSection(tracker) {
	const since = tracker.lastReviewAt || null;
	const out = [`Since ${since || "(no previous review: all comments)"}:`];
	const prs = Object.keys(tracker.prs || {});
	if (!prs.length) return "No tracked PRs.";
	for (const n of prs) {
		const r = run(GH, ["pr", "view", n, "--json", "comments"]);
		if (!r.ok) {
			out.push("", `#${n}: gh failed: ${(r.error ? r.error.message : r.out).trim().split(/\r?\n/)[0]}`);
			continue;
		}
		let comments;
		try {
			comments = JSON.parse(r.out).comments || [];
		} catch (e) {
			out.push("", `#${n}: could not parse gh output`);
			continue;
		}
		const fresh = comments.filter((c) => !since || Date.parse(c.createdAt) > Date.parse(since));
		if (!fresh.length) continue;
		out.push("", `**#${n} ${tracker.prs[n].title}**`);
		for (const c of fresh) {
			const who = (c.author && c.author.login) || "?";
			const text = String(c.body || "").trim().replace(/\r?\n/g, "\n  ");
			out.push(`- ${c.createdAt} ${who}: ${text}`);
		}
	}
	if (out.length === 1) out.push("", "No new comments.");
	return out.join("\n");
}

// --- main ------------------------------------------------------------------------------------------------
// Ping clicks vs pings the bot API saw (#222, game 078: the maintainer spammed pings, the bots saw one per ~1.5s).
// The server prints `PR:NotePlayerCommsTime <slot>:[U:1:<account id>] communicated at <time>` for each ping click (and
// chat line); the scripts print `[SHy-PING] x y z normal= t=` once per new GetMostRecentPing (the trace in
// ability_item_usage_generic.lua). A burst is clicks of one player slot at most 1s apart; its pings are the trace
// lines from the burst's first click to 1s after its last (wall clock). The account id is never copied.
const COMMS = /PR:NotePlayerCommsTime (\d+):\S+ communicated at (\d+(?:\.\d+)?)/;
const PING_TRACE = /\[SHy-PING\] -?\d+ -?\d+ -?\d+ normal=/;
function wallSeconds(wall) {
	const m = wall && wall.match(/(\d+):(\d+):(\d+)$/);
	return m ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) : null;
}
function pingsSection(lines) {
	const bursts = [];
	const open = new Map();
	let clock = null;
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (line.includes("[VScript]")) {
			const t = body(line).match(/\bt=(-?\d+(?:\.\d+)?)/);
			if (t) clock = Number(t[1]);
		}
		const m = line.match(COMMS);
		if (!m) continue;
		const slot = m[1];
		const at = Number(m[2]);
		const b = open.get(slot);
		if (b && at - b.last <= 1.0) {
			b.last = at;
			b.clicks++;
			b.lastIndex = i;
			b.endWall = wallSeconds(wallTime(line));
		} else {
			const nb = { slot, first: at, last: at, clicks: 1, firstIndex: i, lastIndex: i, clock, wall: wallTime(line), endWall: wallSeconds(wallTime(line)) };
			bursts.push(nb);
			open.set(slot, nb);
		}
	}
	const shown = bursts.filter((b) => b.clicks >= 4);
	if (!bursts.length) return "No ping clicks in the server log (`PR:NotePlayerCommsTime` lines).";
	for (const b of shown) {
		let pings = 0;
		for (let i = b.firstIndex; i < lines.length; i++) {
			const w = wallSeconds(wallTime(lines[i]));
			if (i > b.lastIndex && w != null && b.endWall != null && w > b.endWall + 1) break;
			if (PING_TRACE.test(lines[i])) pings++;
		}
		b.pings = pings;
	}
	const clicks = shown.reduce((a, b) => a + b.clicks, 0);
	const pings = shown.reduce((a, b) => a + b.pings, 0);
	const head = [
		`${bursts.length} click burst(s), ${shown.length} with 4+ clicks: ${clicks} clicks, ${pings} pings seen by the bot API` +
			(pings ? ` (${(clicks / pings).toFixed(1)} clicks per ping seen)` : "") +
			". A low ratio means the bots see most clicks; a high one that the game passes only some of them on.",
	];
	if (!shown.length) return head.join("\n");
	return head
		.concat(["", "| game / wall | slot | clicks | span s | pings seen | s per ping |", "|---|---:|---:|---:|---:|---:|"])
		.concat(
			shown.map((b) => {
				const span = b.last - b.first;
				return `| ${fmtClock(b.clock)} / ${b.wall || "?"} | ${b.slot} | ${b.clicks} | ${span.toFixed(1)} | ${b.pings} | ${b.pings ? (span / b.pings).toFixed(1) : "-"} |`;
			})
		)
		.join("\n");
}

function main() {
	const o = parseArgs(process.argv.slice(2));
	const startedAt = new Date().toISOString();
	const { game } = splitAndPick(o);
	const reviewFile = path.join(LOGS, `game-${game.num}_review.md`);
	if (fs.existsSync(reviewFile) && !o.force) {
		console.error(`${path.relative(ROOT, reviewFile)} exists (maybe with findings); pass --force to overwrite.`);
		process.exit(1);
	}
	const logFile = path.join(LOGS, game.file);
	// An old log prints [OHA-...]: read it in the new form (tools/shared.js normTags). // restructure:keep
	const lines = normTags(fs.readFileSync(logFile, "utf8")).split(/\r?\n/);
	const summaryFile = path.join(LOGS, game.summary || game.file.replace(/\.log$/, ".summary.txt"));
	const summary = fs.existsSync(summaryFile) ? fs.readFileSync(summaryFile, "utf8") : "";
	const rel = (f) => path.relative(ROOT, f).replace(/\\/g, "/");

	console.log(`game ${game.num}: ${game.file}`);
	const build = buildSection(lines, summary);
	const checkArgs = [path.join(__dirname, "verify.js"), "check", rel(logFile), "--game", game.num];
	if (gamePrs) checkArgs.push("--prs", gamePrs.join(",") || "none");
	const verify = run(process.execPath, checkArgs);
	const tracker = readJson(TRACKER, { prs: {} });
	const head = summary.split(/\r?\n/).slice(0, 7).join("\n");

	const md = [
		`# Game ${game.num} review`,
		"",
		`Log: \`${rel(logFile)}\` (${game.lines || "?"} lines), summary: \`${rel(summaryFile)}\`, match ${game.match || "?"}`,
		"",
		fence(head),
		"",
		"## Build",
		"",
		build,
		"",
		"## Tracker",
		"",
		`\`node tools/verify.js check ${rel(logFile)} --game ${game.num}\`${verify.ok ? "" : " (FAILED)"}:`,
		"",
		fence(verify.out.trim() || "(no output: no tracked PRs)"),
		"",
		"## Errors",
		"",
		errorsSection(lines),
		"",
		"## Spam",
		"",
		spamSection(lines),
		"",
		"## Deaths",
		"",
		deathsSection(summary),
		"",
		"## Mode flips",
		"",
		flipsSection(lines),
		"",
		"## Ping clicks",
		"",
		pingsSection(lines),
		"",
		"## Maintainer comments",
		"",
		commentsSection(tracker),
		"",
		"## Findings",
		"",
		"<!-- what happened (time + log line) / why it matters / code location / suggested fix / confidence -->",
		"",
		"## Issues to file",
		"",
		"<!-- grouped cards (AGENTS.md step 1); then node tools/issue-prs.js -->",
		"",
	].join("\n");
	fs.writeFileSync(reviewFile, md, "utf8");

	if (o.mark) {
		const db = readJson(TRACKER, null);
		if (db) {
			db.lastReviewAt = startedAt;
			fs.writeFileSync(TRACKER, JSON.stringify(db, null, 2) + "\n");
		}
	}
	console.log(`review: ${rel(reviewFile)}${o.mark ? "" : "  (--no-mark: lastReviewAt not updated)"}`);
}

if (require.main === module) {
	try {
		main();
	} catch (err) {
		console.error(err.message || err);
		process.exit(1);
	}
}
module.exports = { buildSection, errorsSection, spamSection, deathsSection, flipsSection, pingsSection };
