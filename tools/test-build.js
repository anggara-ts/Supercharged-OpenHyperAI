#!/usr/bin/env node
// Integration branch for one test game: every PR in the verify tracker merged onto origin/main.
//
//   node tools/test-build.js [--dry-run] [--no-switch]
//
// 1. git fetch --prune origin (also in --dry-run: updates origin/* and drops deleted remote branches).
// 2. Builds the LOCAL branch `test/next` (never pushed) = origin/main + each tracked PR branch
//    (local/verify/tracker.json, ascending PR number) merged with `git merge --no-edit --no-ff origin/<branch>`.
//    The merges run in a temporary detached worktree, so your working tree, index and HEAD are not touched
//    while it builds. A PR that conflicts is aborted (`git merge --abort`) and skipped.
//    A PR branch still on the layout before #221 (its bot scripts outside bots/) is skipped as "needs
//    migration": it would merge, but its new files would sit outside bots/ and never load. Migrate it with
//    node tools/restructure.js --migrate-branch (on that branch). A PR that merges but brings old paths or log tags
//    (tools/restructure.js --check fails after its merge) is skipped the same way (not in --dry-run).
// 3. Writes local/verify/test-build.json: { base, head, builtAt, included, upToDate, conflicts, missing, needsMigration }.
// 4. Switches the working tree to test/next (the game runs the checked-out tree) unless --no-switch.
//    Only bots/customize/general.lua (the local test lineup) may be modified: it is carried across the switch
//    (a copy is kept in local/verify/general.lua.bak). Any other modified tracked file stops the switch.
//    The first switch from a tree on the old layout carries the old lineup file to bots/customize/general.lua.
//
// Runs on the repo of the current directory, so the first build after the layout change can run main's copy
// from a tree that is still on the old layout (after tools/restructure.js --move-local):
//   git show origin/main:tools/test-build.js > ../test-build.js && node ../test-build.js
//
// --dry-run   fetch, then report what would merge or conflict (git merge-tree: no commits, no branch, no files).
// --no-switch build test/next but stay on the current branch.
// --with <branch>  also merge this origin branch (repeatable), after the tracked PRs: e.g. a tooling PR that
//             isn't tracked (nothing to see in game) but whose files you need on test/next, such as
//             tools/after-game.js before it reaches main.
//
// Afterwards: play the game, then `node tools/verify.js check <log> --game NNN`. Go back with `git switch <branch>`.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

// The repo of the current directory (not of this file: see the header).
const ROOT = cp.execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const DATA = path.join(ROOT, "local", "verify");
const TRACKER = path.join(DATA, "tracker.json");
const OUT = path.join(DATA, "test-build.json");
const BRANCH = "test/next";
const LINEUP = "bots/customize/general.lua";
// The lineup's place before the layout change of #221.
const LINEUP_OLD = "Customize/general.lua"; // restructure:keep
const LINEUPS = [LINEUP, LINEUP_OLD];

const args = process.argv.slice(2);
const DRY = args.includes("--dry-run");
const NO_SWITCH = args.includes("--no-switch");

function git(a, opts = {}) {
	const r = cp.spawnSync("git", a, { cwd: opts.cwd || ROOT, encoding: "utf8" });
	if (r.status !== 0 && !opts.allowFail) {
		throw new Error(`git ${a.join(" ")} failed (${r.status}):\n${(r.stderr || "") + (r.stdout || "")}`.trim());
	}
	return opts.allowFail ? r : r.stdout.trim();
}

function trackedPrs() {
	let db;
	try {
		db = JSON.parse(fs.readFileSync(TRACKER, "utf8"));
	} catch (e) {
		throw new Error(`cannot read ${path.relative(ROOT, TRACKER)}: ${e.message}`);
	}
	const list = Object.entries(db.prs || {})
		.map(([n, p]) => ({ n: Number(n), branch: p.branch, title: p.title }))
		.filter((p) => p.branch)
		.sort((a, b) => a.n - b.n);
	// --with <branch>: extra branches merged after the tracked PRs (n = the branch name: not a tracked PR).
	for (let i = 0; i < args.length; i++) {
		if (args[i] === "--with" && args[i + 1] && !list.some((p) => p.branch === args[i + 1])) {
			list.push({ n: args[i + 1], branch: args[i + 1], title: `(--with) ${args[i + 1]}` });
		}
	}
	return list;
}

