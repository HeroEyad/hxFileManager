// hxdoc - tiny api doc generator for haxe
// usage: node hxdoc.js <srcDir> <outDir> [--title "My Library"]
// parses .hx files, reads doc comments + signatures.
// the result? you get htmls for each class.

const fs = require("fs");
const path = require("path");

// client

const args = process.argv.slice(2);
if (args.length < 2) {
	console.log('usage: node hxdoc.js <srcDir> <outDir> [--title "My Library"]');
	process.exit(1);
}
const SRC = path.resolve(args[0]);
const OUT = path.resolve(args[1]);
const TITLE = (() => {
	const i = args.indexOf("--title");
	return i !== -1 && args[i + 1] ? args[i + 1] : "HxFileManager API Documentation";
})();


// scan the directory for any hx file
function findHxFiles(dir) {
	let out = [];
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) out = out.concat(findHxFiles(full));
		else if (entry.name.endsWith(".hx")) out.push(full);
	}
	return out;
}

// le parser

function parseFile(source, filePath) {
	const pkg = (source.match(/^\s*package\s+([\w.]*)\s*;/m) || [])[1] || "";
	const classes = [];

	let i = 0;
	let pendingDoc = null;
	let pendingMeta = [];
	let currentClass = null;
	let braceDepth = 0;
	let classDepth = -1;

	const len = source.length;

	function skipLineComment() { while (i < len && source[i] !== "\n") i++; }

	function readBlockComment() {
		const start = i;
		i += 2;
		while (i < len && !(source[i] === "*" && source[i + 1] === "/")) i++;
		i += 2;
		return source.slice(start, i);
	}

	function readString(quote) {
		i++;
		while (i < len && source[i] !== quote) {
			if (source[i] === "\\") i++;
			i++;
		}
		i++;
	}

	function readBalanced(open, close) {
		// assumes source[i] === open, returns content inside, leaves i after close
		let depth = 0;
		const start = i;
		while (i < len) {
			const c = source[i];
			if (c === '"' || c === "'") { readString(c); continue; }
			if (c === open) depth++;
			else if (c === close) { depth--; if (depth === 0) { i++; break; } }
			i++;
		}
		return source.slice(start + 1, i - 1);
	}

	function skipStringAt(j) {
		const q = source[j];
		j++;
		while (j < len && source[j] !== q) {
			if (source[j] === "\\") j++;
			j++;
		}
		return j + 1;
	}

	function declStartBefore(pos) {
		// start of the declaration line, after the previous statement or doc comment
		const region = source.slice(0, pos);
		const cands = [region.lastIndexOf(";"), region.lastIndexOf("}"), region.lastIndexOf("{")];
		const cm = region.lastIndexOf("*/");
		if (cm !== -1) cands.push(cm + 1);
		let start = Math.max(...cands) + 1;
		while (start < pos && /\s/.test(source[start])) start++;
		return start;
	}

	function findBodyEnd(from) {
		// end index (exclusive) of a function body starting at or after `from`,
		// either a balanced { } block or an expression body ending in ;
		let j = from;
		while (j < len && /\s/.test(source[j])) j++;
		let d = 0;
		const block = source[j] === "{";
		while (j < len) {
			const ch = source[j];
			if (ch === '"' || ch === "'") { j = skipStringAt(j); continue; }
			if (ch === "/" && source[j + 1] === "/") { while (j < len && source[j] !== "\n") j++; continue; }
			if (ch === "/" && source[j + 1] === "*") { j += 2; while (j < len && !(source[j] === "*" && source[j + 1] === "/")) j++; j += 2; continue; }
			if (ch === "{" || ch === "(" || ch === "[") d++;
			else if (ch === "}" || ch === ")" || ch === "]") {
				d--;
				if (block && ch === "}" && d === 0) return j + 1;
			}
			else if (!block && ch === ";" && d <= 0) return j + 1;
			j++;
		}
		return j;
	}

	function dedent(code) {
		const lines = code.split("\n");
		let min = Infinity;
		for (const l of lines) {
			if (!l.trim()) continue;
			const m = l.match(/^[\t ]*/)[0].length;
			if (m < min) min = m;
		}
		if (!isFinite(min) || min === 0) return code; // O' Math.isNaN... where were you when i needed you...?
		return lines.map(l => l.slice(min)).join("\n");
	}

	function modifiersBefore(pos) {
		// only the raw code between the previous comment and this keyword
		let tail = source.slice(Math.max(0, pos - 200), pos);
		const cm = tail.lastIndexOf("*/");
		if (cm !== -1) tail = tail.slice(cm + 2);
		tail = tail.split(";").pop().split("}").pop().split("{").pop();
		return {
			isPublic: /\bpublic\b/.test(tail),
			isPrivate: /\bprivate\b/.test(tail),
			isStatic: /\bstatic\b/.test(tail),
			isInline: /\binline\b/.test(tail)
		};
	}

	function readType() {
		// it reads a type annotation after ':' handling <>, {}, ->
		// and stops at a function body '{', at ';', '=', or at end of line so it
		// also it never eats braces that belong to code (that desyncs depth tracking)
		// with that being said i forgot i have a pure math exam tommorow
		// update: it was fucking bad
		let out = "";
		let angle = 0, brace = 0, paren = 0;
		const atTop = () => angle === 0 && brace === 0 && paren === 0;
		while (i < len) {
			const c = source[i];
			if (c === "<") angle++;
			else if (c === ">") {
				if (source[i - 1] !== "-") { // not part of ->
					if (angle === 0) break;
					angle--;
				}
			}
			else if (c === "(") paren++;
			else if (c === ")") { if (paren === 0) break; paren--; }
			else if (c === "{") {
				// anon struct only if it's the start of the type or nested in one,
				// otherwise it's a block body and the type ends here
				if (atTop() && out.trim() !== "") break;
				brace++;
			}
			else if (c === "}") { if (brace === 0) break; brace--; }
			else if ((c === ";" || c === "=" || c === ",") && atTop()) break;
			else if (c === "\n" && atTop() && out.trim() !== "") break; // expression-bodied fn
			out += c;
			i++;
		}
		return out.trim();
	}

	while (i < len) {
		const c = source[i];

		if (c === "/" && source[i + 1] === "/") { skipLineComment(); continue; }
		if (c === "/" && source[i + 1] === "*") {
			const block = readBlockComment();
			if (block.startsWith("/**")) pendingDoc = block;
			continue;
		}
		if (c === '"' || c === "'") { readString(c); continue; }

		if (c === "@") {
			// metadata like @:deprecated("...") or @:noCompletion
			let s = i;
			i++;
			if (source[i] === ":") i++;
			while (i < len && /[\w]/.test(source[i])) i++;
			let meta = source.slice(s, i);
			if (source[i] === "(") meta += "(" + readBalanced("(", ")") + ")";
			pendingMeta.push(meta);
			continue;
		}

		if (c === "{") { braceDepth++; i++; continue; }
		if (c === "}") {
			braceDepth--;
			if (currentClass && braceDepth <= classDepth) { currentClass = null; classDepth = -1; }
			i++;
			continue;
		}

		// keywords
		if (/[a-zA-Z_]/.test(c)) {
			let s = i;
			while (i < len && /[\w]/.test(source[i])) i++;
			const word = source.slice(s, i);

			if ((word === "class" || word === "enum" || word === "interface" || word === "abstract" || word === "typedef") && braceDepth === 0) {
				const cmods = modifiersBefore(s);
				// read name
				while (i < len && /\s/.test(source[i])) i++;
				let ns = i;
				while (i < len && /[\w]/.test(source[i])) i++;
				const name = source.slice(ns, i);
				currentClass = {
					kind: word,
					name,
					pkg,
					file: filePath,
					doc: cleanDoc(pendingDoc),
					meta: pendingMeta,
					fields: []
				};
				if (!cmods.isPrivate) classes.push(currentClass);
				pendingDoc = null;
				pendingMeta = [];
				// class body starts at next '{'
				classDepth = braceDepth;
				continue;
			}

			if (word === "function" && currentClass && braceDepth === classDepth + 1) {
				const mods = modifiersBefore(s);
				while (i < len && /\s/.test(source[i])) i++;
				let ns = i;
				while (i < len && /[\w]/.test(source[i])) i++;
				const name = source.slice(ns, i);
				while (i < len && /\s/.test(source[i])) i++;
				let argsRaw = "";
				if (source[i] === "(") argsRaw = readBalanced("(", ")");
				while (i < len && /\s/.test(source[i])) i++;
				let ret = "";
				if (source[i] === ":") { i++; ret = readType(); }

				const visible = mods.isPublic && !mods.isPrivate;
				if (name && visible) {
					const src = dedent(source.slice(declStartBefore(s), findBodyEnd(i)));
					currentClass.fields.push({
						kind: "function",
						name,
						args: parseArgs(argsRaw),
						ret: ret || "Void",
						isStatic: mods.isStatic,
						isInline: mods.isInline,
						src,
						doc: cleanDoc(pendingDoc),
						meta: pendingMeta
					});
				}
				pendingDoc = null;
				pendingMeta = [];
				continue;
			}

			if (word === "var" && currentClass && braceDepth === classDepth + 1) {
				const vm = modifiersBefore(s);
				const isPublic = vm.isPublic, isStatic = vm.isStatic;
				while (i < len && /\s/.test(source[i])) i++;
				let ns = i;
				while (i < len && /[\w]/.test(source[i])) i++;
				const name = source.slice(ns, i);
				while (i < len && /\s/.test(source[i])) i++;
				let access = "";
				if (source[i] === "(") access = readBalanced("(", ")");
				while (i < len && /\s/.test(source[i])) i++;
				let type = "";
				if (source[i] === ":") { i++; type = readType(); }
				if (name && isPublic) {
					currentClass.fields.push({
						kind: "var",
						name,
						type: type || "Dynamic",
						access,
						isStatic,
						doc: cleanDoc(pendingDoc),
						meta: pendingMeta
					});
				}
				pendingDoc = null;
				pendingMeta = [];
				continue;
			}

			if (word === "final" && currentClass && braceDepth === classDepth + 1) {
				const fm = modifiersBefore(s);
				const isPublic = fm.isPublic, isStatic = fm.isStatic;
				while (i < len && /\s/.test(source[i])) i++;
				let ns = i;
				while (i < len && /[\w]/.test(source[i])) i++;
				const name = source.slice(ns, i);
				while (i < len && /\s/.test(source[i])) i++;
				let type = "";
				if (source[i] === ":") { i++; type = readType(); }
				if (name && isPublic) {
					currentClass.fields.push({
						kind: "final",
						name,
						type: type || "Dynamic",
						isStatic,
						doc: cleanDoc(pendingDoc),
						meta: pendingMeta
					});
				}
				pendingDoc = null;
				pendingMeta = [];
				continue;
			}
			continue;
		}

		i++;
	}

	return classes.filter(c => c.kind !== "typedef" || c.fields.length);
}

