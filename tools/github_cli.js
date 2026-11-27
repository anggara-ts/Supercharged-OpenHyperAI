"use strict";
// Which GitHub CLI binary the tools run. gh_personal is the anggara-ts login and
// wins whenever it is on PATH. GH, then plain gh, are only the fallback.
const fs = require("fs");
const path = require("path");

function onPath(name) {
	const exts = process.platform === "win32" ? ["", ".exe", ".cmd", ".bat"] : [""];
	for (const dir of (process.env.PATH || "").split(path.delimiter)) {
		if (!dir) continue;
		for (const ext of exts) {
			try {
				fs.accessSync(path.join(dir, name + ext));
				return true;
			} catch (_err) {
				// next directory
			}
		}
	}
	return false;
}

function githubCli() {
	if (onPath("gh_personal")) return "gh_personal";
	if (process.env.GH) return process.env.GH;
	return "gh";
}

module.exports = githubCli;