// Modified tracked files other than the test lineup (untracked files are ignored).
function otherChanges() {
	return git(["status", "--porcelain", "--untracked-files=no"], { allowFail: true })
		.stdout.split(/\r?\n/)
		.filter(Boolean)
		.map((l) => l.slice(3).replace(/^"|"$/g, ""))
		.filter((f) => !LINEUPS.includes(f));
}

// A branch from before the layout change of #221 that was not migrated yet (tools/restructure.js --migrate-branch).
function oldLayout(ref) {
	return git(["cat-file", "-e", `${ref}:FuncLib`], { allowFail: true }).status === 0; // restructure:keep
}

// null when tools/restructure.js --check passes in that tree (or the tree has no such tool), else its first finding.
function layoutFindings(cwd) {
	const tool = path.join(cwd, "tools", "restructure.js");
	if (!fs.existsSync(tool)) return null;
	const r = cp.spawnSync(process.execPath, [tool, "--check"], { cwd, encoding: "utf8" });
	if (r.status === 0) return null;
	const lines = (r.stdout || "").split(/\r?\n/).filter(Boolean);
	return `${lines[lines.length - 1] || "check failed"}; first: ${lines[0] || "?"}`;
}

function remoteExists(branch) {
	return git(["rev-parse", "--verify", "--quiet", `refs/remotes/origin/${branch}`], { allowFail: true }).status === 0;
}

function isAncestor(a, b, cwd) {
	return git(["merge-base", "--is-ancestor", a, b], { allowFail: true, cwd }).status === 0;
}

// --dry-run: chain the merges as trees with `git merge-tree --write-tree` (git >= 2.40); nothing is written
// except loose tree/blob objects. The merge base of each step is the base between the PR branch and the
// hypothetical merge of origin/main with every PR merged before it, which is what a real merge would use.
function dryRun(prs, result) {
	let tree = git(["rev-parse", "origin/main^{tree}"]);
	const merged = ["origin/main"];
	for (const p of prs) {
		const ref = `origin/${p.branch}`;
		if (!remoteExists(p.branch)) {
			result.missing.push(p.n);
			console.log(`#${p.n} ${p.branch}: MISSING (no origin/${p.branch})`);
			continue;
		}
		if (merged.some((m) => isAncestor(ref, m))) {
			result.upToDate.push(p.n);
			console.log(`#${p.n} ${p.branch}: already contained (nothing to merge)`);
			continue;
		}
		if (oldLayout(ref)) {
			result.needsMigration.push(p.n);
			console.log(`#${p.n} ${p.branch}: NEEDS MIGRATION (old layout, skipped): node tools/restructure.js --migrate-branch`);
			continue;
		}
		const base = git(["merge-base", ref, ...merged]).split(/\r?\n/)[0];
		const r = git(["merge-tree", "--write-tree", "--name-only", `--merge-base=${base}`, tree, ref], { allowFail: true });
		if (r.status === 0) {
			tree = r.stdout.trim().split(/\r?\n/)[0];
			merged.push(ref);
			result.included.push(p.n);
			console.log(`#${p.n} ${p.branch}: merges cleanly`);
		} else if (r.status === 1) {
			// output: tree oid, conflicted file names, blank line, messages
			const files = r.stdout.split(/\r?\n\r?\n/)[0].split(/\r?\n/).slice(1).filter(Boolean);
			result.conflicts.push(p.n);
			console.log(`#${p.n} ${p.branch}: CONFLICT (skipped) in ${files.join(", ")}`);
		} else {
			throw new Error(`git merge-tree failed for ${ref}:\n${r.stderr}`);
		}
	}
}

