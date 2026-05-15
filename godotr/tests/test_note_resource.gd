## NoteResource 模型单元测试
extends RefCounted

var _a: RefCounted


func _init() -> void:
	_a = load("res://tests/test_assert.gd").new()


# --------------------------------------------------------------------------
#  _to_slug
# --------------------------------------------------------------------------

func test_slug_basic_english() -> bool:
	return _a.eq(NoteResource._to_slug("Hello World"), "hello-world")


func test_slug_chinese_preserved() -> bool:
	var result := NoteResource._to_slug("你好世界")
	return _a.eq(result, "你好世界", "中文字符应保留")


func test_slug_mixed() -> bool:
	var result := NoteResource._to_slug("Godot 引擎入门")
	return _a.ok(result.length() > 0)


func test_slug_max_length() -> bool:
	var long_title := "a".repeat(100)
	var result := NoteResource._to_slug(long_title)
	return _a.ok(result.length() <= 60)


# --------------------------------------------------------------------------
#  _guess_title
# --------------------------------------------------------------------------

func test_guess_h1_title() -> bool:
	return _a.eq(NoteResource._guess_title("# 入门指南"), "入门指南")


func test_guess_title_no_hash() -> bool:
	return _a.eq(NoteResource._guess_title("这是正文内容"), "这是正文内容")


func test_guess_title_empty() -> bool:
	return _a.eq(NoteResource._guess_title(""), "")


# --------------------------------------------------------------------------
#  from_markdown 解析
# --------------------------------------------------------------------------

func test_from_markdown_with_frontmatter() -> bool:
	var md := """---
title: "测试笔记"
tags: [godot, gdscript]
created: 2026-01-15
source: manual
---
这是笔记正文内容。"""
	var note := NoteResource.from_markdown(md, "notes/test.md")
	return (_a.eq(note.title, "测试笔记")
		and _a.eq(note.tags.size(), 2)
		and _a.eq(note.tags[0], "godot")
		and _a.eq(note.tags[1], "gdscript")
		and _a.eq(note.created, "2026-01-15")
		and _a.eq(note.source, "manual")
		and _a.eq(note.body, "这是笔记正文内容。")
		and _a.eq(note.file_path, "notes/test.md"))


func test_from_markdown_no_frontmatter() -> bool:
	var md := "直接开始正文内容\n\n无 YAML 头"
	var note := NoteResource.from_markdown(md)
	return (_a.eq(note.body, md)
		and _a.ok(note.title.length() > 0, "应自动生成标题")
		and _a.ok(note.created.length() > 0, "应填充创建日期"))


func test_from_markdown_empty_body() -> bool:
	var md := """---
title: "空笔记"
tags: []
source: manual
---"""
	var note := NoteResource.from_markdown(md)
	return (_a.eq(note.title, "空笔记")
		and _a.eq(note.body, ""))


# --------------------------------------------------------------------------
#  to_frontmatter 序列化
# --------------------------------------------------------------------------

func test_to_frontmatter_basic() -> bool:
	var note := NoteResource.new()
	note.title = "测试"
	note.tags = ["gdx"]
	note.created = "2026-01-15"
	note.source = "manual"
	var fm := note.to_frontmatter()
	return (_a.contains(fm, "---")
		and _a.contains(fm, "title:")
		and _a.contains(fm, "gdx")
		and _a.contains(fm, "2026-01-15"))


func test_to_frontmatter_no_tags() -> bool:
	var note := NoteResource.new()
	note.title = "无标签"
	note.created = "2026-01-15"
	note.source = "manual"
	var fm := note.to_frontmatter()
	return _a.ok(not "tags:" in fm)


func test_to_frontmatter_with_summary() -> bool:
	var note := NoteResource.new()
	note.title = "有摘要"
	note.source = "manual"
	note.summary = "这是一个摘要"
	var fm := note.to_frontmatter()
	return _a.contains(fm, "summary:")


# --------------------------------------------------------------------------
#  to_markdown
# --------------------------------------------------------------------------

func test_to_markdown_roundtrip() -> bool:
	var expected_body := "正文段落一\n\n正文段落二"
	var note := NoteResource.new()
	note.title = "往返测试"
	note.body = expected_body
	note.source = "manual"
	return _a.ok(note.to_markdown().ends_with(expected_body))


# --------------------------------------------------------------------------
#  get_filename
# --------------------------------------------------------------------------

func test_get_filename_format() -> bool:
	var note := NoteResource.new()
	note.title = "Hello World"
	note.created = "2026-01-15"
	var filename := note.get_filename()
	return (_a.ok(filename.ends_with(".md"))
		and _a.ok(filename.begins_with("20260115"))
		and _a.contains(filename, "hello-world"))
