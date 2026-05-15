## KnowledgeBase 核心逻辑测试 — 使用临时目录隔离
extends RefCounted

var _a: RefCounted
var _saved_kb_dir: String
var _saved_index: NoteIndex
var _saved_ready: bool
var _test_dir: String


func _init() -> void:
	_a = load("res://tests/test_assert.gd").new()


func _setup() -> void:
	_saved_kb_dir = KnowledgeBase.kb_dir
	_saved_index = KnowledgeBase.index
	_saved_ready = KnowledgeBase._ready_emitted

	_test_dir = ProjectSettings.globalize_path("user://test_kb")
	DirAccess.make_dir_recursive_absolute(_test_dir + "/notes")
	KnowledgeBase.kb_dir = _test_dir
	KnowledgeBase.index = NoteIndex.new()
	KnowledgeBase._ready_emitted = true


func _teardown() -> void:
	KnowledgeBase.kb_dir = _saved_kb_dir
	KnowledgeBase.index = _saved_index
	KnowledgeBase._ready_emitted = _saved_ready

	var base := ProjectSettings.globalize_path("user://test_kb")
	if DirAccess.dir_exists_absolute(base):
		_rm_dir(base)


func _rm_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name:
		if name not in [".", ".."]:
			var full := path + "/" + name
			if dir.current_is_dir():
				_rm_dir(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# =====================================================================
#  CRUD
# =====================================================================

func test_create_note() -> bool:
	_setup()
	var note := KnowledgeBase.create_note("测试笔记", "正文内容\n\n第二段", ["godot"], "manual")
	var ok: bool = (_a.eq(note.title, "测试笔记")
		and _a.eq(note.body, "正文内容\n\n第二段")
		and _a.eq(note.tags.size(), 1)
		and _a.eq(note.tags[0], "godot")
		and _a.eq(note.source, "manual")
		and _a.ok(not note.file_path.is_empty(), "file_path 不能为空")
		and _a.ok(note.created.length() > 0, "created 应自动填充")
		and _a.ok(note.updated.length() > 0, "updated 应自动填充"))
	_teardown()
	return ok


func test_create_and_get_note() -> bool:
	_setup()
	var note := KnowledgeBase.create_note("读取测试", "正文", [], "manual")
	var loaded := KnowledgeBase.get_note(note.file_path)
	var ok: bool = (_a.ok(loaded != null)
		and _a.eq(loaded.title, "读取测试")
		and _a.eq(loaded.body, "正文"))
	_teardown()
	return ok


func test_get_nonexistent_note() -> bool:
	_setup()
	var result := KnowledgeBase.get_note("notes/nonexist.md")
	var ok: bool = _a.ok(result == null, "不存在的笔记应返回 null")
	_teardown()
	return ok


func test_get_all_notes() -> bool:
	_setup()
	KnowledgeBase.create_note("A", "", [], "manual")
	KnowledgeBase.create_note("B", "", [], "manual")
	var ok: bool = _a.eq(KnowledgeBase.get_all_notes().size(), 2)
	_teardown()
	return ok


func test_update_note() -> bool:
	_setup()
	var note := KnowledgeBase.create_note("原文", "原正文", ["tag1"], "manual")
	note.title = "修改后"
	note.body = "新正文"
	note.tags = ["tag2"]
	KnowledgeBase.update_note(note)
	var reloaded := KnowledgeBase.get_note(note.file_path)
	var ok: bool = (_a.eq(reloaded.title, "修改后")
		and _a.eq(reloaded.body, "新正文")
		and _a.eq(reloaded.tags[0], "tag2")
		and _a.eq(reloaded.source, "manual"))
	_teardown()
	return ok


func test_delete_note() -> bool:
	_setup()
	var note := KnowledgeBase.create_note("待删除", "", [], "manual")
	var fp := note.file_path
	KnowledgeBase.delete_note(fp)
	var ok: bool = _a.ok(KnowledgeBase.get_note(fp) == null, "删除后应返回 null")
	_teardown()
	return ok


func test_delete_preserves_other() -> bool:
	_setup()
	var n1 := KnowledgeBase.create_note("保留", "", [], "manual")
	var n2 := KnowledgeBase.create_note("删除", "", [], "manual")
	KnowledgeBase.delete_note(n2.file_path)
	var all := KnowledgeBase.get_all_notes()
	var ok: bool = (_a.eq(all.size(), 1)
		and _a.eq(all[0].file_path, n1.file_path))
	_teardown()
	return ok


# --------------------------------------------------------------------------
#  搜索
# --------------------------------------------------------------------------

func test_kb_search() -> bool:
	_setup()
	KnowledgeBase.create_note("Godot引擎", "", ["godot"], "manual")
	KnowledgeBase.create_note("Unity入门", "", ["unity"], "manual")
	var ok: bool = _a.eq(KnowledgeBase.search("godot").size(), 1)
	_teardown()
	return ok


func test_kb_search_empty() -> bool:
	_setup()
	KnowledgeBase.create_note("A", "", [], "manual")
	KnowledgeBase.create_note("B", "", [], "manual")
	var ok: bool = _a.eq(KnowledgeBase.search("").size(), 2)
	_teardown()
	return ok


# --------------------------------------------------------------------------
#  标签操作
# --------------------------------------------------------------------------

func test_get_notes_by_tag() -> bool:
	_setup()
	KnowledgeBase.create_note("A", "", ["godot", "3d"], "manual")
	KnowledgeBase.create_note("B", "", ["unity"], "manual")
	var ok: bool = _a.eq(KnowledgeBase.get_notes_by_tag("godot").size(), 1)
	_teardown()
	return ok


func test_get_all_tags_sorted() -> bool:
	_setup()
	KnowledgeBase.create_note("A", "", ["ccc", "aaa", "bbb"], "manual")
	var tags := KnowledgeBase.get_all_tags()
	var ok: bool = (_a.eq(tags.size(), 3)
		and _a.eq(tags[0], "aaa")
		and _a.eq(tags[1], "bbb")
		and _a.eq(tags[2], "ccc"))
	_teardown()
	return ok


func test_get_tag_count() -> bool:
	_setup()
	KnowledgeBase.create_note("A", "", ["godot"], "manual")
	KnowledgeBase.create_note("B", "", ["godot", "3d"], "manual")
	var ok: bool = (_a.eq(KnowledgeBase.get_tag_count("godot"), 2)
		and _a.eq(KnowledgeBase.get_tag_count("3d"), 1)
		and _a.eq(KnowledgeBase.get_tag_count("nonexist"), 0))
	_teardown()
	return ok


# --------------------------------------------------------------------------
#  import_markdown
# --------------------------------------------------------------------------

func test_import_markdown_with_frontmatter() -> bool:
	_setup()
	var md := """---
title: "导入标题"
tags: [import, test]
source: manual
---
导入的正文内容。"""
	var note := KnowledgeBase.import_markdown(md, "import_test")
	var ok: bool = (_a.eq(note.title, "导入标题")
		and _a.eq(note.body, "导入的正文内容。")
		and _a.eq(note.tags.size(), 2)
		and _a.eq(note.source, "import_test"))
	_teardown()
	return ok


func test_import_markdown_no_title() -> bool:
	_setup()
	var md := "# 自动标题\n\n正文内容"
	var note := KnowledgeBase.import_markdown(md)
	var ok: bool = _a.eq(note.title, "自动标题")
	_teardown()
	return ok


# --------------------------------------------------------------------------
#  create_ai_summary
# --------------------------------------------------------------------------

func test_create_ai_summary() -> bool:
	_setup()
	var note := KnowledgeBase.create_ai_summary("原始长内容", "AI总结笔记", ["ai", "summary"], "这是AI生成的总结")
	var ok: bool = (_a.eq(note.title, "AI总结笔记")
		and _a.eq(note.source, "ai_summary")
		and _a.eq(note.summary, "这是AI生成的总结")
		and _a.eq(note.body, "原始长内容"))
	var loaded := KnowledgeBase.get_note(note.file_path)
	var ok2: bool = _a.ok(loaded != null, "AI 总结应写入文件")
	_teardown()
	return ok and ok2


# --------------------------------------------------------------------------
#  split_large_content
# --------------------------------------------------------------------------

func test_split_small_content() -> bool:
	var content := "段落一。\n\n段落二。\n\n段落三。"
	var chunks := KnowledgeBase.split_large_content(content, 4000)
	return _a.eq(chunks.size(), 1, "短内容不应分片")


func test_split_at_boundary() -> bool:
	var content := "段落一。\n\n段落二。\n\n段落三。\n\n段落四。\n\n段落五。"
	var chunks := KnowledgeBase.split_large_content(content, 20)
	return _a.ok(chunks.size() > 1, "应分成多片")


func test_split_empty() -> bool:
	var chunks := KnowledgeBase.split_large_content("", 100)
	return _a.eq(chunks.size(), 0)


func test_split_single_paragraph_exceeds_limit() -> bool:
	var long_para := "A" + "B".repeat(100)
	var chunks := KnowledgeBase.split_large_content(long_para, 10)
	return _a.eq(chunks.size(), 1, "单段超过限制应整体保留")
