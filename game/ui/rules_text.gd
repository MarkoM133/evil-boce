class_name RulesText
extends RefCounted
## The players' rules (data/rules/rules.md in the shared folder, the same file Card Studio shows on its Rules page)
## as sections of BBCode for the pause menu's RULES tab (Marko 2026-11-11, G1). Markdown kept small: "## " starts a
## section, "### " a subheading, "> " a note, "- " and "1. " lists (an indented line goes on with its item),
## "| … |" tables (the first column as a heading), **bold**, `code`, *italic*, and **[?]** for a wording still
## to be checked.

const PATH: String = "rules/rules.md"
const HEAD_FONT: String = "res://ui/fonts/BarlowCondensed-Bold.ttf"
const STRAW: String = "#f4b62a"
const BONE: String = "#f3efe7"


## The rules file under a data folder, or "" when there is none.
static func read(data_dir: String) -> String:
	var path: String = data_dir.path_join(PATH)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## The sections after the first "## " (the intro before it and the "# " title are Card Studio's): {title, bb}.
static func sections(md: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var title: String = ""
	var lines := PackedStringArray()
	for line: String in md.replace("\r\n", "\n").split("\n"):
		if line.begins_with("## "):
			if not title.is_empty():
				out.append({"title": title, "bb": to_bbcode(lines)})
			title = line.substr(3).strip_edges()
			lines = PackedStringArray()
		elif not title.is_empty():
			lines.append(line)
	if not title.is_empty():
		out.append({"title": title, "bb": to_bbcode(lines)})
	return out


## A section's heading and body, ready for a RichTextLabel.
static func page(section: Dictionary) -> String:
	return "[font=%s][font_size=32][color=%s]%s[/color][/font_size][/font]\n\n%s" % [HEAD_FONT, BONE,
		str(section.get("title", "")).replace("[", "[lb]"), str(section.get("bb", ""))]


static func to_bbcode(lines: PackedStringArray) -> String:
	var out := PackedStringArray()
	var item := RegEx.create_from_string("^(- |\\d+\\. )")
	var i: int = 0
	while i < lines.size():
		var l: String = lines[i]
		if l.strip_edges().is_empty():
			i += 1
		elif l.begins_with("#"):
			# "### " and any other heading inside a section ("####", "#x"): a subheading. (A "#" line no branch
			# took used to stop this loop, and the game with it: code review 2026-11-13.)
			out.append("[font=%s][font_size=22][color=%s]%s[/color][/font_size][/font]" % [HEAD_FONT, BONE, inline(l.lstrip("#").strip_edges())])
			i += 1
		elif l.begins_with("> "):
			out.append("[color=%s]%s[/color]" % [STRAW, inline(l.substr(2))])
			i += 1
		elif l.begins_with("|"):
			var rows: Array[PackedStringArray] = []
			while i < lines.size() and lines[i].begins_with("|"):
				var cells: PackedStringArray = lines[i].strip_edges().trim_prefix("|").trim_suffix("|").split("|")
				if not lines[i].replace("|", "").replace("-", "").replace(":", "").strip_edges().is_empty():
					rows.append(cells)
				i += 1
			var table: String = "[table=2]"
			for r: int in range(1, rows.size()):
				var key: String = rows[r][0].strip_edges() if rows[r].size() > 0 else ""
				var text: String = rows[r][1].strip_edges() if rows[r].size() > 1 else ""
				table += "[cell padding=0,5,20,5][b][color=%s]%s[/color][/b][/cell][cell padding=0,5,0,5]%s[/cell]" % [BONE, inline(key), inline(text)]
			out.append(table + "[/table]")
		elif item.search(l) != null:
			var items := PackedStringArray()
			while i < lines.size() and not lines[i].strip_edges().is_empty() and (item.search(lines[i]) != null or lines[i].begins_with("  ")):
				if lines[i].begins_with("  ") and not items.is_empty():
					items[items.size() - 1] = items[items.size() - 1] + " " + lines[i].strip_edges()
				else:
					var m: RegExMatch = item.search(lines[i])
					var mark: String = "•" if m.get_string(1) == "- " else m.get_string(1).strip_edges()
					items.append("%s  %s" % [mark, lines[i].substr(m.get_end())])
				i += 1
			var listed := PackedStringArray()
			for it: String in items:
				var sep: int = it.find("  ")
				listed.append("[indent]%s%s[/indent]" % [it.substr(0, sep + 2), inline(it.substr(sep + 2))])
			out.append("\n".join(listed))
		else:
			# A paragraph: this line whatever it is (so the loop always moves on), and the plain lines after it.
			var para := PackedStringArray([l])
			i += 1
			while i < lines.size() and not lines[i].strip_edges().is_empty() and not lines[i].begins_with("#") \
					and not lines[i].begins_with("> ") and not lines[i].begins_with("|") and item.search(lines[i]) == null:
				para.append(lines[i])
				i += 1
			out.append(inline(" ".join(para)))
	return "\n\n".join(out)


## One line of Markdown as BBCode; a "[" of the text (like "[EN]") stays text.
static func inline(s: String) -> String:
	var t: String = s.replace("**[?]**", "\u0001").replace("[", "[lb]")
	t = t.replace("\u0001", "[color=%s](?)[/color]" % STRAW)
	t = RegEx.create_from_string("\\*\\*(.+?)\\*\\*").sub(t, "[b][color=%s]$1[/color][/b]" % BONE, true)
	t = RegEx.create_from_string("`(.+?)`").sub(t, "[color=%s]$1[/color]" % STRAW, true)
	t = RegEx.create_from_string("(^|[^*\\w])\\*([^*\\s][^*]*?)\\*").sub(t, "$1[i]$2[/i]", true)
	return t
