// First, run:
// wget -m http://qntm.org/
// (I hope this is OK)

import std.algorithm;
import std.array;
import std.datetime;
import std.file;
import std.format;
import std.path;
import std.regex;
import std.stdio;
import std.string;

import ae.utils.array;

string[] queue;
bool[string] seen;

struct Page
{
	string title, parent;
	string[] children;
}

Page[string] pages;
ref Page getPage(string id) { if (auto p = id in pages) return *p; pages[id] = Page(); return pages[id]; }
string[] extraFiles;

void main()
{
	if ("out".exists)
		rmdirRecurse("out");

	queue = [null];
	while (queue.length)
	{
		auto page = queue.shift();
		if (page !in seen)
		{
			scan(page);
			seen[page] = true;
		}
	}

	copyDir("files");
	genNav();
	genOPF();
}

void scan(string id)
{
	auto fn = id;
	if (!fn.length)
		fn = "index.html";
	fn = "qntm.org/" ~ fn;
	if (!fn.exists)
	{
		stderr.writeln("Warning: ", fn, " not found");
		return;
	}

	auto html = cast(string)read(fn);

	static reTitle = regex(`<title>(.*?) @ Things Of Interest</title>`);
	static reAncestor = regex(`<a class="ancestor" href="/(.*?)">Back to `);
	static reChildren = regex(`^									href='/(.*?)'$`, "m");
	auto page = &getPage(id);
	page.title = html.matchFirst(reTitle).captures[1];
	page.parent = html.matchFirst(reAncestor).captures[1];
	foreach (m; html.matchAll(reChildren))
		page.children ~= m.captures[1];

	html = html
		.findSplit(`<div id="page">`)[2]
		.findSplit(`<!-- nontop -->`)[0]
		.replace(`<div id="`, `<div class="`)
		.replace(`<h3 id="`, `<h3 class="`)
		.replace("\0", " ")
	;

	static reHref = regex(`<a\s+(class="\w+"\s+)?href\s*=\s*(["'])/([a-z0-9_\-]*?)\2\s*>`);
	string[] newLinks;
	foreach (m; html.matchAll(reHref))
		newLinks ~= m.captures[3];
	queue = newLinks ~ queue;

	static reYT = regex(`<iframe width="\d+" height="\d+" src="//www.youtube.com/embed/([a-zA-Z0-9_-]+)" frameborder="0" allowfullscreen></iframe>`);
	static reRSS = regex(` <a href='/rss\.php(\?\w+)?'><img alt='feed' src='page/feed\.png'/>`);
	html = html
		.replaceAll(reHref, `<a $1href="$3.html">`)
		.replaceAll(reYT, `<div><a href="http://www.youtube.com/watch?v=$1">YouTube video $1</a></div>`)
		.replaceAll(reRSS, ``)
	;

	mkdirRecurse("out");
	auto result = File("out/" ~ id ~ ".html", "wb");
	result.writeln(`<html>`);
	result.writeln(`<head>`);
	result.writeln(`<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>`);
	result.writeln(`<title>`, page.title, `</title>`);
	result.writeln(`<link rel="stylesheet" type="text/css" href="../style.css"/>`);
	result.writeln(`</head>`);

	result.writeln(`<body>`);
	result.writeln(`<mbp:section>`);
	result.writeln(html);
	result.writeln(`</mbp:section>`);
	result.writeln(`<hr/><mbp:pagebreak/>`);
	result.writeln(`</body>`);
	result.writeln(`</html>`);
}

string[] pageOrder;

void genNav()
{
	auto toc = File("toc.xhtml", "wb");
	toc.writeln(`<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">`);
	toc.writeln(`<html xmlns="http://www.w3.org/1999/xhtml">`);
	toc.writeln(`<body>`);
	toc.writeln(`<nav epub:type="toc">`);

	auto ncx = File("toc.ncx", "wb");
	ncx.writeln(`<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en-US">`);
	ncx.writeln(`<navMap>`);
	int n = 0;

	void genList(string[] ids, string parent)
	{
		toc.writeln(`<ol>`);
		foreach (id; ids)
		{
			if (id !in pages)
			{
				stderr.writefln("Page %s not found (referenced from %s)".format(id, parent));
				continue;
			}
			pageOrder ~= id;
			auto page = pages[id];
			assert(page.parent == parent, "Parent mismatch for page %s: linking parent is %d, page thinks it's %s".format(id, parent, page.parent));

			toc.writeln(`<li><a href="out/`, id , `.html">`, page.title, `</a>`);
			ncx.writeln(`<navPoint id="navpoint-`, id, `" playOrder="`, ++n, `">`);
			ncx.writeln(`<navLabel><text>`, page.title, `</text></navLabel>`);
			ncx.writeln(`<content src="out/`, id , `.html" />`);

			if (page.children.length)
				genList(page.children, id);

			toc.writeln(`</li>`);
			ncx.writeln(`</navPoint>`);
		}
		toc.writeln(`</ol>`);
	}

	genList([null], null);

	toc.writeln(`</nav>`);
	toc.writeln(`</body>`);
	toc.writeln(`</html>`);

	ncx.writeln(`</navMap>`);
	ncx.writeln(`</ncx>`);
}

