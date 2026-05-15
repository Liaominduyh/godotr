## NoteIndex 搜索/索引单元测试
extends RefCounted

var _a: RefCounted


func _init() -> void:
	_a = load("res://tests/test_assert.gd").new()


func _make_note(title: String, tags: Array[String], summary := "", fp := "") -> NoteResource:
	var note := NoteResource.new()
	note.title = title
	note.tags = tags
	note.summary = summary
	note.file_path = fp
	note.source = "manual"
	return note


# --------------------------------------------------------------------------
#  add_note / get_by_path / remove_note
# --------------------------------------------------------------------------

func test_add_and_get() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("测试", ["gdx"], "", "notes/test.md"))
	return _a.ok(idx.get_by_path("notes/test.md") != null, "应能找到刚添加的笔记")


func test_add_replace_same_path() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("标题1", ["a"], "", "notes/1.md"))
	idx.add_note(_make_note("标题2", ["b"], "", "notes/1.md"))
	return (_a.eq(idx.notes.size(), 1, "同路径应替换不新增")
		and _a.eq(idx.notes[0].title, "标题2"))


func test_remove_note() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("待删除", [], "", "notes/del.md"))
	idx.remove_note("notes/del.md")
	return (_a.eq(idx.notes.size(), 0)
		and _a.ok(idx.get_by_path("notes/del.md") == null, "删除后应查不到"))


func test_remove_nonexistent() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("保留", [], "", "notes/keep.md"))
	idx.remove_note("notes/nonexist.md")
	return _a.eq(idx.notes.size(), 1)


# --------------------------------------------------------------------------
#  search
# --------------------------------------------------------------------------

func test_search_by_title() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("Godot入门", [], "", "notes/1.md"))
	idx.add_note(_make_note("Unity教程", [], "", "notes/2.md"))
	return _a.eq(idx.search("Godot").size(), 1)


func test_search_by_tag() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("笔记A", ["godot", "3d"], "", "notes/a.md"))
	idx.add_note(_make_note("笔记B", ["unity"], "", "notes/b.md"))
	var results := idx.search("godot")
	return (_a.eq(results.size(), 1)
		and _a.eq(results[0].title, "笔记A"))


func test_search_by_summary() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("性能优化", ["性能"], "如何提升帧率", "notes/perf.md"))
	idx.add_note(_make_note("UI设计", ["UI"], "", "notes/ui.md"))
	return _a.eq(idx.search("帧率").size(), 1)


func test_search_multi_word_and() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("Godot 2D 游戏开发", ["godot", "2d"], "", "notes/1.md"))
	idx.add_note(_make_note("Unity 2D 游戏入门", ["unity", "2d"], "", "notes/2.md"))
	var results := idx.search("2d godot")
	return (_a.eq(results.size(), 1)
		and _a.eq(results[0].title, "Godot 2D 游戏开发"))


func test_search_empty_query_returns_all() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("A", [], "", "notes/a.md"))
	idx.add_note(_make_note("B", [], "", "notes/b.md"))
	return _a.eq(idx.search("").size(), 2)


func test_search_case_insensitive() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("GODOT入门", [], "", "notes/1.md"))
	return _a.eq(idx.search("godot").size(), 1)


func test_search_chinese() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("游戏引擎性能优化指南", ["性能"], "针对 Godot 引擎的优化技巧", "notes/1.md"))
	idx.add_note(_make_note("美术资源管理", ["资源"], "", "notes/2.md"))
	return _a.eq(idx.search("性能优化").size(), 1)


# --------------------------------------------------------------------------
#  get_by_tag
# --------------------------------------------------------------------------

func test_get_by_tag_multiple() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("A", ["godot"], "", "notes/a.md"))
	idx.add_note(_make_note("B", ["godot", "3d"], "", "notes/b.md"))
	idx.add_note(_make_note("C", ["unity"], "", "notes/c.md"))
	return _a.eq(idx.get_by_tag("godot").size(), 2)


func test_get_by_tag_nonexistent() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("A", ["godot"], "", "notes/a.md"))
	return _a.eq(idx.get_by_tag("unity").size(), 0)


# --------------------------------------------------------------------------
#  tag_counts
# --------------------------------------------------------------------------