function parseArgs(raw) {
	if (!raw.trim()) return [];
	// split on commas at depth 0
	const parts = [];
	let depth = 0, cur = "";
	for (let j = 0; j < raw.length; j++) {
		const ch = raw[j];
		if (ch === "<" || ch === "{" || ch === "(") depth++;
		else if ((ch === ">" && raw[j - 1] !== "-") || ch === "}" || ch === ")") depth--;
		if (ch === "," && depth === 0) { parts.push(cur); cur = ""; }
		else cur += ch;
	}
	if (cur.trim()) parts.push(cur);
	return parts.map(p => {
		p = p.trim();
		const optional = p.startsWith("?");
		if (optional) p = p.slice(1);
		const eq = splitTop(p, "=");
		const def = eq.length > 1 ? eq[1].trim() : null;
		const colon = splitTop(eq[0], ":");
		return {
			name: colon[0].trim(),
			type: colon[1] ? colon[1].trim() : "Dynamic",
			optional,
			def
		};
	});
}

function splitTop(str, sep) {
	const open = { "<": 1, "{": 1, "(": 1 };
	const close = { "}": 1, ")": 1, ">": 1 };

	let depth = 0;

	for (let i = 0; i < str.length; i++) {
		const ch = str[i];

		if (open[ch]) depth++;
		else if (close[ch] && (ch !== ">" || str[i - 1] !== "-")) depth--;
		else if (ch === sep && depth === 0) return [str.slice(0, i), str.slice(i + 1)];
	}

	return [str];
}

