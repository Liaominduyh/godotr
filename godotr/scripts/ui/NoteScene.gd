## 笔记查看/编辑场景 — 全屏，支持查看/编辑模式切换
extends Control

var _file_path: String = ""
var _is_view_mode: bool = true
var _is_new: bool = false
var _dirty: bool = false

# Markdown → BBCode 编译好的正则（_ready 中初始化）
var _md_re: Array[RegEx] = []
var _md_sub: Array[String] = []
var _auto_save_timer: Timer

@onready var back_btn: Button = $TopBar/TopInner/BackBtn
@onready var mode_btn: Button = $TopBar/TopInner/ModeBtn
@onready var save_btn: Button = $TopBar/TopInner/SaveBtn
@onready var delete_btn: Button = $TopBar/TopInner/DeleteBtn
@onready var title_input: LineEdit = $VBox/TitleInput
@onready var tag_input: LineEdit = $VBox/TagRow/TagInput
@onready var tag_view_label: Label = $VBox/TagRow/TagViewLabel
@onready var body_editor: TextEdit = $VBox/BodyEditor
@onready var body_display: RichTextLabel = $VBox/BodyDisplay
@onready var word_count_label: Label = $VBox/StatusBar/WordCount
@onready var save_status_label: Label = $VBox/StatusBar/SaveStatus


func _ready() -> void:
	back_btn.pressed.connect(_go_back)
	mode_btn.pressed.connect(_toggle_mode)
	save_btn.pressed.connect(_save)
	delete_btn.pressed.connect(_delete)

	# 自动保存定时器
	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = 2.0
	_auto_save_timer.one_shot = true
	_auto_save_timer.timeout.connect(_auto_save)
	add_child(_auto_save_timer)
	title_input.text_changed.connect(_reset_auto_save)
	tag_input.text_changed.connect(_reset_auto_save)
	body_editor.text_changed.connect(_reset_auto_save)
	body_editor.text_changed.connect(_update_status_bar)
	title_input.text_changed.connect(_mark_dirty)
	body_editor.text_changed.connect(_mark_dirty)

	_init_md_regex()
	_setup_syntax_highlighter()

	_file_path = KnowledgeBase.pending_note_path
	_is_new = _file_path.is_empty()

	if _is_new:
		_is_view_mode = false
		_apply_mode()
		title_input.grab_focus()
	else:
		_load_note(_file_path)
		_apply_mode()


func _load_note(file_path: String) -> void:
	var note := KnowledgeBase.get_note(file_path)
	if not note:
		return

	title_input.text = note.title
	tag_input.text = ", ".join(note.tags)
	tag_view_label.text = "# " + "  #".join(note.tags) if note.tags.size() > 0 else ""
	body_editor.text = note.body
	body_display.text = _md_to_bbcode(note.body)
	_update_status_bar()


func _apply_mode() -> void:
	delete_btn.visible = not _is_new
	if _is_view_mode:
		mode_btn.text = "编辑"
		save_btn.hide()
		title_input.editable = false
		tag_input.hide()
		tag_view_label.show()
		body_editor.hide()
		body_display.show()
	else:
		mode_btn.text = "查看"
		save_btn.show()
		title_input.editable = true
		tag_input.show()
		tag_view_label.hide()
		body_editor.show()
		body_display.hide()


func _toggle_mode() -> void:
	_is_view_mode = not _is_view_mode
	if not _is_view_mode and not _is_new:
		var note := KnowledgeBase.get_note(_file_path)
		if note:
			body_editor.text = note.body
	_apply_mode()


func _save() -> void:
	var title := title_input.text.strip_edges()
	if title.is_empty():
		_show_save_hint("请输入笔记标题")
		return

	var tags_str := tag_input.text.strip_edges()
	var tags: Array[String] = []
	if not tags_str.is_empty():
		for raw in tags_str.split(",", false):
			var tag: String = raw.strip_edges()
			if not tag.is_empty():
				tags.append(tag)

	var body := body_editor.text

	if _is_new:
		var note := KnowledgeBase.create_note(title, body, tags, "manual")
		KnowledgeBase.update_note(note)
		_file_path = note.file_path
		_is_new = false
	else:
		var note := KnowledgeBase.get_note(_file_path)
		if note:
			note.title = title
			note.tags = tags
			note.body = body
			KnowledgeBase.update_note(note)

	_is_view_mode = true
	_load_note(_file_path)
	_apply_mode()
	_update_status_bar()
	_dirty = false




