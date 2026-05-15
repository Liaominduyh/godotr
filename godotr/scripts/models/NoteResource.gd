class_name NoteResource
extends Resource

## YAML frontmatter fields
@export var title: String = ""
@export var tags: Array[String] = []
@export var created: String = ""  # ISO date string
@export var updated: String = ""  # ISO date string
@export var source: String = "manual"  # manual, import_url, import_file, ai_summary
@export var summary: String = ""
@export var tag_color: Color = Color(0.55, 0.7, 0.9, 1)  # 标签文字颜色

## Markdown body content
@export var body: String = ""

## Internal: relative path under knowledge_base_dir
@export var file_path: String = ""


func get_filename() -> String:
	var date_prefix: String = created.replace("-", "") if created else Time.get_datetime_string_from_system().replace("-", "")
	var slug: String = _to_slug(title)
	return "%s-%s.md" % [date_prefix, slug]


func to_frontmatter() -> String:
	var yaml_lines: PackedStringArray = []
	yaml_lines.append("---")
	yaml_lines.append("title: \"%s\"" % _escape_yaml(title))
	if tags.size() > 0:
		yaml_lines.append("tags: [%s]" % ", ".join(tags))
	if created:
		yaml_lines.append("created: %s" % created)
	if updated:
		yaml_lines.append("updated: %s" % updated)
	yaml_lines.append("source: %s" % source)
	if summary:
		yaml_lines.append("summary: \"%s\"" % _escape_yaml(summary))
	if tag_color != Color(0.55, 0.7, 0.9, 1):
		yaml_lines.append("tag_color: \"%s\"" % tag_color.to_html(false))
	yaml_lines.append("---")
	return "\n".join(yaml_lines)


func to_markdown() -> String:
	return to_frontmatter() + "\n\n" + body


static func from_markdown(text: String, path: String = "") -> NoteResource:
	var note := NoteResource.new()
	note.file_path = path

	if text.begins_with("---"):
		var end_idx := text.find("\n---", 3)
		if end_idx != -1:
			var frontmatter := text.substr(3, end_idx - 3).strip_edges()
			note.body = text.substr(end_idx + 4).strip_edges(true, false)
			_parse_frontmatter(frontmatter, note)
		else:
			note.body = text.strip_edges()
	else:
		note.body = text.strip_edges()

	if note.title.is_empty():
		note.title = _guess_title(note.body)
	if note.created.is_empty():
		note.created = Time.get_datetime_string_from_system().split("T")[0]

	return note


static func _parse_frontmatter(yaml_text: String, note: NoteResource) -> void:
	for line in yaml_text.split("\n"):
		line = line.strip_edges()
		if ":" in line:
			var colon_idx := line.find(":")
			var key := line.substr(0, colon_idx).strip_edges()
			var value := line.substr(colon_idx + 1).strip_edges().strip_escapes()

			match key:
				"title":
					note.title = _unescape_yaml(value)
				"tags":
					var tag_str := value.trim_prefix("[").trim_suffix("]")
					for t in tag_str.split(","):
						var tag := t.strip_edges().strip_escapes()
						if tag:
							note.tags.append(tag)
				"created":
					note.created = value
				"updated":
					note.updated = value
				"source":
					note.source = value
				"summary":
					note.summary = _unescape_yaml(value)
				"tag_color":
					note.tag_color = Color(value)


static func _escape_yaml(s: String) -> String:
	return s.replace("\"", "\\\"")


static func _unescape_yaml(s: String) -> String:
	s = s.trim_prefix("\"").trim_suffix("\"")
	return s.replace("\\\"", "\"")


static func _guess_title(body: String) -> String:
	var first_line := body.strip_edges().split("\n")[0] if body else ""
	return first_line.trim_prefix("#").strip_edges()


static func _to_slug(s: String) -> String:
	var slug := s.to_lower()
	slug = slug.replace(" ", "-")
	var result := ""
	for c in slug:
		if c.is_valid_unicode_identifier() or c == "-":
			result += c
	return result.substr(0, 60)