function cleanDoc(block) {
	if (!block) return null;

	const doc = { text: [], params: {}, returns: null, deprecated: null };

	for (const line of block.replace(/^\/\*\*|\*\/$/g, "").split("\n").map(l => l.replace(/^\s*\*\s?/, "").trimEnd())) {
		const tag = line.match(/^@(param|returns?|deprecated)\s*(.*)$/);

		if (!tag) {
			doc.text.push(line);
			continue;
		}

		const [, type, value] = tag;

		switch (type) {
			case "param": {
				const [, name, desc = ""] = value.match(/^(\w+)\s*(.*)$/) || [];
				if (name) doc.params[name] = desc;
				break;
			}
			case "return":
			case "returns":
				doc.returns = value;
				break;
			case "deprecated":
				doc.deprecated = value || "Deprecated.";
		}
	}

	doc.text = doc.text.join("\n").trim();
	return doc;
}

// html

const esc = s => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function typeHtml(t) {
	// hyperlink known class names, color the rest
	return esc(t).replace(/\b([A-Z]\w*)\b/g, (m, name) => {
		if (KNOWN.has(name)) return `<a class="type" href="${name}.html">${name}</a>`;
		return `<span class="type">${name}</span>`;
	});
}

function sigHtml(f) {
	if (f.kind === "function") {
		const argStr = f.args.map(a => `${a.optional ? "<span class='opt'>?</span>" : ""}<span class="arg">${esc(a.name)}</span>:${typeHtml(a.type)}${a.def ? `<span class="def"> = ${esc(a.def)}</span>` : ""}`).join(", ");
		return `${f.isStatic ? '<span class="kw">static</span> ' : ""}${f.isInline ? '<span class="kw">inline</span> ' : ""}<span class="kw">function</span> <span class="fname">${esc(f.name)}</span>(${argStr}):${typeHtml(f.ret)}`;
	}
	const kw = f.kind === "final" ? "final" : "var";
	return `${f.isStatic ? '<span class="kw">static</span> ' : ""}<span class="kw">${kw}</span> <span class="fname">${esc(f.name)}</span>${f.access ? `(${esc(f.access)})` : ""}:${typeHtml(f.type)}`;
}

