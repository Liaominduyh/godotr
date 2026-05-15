## 知识库主界面 — Steam 风格卡片网格 + 标签筛选
extends Control

@onready var title_label: Label = $VBox/TopBar/TopInner/TitleLabel
@onready var search_input: LineEdit = $VBox/TopBar/TopInner/SearchInput
@onready var card_container: HFlowContainer = $VBox/Scroll/Margin/CardGrid
@onready var settings_btn: MenuButton = $VBox/TopBar/TopInner/SettingsBtn
@onready var mcp_btn: Button = $VBox/TopBar/TopInner/MCPBtn
@onready var import_btn: Button = $VBox/TopBar/TopInner/ImportBtn
@onready var add_btn: Button = $VBox/TopBar/TopInner/AddBtn
@onready var empty_label: Label = $EmptyLabel
@onready var tag_bar: MarginContainer = $VBox/TagBar
@onready var tag_chips: HBoxContainer = $VBox/TagBar/TagScroll/TagChips

var all_notes: Array[NoteResource] = []
var _active_tag: String = ""  # 空 = 全部
var _import_popup: PopupMenu

# MCP 本地服务
var _mcp_server: TCPServer
var _mcp_port: int = 8090
var _mcp_timer: Timer
var _mcp_peers: Array[StreamPeerTCP] = []

# 用户设置
var _font_path: String = ""
var _tag_colors: Dictionary = {}  # tag → {font: "#hex", bg: "#hex"}


func _ready() -> void:
	search_input.text_changed.connect(_on_search)
	add_btn.pressed.connect(_new_note)
	settings_btn.get_popup().add_item("MCP 说明", 0)
	settings_btn.get_popup().add_item("字体设置", 1)
	settings_btn.get_popup().add_item("导出全部笔记", 2)
	settings_btn.get_popup().add_separator()
	settings_btn.get_popup().add_item("关于", 3)
	settings_btn.get_popup().id_pressed.connect(_on_settings_menu)
	mcp_btn.toggled.connect(_toggle_mcp)
	import_btn.pressed.connect(_show_import_menu)
	EventBus.knowledge_base_ready.connect(refresh)
	_load_settings()
	_build_import_menu()
	refresh()


func refresh() -> void:
	all_notes = KnowledgeBase.get_all_notes()
	all_notes.sort_custom(func(a: NoteResource, b: NoteResource): return a.updated > b.updated)
	title_label.text = "知识库 (%d 篇)" % all_notes.size()
	_rebuild_tags()
	_rebuild(all_notes)


func _rebuild_tags() -> void:
	for child in tag_chips.get_children():
		child.queue_free()

	var tags := KnowledgeBase.get_all_tags()
	if tags.is_empty():
		tag_bar.hide()
		return

	tag_bar.show()

	# "全部" 按钮
	var all_btn := _make_tag_btn("全部", "")
	tag_chips.add_child(all_btn)

	for tag in tags:
		var count := KnowledgeBase.get_tag_count(tag)
		var label := "%s (%d)" % [tag, count]
		var btn := _make_tag_btn(label, tag)
		tag_chips.add_child(btn)


func _rebuild(notes: Array[NoteResource]) -> void:
	for child in card_container.get_children():
		child.queue_free()

	if notes.is_empty():
		empty_label.show()
		if all_notes.is_empty():
			empty_label.text = "暂无笔记，点击右上角「+ 新建笔记」开始"
		elif not search_input.text.strip_edges().is_empty() and not _active_tag.is_empty():
			empty_label.text = "没有同时匹配「%s」和标签「%s」的笔记" % [search_input.text.strip_edges(), _active_tag]
		elif not _active_tag.is_empty():
			empty_label.text = "没有包含标签「%s」的笔记" % _active_tag
		else:
			empty_label.text = "没有匹配的笔记，换个关键词试试"
		return

	empty_label.hide()
	for note in notes:
		var card: Node = load("res://scenes/components/NoteCard.tscn").instantiate()
		card_container.add_child(card)
		card.setup(note, _tag_colors)


func _apply_filters() -> void:
	var result := all_notes.duplicate()
	# 搜索筛选
	var q := search_input.text.strip_edges()
	if not q.is_empty():
		result = KnowledgeBase.search(q)
	# 标签筛选
	if not _active_tag.is_empty():
		var filtered: Array[NoteResource] = []
		for note in result:
			if _active_tag in note.tags:
				filtered.append(note)
		result = filtered
	_rebuild(result)


