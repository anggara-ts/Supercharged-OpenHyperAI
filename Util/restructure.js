#!/usr/bin/env node
// The repo layout change of #221 as one deterministic codemod: run on any checkout of the old layout (main or a PR
// branch) it does every rename with `git mv` and every text rewrite, so each branch migrates the same way and its
// merge with the new main shows only real conflicts. Idempotent: on the new layout it changes nothing.
//
//   node tools/restructure.js                   migrate this checkout (needs a clean tracked tree), stage the result
//   node tools/restructure.js --check           report old paths and old log tags left in tracked files (exit 1)
//   node tools/restructure.js --move-local      move the untracked local data (match logs, tracker, reports, caches)
//                                               of an existing clone into local/
//   node tools/restructure.js --migrate-branch  a PR branch in one go: merge the last old-layout main, migrate and
//                                               commit, then merge the new main against the migrated old main (so
//                                               only the PR's own changes can conflict), then the rest of main
//   options: --dry-run (list what would change, write nothing), --stylua <exe> (else $STYLUA or stylua on PATH),
//            --main <ref> (--migrate-branch: the new main; default origin/main, fetched first)
//
// A branch that does not have this file runs main's copy:
//   git show origin/main:tools/restructure.js > ../restructure.js && node ../restructure.js --migrate-branch
// It works on the repo of the current directory (git rev-parse --show-toplevel), not on the folder it lives in.
//
// Layout (old -> new):
//   root *.lua (engine entry files)  -> bots/            Dota loads them from the bots folder root by exact name
//   BotsLib/  -> bots/heroes/        FuncLib/ -> bots/lib/ (FuncLib/lib/ -> bots/lib/vendor/)
//   Customize/ -> bots/customize/    Tests/ -> tests/    Util/ -> tools/    Docs/ -> docs/
//   Install-to-vscript/ -> install/  local data (Util/match-logs, Util/verify, generated reports, caches) -> local/
// Text: paths inside the game (GetScriptDirectory() .. "/FuncLib/x", "bots.FuncLib.x", game/Customize, Windows
// paths in logs) become bots-relative (lib/x); every other path becomes repo-relative (bots/lib/x). Log tags
// [OHA-X] become [SHy-X] (also Lua patterns %[OHA%- and bare "OHA-PERF"); the bot name suffix OHA-DEV stays.
// A line containing "restructure:keep" is never rewritten and never reported (intentional legacy text).
"use strict";
const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const KEEP = "restructure:keep";
const SELF_PATHS = new Set(["tools/restructure.js", "Util/restructure.js"]);
const SELF_DEST = "tools/restructure.js";
// Read at start: a run from Util/ moves this very file.
const SELF_SOURCE = fs.readFileSync(__filename);

// Folder moves, in order. caseOnly: a rename that differs only in case needs two steps on Windows.
const MOVES = [
	{ from: "FuncLib", to: "bots/lib" },
	{ from: "bots/lib/lib", to: "bots/lib/vendor" },
	{ from: "BotsLib", to: "bots/heroes" },
	{ from: "Customize", to: "bots/customize" },
	{ from: "Tests", to: "tests", caseOnly: true },
	{ from: "Util", to: "tools" },
	{ from: "Docs", to: "docs", caseOnly: true },
	{ from: "Install-to-vscript", to: "install" },
];
const OLD_TOP_DIRS = ["FuncLib", "BotsLib", "Customize", "Tests", "Util", "Docs", "Install-to-vscript"];

// Untracked local data -> local/. Looked for under Util/ (a clone switched to the new layout keeps its ignored
// files there) and tools/ (a whole-folder git mv carries them along).
const LOCAL_DATA = [
	"match-logs",
	"verify",
	"role-weights/rows.json",
	"hero-review/hero-review.html",
	"meta-builds/heroes",
	"item-builds/cache",
	"item-builds/report.md",
];

// Runtime folders: old name -> new name inside bots/ (longest first).
const RUNTIME = [
	["FuncLib/lib", "lib/vendor"],
	["FuncLib", "lib"],
	["BotsLib", "heroes"],
	["Customize", "customize"],
];
const RUNTIME_ALT = "FuncLib[/.\\\\]lib(?![A-Za-z0-9_])|FuncLib|BotsLib|Customize";