function isDeprecated(f) {return (f.doc && f.doc.deprecated) || (f.meta || []).some(m => m.startsWith("@:deprecated"));}

function deprecationMsg(f) {
	if (f.doc && f.doc.deprecated) return f.doc.deprecated;
	const m = (f.meta || []).find(m => m.startsWith("@:deprecated"));
	if (m) {
		const inner = m.match(/\("(.*)"\)/);
		return inner ? inner[1] : "Deprecated.";
	}
	return "";
}

// the css of doom (will used in html under <style> inline)
const CSS = `
:root {
	--bg: #16181d; --fg: #d4d7dd; --muted: #8b93a1;
	--header: #0d0f12; --header2: #151a22; --accent: #4fa3ff;
	--sidebar: #1b1e24; --border: #2a2e37;
	--sig-bg: #1e222a; --kw: #ff7b72; --type: #d2a8ff; --fname: #79c0ff;
	--dep-bg: #2b2413; --dep-border: #6b5518;
	font-size: 15px;
}
* { box-sizing: border-box; }
body { margin: 0; font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif; color: var(--fg); background: var(--bg); }
code, .sig, .search { font-family: "JetBrains Mono", Consolas, Menlo, monospace; }
::selection { background: #2b4a75; }

header {
	background: linear-gradient(180deg, var(--header) 0%, var(--header2) 100%);
	color: #fff;
	padding: 14px 24px;
	display: flex;
	align-items: center;
	gap: 14px;
	position: sticky;
	top: 0;
	z-index: 10;
	border-bottom: 1px solid var(--border);
}

header .logo {
	width: 48px;
	height: auto;
	flex-shrink: 0;
	image-rendering: auto;
}

header h1 {
	font-size: 18px;
	margin: 0;
	font-weight: 600;
	letter-spacing: .3px;
}

header h1 a {
	color: #fff;
	text-decoration: none;
}

header .sub {
	display: block;
	color: #6d7686;
	font-size: 13px;
	margin-top: 2px;
}

.layout { display: flex; min-height: calc(100vh - 50px); }

nav {
	width: 270px; flex-shrink: 0; background: var(--sidebar);
	border-right: 1px solid var(--border); padding: 16px 0;
	position: sticky; top: 50px; height: calc(100vh - 50px); overflow-y: auto;
}
nav .search {
	display: block; width: calc(100% - 32px); margin: 0 16px 14px;
	padding: 7px 10px; border: 1px solid var(--border); border-radius: 5px;
	font-size: 13px; outline: none; background: #14161b; color: var(--fg);
}
nav .search::placeholder { color: #5b6272; }
nav .search:focus { border-color: var(--accent); }
nav .pkg { padding: 4px 16px; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .6px; }
nav ul { list-style: none; margin: 0 0 12px; padding: 0; }
nav li a {
	display: block; padding: 5px 16px 5px 28px; color: var(--fg);
	text-decoration: none; font-size: 14px; border-left: 3px solid transparent;
}
nav li a:hover { background: #23272f; }
nav li a.active { border-left-color: var(--accent); background: #23272f; font-weight: 600; }
nav li .k { color: var(--muted); font-size: 11px; margin-right: 6px; }
nav .mem { display: none; margin: 0; }
nav li.expanded > .mem { display: block; }
nav .mem > li { display: none; }
nav .mem > li.mhit { display: block; }
nav .mem > li > a {
	padding: 3px 16px 3px 44px; font-size: 12.5px; color: var(--muted);
	font-family: Consolas, Menlo, monospace;
}
nav .mem > li > a:hover { color: var(--fg); }

main { flex: 1; padding: 28px 40px 80px; max-width: 1000px; }
main h1.classname { font-size: 26px; margin: 0 0 2px; font-weight: 600; color: #fff; }
main .pkgline { color: var(--muted); font-size: 13px; margin-bottom: 18px; }
main .pkgline code { color: #a5b4c8; }
main .classdoc { margin-bottom: 26px; line-height: 1.6; }
main h2.section {
	font-size: 13px; text-transform: uppercase; letter-spacing: .8px;
	color: var(--muted); border-bottom: 1px solid var(--border);
	padding-bottom: 6px; margin: 34px 0 6px;
}

.field { padding: 16px 0 18px; border-bottom: 1px solid var(--border); }
.field:target { background: #22262e; margin: 0 -14px; padding-left: 14px; padding-right: 14px; border-radius: 6px; }
.sig {
	background: var(--sig-bg); border: 1px solid var(--border); border-radius: 6px;
	padding: 10px 14px; font-size: 13.5px; overflow-x: auto; white-space: pre-wrap; word-break: break-word;
}
.fold { margin: 0; }
summary.sig { list-style: none; cursor: pointer; position: relative; padding-left: 30px; }
summary.sig::-webkit-details-marker { display: none; }
summary.sig::before {
	content: ""; position: absolute; left: 13px; top: 16px;
	width: 0; height: 0;
	border-left: 6px solid var(--muted); border-top: 5px solid transparent; border-bottom: 5px solid transparent;
	transition: transform .12s ease;
}
.fold[open] summary.sig::before { transform: rotate(90deg); border-left-color: var(--accent); }
summary.sig:hover { border-color: #3a4150; }
summary.sig:hover::before { border-left-color: var(--fg); }
.fold[open] summary.sig { border-bottom-left-radius: 0; border-bottom-right-radius: 0; border-bottom-color: transparent; }
.fold .srccode { border-top-left-radius: 0; border-top-right-radius: 0; margin-top: 0; }
.kw { color: var(--kw); } .type { color: var(--type); text-decoration: none; }
a.type:hover { text-decoration: underline; }
.fname { color: var(--fname); font-weight: 600; } .arg { color: #e6edf3; }
.opt, .def { color: var(--muted); }

.fdoc { margin: 10px 2px 0; line-height: 1.55; }
.fdoc p { margin: 0 0 8px; }
table.params { border-collapse: collapse; margin: 10px 0 0; font-size: 13.5px; width: 100%; }
table.params td { border: 1px solid var(--border); padding: 6px 10px; vertical-align: top; }
table.params td.pn { font-family: Consolas, Menlo, monospace; color: var(--fname); white-space: nowrap; width: 1%; }
table.params td.pt { font-family: Consolas, Menlo, monospace; color: var(--type); white-space: nowrap; width: 1%; }
.returns { margin-top: 8px; font-size: 13.5px; }
.returns b { color: var(--muted); font-weight: 600; }

.srccode {
	margin: 0; background: #14171c; border: 1px solid var(--border); border-radius: 6px;
	padding: 12px 14px; font-size: 12.5px; line-height: 1.5; overflow-x: auto;
	tab-size: 4; color: #cdd3dc;
	font-family: "JetBrains Mono", Consolas, Menlo, monospace;
}
.srccode .c { color: #6d7686; font-style: italic; }
.srccode .s { color: #a5d6a7; }
.srccode .num { color: #f0b26b; }
.srccode .kw { color: var(--kw); }
.srccode .type { color: var(--type); }

.badge {
	display: inline-block; font-size: 11px; padding: 2px 8px; border-radius: 10px;
	vertical-align: middle; margin-left: 8px; font-weight: 600;
}
.badge.dep { background: var(--dep-bg); border: 1px solid var(--dep-border); color: #d9b44a; }
.depnote {
	background: var(--dep-bg); border: 1px solid var(--dep-border);
	border-radius: 6px; padding: 8px 12px; margin: 8px 0 0; font-size: 13.5px; color: #d9c17a;
}

.toc { columns: 2; column-gap: 40px; margin: 8px 0 0; padding: 0; list-style: none; font-size: 13.5px; }
.toc li { margin: 3px 0; break-inside: avoid; }
.toc a { color: var(--fname); text-decoration: none; font-family: Consolas, Menlo, monospace; }
.toc a:hover { text-decoration: underline; }
.toc .dep-toc { opacity: .55; }

.index-list { list-style: none; padding: 0; }
.index-list li { padding: 10px 0; border-bottom: 1px solid var(--border); }
.index-list a { font-size: 17px; color: var(--fname); text-decoration: none; font-weight: 600; }
.index-list a:hover { text-decoration: underline; }
.index-list .d { color: var(--muted); font-size: 13.5px; margin-top: 3px; line-height: 1.5; }
.hidden { display: none; }
footer { color: var(--muted); font-size: 12px; margin-top: 60px; }

nav::-webkit-scrollbar, body::-webkit-scrollbar { width: 10px; }
nav::-webkit-scrollbar-thumb, body::-webkit-scrollbar-thumb { background: #2e333d; border-radius: 5px; }
nav::-webkit-scrollbar-track, body::-webkit-scrollbar-track { background: transparent; }

@media (max-width: 760px) {
	.layout { flex-direction: column; }
	nav { width: 100%; height: auto; position: static; }
	main { padding: 20px 18px 60px; }
	.toc { columns: 1; }
}
`;