func _on_search(_query: String) -> void:
	_apply_filters()


func _on_tag_clicked(tag: String) -> void:
	_active_tag = tag
	_rebuild_tags()
	_apply_filters()


func _new_note() -> void:
	KnowledgeBase.pending_note_path = ""
	get_tree().change_scene_to_file("res://scenes/main/NoteScene.tscn")


func _make_tag_btn(label: String, tag: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.flat = false
	btn.add_theme_font_size_override("font_size", 12)

	# 块状背景 — 选中蓝色，未选中灰色
	var normal_sb := StyleBoxFlat.new()
	var hover_sb := StyleBoxFlat.new()
	if _active_tag == tag:
		normal_sb.bg_color = Color(0.2, 0.42, 0.7, 0.7)
		hover_sb.bg_color = Color(0.25, 0.5, 0.8, 0.8)
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	else:
		normal_sb.bg_color = Color(0.25, 0.25, 0.28, 0.7)
		hover_sb.bg_color = Color(0.32, 0.32, 0.36, 0.8)
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))

	normal_sb.corner_radius_top_left = 4
	normal_sb.corner_radius_top_right = 4
	normal_sb.corner_radius_bottom_left = 4
	normal_sb.corner_radius_bottom_right = 4
	normal_sb.content_margin_left = 8
	normal_sb.content_margin_right = 8
	normal_sb.content_margin_top = 4
	normal_sb.content_margin_bottom = 4

	hover_sb.corner_radius_top_left = 4
	hover_sb.corner_radius_top_right = 4
	hover_sb.corner_radius_bottom_left = 4
	hover_sb.corner_radius_bottom_right = 4
	hover_sb.content_margin_left = 8
	hover_sb.content_margin_right = 8
	hover_sb.content_margin_top = 4
	hover_sb.content_margin_bottom = 4

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)

	# 左键筛选，右键设置颜色（"全部" 除外）
	btn.pressed.connect(func(): _on_tag_clicked(tag))
	if not tag.is_empty():
		btn.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_show_tag_color_menu(tag, btn)
		)
	return btn


func _show_tag_color_menu(tag: String, btn: Button) -> void:
	var popup := PopupMenu.new()
	popup.add_item("设置字体颜色", 0)
	popup.add_item("设置标签背景颜色", 1)
	popup.add_item("设置字体大小", 2)
	popup.id_pressed.connect(func(id: int):
		match id:
			0: _pick_tag_color(tag, "font")
			1: _pick_tag_color(tag, "bg")
			2: _set_tag_font_size(tag)
	)
	add_child(popup)
	popup.position = btn.get_screen_position() + Vector2(0, btn.size.y)
	popup.popup()


func _pick_tag_color(tag: String, key: String) -> void:
	var picker := ColorPicker.new()
	if _tag_colors.has(tag) and _tag_colors[tag].has(key):
		picker.color = Color(_tag_colors[tag][key])
	picker.color_changed.connect(func(c: Color):
		if not _tag_colors.has(tag):
			_tag_colors[tag] = {}
		_tag_colors[tag][key] = c.to_html(false)
		_save_settings()
		_rebuild(all_notes)
	)
	var popup := PopupPanel.new()
	popup.add_child(picker)
	add_child(popup)
	popup.popup_centered()