func _mark_dirty(_arg = "") -> void:
	if not _is_view_mode:
		_dirty = true


func _delete() -> void:
	if _dirty:
		_confirm_action("删除", "有未保存的修改，确定要删除吗？", func(): _do_delete())
		return
	_do_delete()


func _do_delete() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认删除"
	dialog.dialog_text = "确定要删除「%s」吗？此操作不可撤销。" % title_input.text
	dialog.confirmed.connect(func():
		KnowledgeBase.delete_note(_file_path)
		_go_back()
	)
	add_child(dialog)
	dialog.popup_centered()


func _reset_auto_save(_arg = "") -> void:
	if _is_view_mode:
		return
	_auto_save_timer.start()


func _auto_save() -> void:
	if _is_view_mode:
		return
	_save()


func _update_status_bar() -> void:
	var text := body_editor.text
	var words := text.split(" ", false).size() if text else 0
	var lines := body_editor.get_line_count()
	word_count_label.text = "字数: %d  ·  行数: %d" % [words, lines]
	word_count_label.add_theme_font_size_override("font_size", 15)
	word_count_label.add_theme_color_override("font_color", Color(0.26, 0.75, 0.35))

	var now := Time.get_datetime_string_from_system().split("T")[1].split(":")
	var time_str := "%s:%s" % [now[0], now[1]]
	var status_text := "已保存 %s" % time_str
	save_status_label.text = status_text
	save_status_label.add_theme_font_size_override("font_size", 15)
	save_status_label.add_theme_color_override("font_color", Color(0.26, 0.75, 0.35))