function build(prs, result) {
	const wt = fs.mkdtempSync(path.join(os.tmpdir(), "oha-test-build-"));
	fs.rmdirSync(wt); // git worktree add wants to create it
	try {
		// --no-checkout + reset --hard: a post-checkout hook in the temp tree (pre-commit without its config on
		// origin/main) would otherwise fail the add
		git(["worktree", "add", "--detach", "--no-checkout", "--quiet", wt, "origin/main"]);
		git(["reset", "--hard", "--quiet"], { cwd: wt });
		// Old paths or log tags a PR brought in (an old-layout branch merged with main by hand still has its own
		// requires of the old paths): tools/restructure.js --check after each merge, if main itself passes it.
		const checkLayout = layoutFindings(wt) === null;
		for (const p of prs) {
			const ref = `origin/${p.branch}`;
			if (!remoteExists(p.branch)) {
				result.missing.push(p.n);
				console.log(`#${p.n} ${p.branch}: MISSING (no origin/${p.branch})`);
				continue;
			}
			if (isAncestor(ref, "HEAD", wt)) {
				result.upToDate.push(p.n);
				console.log(`#${p.n} ${p.branch}: already contained (nothing to merge)`);
				continue;
			}
			if (oldLayout(ref)) {
				result.needsMigration.push(p.n);
				console.log(`#${p.n} ${p.branch}: NEEDS MIGRATION (old layout, skipped): node tools/restructure.js --migrate-branch`);
				continue;
			}
			const r = git(["merge", "--no-edit", "--no-ff", "-m", `Merge ${ref} (#${p.n}) into ${BRANCH}`, ref], {
				cwd: wt,
				allowFail: true,
			});
			if (r.status === 0) {
				const findings = checkLayout ? layoutFindings(wt) : null;
				if (findings) {
					git(["reset", "--hard", "--quiet", "HEAD^1"], { cwd: wt });
					result.needsMigration.push(p.n);
					console.log(`#${p.n} ${p.branch}: NEEDS MIGRATION (merges, but brings old paths or tags; skipped): ${findings}`);
					continue;
				}
				result.included.push(p.n);
				console.log(`#${p.n} ${p.branch}: merged`);
				continue;
			}
			const unmerged = git(["diff", "--name-only", "--diff-filter=U"], { cwd: wt, allowFail: true }).stdout.trim();
			git(["merge", "--abort"], { cwd: wt, allowFail: true });
			if (!unmerged) {
				// not a conflict (signing, hooks, ...): stop rather than silently skipping the PR
				throw new Error(`merging ${ref} failed without a conflict:\n${(r.stderr || "") + (r.stdout || "")}`);
			}
			result.conflicts.push(p.n);
			console.log(`#${p.n} ${p.branch}: CONFLICT (skipped) in ${unmerged.split(/\r?\n/).join(", ")}`);
		}
		require("./lua_locals").checkDir(path.join(wt, "bots"));
		result.head = git(["rev-parse", "HEAD"], { cwd: wt });
	} finally {
		git(["worktree", "remove", "--force", wt], { allowFail: true });
		git(["worktree", "prune"], { allowFail: true });
	}
	const current = git(["symbolic-ref", "--quiet", "--short", "HEAD"], { allowFail: true }).stdout.trim();
	if (current === BRANCH) {
		// already on test/next (an earlier build): move it, keeping the local lineup edit
		carryLineup(result.head, () => git(["reset", "--keep", result.head]));
	} else {
		git(["branch", "-f", BRANCH, result.head]);
	}
	return current;
}

// git switch exits non-zero when a post-checkout hook fails although the switch happened: check the branch.
function switchBranch() {
	const r = git(["switch", BRANCH], { allowFail: true });
	if (r.status === 0) return;
	const now = git(["symbolic-ref", "--quiet", "--short", "HEAD"], { allowFail: true }).stdout.trim();
	if (now !== BRANCH) throw new Error(`git switch ${BRANCH} failed:\n${r.stderr}`);
	console.log(`warning: switched, but a post-checkout hook failed:\n${r.stderr.trim()}`);
}