func _set_tag_font_size(tag: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "标签字体大小 — " + tag
	dialog.ok_button_text = "确定"

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var spin := SpinBox.new()
	spin.min_value = 8
	spin.max_value = 30
	spin.step = 1
	if _tag_colors.has(tag) and _tag_colors[tag].has("size"):
		spin.value = int(_tag_colors[tag]["size"])
	else:
		spin.value = 14
	vbox.add_child(spin)

	dialog.confirmed.connect(func():
		if not _tag_colors.has(tag):
			_tag_colors[tag] = {}
		_tag_colors[tag]["size"] = str(int(spin.value))
		_save_settings()
		_rebuild(all_notes)
	)

	add_child(dialog)
	dialog.popup_centered()


# --------------------------------------------------------------------------
#  导入
# --------------------------------------------------------------------------

func _build_import_menu() -> void:
	_import_popup = PopupMenu.new()
	_import_popup.add_item("从 URL 导入", 0)
	_import_popup.add_item("从文件导入", 1)
	_import_popup.add_item("粘贴 Markdown", 2)
	_import_popup.add_item("手动 AI 总结", 3)
	_import_popup.id_pressed.connect(_on_import_option)
	add_child(_import_popup)


func _show_import_menu() -> void:
	_import_popup.position = import_btn.get_screen_position() + Vector2(0, import_btn.size.y)
	_import_popup.popup()


func _on_import_option(id: int) -> void:
	match id:
		0: _import_url_dialog()
		1: _import_file_dialog()
		2: _import_paste_dialog()
		3: _ai_summary_dialog()


func _import_url_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "从 URL 导入"
	dialog.ok_button_text = "导入"

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var label := Label.new()
	label.text = "输入网页或文档 URL："
	vbox.add_child(label)

	var url_input := LineEdit.new()
	url_input.placeholder_text = "https://..."
	url_input.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(url_input)

	var status := Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(status)

	dialog.confirmed.connect(func():
		var url := url_input.text.strip_edges()
		if url.is_empty():
			return
		status.text = "正在获取..."
		_do_url_import(url, status)
	)

	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


func _do_url_import(url: String, status: Label) -> void:
	var result: Dictionary = await KnowledgeBase.import_from_url(url)
	if result.get("success"):
		status.text = "导入成功！"
		status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
		refresh()
	else:
		var err: String = result.get("error", "未知错误")
		status.text = "导入失败: %s" % err
		status.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))


func _import_file_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.add_filter("*.md, *.txt, *.json", "Markdown / 文本文件")

	fd.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			return
		var text := file.get_as_text()
		KnowledgeBase.import_markdown(text, "import_file")
		refresh()
	)

	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _import_paste_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "粘贴 Markdown"
	dialog.ok_button_text = "导入"
	dialog.size = Vector2(500, 400)

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var label := Label.new()
	label.text = "粘贴 Markdown 内容（支持 YAML frontmatter）："
	vbox.add_child(label)

	var editor := TextEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.placeholder_text = "在此粘贴 Markdown 内容..."
	vbox.add_child(editor)

	var status := Label.new()
	vbox.add_child(status)

	dialog.confirmed.connect(func():
		var text := editor.text.strip_edges()
		if text.is_empty():
			return
		var note := KnowledgeBase.import_markdown(text)
		status.text = "导入成功: %s" % note.title
		status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
		refresh()
	)

	add_child(dialog)
	dialog.popup_centered()


func _ai_summary_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "手动 AI 总结"
	dialog.ok_button_text = "保存"
	dialog.size = Vector2(520, 480)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	var lbl_t := Label.new()
	lbl_t.text = "标题："
	vbox.add_child(lbl_t)

	var title_in := LineEdit.new()
	title_in.placeholder_text = "AI 总结标题"
	vbox.add_child(title_in)

	var lbl_tags := Label.new()
	lbl_tags.text = "标签（逗号分隔）："
	vbox.add_child(lbl_tags)

	var tags_in := LineEdit.new()
	tags_in.placeholder_text = "ai, 总结"
	vbox.add_child(tags_in)

	var lbl_content := Label.new()
	lbl_content.text = "原始内容："
	vbox.add_child(lbl_content)

	var content_edit := TextEdit.new()
	content_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_edit.placeholder_text = "粘贴原始文档或 URL 内容..."
	vbox.add_child(content_edit)

	var lbl_summary := Label.new()
	lbl_summary.text = "AI 总结："
	vbox.add_child(lbl_summary)

	var summary_edit := TextEdit.new()
	summary_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_edit.placeholder_text = "粘贴 AI 生成的总结..."
	vbox.add_child(summary_edit)

	var status := Label.new()
	vbox.add_child(status)

	dialog.confirmed.connect(func():
		var title := title_in.text.strip_edges()
		if title.is_empty():
			status.text = "请输入标题"
			status.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
			return
		var tags_str := tags_in.text.strip_edges()
		var tags: Array[String] = []
		if not tags_str.is_empty():
			var raw := tags_str.split(",", false)
			for t in raw:
				var tag: String = t.strip_edges()
				if not tag.is_empty():
					tags.append(tag)
		var note := KnowledgeBase.create_ai_summary(
			content_edit.text,
			title,
			tags,
			summary_edit.text
		)
		status.text = "已保存: %s" % note.title
		status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
		refresh()
	)

	add_child(dialog)
	dialog.popup_centered()


# --------------------------------------------------------------------------
#  设置
# --------------------------------------------------------------------------