func _show_save_hint(msg: String) -> void:
	var hint := Label.new()
	hint.text = msg
	hint.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0
	add_child(hint)
	# 放在标题输入框下方
	hint.position = title_input.position + Vector2(0, title_input.size.y + 4)
	hint.size.x = title_input.size.x
	var tw := create_tween()
	tw.tween_property(hint, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.5)
	tw.tween_property(hint, "modulate:a", 0.0, 0.5)
	tw.tween_callback(hint.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	_reset_auto_save()
	match event.keycode:
		KEY_ESCAPE:
			_go_back()
		KEY_S:
			if event.ctrl_pressed or event.meta_pressed:
				_save()
		KEY_D:
			if (event.ctrl_pressed or event.meta_pressed) and not _is_new:
				_delete()


func _go_back() -> void:
	if _dirty:
		_confirm_action("返回", "有未保存的修改，确定要离开吗？", func(): _do_go_back())
		return
	_do_go_back()


func _do_go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main/LibraryScene.tscn")


func _confirm_action(title: String, msg: String, on_confirm: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = msg
	dialog.confirmed.connect(on_confirm)
	add_child(dialog)
	dialog.popup_centered()


func _init_md_regex() -> void:
	var patterns: Array[String] = [
		# 标题 — 必须在加粗/斜体之前，避免 [b] 嵌套
		"(?m)^### (.+)$",
		"(?m)^## (.+)$",
		"(?m)^# (.+)$",
		# 行内代码
		"`([^`]+)`",
		# 加粗
		"\\*\\*(.+?)\\*\\*",
		# 斜体
		"\\*(.+?)\\*",
		# 链接
		"\\[([^\\]]+)\\]\\(([^)]+)\\)",
		# 图片
		"!\\[([^\\]]*)\\]\\(([^)]+)\\)",
		# 无序列表
		"(?m)^- (.+)$",
		# 水平线
		"(?m)^---+$",
	]
	var replacements: Array[String] = [
		"[font_size=16]$1[/font_size]",
		"[font_size=19]$1[/font_size]",
		"[font_size=23]$1[/font_size]",
		"[code]$1[/code]",
		"[b]$1[/b]",
		"[i]$1[/i]",
		"[url=$2]$1[/url]",
		"[img]$2[/img]",
		"• $1",
		"[fill]━[/fill]",
	]
	for pat in patterns:
		var r := RegEx.new()
		r.compile(pat)
		_md_re.append(r)
	_md_sub = replacements


func _setup_syntax_highlighter() -> void:
	var hl := CodeHighlighter.new()
	# 数字
	hl.number_color = Color(0.71, 0.78, 0.66)
	# 符号
	hl.symbol_color = Color(0.46, 0.46, 0.46)
	# 行内代码
	hl.add_color_region("`", "`", Color(0.85, 0.65, 0.35), true)
	# 加粗
	hl.add_color_region("**", "**", Color(0.33, 0.60, 0.87), true)
	# 斜体
	hl.add_color_region("*", "*", Color(0.33, 0.60, 0.87), true)
	# 链接文字
	hl.add_color_region("[", "]", Color(0.33, 0.60, 0.87), true)
	# 关键词（标题标记 `#` 在行首时高亮）
	hl.keyword_colors = {
		"#": Color(0.57, 0.36, 0.51),
		"##": Color(0.57, 0.36, 0.51),
		"###": Color(0.57, 0.36, 0.51),
	}
	body_editor.syntax_highlighter = hl


func _md_to_bbcode(md: String) -> String:
	var bb := _highlight_code_blocks(md)
	# 从索引 0 开始（围栏代码块已移除，剩余 10 个正则）
	for i in _md_re.size():
		bb = _md_re[i].sub(bb, _md_sub[i], true)
	return bb


func _highlight_code_blocks(text: String) -> String:
	var re := RegEx.new()
	re.compile("```(\\w*)\\n?([\\s\\S]*?)```")
	var matches := re.search_all(text)
	var result := text
	# 从后向前替换，保持索引有效
	for idx in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[idx]
		var lang := m.get_string(1)
		var code := m.get_string(2)
		var colored := _highlight_code(code, lang)
		result = result.substr(0, m.get_start()) + "[code]" + colored + "[/code]" + result.substr(m.get_end())
	return result


func _highlight_code(code: String, lang: String) -> String:
	var kw: Array[String] = []
	if lang in ["gdscript", "gd", ""]:
		kw = ["func", "var", "extends", "if", "else", "elif", "for", "while",
			"return", "class", "static", "const", "signal", "match", "break",
			"continue", "pass", "await", "void", "int", "float", "String",
			"bool", "Array", "Dictionary", "true", "false", "null", "self",
			"super", "not", "and", "or", "is", "as", "in", "enum",
			"class_name", "@export", "@onready", "@tool", "@rpc"]
	elif lang in ["csharp", "cs", "c#"]:
		kw = ["using", "namespace", "class", "struct", "interface", "void",
			"int", "float", "double", "string", "bool", "var", "public",
			"private", "protected", "static", "override", "virtual", "new",
			"return", "if", "else", "for", "foreach", "while", "break",
			"continue", "null", "true", "false", "async", "await", "this"]

	var result := code
	# 注释
	var cmt := RegEx.new()
	cmt.compile("(#.+)$")
	result = cmt.sub(result, "[color=#6a9955]$1[/color]", true)

	# 字符串
	var sre := RegEx.new()
	sre.compile("(\"[^\"]*\")")
	result = sre.sub(result, "[color=#ce9178]$1[/color]", true)

	# 数字
	var num := RegEx.new()
	num.compile("\\b(\\d+)\\b")
	result = num.sub(result, "[color=#b5cea8]$1[/color]", true)

	# 关键词
	var escaped: Array[String] = []
	for k in kw:
		escaped.append("\\b" + k.replace("@", "\\@").replace("?", "\\?").replace("#", "\\#") + "\\b")
	var kw_re := RegEx.new()
	kw_re.compile("(" + "|".join(escaped) + ")")
	result = kw_re.sub(result, "[color=#569cd6]$1[/color]", true)

	return result