const SIDEBAR_JS = `
function fuzzy(q, s) {
	q = q.toLowerCase(); s = s.toLowerCase();
	if (!q) return true;
	var i = 0;
	for (var j = 0; j < s.length && i < q.length; j++) if (s[j] === q[i]) i++;
	return i === q.length;
}
document.querySelector(".search").addEventListener("input", function () {
	var q = this.value.trim();
	document.querySelectorAll("nav > ul > li, nav ul:not(.mem) > li").forEach(function (li) {
		if (li.parentElement.classList.contains("mem")) return;
		var cls = li.getAttribute("data-name") || "";
		var classHit = fuzzy(q, cls);
		var memberHit = false;
		li.querySelectorAll(".mem > li").forEach(function (mli) {
			var hit = q !== "" && fuzzy(q, mli.getAttribute("data-name") || "");
			mli.classList.toggle("mhit", hit);
			if (hit) memberHit = true;
		});
		li.classList.toggle("hidden", !(classHit || memberHit) && q !== "");
		li.classList.toggle("expanded", memberHit && q !== "");
	});
});
`;

let KNOWN = new Set();

function hlHaxe(code) {
	// escape first, then color in one pass over token boundaries so
	// replacements never touch each other's output
	const KW = new Set(["public","private","static","inline","function","var","final","return","if","else","for","while","do","switch","case","default","try","catch","throw","new","this","null","true","false","break","continue","in","cast","untyped","using","import","package","extends","implements","override","macro","enum","class","interface","abstract","typedef"]);
	let out = "";
	let i = 0;
	const n = code.length;
	while (i < n) {
		const c = code[i];
		if (c === "/" && code[i + 1] === "/") {
			let j = i; while (j < n && code[j] !== "\n") j++;
			out += `<span class="c">${esc(code.slice(i, j))}</span>`; i = j; continue;
		}
		if (c === "/" && code[i + 1] === "*") {
			let j = i + 2; while (j < n && !(code[j] === "*" && code[j + 1] === "/")) j++;
			j = Math.min(n, j + 2);
			out += `<span class="c">${esc(code.slice(i, j))}</span>`; i = j; continue;
		}
		if (c === '"' || c === "'") {
			let j = i + 1;
			while (j < n && code[j] !== c) { if (code[j] === "\\") j++; j++; }
			j = Math.min(n, j + 1);
			out += `<span class="s">${esc(code.slice(i, j))}</span>`; i = j; continue;
		}
		if (/[A-Za-z_]/.test(c)) {
			let j = i; while (j < n && /[\w]/.test(code[j])) j++;
			const w = code.slice(i, j);
			if (KW.has(w)) out += `<span class="kw">${w}</span>`;
			else if (/^[A-Z]/.test(w)) out += `<span class="type">${w}</span>`;
			else out += esc(w);
			i = j; continue;
		}
		if (/[0-9]/.test(c)) {
			let j = i; while (j < n && /[\w.]/.test(code[j])) j++;
			out += `<span class="num">${esc(code.slice(i, j))}</span>`; i = j; continue;
		}
		out += esc(c); i++;
	}
	return out;
}
// after coding this, i'd like to let you know that im never doing ts again