func test_tag_counts() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("A", ["godot", "3d"], "", "notes/a.md"))
	idx.add_note(_make_note("B", ["godot"], "", "notes/b.md"))
	return (_a.eq(idx.get_tag_count("godot"), 2)
		and _a.eq(idx.get_tag_count("3d"), 1)
		and _a.eq(idx.get_tag_count("unity"), 0))


func test_get_all_tags_sorted() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("A", ["zebra", "apple"], "", "notes/a.md"))
	var tags := idx.get_all_tags()
	return (_a.eq(tags.size(), 2)
		and _a.eq(tags[0], "apple")
		and _a.eq(tags[1], "zebra"))


func test_tag_counts_after_remove() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("A", ["godot"], "", "notes/a.md"))
	idx.add_note(_make_note("B", ["godot"], "", "notes/b.md"))
	idx.remove_note("notes/a.md")
	return _a.eq(idx.get_tag_count("godot"), 1)


# --------------------------------------------------------------------------
#  serialize / deserialize
# --------------------------------------------------------------------------

func test_serialize_roundtrip() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("序列化测试", ["test", "gdscript"], "摘要内容", "notes/test.md"))
	var data := idx.serialize()
	var idx2 := NoteIndex.new()
	idx2.deserialize(data)
	return (_a.eq(idx2.notes.size(), 1)
		and _a.eq(idx2.notes[0].title, "序列化测试")
		and _a.eq(idx2.notes[0].tags.size(), 2)
		and _a.eq(idx2.get_tag_count("test"), 1))


func test_serialize_empty_index() -> bool:
	var idx := NoteIndex.new()
	var data := idx.serialize()
	var idx2 := NoteIndex.new()
	idx2.deserialize(data)
	return (_a.eq(idx2.notes.size(), 0)
		and _a.eq(idx2.get_all_tags().size(), 0))


# --------------------------------------------------------------------------
#  _score_note
# --------------------------------------------------------------------------

func test_score_title_match() -> bool:
	var note := _make_note("Godot性能优化", [], "", "")
	var score: int = NoteIndex._score_note(note, ["godot"])
	return _a.eq(score, 3, "标题匹配应得分 3")


func test_score_tag_match() -> bool:
	var note := _make_note("某笔记", ["godot"], "", "")
	var score: int = NoteIndex._score_note(note, ["godot"])
	return _a.ok(score >= 2, "标签匹配应至少得 2 分")


func test_score_summary_match() -> bool:
	var note := _make_note("某笔记", [], "godot相关的优化技巧", "")
	var score: int = NoteIndex._score_note(note, ["godot"])
	return _a.eq(score, 1, "摘要匹配应得分 1")


func test_score_multi_term() -> bool:
	var note := _make_note("Godot 2D游戏", ["godot"], "优化godot引擎", "")
	var score: int = NoteIndex._score_note(note, ["godot", "2d"])
	return _a.ok(score > 3, "多词命中应累积分")


func test_score_no_match() -> bool:
	var note := _make_note("Unity教程", ["unity"], "", "")
	var score: int = NoteIndex._score_note(note, ["godot"])
	return _a.eq(score, 0, "无匹配应得 0 分")


func test_score_partial_match() -> bool:
	var note := _make_note("Godot教程", [], "", "")
	var score: int = NoteIndex._score_note(note, ["godot", "unity"])
	return _a.eq(score, 0, "部分匹配应为 0")


# --------------------------------------------------------------------------
#  搜索按分数排序
# --------------------------------------------------------------------------

func test_search_sorted_by_relevance() -> bool:
	var idx := NoteIndex.new()
	idx.add_note(_make_note("Godot入门指南", ["godot", "入门"], "godot引擎基础", "notes/a.md"))
	idx.add_note(_make_note("Godot高级教程", [], "", "notes/b.md"))
	idx.add_note(_make_note("其他笔记", [], "godot相关的补充", "notes/c.md"))
	var results := idx.search("godot")
	return (_a.eq(results.size(), 3)
		and _a.eq(results[0].title, "Godot入门指南", "高分应排第一")
		and _a.eq(results[2].title, "其他笔记", "低分应排最后"))