function runtimeName(old, sep) {
	const key = old.replace(/[.\\]/g, "/");
	const hit = RUNTIME.find(([from]) => from === key);
	return hit[1].replace(/\//g, sep);
}

const BINARY_EXT = /\.(png|jpe?g|gif|ico|webp|zip|7z|gz|vpk|exe|dll|bin|pdf)$/i;

// ---------------------------------------------------------------- git helpers

let ROOT = null;

function git(args, opts = {}) {
	const r = cp.spawnSync("git", args, {
		cwd: opts.cwd || ROOT,
		encoding: opts.encoding === null ? null : "utf8",
		input: opts.input,
		maxBuffer: 1 << 30,
		env: opts.env || process.env,
	});
	if (r.status !== 0 && !opts.allowFail) {
		throw new Error(`git ${args.join(" ")} failed (${r.status}):\n${(r.stderr || "") + (r.stdout || "")}`.trim());
	}
	return opts.allowFail ? r : typeof r.stdout === "string" ? r.stdout.trim() : r.stdout;
}

function trackedFiles(cwd) {
	return git(["ls-files", "-z"], { cwd })
		.split("\0")
		.filter(Boolean);
}

function topLevel(dir) {
	return git(["rev-parse", "--show-toplevel"], { cwd: dir });
}

// ---------------------------------------------------------------- text rewrites

// Rewrites one line. kind: "runtime" (.lua under bots/), "lua" (other .lua), "js", "text".
function rewriteLine(line, kind, rootLua) {
	if (line.includes(KEEP)) return line;
	let s = line;
	// Log tags. OHA-DEV is the bot name suffix, not a tag.
	s = s.replace(/(?<![A-Za-z0-9_])OHA(-|%-)(?!DEV(?![A-Za-z0-9_]))/g, "SHy$1");

	// Paths the game resolves inside the bots folder: keep them bots-relative.
	s = s.replace(
		new RegExp(`(GetScriptDirectory\\(\\)\\s*\\.\\.\\s*["'])/(${RUNTIME_ALT})(?=[/"'])`, "g"),
		(all, head, old) => `${head}/${runtimeName(old, "/")}`
	);
	s = s.replace(
		new RegExp(`(?<![A-Za-z0-9_])bots([/.\\\\])(${RUNTIME_ALT})(?![A-Za-z0-9_])`, "g"),
		(all, sep, old) => `bots${sep}${runtimeName(old, sep)}`
	);
	if (kind === "runtime" || kind === "lua") {
		// In Lua a literal that starts with "/BotsLib/" is always appended to GetScriptDirectory().
		s = s.replace(new RegExp(`(["'])/(${RUNTIME_ALT})(?=[/"'])`, "g"), (all, q, old) => `${q}/${runtimeName(old, "/")}`);
	}
	// Anywhere (also a Lua expression quoted in a JS comment): "/BotsLib/" .. x is a Lua path built at run time.
	s = s.replace(
		new RegExp(`(["'])/(${RUNTIME_ALT})(/[^"'\\s]*)?\\1(?=\\s*\\.\\.)`, "g"),
		(all, q, old, rest) => `${q}/${runtimeName(old, "/")}${rest || ""}${q}`
	);
	s = s.replace(/(?<![A-Za-z0-9_])game([/\\])Customize(?![A-Za-z0-9_])/g, "game$1customize");
	// Windows paths (logs, installers): bots-relative, lowercase.
	s = s.replace(
		new RegExp(`\\\\(${RUNTIME_ALT})(?=[\\\\"'\\s>]|$)`, "g"),
		(all, old) => `\\${runtimeName(old, "\\")}`
	);

	// Everything else is a repo path.
	s = s.replace(/(?<![A-Za-z0-9_])FuncLib\/lib(?![A-Za-z0-9_])/g, "bots/lib/vendor");
	s = s.replace(/(?<![A-Za-z0-9_])FuncLib(?![A-Za-z0-9_])/g, "bots/lib");
	s = s.replace(/(?<![A-Za-z0-9_])BotsLib(?![A-Za-z0-9_])/g, "bots/heroes");
	s = s.replace(/(?<![A-Za-z0-9_.])Customize(?=\/)/g, "bots/customize");
	s = s.replace(/(["'`])Customize\1/g, "$1bots/customize$1");
	s = s.replace(/(?<![A-Za-z0-9_.])Customize folder/g, "customize folder");

	// Local data first (Util/verify.js is a tool, Util/verify/ is data).
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/match-logs(?![A-Za-z0-9_-])/g, "local/match-logs");
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/verify(?![A-Za-z0-9_.-])/g, "local/verify");
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/role-weights\/rows\.json/g, "local/role-weights/rows.json");
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/hero-review\/hero-review\.html/g, "local/hero-review/hero-review.html");
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/meta-builds\/heroes(?![A-Za-z0-9_.-])/g, "local/meta-builds/heroes");
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/item-builds\/cache(?![A-Za-z0-9_.-])/g, "local/item-builds/cache");
	s = s.replace(/(?<![A-Za-z0-9_.-])Util\/item-builds\/report\.md/g, "local/item-builds/report.md");
	for (const [from, to] of [
		["Util", "tools"],
		["Tests", "tests"],
		["Docs", "docs"],
	]) {
		s = s.replace(new RegExp(`(?<![A-Za-z0-9_.-])${from}(?=[/\\\\])`, "g"), to);
		s = s.replace(new RegExp(`(["'\`])${from}\\1`, "g"), `$1${to}$1`);
	}
	s = s.replace(/(?<![A-Za-z0-9_])Install-to-vscript(?![A-Za-z0-9_])/g, "install");

	// Engine entry files named by repo path in tests and tools ("ability_item_usage_generic.lua" -> "bots/...").
	if ((kind === "lua" || kind === "js") && rootLua.size > 0) {
		s = s.replace(/(["'`])([a-z0-9_]+)\.lua\1/g, (all, q, name) => (rootLua.has(name) ? `${q}bots/${name}.lua${q}` : all));
	}
	return s;
}

function fileKind(file) {
	if (file.endsWith(".lua")) return file.startsWith("bots/") ? "runtime" : "lua";
	if (file.endsWith(".js")) return "js";
	return "text";
}

function isBinary(buffer, file) {
	if (BINARY_EXT.test(file)) return true;
	const n = Math.min(buffer.length, 8000);
	for (let i = 0; i < n; i++) if (buffer[i] === 0) return true;
	return false;
}

function rewriteText(text, kind, rootLua) {
	return text
		.split("\n")
		.map((line) => rewriteLine(line, kind, rootLua))
		.join("\n");
}

// ---------------------------------------------------------------- moves

function hasTracked(files, dir) {
	const prefix = dir + "/";
	return files.some((f) => f.startsWith(prefix));
}

function exists(rel) {
	return fs.existsSync(path.join(ROOT, rel));
}

function gitMv(from, to, dryRun, log) {
	log.push(`git mv ${from} ${to}`);
	if (dryRun) return;
	fs.mkdirSync(path.dirname(path.join(ROOT, to)), { recursive: true });
	git(["mv", from, to]);
}

// Moves the tracked files of `from` to `to`. A whole-folder `git mv` when `to` does not exist yet, else file by file.
function moveDir(move, dryRun, log) {
	const files = trackedFiles();
	if (!hasTracked(files, move.from)) return;
	// On a case-insensitive file system "tests" already "exists" while "Tests" is there: compare the real name.
	const destTaken = move.caseOnly ? hasTracked(files, move.to) : exists(move.to);
	if (!destTaken) {
		if (move.caseOnly) {
			const tmp = `${move.to}.restructure-tmp`;
			gitMv(move.from, tmp, dryRun, log);
			gitMv(tmp, move.to, dryRun, log);
		} else {
			gitMv(move.from, move.to, dryRun, log);
		}
		return;
	}
	const byDest = new Map();
	for (const f of files.filter((x) => x.startsWith(move.from + "/"))) {
		const dest = move.to + f.slice(move.from.length);
		if (files.includes(dest)) throw new Error(`${f} and ${dest} are both tracked: resolve by hand`);
		const dir = path.posix.dirname(dest);
		if (!byDest.has(dir)) byDest.set(dir, []);
		byDest.get(dir).push(f);
	}
	for (const [dir, list] of byDest) {
		log.push(`git mv ${list.length} file(s) ${move.from}/... -> ${dir}/`);
		if (dryRun) continue;
		fs.mkdirSync(path.join(ROOT, dir), { recursive: true });
		for (let i = 0; i < list.length; i += 100) git(["mv", ...list.slice(i, i + 100), dir + "/"]);
	}
	pruneEmpty(move.from, dryRun);
}

function pruneEmpty(rel, dryRun) {
	const full = path.join(ROOT, rel);
	if (dryRun || !fs.existsSync(full) || !fs.statSync(full).isDirectory()) return;
	for (const name of fs.readdirSync(full)) pruneEmpty(path.posix.join(rel, name), dryRun);
	if (fs.readdirSync(full).length === 0) fs.rmdirSync(full);
}

// The engine entry files: tracked .lua at the repo root (old layout) or directly under bots/ (new layout).
function rootLuaNames(files) {
	const names = new Set();
	for (const f of files) {
		const m = /^(?:bots\/)?([a-z0-9_]+)\.lua$/.exec(f);
		if (m) names.add(m[1]);
	}
	return names;
}

// ---------------------------------------------------------------- migrate (the codemod)

function findStylua(args) {
	const candidates = [args.stylua, process.env.STYLUA, "stylua"].filter(Boolean);
	for (const exe of candidates) {
		const r = cp.spawnSync(exe, ["--version"], { encoding: "utf8" });
		if (r.status === 0) return { exe, version: r.stdout.trim() };
	}
	return null;
}

function migrate(args) {
	const dryRun = args.dryRun;
	const log = [];
	if (!args.allowDirty) {
		const dirty = git(["status", "--porcelain", "--untracked-files=no"]);
		if (dirty) throw new Error(`tracked files have changes; commit or stash them first:\n${dirty}`);
	}
	const before = trackedFiles();
	const rootLua = rootLuaNames(before);

	// 1. Engine entry files from the root into bots/.
	const rootFiles = before.filter((f) => /^[^/]+\.lua$/.test(f));
	if (rootFiles.length > 0) {
		log.push(`git mv ${rootFiles.length} root .lua file(s) -> bots/`);
		if (!dryRun) {
			fs.mkdirSync(path.join(ROOT, "bots"), { recursive: true });
			for (const f of rootFiles) {
				if (exists(`bots/${f}`) && before.includes(`bots/${f}`)) throw new Error(`${f} and bots/${f} are both tracked`);
			}
			git(["mv", ...rootFiles, "bots/"]);
		}
	}
	// 2. Folders.
	for (const move of MOVES) moveDir(move, dryRun, log);

	// 3. Text in every tracked file (after the moves, so kinds follow the new paths).
	const files = dryRun ? before : trackedFiles();
	const changed = [];
	for (const file of files) {
		if (SELF_PATHS.has(file)) continue;
		const full = path.join(ROOT, file);
		if (!fs.existsSync(full)) continue;
		const buffer = fs.readFileSync(full);
		if (isBinary(buffer, file)) continue;
		const text = buffer.toString("utf8");
		const kindPath = dryRun ? newPathOf(file) : file;
		const out = rewriteText(text, fileKind(kindPath), rootLua);
		if (out !== text) {
			changed.push(file);
			if (!dryRun) fs.writeFileSync(full, out, "utf8");
		}
	}
	log.push(`rewrote ${changed.length} file(s)`);

	// 4. This script into tools/ (a branch that ran a copy gets the same file main has).
	const self = SELF_SOURCE;
	const selfDest = path.join(ROOT, SELF_DEST);
	if (!fs.existsSync(selfDest) || !fs.readFileSync(selfDest).equals(self)) {
		log.push(`write ${SELF_DEST}`);
		if (!dryRun) {
			fs.mkdirSync(path.dirname(selfDest), { recursive: true });
			fs.writeFileSync(selfDest, self);
		}
	}

	if (dryRun) {
		for (const l of log) console.log(l);
		for (const f of changed) console.log(`  rewrite ${f} -> ${newPathOf(f)}`);
		return { changed };
	}

	// 5. StyLua on the rewritten Lua files (shorter paths can let a wrapped statement fit on one line).
	const lua = changed.filter((f) => f.endsWith(".lua"));
	const stylua = findStylua(args);
	if (lua.length > 0 && stylua) {
		for (let pass = 0; pass < 2; pass++) {
			for (let i = 0; i < lua.length; i += 100) cp.spawnSync(stylua.exe, lua.slice(i, i + 100), { cwd: ROOT });
		}
		log.push(`stylua (${stylua.version}) on ${lua.length} Lua file(s)`);
	} else if (lua.length > 0) {
		log.push(`stylua not found (pass --stylua <exe> or set STYLUA): the commit hook formats the staged Lua files`);
	}
	pruneOld();
	moveLocal({ quiet: true, log });
	// Stage only what this run touched (the moves are staged by git mv): never unrelated untracked files.
	for (let i = 0; i < changed.length; i += 100) git(["add", "--", ...changed.slice(i, i + 100)]);
	git(["add", "--", SELF_DEST]);
	for (const l of log) console.log(l);
	const left = check({ quiet: true });
	console.log(left.length === 0 ? "check: no old paths or tags left" : `check: ${left.length} finding(s), run --check`);
	console.log("staged; review with `git status`, then commit");
	return { changed };
}

function pruneOld() {
	for (const dir of OLD_TOP_DIRS) pruneEmpty(dir, false);
}

// Where a file of the old layout goes (for --dry-run and the kinds).
function newPathOf(file) {
	if (/^[^/]+\.lua$/.test(file)) return `bots/${file}`;
	if (file.startsWith("FuncLib/lib/")) return "bots/lib/vendor/" + file.slice("FuncLib/lib/".length);
	for (const move of MOVES) {
		if (file.startsWith(move.from + "/")) return move.to + file.slice(move.from.length);
	}
	return file;
}

// ---------------------------------------------------------------- --check

// Broader than the rewrite rules on purpose: it also catches forms a branch adds that no rule knows.
const CHECKS = [
	{ what: "old folder name", re: /(?<![A-Za-z0-9_])(FuncLib|BotsLib|Install-to-vscript)(?![A-Za-z0-9_])/ },
	{ what: "old Customize path", re: /Customize[/]|Customize\\(?![.\\])|[/\\]Customize(?![A-Za-z0-9_.]|\\\.)|["'`]Customize["'`]/ },
	{ what: "old folder path", re: /(?<![A-Za-z0-9_.-])(Util|Tests|Docs)[/\\]|["'`](Util|Tests|Docs)["'`]/ },
	{ what: "old log tag", re: /OHA(-|%-)(?!DEV(?![A-Za-z0-9_]))/ },
	{ what: "doubled bots folder", re: /GetScriptDirectory\(\)\s*\.\.\s*["']\/bots\/|bots[/.]bots[/.]/ },
];

function check(opts = {}) {
	const findings = [];
	const files = trackedFiles();
	for (const f of files) {
		if (/^[^/]+\.lua$/.test(f)) findings.push(`${f}: engine file still at the repo root (belongs in bots/)`);
		const top = f.split("/")[0];
		if (f.includes("/") && OLD_TOP_DIRS.includes(top)) findings.push(`${f}: tracked under the old folder ${top}/`);
		if (/[A-Z]/.test(path.posix.dirname(f)) && !f.startsWith(".")) findings.push(`${f}: folder name with capitals`);
	}
	const rootLua = rootLuaNames(files);
	const known = new Set(files);
	for (const file of files) {
		if (SELF_PATHS.has(file)) continue;
		const full = path.join(ROOT, file);
		if (!fs.existsSync(full)) continue;
		const buffer = fs.readFileSync(full);
		if (isBinary(buffer, file)) continue;
		const kind = fileKind(file);
		const lines = buffer.toString("utf8").split("\n");
		lines.forEach((line, i) => {
			if (line.includes(KEEP)) return;
			for (const c of CHECKS) {
				if (c.re.test(line)) findings.push(`${file}:${i + 1}: ${c.what}: ${line.trim().slice(0, 140)}`);
			}
			if (kind === "lua" || kind === "js") {
				for (const m of line.matchAll(/(["'`])([a-z0-9_]+)\.lua\1/g)) {
					if (rootLua.has(m[2])) findings.push(`${file}:${i + 1}: engine file without bots/: ${m[0]}`);
				}
			}
			if (kind === "runtime" && !/^\s*--/.test(line)) {
				// Every literal GetScriptDirectory() .. "/x" and "bots.x.y" target must exist under bots/.
				const targets = [];
				for (const m of line.matchAll(/GetScriptDirectory\(\)\s*\.\.\s*(["'])\/([^"']+)\1(\s*\.\.)?/g)) {
					if (!m[3]) targets.push(m[2]);
				}
				for (const m of line.matchAll(/\b(?:require|dofile)\s*\(?\s*(["'])bots[./]([^"']+)\1/g)) {
					targets.push(m[2].replace(/\./g, "/"));
				}
				for (const t of targets) {
					const rel = "bots/" + t.replace(/\.lua$/, "") + ".lua";
					if (!known.has(rel) && !/customize\/build_info$/.test(t)) {
						findings.push(`${file}:${i + 1}: require target ${t} is not a tracked file (${rel})`);
					}
				}
			}
		});
	}
	if (!opts.quiet) {
		for (const f of findings) console.log(f);
		console.log(findings.length === 0 ? "restructure --check: clean" : `restructure --check: ${findings.length} finding(s)`);
	}
	return findings;
}

// ---------------------------------------------------------------- --move-local

function isTrackedPath(rel) {
	return git(["ls-files", "--", rel]).length > 0;
}

function moveInto(src, dest, dryRun, log) {
	const s = path.join(ROOT, src);
	const d = path.join(ROOT, dest);
	if (!fs.existsSync(d)) {
		log.push(`move ${src} -> ${dest}`);
		if (!dryRun) {
			fs.mkdirSync(path.dirname(d), { recursive: true });
			fs.renameSync(s, d);
		}
		return;
	}
	if (fs.statSync(s).isDirectory() && fs.statSync(d).isDirectory()) {
		for (const name of fs.readdirSync(s)) moveInto(path.posix.join(src, name), path.posix.join(dest, name), dryRun, log);
		if (!dryRun && fs.readdirSync(s).length === 0) fs.rmdirSync(s);
		return;
	}
	log.push(`kept ${src}: ${dest} exists already (move it by hand)`);
}

function moveLocal(opts = {}) {
	const log = opts.log || [];
	const dryRun = !!opts.dryRun;
	for (const item of LOCAL_DATA) {
		for (const base of ["Util", "tools"]) {
			const src = `${base}/${item}`;
			if (!exists(src) || isTrackedPath(src)) continue;
			moveInto(src, `local/${item}`, dryRun, log);
		}
	}
	// A stale build_info.lua at the old place (the hooks write bots/customize/build_info.lua now).
	if (exists("Customize/build_info.lua") && !isTrackedPath("Customize") && exists("bots/customize")) {
		log.push("delete Customize/build_info.lua (stale; build-info.js writes bots/customize/build_info.lua)");
		if (!dryRun) fs.unlinkSync(path.join(ROOT, "Customize/build_info.lua"));
	}
	if (!dryRun) for (const dir of ["Util", "Customize"]) if (!isTrackedPath(dir)) pruneEmpty(dir, false);
	if (!opts.quiet) {
		for (const l of log) console.log(l);
		console.log(log.length === 0 ? "move-local: nothing to move" : "move-local: done");
		const leftovers = dryRun ? [] : ["Util", "Customize"].filter((d) => exists(d) && !isTrackedPath(d));
		if (leftovers.length) console.log(`left (untracked, not known local data): ${leftovers.join(", ")}`);
	}
	return log;
}

// ---------------------------------------------------------------- --migrate-branch

function oldLayout(ref, cwd) {
	return git(["cat-file", "-e", `${ref}:FuncLib`], { cwd, allowFail: true }).status === 0;
}

function migrateBranch(args) {
	const dirty = git(["status", "--porcelain", "--untracked-files=no"]);
	if (dirty) throw new Error(`tracked files have changes; commit or stash them first:\n${dirty}`);
	const branch = git(["symbolic-ref", "--quiet", "--short", "HEAD"], { allowFail: true }).stdout.trim();
	if (!branch) throw new Error("not on a branch");
	const main = args.main || "origin/main";
	if (!args.main) git(["fetch", "--quiet", "origin"]);
	const added = git(["log", "--format=%H", "--diff-filter=A", main, "--", SELF_DEST]).split(/\r?\n/).filter(Boolean);
	if (added.length === 0) throw new Error(`${main} has no ${SELF_DEST} yet: nothing to migrate to`);
	const n0 = added[added.length - 1];
	const lastOld = git(["rev-parse", `${n0}^1`]);
	console.log(`new layout on main since ${n0.slice(0, 10)}; last old-layout main ${lastOld.slice(0, 10)}`);
	const isAncestor = (a) => git(["merge-base", "--is-ancestor", a, "HEAD"], { allowFail: true }).status === 0;
	if (isAncestor(n0)) {
		console.log(`${branch} has the new layout from main already: \`git merge ${main}\` keeps it current`);
		return;
	}
	if (oldLayout("HEAD")) {
		// 1. The last old-layout main into the branch (an ordinary merge; real conflicts stop here).
		if (!isAncestor(lastOld)) {
			const r = git(["merge", "--no-edit", lastOld], { allowFail: true });
			if (r.status !== 0) {
				throw new Error(`merging the last old-layout main ${lastOld.slice(0, 10)} conflicts: resolve, commit, run again\n${r.stdout}${r.stderr}`);
			}
			console.log(`merged the last old-layout main ${lastOld.slice(0, 10)}`);
		}
		// 2. The codemod on the branch, committed.
		migrate({ ...args, allowDirty: false });
		commitWithHooks([
			"chore: move to the new repo layout (tools/restructure.js, #221)",
			"",
			"Ran tools/restructure.js: bot scripts under bots/ (heroes/, lib/, customize/), tests/, tools/, docs/,",
			"install/, and the log tags [OHA-*] -> [SHy-*]. No hand edits.",
		]);
	} else if (!isAncestor(lastOld)) {
		// Migrated by hand (or a run that stopped) without the last old-layout main: the special merge base
		// below would not fit. Merge the new main by hand instead.
		throw new Error(`${branch} is on the new layout but lacks ${lastOld.slice(0, 10)}: run \`git merge ${main}\` and resolve`);
	}
	const migrated = git(["rev-parse", "HEAD"]);
	// 3. The same codemod on the last old-layout main, in a temporary worktree: the merge base for the new main.
	const baseTree = codemodTree(lastOld, args);
	// 4. Merge the commit that brought the new layout against that base: only the branch's own changes can conflict.
	const mt = git(["merge-tree", "--write-tree", `--merge-base=${baseTree}`, migrated, n0], { allowFail: true });
	if (mt.status !== 0 && mt.status !== 1) throw new Error(`git merge-tree failed:\n${mt.stderr}`);
	const [infoPart, messages = ""] = mt.stdout.split(/\r?\n\r?\n/);
	const infoLines = infoPart.split(/\r?\n/).filter(Boolean);
	const resultTree = infoLines[0];
	const stages = infoLines.slice(1);
	git(["merge", "--no-ff", "--no-commit", "-s", "ours", n0], { allowFail: true });
	git(["read-tree", "-u", "--reset", resultTree]);
	if (stages.length > 0) {
		const paths = [...new Set(stages.map((l) => l.split("\t")[1]))];
		const removal = paths.map((p) => `0 ${"0".repeat(40)}\t${p}`).join("\n") + "\n";
		git(["update-index", "--index-info"], { input: removal });
		git(["update-index", "--index-info"], { input: stages.join("\n") + "\n" });
		console.log(`CONFLICTS (the branch's own changes against the new main) in:\n  ${paths.join("\n  ")}`);
		console.log(messages.trim());
		console.log("resolve them, `git add` and `git commit`, then `git merge origin/main` and run --check");
		return;
	}
	commitWithHooks([`Merge the new layout (${n0.slice(0, 10)}) into ${branch}`, "", `Merge base: ${SELF_DEST} run on ${lastOld.slice(0, 10)}.`]);
	console.log(`merged ${n0.slice(0, 10)} against the migrated old main: no conflicts`);
	// 5. The rest of main (ordinary merge, base = the layout commit).
	if (git(["merge-base", "--is-ancestor", main, "HEAD"], { allowFail: true }).status !== 0) {
		const r = git(["merge", "--no-edit", main], { allowFail: true });
		if (r.status !== 0) {
			console.log(`merging ${main} conflicts:\n${r.stdout}${r.stderr}\nresolve, commit, then run --check`);
			return;
		}
		console.log(`merged ${main}`);
	}
	check();
}

// Commits the index; when the StyLua hook reformats files it stops the commit: stage them and commit once more.
function commitWithHooks(messageLines) {
	const msg = messageLines.join("\n") + "\n";
	for (let attempt = 0; attempt < 2; attempt++) {
		const r = git(["commit", "-q", "-F", "-"], { input: msg, allowFail: true });
		if (r.status === 0) return;
		git(["add", "-u"]);
		if (attempt === 1) throw new Error(`git commit failed:\n${r.stdout}${r.stderr}`);
	}
}

// Tree of `ref` after the codemod (temporary detached worktree; nothing is committed).
function codemodTree(ref, args) {
	const os = require("os");
	const wt = fs.mkdtempSync(path.join(os.tmpdir(), "restructure-base-"));
	fs.rmdirSync(wt);
	const saved = ROOT;
	try {
		git(["worktree", "add", "--detach", "--no-checkout", "--quiet", wt, ref]);
		git(["reset", "--hard", "--quiet"], { cwd: wt });
		ROOT = wt;
		const quietLog = console.log;
		console.log = () => {};
		try {
			migrate({ ...args, allowDirty: false });
		} finally {
			console.log = quietLog;
		}
		return git(["write-tree"]);
	} finally {
		ROOT = saved;
		git(["worktree", "remove", "--force", wt], { allowFail: true });
		git(["worktree", "prune"], { allowFail: true });
	}
}

// ---------------------------------------------------------------- self-test

function selfTest() {
	let failed = 0;
	const eq = (name, actual, expected) => {
		const ok = actual === expected;
		if (!ok) failed++;
		console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `\n     got:      ${actual}\n     expected: ${expected}`}`);
	};
	const root = new Set(["ability_item_usage_generic", "mode_farm_generic"]);
	const r = (line, kind = "runtime") => rewriteLine(line, kind, root);
	eq("require", r('local Fu = require(GetScriptDirectory() .. "/FuncLib/func_utils")'), 'local Fu = require(GetScriptDirectory() .. "/lib/func_utils")');
	eq("vendor", r('require(GetScriptDirectory() .. "/FuncLib/lib/json")'), 'require(GetScriptDirectory() .. "/lib/vendor/json")');
	eq("dofile hero", r('dofile(GetScriptDirectory() .. "/BotsLib/" .. name)'), 'dofile(GetScriptDirectory() .. "/heroes/" .. name)');
	eq("dotted", r('require("bots.FuncLib.systems.custom_loader")'), 'require("bots.lib.systems.custom_loader")');
	eq("dotted customize", r('require("bots.Customize.general")'), 'require("bots.customize.general")');
	eq("game folder", r('local p = "game/Customize/general"'), 'local p = "game/customize/general"');
	eq("comment path", r("-- see FuncLib/systems/perf.lua"), "-- see bots/lib/systems/perf.lua");
	eq("identifier kept", r("Customize.Weak_Hero_Cap = 1; Fu.Customize = x; LoadCustomize()"), "Customize.Weak_Hero_Cap = 1; Fu.Customize = x; LoadCustomize()");
	eq("tag", r('print("[OHA-PERF] t=1")'), 'print("[SHy-PERF] t=1")');
	eq("lua pattern tag", r('"^%[OHA%-PERF%]"'), '"^%[SHy%-PERF%]"');
	eq("bare tag", r('Perf.Format("OHA-PERF", now)'), 'Perf.Format("SHy-PERF", now)');
	eq("name suffix kept", r('TeamNames.defaultPostfix = "OHA-DEV"'), 'TeamNames.defaultPostfix = "OHA-DEV"');
	eq("keep marker", r('"game/Customize/general", -- restructure:keep'), '"game/Customize/general", -- restructure:keep');
	eq("windows log path", r("vscripts\\bots\\BotsLib\\hero_wisp.lua:12", "text"), "vscripts\\bots\\heroes\\hero_wisp.lua:12");
	eq("installer", r('xcopy "%~dp0..\\Customize\\" "x\\game\\Customize\\"', "text"), 'xcopy "%~dp0..\\customize\\" "x\\game\\customize\\"');
	eq("test read", r('T.read("FuncLib/systems/item.lua")', "lua"), 'T.read("bots/lib/systems/item.lua")');
	eq("test files", r('T.files("^BotsLib/hero_[%w_]+%.lua$")', "lua"), 'T.files("^bots/heroes/hero_[%w_]+%.lua$")');
	eq("test load", r('Stub.load("BotsLib/" .. file)', "lua"), 'Stub.load("bots/heroes/" .. file)');
	eq("test root file", r('dofile("ability_item_usage_generic.lua")', "lua"), 'dofile("bots/ability_item_usage_generic.lua")');
	eq("test root module kept", r('Stub.load("ability_item_usage_generic")', "lua"), 'Stub.load("ability_item_usage_generic")');
	eq("test dirs", r('if not string.find(path, "^Tests/") and not string.find(path, "^Util/") then', "lua"), 'if not string.find(path, "^tests/") and not string.find(path, "^tools/") then');
	eq("js join", r('path.join(ROOT, "Customize", "general.lua")', "js"), 'path.join(ROOT, "bots/customize", "general.lua")');
	eq("js repo path", r('REPO + "/BotsLib/" + f', "js"), 'REPO + "/bots/heroes/" + f');
	eq("js regex tag", r("const TAG = /\\[(OHA-[A-Z0-9_]+)\\]/;", "js"), "const TAG = /\\[(SHy-[A-Z0-9_]+)\\]/;");
	eq("js comment on a Lua path", r('// Paths built at run time ("/BotsLib/" .. heroFile) are skipped', "js"), '// Paths built at run time ("/heroes/" .. heroFile) are skipped');
	eq("check: a JS regex on the Customize table is not a path", CHECKS.some((c) => c.re.test("const cap = /Customize\\.Weak_Hero_Cap\\s*=/")), false);
	eq("js tests dir", r('path.join(__dirname, "..", "Tests", "data")', "js"), 'path.join(__dirname, "..", "tests", "data")');
	eq("doc", r("`node Util/verify.js` writes `Util/verify/tracker.json`", "text"), "`node tools/verify.js` writes `local/verify/tracker.json`");
	eq("doc logs", r("Util/match-logs/game-001.log and Util/item-builds/cache/", "text"), "local/match-logs/game-001.log and local/item-builds/cache/");
	eq("installer folder", r("Install-to-vscript/README.md", "text"), "install/README.md");
	eq("idempotent", r(r('require(GetScriptDirectory() .. "/FuncLib/lib/json") -- [OHA-X] FuncLib/x')), r('require(GetScriptDirectory() .. "/FuncLib/lib/json") -- [OHA-X] FuncLib/x'));
	for (const c of CHECKS) {
		if (c.what === "old log tag") eq("check: a normaliser written as \\[OHA(?=-) is not a finding", c.re.test("/\\[OHA(?=-)/g"), false);
	}
	console.log(failed === 0 ? "self-test passed" : `self-test: ${failed} failed`);
	return failed === 0;
}

// ---------------------------------------------------------------- command line

function parseArgs(argv) {
	const args = { dryRun: false };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--check") args.mode = "check";
		else if (a === "--move-local") args.mode = "move-local";
		else if (a === "--migrate-branch") args.mode = "migrate-branch";
		else if (a === "--self-test") args.mode = "self-test";
		else if (a === "--dry-run") args.dryRun = true;
		else if (a === "--stylua") args.stylua = argv[++i];
		else if (a === "--main") args.main = argv[++i];
		else if (a === "--help" || a === "-h") args.mode = "help";
		else throw new Error(`unknown option ${a} (see --help)`);
	}
	return args;
}

if (require.main === module) {
	try {
		const args = parseArgs(process.argv.slice(2));
		if (args.mode === "help") {
			const head = fs.readFileSync(__filename, "utf8").split(/\r?\n/).slice(1);
			console.log(head.filter((l) => l.startsWith("//")).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
		} else if (args.mode === "self-test") {
			process.exit(selfTest() ? 0 : 1);
		} else {
			ROOT = topLevel(process.cwd());
			if (args.mode === "check") process.exit(check().length === 0 ? 0 : 1);
			else if (args.mode === "move-local") moveLocal({ dryRun: args.dryRun });
			else if (args.mode === "migrate-branch") migrateBranch(args);
			else migrate(args);
		}
	} catch (err) {
		console.error(`restructure: ${err.message}`);
		process.exit(1);
	}
}

module.exports = { rewriteLine, rewriteText, newPathOf, CHECKS };