// Runs move() (a switch or reset to `target`) carrying the local lineup edit: the edited lineup is copied to
// local/verify/general.lua.bak, put back to HEAD's version, and after the move written to the lineup path of the
// new commit (bots/customize/general.lua, or LINEUP_OLD on a commit from before #221).
function carryLineup(target, move) {
	const dirty = LINEUPS.find((file) => git(["status", "--porcelain", "--", file]).length > 0);
	if (!dirty) {
		move();
		return;
	}
	const content = fs.readFileSync(path.join(ROOT, dirty));
	fs.mkdirSync(DATA, { recursive: true });
	const backup = path.join(DATA, "general.lua.bak");
	fs.writeFileSync(backup, content);
	git(["checkout", "HEAD", "--", dirty]);
	try {
		move();
	} catch (e) {
		fs.writeFileSync(path.join(ROOT, dirty), content);
		throw e;
	}
	const inTarget = git(["cat-file", "-e", `${target}:${LINEUP}`], { allowFail: true }).status === 0;
	const dest = inTarget ? LINEUP : LINEUP_OLD;
	fs.mkdirSync(path.dirname(path.join(ROOT, dest)), { recursive: true });
	fs.writeFileSync(path.join(ROOT, dest), content);
	console.log(`(lineup ${dirty} carried over to ${dest}; copy kept in ${path.relative(ROOT, backup)})`);
}

// Switch to test/next carrying the local lineup.
function switchTo() {
	carryLineup(BRANCH, switchBranch);
}

function main() {
	const others = otherChanges();
	if (others.length) {
		const msg = `modified tracked files besides ${LINEUP}: ${others.join(", ")}`;
		if (!DRY && !NO_SWITCH) throw new Error(`refusing to switch: ${msg}\ncommit or stash them first`);
		console.log(`warning: ${msg} (would refuse without --dry-run / --no-switch)`);
	}
	const prs = trackedPrs();
	if (!prs.length) throw new Error("no PRs in the tracker (node tools/verify.js add <pr>)");
	console.log(`fetching origin ...`);
	git(["fetch", "--quiet", "--prune", "origin"]);
	const result = {
		base: git(["rev-parse", "origin/main"]),
		head: null,
		builtAt: new Date().toISOString(),
		included: [],
		upToDate: [],
		conflicts: [],
		missing: [],
		needsMigration: [],
	};
	console.log(`base origin/main ${result.base.slice(0, 10)}; PRs: ${prs.map((p) => `#${p.n}`).join(" ")}`);
	if (DRY) {
		dryRun(prs, result);
		console.log(`\ndry run: would build ${BRANCH} with ${result.included.map((n) => `#${n}`).join(" ") || "nothing"}` +
			(result.conflicts.length ? `; conflicting: ${result.conflicts.map((n) => `#${n}`).join(" ")}` : "") +
			(result.needsMigration.length ? `; needs migration: ${result.needsMigration.map((n) => `#${n}`).join(" ")}` : ""));
		return;
	}
	const current = build(prs, result);
	fs.mkdirSync(DATA, { recursive: true });
	fs.writeFileSync(OUT, JSON.stringify(result, null, 2) + "\n");
	console.log(`\n${BRANCH} = ${result.head.slice(0, 10)}  included: ${result.included.map((n) => `#${n}`).join(" ") || "none"}` +
		(result.conflicts.length ? `  CONFLICTS: ${result.conflicts.map((n) => `#${n}`).join(" ")}` : "") +
		(result.missing.length ? `  missing: ${result.missing.map((n) => `#${n}`).join(" ")}` : "") +
		(result.needsMigration.length ? `  NEEDS MIGRATION: ${result.needsMigration.map((n) => `#${n}`).join(" ")}` : ""));
	console.log(`wrote ${path.relative(ROOT, OUT)}`);
	if (NO_SWITCH || current === BRANCH) {
		console.log(current === BRANCH ? `working tree is on ${BRANCH}` : `staying on ${current || "detached HEAD"} (--no-switch)`);
		return;
	}
	switchTo();
	console.log(`switched to ${BRANCH} (from ${current || "detached HEAD"}); go back with: git switch ${current || "<branch>"}`);
}

try {
	main();
} catch (e) {
	console.error(e.message);
	process.exit(1);
}