function page(title, sidebar, content) {
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} - ${esc(TITLE)}</title>
<style>${CSS}</style>
</head>
<body>
<header>
<img class="logo" src="hxfilemanagerlogo.png" alt="HxFileManager Logo">
<div>
<h1><a href="index.html">${esc(TITLE)}</a></h1>
<span class="sub">API documentation</span>
</div>
</header>
<div class="layout">
<nav>
<input class="search" type="text" placeholder="Filter classes...">
${sidebar}
</nav>
<main>
${content}
<footer>generated by hxdoc // hxdoc made by HeroEyad</footer>
</main>
</div>
<script>${SIDEBAR_JS}</script>
</body>
</html>`;
}

function buildSidebar(classes, activeName) {
	const byPkg = {};
	for (const c of classes) (byPkg[c.pkg] = byPkg[c.pkg] || []).push(c);
	let html = "";
	for (const pkg of Object.keys(byPkg).sort()) {
		html += `<div class="pkg">${esc(pkg || "(root)")}</div><ul>`;
		for (const c of byPkg[pkg].sort((a, b) => a.name.localeCompare(b.name))) {
			html += `<li data-name="${esc(c.name)}"><a href="${c.name}.html"${c.name === activeName ? ' class="active"' : ""}><span class="k">${c.kind[0].toUpperCase()}</span>${esc(c.name)}</a>`;
			if (c.fields.length) {
				html += `<ul class="mem">`;
				for (const f of c.fields) html += `<li data-name="${esc(f.name)}"><a href="${c.name}.html#${esc(f.name)}">${esc(f.name)}</a></li>`;
				html += `</ul>`;
			}
			html += `</li>`;
		}
		html += "</ul>";
	}
	return html;
}

function docTextHtml(text) {
	return esc(text).split(/\n{2,}/).map(p => `<p>${p.replace(/\n/g, "<br>")}</p>`).join("");
}

function buildClassPage(cls, sidebar) {
	const vars = cls.fields.filter(f => f.kind !== "function");
	const funcs = cls.fields.filter(f => f.kind === "function" && !isDeprecated(f));
	const deprecated = cls.fields.filter(f => f.kind === "function" && isDeprecated(f));

	let body = `<h1 class="classname">${esc(cls.name)}</h1>`;
	body += `<div class="pkgline">${cls.kind} - package <code>${esc(cls.pkg)}</code></div>`;
	if (cls.doc && cls.doc.text) body += `<div class="classdoc">${docTextHtml(cls.doc.text)}</div>`;

	
	if (funcs.length + vars.length > 4) {
		body += `<h2 class="section">Members</h2><ul class="toc">`;
		for (const f of [...vars, ...funcs]) body += `<li><a href="#${f.name}">${esc(f.name)}</a></li>`;
		for (const f of deprecated) body += `<li class="dep-toc"><a href="#${f.name}">${esc(f.name)}</a></li>`;
		body += `</ul>`;
	}

	function renderField(f) {
		const dep = isDeprecated(f);
		let h = `<div class="field" id="${esc(f.name)}">`;
		const sigInner = `${sigHtml(f)}${dep ? '<span class="badge dep">deprecated</span>' : ""}`;
		h += f.src ? `<details class="fold"><summary class="sig has-src">${sigInner}</summary><pre class="srccode">${hlHaxe(f.src)}</pre></details>` : `<div class="sig">${sigInner}</div>`;
		if (dep) h += `<div class="depnote">${esc(deprecationMsg(f))}</div>`;
		if (f.doc && f.doc.text) h += `<div class="fdoc">${docTextHtml(f.doc.text)}</div>`;
		if (f.kind === "function" && f.doc && Object.keys(f.doc.params).length) {
			h += `<table class="params">`;
			for (const a of f.args) {
				if (!(a.name in f.doc.params)) continue;
				h += `<tr><td class="pn">${a.optional ? "?" : ""}${esc(a.name)}</td><td class="pt">${esc(a.type)}</td><td>${esc(f.doc.params[a.name])}</td></tr>`;
			}
			h += `</table>`;
		}
		if (f.doc && f.doc.returns) h += `<div class="returns"><b>Returns:</b> ${esc(f.doc.returns)}</div>`;
		h += `</div>`;
		return h;
	}

	// one for you, and one for me
	if (vars.length) {
		body += `<h2 class="section">Variables</h2>`;
		for (const f of vars) body += renderField(f);
	}
	// two for you, and one for me
	if (funcs.length) {
		body += `<h2 class="section">Functions</h2>`;
		for (const f of funcs) body += renderField(f);
	}
	// three for you, and one for me
	if (deprecated.length) {
		body += `<h2 class="section">Deprecated</h2>`;
		for (const f of deprecated) body += renderField(f);
	}

	return page(cls.name, sidebar, body);
}

function buildIndex(classes, sidebar) {
	let body = `<h1 class="classname">${esc(TITLE)}</h1><div class="pkgline">${classes.length} types</div><ul class="index-list">`;
	for (const c of classes.sort((a, b) => a.name.localeCompare(b.name))) {
		// i actually didnt know what was localeCompare, guess i do now
		const summary = c.doc && c.doc.text ? c.doc.text.split("\n")[0] : "";
		body += `<li><a href="${c.name}.html">${esc(c.name)}</a><div class="d">${esc(summary)}</div></li>`;
	}
	body += `</ul>`;
	return page("Index", sidebar, body);
}

// main

const files = findHxFiles(SRC);
let allClasses = [];
for (const f of files) {
	try {
		allClasses = allClasses.concat(parseFile(fs.readFileSync(f, "utf8"), f));
	} catch (e) {
		console.error("failed to parse ts " + f + ": " + e.message);
	}
}

KNOWN = new Set(allClasses.map(c => c.name));

fs.mkdirSync(OUT, { recursive: true });
for (const cls of allClasses) {
	const sidebar = buildSidebar(allClasses, cls.name);
	fs.writeFileSync(path.join(OUT, cls.name + ".html"), buildClassPage(cls, sidebar));
}
fs.writeFileSync(path.join(OUT, "index.html"), buildIndex(allClasses, buildSidebar(allClasses, null)));

console.log(`hxdoc: ${allClasses.length} types from ${files.length} files -> ${OUT}`);
for (const c of allClasses) {
	const pub = c.fields.length;
	console.log(`  ${c.pkg ? c.pkg + "." : ""}${c.name} (${pub} public members)`);
}

// after all this, i'd like to let you know im never coding in js ever again