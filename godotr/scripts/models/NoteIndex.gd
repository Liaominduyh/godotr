class_name NoteIndex
extends Resource

## The in-memory index of all notes for fast lookup and search.
## Persisted as index.json under the knowledge base directory.

var notes: Array[NoteResource] = []  # All notes with their metadata (body may be empty in index)
var tag_counts: Dictionary = {}  # tag_name -> count
var dirty: bool = false


func build_from_notes(all_notes: Array[NoteResource]) -> void:
	notes = all_notes.duplicate()
	_rebuild_tag_counts()


func add_note(note: NoteResource) -> void:
	# Replace if exists by file_path
	for i in notes.size():
		if notes[i].file_path == note.file_path:
			notes[i] = note
			_rebuild_tag_counts()
			dirty = true
			return
	notes.append(note)
	_rebuild_tag_counts()
	dirty = true


func remove_note(file_path: String) -> void:
	for i in notes.size():
		if notes[i].file_path == file_path:
			notes.remove_at(i)
			_rebuild_tag_counts()
			dirty = true
			return


func get_by_path(file_path: String) -> NoteResource:
	for note in notes:
		if note.file_path == file_path:
			return note
	return null


func get_by_tag(tag: String) -> Array[NoteResource]:
	var result: Array[NoteResource] = []
	for note in notes:
		if tag in note.tags:
			result.append(note)
	return result


func search(query: String) -> Array[NoteResource]:
	## Full-text search across title, tags, summary, and body content.
	## Body content is loaded on demand, so search skips it for performance.
	var q := query.to_lower().strip_edges()
	if q.is_empty():
		return notes.duplicate()

	var terms := q.split(" ", false)
	var scored: Array = []

	for note in notes:
		var s := _score_note(note, terms)
		if s > 0:
			scored.append({"note": note, "score": s})

	scored.sort_custom(func(a: Dictionary, b: Dictionary): return a.score > b.score)

	var result: Array[NoteResource] = []
	for entry in scored:
		result.append(entry.note)
	return result


func search_with_body(query: String, body_text: String = "") -> Array[NoteResource]:
	## Full-text search including body content for specific notes.
	var q := query.to_lower().strip_edges()
	if q.is_empty():
		return notes.duplicate()

	var terms := q.split(" ", false)
	var result: Array[NoteResource] = []

	for note in notes:
		if _matches_all_terms(note, terms):
			result.append(note)
			continue
		# Check body if provided
		if body_text and _matches_body(body_text, terms):
			result.append(note)

	return result


func get_all_tags() -> Array[String]:
	var tags: Array[String] = []
	for tag in tag_counts.keys():
		tags.append(tag)
	tags.sort()
	return tags


func get_tag_count(tag: String) -> int:
	return tag_counts.get(tag, 0)


func serialize() -> Dictionary:
	var note_list: Array[Dictionary] = []
	for note in notes:
		note_list.append({
			"title": note.title,
			"tags": note.tags.duplicate(),
			"created": note.created,
			"updated": note.updated,
			"source": note.source,
			"summary": note.summary,
			"file_path": note.file_path,
			"tag_color": note.tag_color.to_html(false)
		})

	return {
		"version": 1,
		"notes": note_list,
		"tags": tag_counts.duplicate()
	}


func deserialize(data: Dictionary) -> void:
	notes.clear()
	tag_counts.clear()

	var note_list: Array = data.get("notes", [])
	for entry in note_list:
		var note := NoteResource.new()
		note.title = entry.get("title", "")
		var raw_tags: Array = entry.get("tags", [])
		for t in raw_tags:
			note.tags.append(str(t))
		note.created = entry.get("created", "")
		note.updated = entry.get("updated", "")
		note.source = entry.get("source", "manual")
		note.summary = entry.get("summary", "")
		note.file_path = entry.get("file_path", "")
		var color_str: String = entry.get("tag_color", "")
		if not color_str.is_empty():
			note.tag_color = Color(color_str)
		notes.append(note)

	tag_counts = data.get("tags", {}).duplicate()
	dirty = false


func _rebuild_tag_counts() -> void:
	tag_counts.clear()
	for note in notes:
		for tag in note.tags:
			tag_counts[tag] = tag_counts.get(tag, 0) + 1


static func _matches_all_terms(note: NoteResource, terms: Array[String]) -> bool:
	var haystack := "%s %s %s" % [note.title.to_lower(), note.summary.to_lower(), " ".join(note.tags)]
	for term in terms:
		if not haystack.contains(term):
			return false
	return true


static func _matches_body(body_text: String, terms: Array[String]) -> bool:
	var haystack := body_text.to_lower()
	for term in terms:
		if not haystack.contains(term):
			return false
	return true


static func _score_note(note: NoteResource, terms: Array[String]) -> int:
	var score := 0
	var tl := note.title.to_lower()
	var sl := note.summary.to_lower()
	var tags := " ".join(note.tags)
	for term in terms:
		var term_match := false
		if term in tl:
			score += 3
			term_match = true
		if term in tags:
			score += 2
			term_match = true
		if term in sl:
			score += 1
			term_match = true
		if not term_match:
			return 0
	return score
