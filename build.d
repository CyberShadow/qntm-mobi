// First, run:
// wget -m http://qntm.org/
// (I hope this is OK)

import std.algorithm;
import std.array;
import std.file;
import std.format;
import std.regex;
import std.stdio;

import ae.utils.array;

File result;

string[] queue;
bool[string] seen;

struct Page
{
	string title, parent;
	string[] children;
}

Page[string] pages;
ref Page getPage(string id) { if (auto p = id in pages) return *p; pages[id] = Page(); return pages[id]; }

void main()
{
	result = File("qntm.html", "wb");
	result.writeln(readText("header.html"));

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

	result.writeln(readText("footer.html"));
	result.close();

	genNav();
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
	with (getPage(id))
	{
		title = html.matchFirst(reTitle).captures[1];
		parent = html.matchFirst(reAncestor).captures[1];
		foreach (m; html.matchAll(reChildren))
			children ~= m.captures[1];
	}

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
		.replaceAll(reHref, `<a $1href="#$3">`)
		.replaceAll(reYT, `<div><a href="http://www.youtube.com/watch?v=$1">YouTube video $1</a></div>`)
		.replaceAll(reRSS, ``)
	;

	result.writeln(`<mbp:section>`);
	result.writeln(`<div id="` ~ id ~ `">`);
	result.writeln(`<a name="` ~ id ~ `"></a>`);
	result.writeln(html);
	result.writeln(`</div>`);
	result.writeln(`</mbp:section>`);
	result.writeln(`<hr/><mbp:pagebreak/>`);
}

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
			auto page = pages[id];
			assert(page.parent == parent, "Parent mismatch for page %s: linking parent is %d, page thinks it's %s".format(id, parent, page.parent));

			toc.writeln(`<li><a href="qntm.html#`, id , `">`, page.title, `</a></li>`);
			ncx.writeln(`<navPoint id="navpoint-`, id, `" playOrder="`, ++n, `">`);
			ncx.writeln(`<navLabel><text>`, page.title, `</text></navLabel>`);
			ncx.writeln(`<content src="qntm.html#`, id , `" />`);

			if (page.children.length)
				genList(page.children, id);

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