void genOPF()
{
	auto opf = File("qntm.opf", "wb");

	opf.writeln(`<?xml version="1.0"?>`);
	opf.writeln(`<package version="2.0" xmlns="http://www.idpf.org/2007/opf">`);
	opf.writeln();
	opf.writeln(`  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">`);
	opf.writeln(`    <dc:title>Things of Interest</dc:title>`);
	opf.writeln(`    <dc:language>en</dc:language>`);
	opf.writeln(`    <dc:creator opf:file-as="Hughes, Sam" opf:role="aut">Sam Hughes</dc:creator>`);
//	opf.writeln(`    <dc:creator opf:file-as="Panteleev, Vladimir" opf:role="red">Vladimir Panteleev</dc:creator>`);
	opf.writeln(`    <dc:description>qntm.org in eBook format</dc:description>`);
	auto t = Clock.currTime();
	opf.writeln(`    <dc:date>`, "%04d-%02d-%02d".format(t.year, t.month, t.day), `</dc:date>`);
	opf.writeln(`    <meta name="cover" content="cimage" />`);
	opf.writeln(`  </metadata>`);
	opf.writeln();

	opf.writeln(`  <manifest>`);
	opf.writeln(`    <item id="tc" href="toc.xhtml" media-type="application/xhtml+xml"/>`);
	opf.writeln(`    <item id="stylesheet" href="style.css" media-type="text/css"/>`);
	opf.writeln(`    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>  `);
	opf.writeln(`    <item id="cimage" href="cover/cover.jpeg" media-type="image/jpeg" properties="cover-image" />`);
	foreach (id; pageOrder)
	opf.writeln(`    <item id="qntm-`, id, `" href="out/`, id, `.html" media-type="application/xhtml+xml"/>`);
	foreach (path; extraFiles)
	opf.writeln(`    <item id="qntmfiles-`, path.stripExtension.replace("/", "-"), `" href="out/`, path, `" media-type="application/xhtml+xml"/>`);
	opf.writeln(`  </manifest>`);
	opf.writeln();

	opf.writeln(`  <!-- Each itemref references the id of a document designated in the manifest. The order of the itemref elements organizes the associated content files into the linear reading order of the publication.  -->`);
	opf.writeln(`  <spine toc="ncx">`);
	opf.writeln(`    <itemref idref="tc" />`);
	foreach (id; pageOrder)
	opf.writeln(`    <itemref idref="qntm-`, id, `" />`);
	opf.writeln(`  </spine>`);
	opf.writeln();

	opf.writeln(`  <!-- The Kindle reading system supports two special guide items which are both mandatory.`);
	opf.writeln(`  type="toc" [mandatory]: a link to the HTML table of contents`);
	opf.writeln(`  type="text" [mandatory]: a link to where the content of the book starts (typically after the front matter) -->`);
	opf.writeln(`  <guide>`);
	opf.writeln(`    <reference type="toc" title="Table of Contents" href="toc.xhtml"/>`);
	opf.writeln(`    <reference type="text" title="Index" href="out/.html"/>`);
	opf.writeln(`  </guide>`);
	opf.writeln();

	opf.writeln(`</package>`);
}

void copyDir(string dir)
{
	mkdirRecurse("out/" ~ dir);
	foreach (de; dirEntries("qntm.org/" ~ dir, SpanMode.shallow))
		if (de.isFile)
		{
			if (de.extension.toLower.isOneOf(".jpg", ".jpeg", ".png", ".gif", ".htm", ".html"))
				copy(de, buildPath("out", dir, de.baseName));
			if (de.extension.toLower.isOneOf(".htm", ".html"))
				extraFiles ~= dir ~ "/" ~ de.baseName;
		}
		else
		{
			if (!de.baseName.isOneOf("maps", "tax", "alphabet", "atoz"))
				copyDir(dir ~ "/" ~ de.baseName);
		}
}
