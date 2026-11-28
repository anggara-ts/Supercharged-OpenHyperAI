// Column-0 local count for the five root scripts the engine loads as one chunk each.
// Lua allows 200 locals in a chunk. A top-level `do` adds its own locals on top of every
// chunk local already declared. This is not a Lua parse: it counts `local` at column 0,
// and `local` indented one tab while a column-0 `do` is open.
const fs = require("fs");
const path = require("path");

const WARN_AT = 180;
const REFUSE_AT = 195;

const ROOT_FILES = new Set([
	"ability_item_usage_generic.lua",
	"bot_generic.lua",
	"hero_selection.lua",
	"item_purchase_generic.lua",
]);

function isRootChunk(name) {
	const base = name.split(/[/\\]/).pop();
	if (name.includes("/") || name.includes("\\")) return false;
	return ROOT_FILES.has(base) || /^mode_.*_generic\.lua$/.test(base);
}

function codeOf(line) {
	let out = "";
	let quote = null;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (quote) {
			if (c === "\\") {
				i++;
				continue;
			}
			if (c === quote) quote = null;
			continue;
		}
		if (c === '"' || c === "'") {
			quote = c;
			continue;
		}
		if (c === "-" && line[i + 1] === "-") break;
		out += c;
	}
	return out;
}

function namesInLocal(code) {
	const m = code.match(/^local\s+(.+)$/);
	if (!m) return [];
	let rest = m[1];
	if (rest.startsWith("function ")) {
		const n = rest.slice(9).match(/^([A-Za-z_][A-Za-z0-9_]*)/);
		return n ? [n[1]] : [];
	}
	rest = rest.split("=")[0];
	return rest
		.split(",")
		.map((s) => s.trim())
		.filter((s) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(s));
}

// Peak locals in scope: column-0 locals declared so far, plus locals of a column-0 do
// block while that block is open.
function peakOf(src) {
	const lines = String(src).split(/\n/);
	let chunk = 0;
	let bestN = 0;
	let bestLine = 1;
	let bestExtra = 0;
	let inDo = false;
	let doLocals = 0;
	for (let i = 0; i < lines.length; i++) {
		const raw = lines[i].replace(/\r$/, "");
		const t = codeOf(raw);
		if (!inDo && raw === "do") {
			inDo = true;
			doLocals = 0;
		} else if (inDo && raw === "end") {
			const closed = chunk + doLocals;
			if (closed >= bestN) {
				bestN = closed;
				bestLine = i + 1;
				bestExtra = doLocals;
			}
			inDo = false;
		} else if (!inDo && /^local\b/.test(raw) && /^local\b/.test(t)) {
			chunk += namesInLocal(t).length;
		} else if (inDo && /^\tlocal\b/.test(raw) && !/^\t\t/.test(raw)) {
			const inner = codeOf(raw.replace(/^\t/, ""));
			if (/^local\b/.test(inner)) doLocals += namesInLocal(inner).length;
		}
		const here = chunk + (inDo ? doLocals : 0);
		if (here >= bestN) {
			bestN = here;
			bestLine = i + 1;
			bestExtra = inDo ? doLocals : 0;
		}
	}
	return { peak: bestN, line: bestLine, extra: bestExtra, chunk };
}

function checkSources(sources) {
	const refused = [];
	for (const source of sources) {
		const result = peakOf(source.text);
		const text = `${source.name}:${result.line} peak=${result.peak} (column-0 locals ${result.chunk}, do-block locals in that peak ${result.extra})`;
		if (result.peak >= REFUSE_AT) refused.push(text);
		else if (result.peak >= WARN_AT) console.log(`locals: warning ${text} (warn at ${WARN_AT})`);
	}
	if (refused.length > 0) {
		throw new Error(
			`refusing: a root bot script is at ${REFUSE_AT} chunk locals or more (Lua's limit is 200):\n` +
				refused.map((line) => `  ${line}`).join("\n"),
		);
	}
}

function checkDir(dir) {
	const names = fs.readdirSync(dir).filter((name) => isRootChunk(name));
	checkSources(
		names.map((name) => ({
			name,
			text: fs.readFileSync(path.join(dir, name), "utf8"),
		})),
	);
}

// Export map keys are paths inside the bots copy (no bots/ prefix).
function checkMap(files) {
	const sources = [];
	for (const [name, body] of files) {
		if (!isRootChunk(name)) continue;
		sources.push({ name, text: Buffer.isBuffer(body) ? body.toString("utf8") : String(body) });
	}
	checkSources(sources);
}

module.exports = { WARN_AT, REFUSE_AT, isRootChunk, peakOf, checkSources, checkDir, checkMap };
