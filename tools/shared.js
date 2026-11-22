// Shared by the tools: where the local data lives, and the log tag rename of #221.
"use strict";
const path = require("path");

// Git-ignored local data: match logs, the verify tracker, generated reports and caches (#221).
const LOCAL_DIR = path.join(__dirname, "..", "local");

// The bots print [SHy-<TAG>] since #221; before that the same tags had the OHA prefix. Old match logs, tracker items
// and the "How to verify in game" lists of older PRs quote the old form, so every tool that reads a log line or a
// pattern passes it through normTags first and then only knows [SHy-...]. The old prefix is written so that it is not
// itself an old tag (tools/restructure.js --check).
const OLD_PREFIX = /\[OHA(?=-)/g;
const OLD_LUA_PREFIX = /%\[OHA(?=%-)/g;

function normTags(text) {
	return String(text).replace(OLD_PREFIX, "[SHy").replace(OLD_LUA_PREFIX, "%[SHy");
}

module.exports = { LOCAL_DIR, normTags };