func _load_settings() -> void:
	var path := _settings_path()
	if not FileAccess.file_exists(path):
		return
	var text := _read_text_file(path)
	if text.is_empty():
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data := json.data as Dictionary
	if data.is_empty():
		return
	_font_path = data.get("font_path", "")
	_tag_colors = data.get("tag_colors", {})
	_apply_font()


func _on_settings_menu(id: int) -> void:
	match id:
		0: _settings_dialog()
		1: _font_dialog()
		2: _export_dialog()
		3: _about_dialog()


func _font_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "字体设置"
	dialog.ok_button_text = "确定"
	dialog.size = Vector2(360, 120)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "选择字体："
	vbox.add_child(lbl)

	var dropdown := OptionButton.new()
	var fonts := _get_available_fonts()
	dropdown.add_item("系统默认", 0)
	dropdown.set_item_metadata(0, "")
	var selected_idx := 0
	for i in fonts.size():
		var info: Dictionary = fonts[i]
		dropdown.add_item(info.name, i + 1)
		dropdown.set_item_metadata(i + 1, info.path)
		if info.path == _font_path:
			selected_idx = i + 1
	dropdown.select(selected_idx)
	vbox.add_child(dropdown)

	dialog.confirmed.connect(func():
		var idx := dropdown.selected
		_font_path = dropdown.get_item_metadata(idx) as String
		_save_settings()
		_apply_font()
	)

	add_child(dialog)
	dialog.popup_centered()


func _get_available_fonts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# 编辑器：扫描 res:// 目录
	_scan_font_dir(result, "res://runtime/fonts")
	# 部署模式：扫描 godotr/runtime/fonts（支持部署后添加字体）
	var godotr_dir := KnowledgeBase.get_godotr_dir()
	if not godotr_dir.is_empty():
		_scan_font_dir(result, godotr_dir.path_join("runtime/fonts"))
	return result


func _scan_font_dir(result: Array[Dictionary], dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name:
		if name.ends_with(".ttf") or name.ends_with(".otf"):
			var full := dir_path.path_join(name) if dir_path.ends_with("/") else dir_path + "/" + name
			# 避免重复（同名文件）
			var dup := false
			for r in result:
				if r.name == name:
					dup = true
					break
			if not dup:
				result.append({"name": name, "path": full})
		name = dir.get_next()
	dir.list_dir_end()


func _apply_font() -> void:
	var theme := get_tree().root.theme
	if not theme:
		theme = Theme.new()
		get_tree().root.theme = theme
	if _font_path.is_empty():
		theme.default_font = null
		return
	if not FileAccess.file_exists(_font_path):
		return
	var font: Font = load(_font_path)
	theme.default_font = font




func _save_settings() -> void:
	var data: Dictionary = {
		"font_path": _font_path,
		"tag_colors": _tag_colors,
	}
	var json_text := JSON.new().stringify(data, "\t")
	var path := _settings_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_text)


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	return file.get_as_text()


func _settings_path() -> String:
	var godotr_dir := KnowledgeBase.get_godotr_dir()
	if not godotr_dir.is_empty():
		return godotr_dir.path_join("settings.json")
	return ProjectSettings.globalize_path("user://settings.json")


func _settings_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "设置"
	dialog.ok_button_text = "确定"
	dialog.size = Vector2(360, 140)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	var info := Label.new()
	info.text = "MCP 服务端口: 8090\nAI 功能通过 MCP 接入，无需配置 API Key。\n字体配置请使用「字体设置」。"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)

	add_child(dialog)
	dialog.popup_centered()


# --------------------------------------------------------------------------
#  AI API 调用
# --------------------------------------------------------------------------

func _export_dialog() -> void:
	var all := KnowledgeBase.get_all_notes()
	if all.is_empty():
		var d := AcceptDialog.new()
		d.title = "导出"
		d.dialog_text = "没有可导出的笔记"
		add_child(d)
		d.popup_centered()
		return

	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "选择导出目录"

	fd.dir_selected.connect(func(path: String):
		var notes_dir := KnowledgeBase.kb_dir + "/" + KnowledgeBase.NOTES_DIR
		var count := 0
		for note in all:
			var src := notes_dir + "/" + note.get_filename()
			var dst := path + "/" + note.get_filename()
			var err := DirAccess.copy_absolute(src, dst)
			if err == OK:
				count += 1
		var d2 := AcceptDialog.new()
		d2.title = "导出完成"
		d2.dialog_text = "已导出 %d/%d 篇笔记到:\n%s" % [count, all.size(), path]
		add_child(d2)
		d2.popup_centered()
	)

	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _about_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "关于"
	dialog.ok_button_text = "好的"
	dialog.size = Vector2(320, 200)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	dialog.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = "知识库 — 本地知识管理系统"
	name_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_lbl)

	var ver_lbl := Label.new()
	ver_lbl.text = "版本 1.0  ·  Godot 4.6"
	ver_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(ver_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var desc := Label.new()
	desc.text = "面向游戏开发者的个人知识库工具。\n支持 Markdown 编辑、标签管理、全文搜索、\n外部导入和 AI 总结。"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	add_child(dialog)
	dialog.popup_centered()


# --------------------------------------------------------------------------
#  MCP 本地服务
# --------------------------------------------------------------------------

func _toggle_mcp(on: bool) -> void:
	if on:
		_start_mcp()
	else:
		_stop_mcp()


func _start_mcp() -> void:
	_mcp_server = TCPServer.new()
	var err := _mcp_server.listen(_mcp_port, "127.0.0.1")
	if err != OK:
		mcp_btn.text = "MCP ✗"
		mcp_btn.button_pressed = false
		return
	mcp_btn.text = "MCP ✓"
	_mcp_timer = Timer.new()
	_mcp_timer.wait_time = 0.3
	_mcp_timer.timeout.connect(_poll_mcp)
	add_child(_mcp_timer)
	_mcp_timer.start()
	print("MCP 服务已启动: 127.0.0.1:%d" % _mcp_port)


func _stop_mcp() -> void:
	if _mcp_timer:
		_mcp_timer.queue_free()
	for peer in _mcp_peers:
		peer.disconnect_from_host()
	_mcp_peers.clear()
	if _mcp_server:
		_mcp_server.stop()
	mcp_btn.text = "MCP"
	print("MCP 服务已停止")


func _poll_mcp() -> void:
	if not _mcp_server or not _mcp_server.is_connection_available():
		return
	var peer: StreamPeerTCP = _mcp_server.take_connection()
	if not peer:
		return
	_mcp_peers.append(peer)


func _process(_delta: float) -> void:
	for i in range(_mcp_peers.size() - 1, -1, -1):
		var peer := _mcp_peers[i]
		peer.poll()
		match peer.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				var avail := peer.get_available_bytes()
				if avail > 0:
					var data := peer.get_string(avail)
					var response := _handle_mcp(data)
					peer.put_string(response + "\n")
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				peer.disconnect_from_host()
				_mcp_peers.remove_at(i)


func _handle_mcp(raw: String) -> String:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return JSON.stringify({"error": "invalid json"})

	var req: Dictionary = json.data as Dictionary
	var method: String = req.get("method", "")
	var params: Dictionary = req.get("params", {})

	match method:
		"search":
			var query: String = params.get("query", "")
			var results := KnowledgeBase.search(query)
			var items: Array[Dictionary] = []
			for note in results.slice(0, 20):
				items.append({"title": note.title, "file_path": note.file_path, "tags": note.tags, "created": note.created})
			return JSON.stringify({"items": items})

		"get_note":
			var path: String = params.get("file_path", "")
			var note := KnowledgeBase.get_note(path)
			if not note:
				return JSON.stringify({"error": "not found"})
			return JSON.stringify({"title": note.title, "body": note.body, "tags": note.tags, "created": note.created, "updated": note.updated, "source": note.source, "summary": note.summary})

		"list_notes":
			var all := KnowledgeBase.get_all_notes()
			var items: Array[Dictionary] = []
			for note in all.slice(0, 50):
				items.append({"title": note.title, "file_path": note.file_path, "tags": note.tags})
			return JSON.stringify({"items": items})

		"get_tags":
			var tags := KnowledgeBase.get_all_tags()
			var tag_list: Array[Dictionary] = []
			for tag in tags:
				tag_list.append({"name": tag, "count": KnowledgeBase.get_tag_count(tag)})
			return JSON.stringify({"tags": tag_list})

		"create_summary":
			var note := KnowledgeBase.create_ai_summary(
				params.get("content", ""),
				params.get("title", ""),
				Array(params.get("tags", [])),
				params.get("summary", "")
			)
			return JSON.stringify({"file_path": note.file_path, "title": note.title})

		_:
			return JSON.stringify({"error": "unknown method: " + method})
