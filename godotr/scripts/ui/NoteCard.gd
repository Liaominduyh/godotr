## 笔记卡片 — 日期居中 / 大标题 / 词条标签流式排列
extends Panel

var file_path: String = ""
var _normal_bg: Color = Color(0.07, 0.07, 0.08, 1)
var _hover_bg: Color = Color(0.12, 0.13, 0.15, 1)
var _accent_original: Color

@onready var accent_bar: ColorRect = $AccentBar
@onready var date_label: Label = $Margin/VBox/DateLabel
@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var tag_container: HFlowContainer = $Margin/VBox/TagContainer

const _source_colors := {
	"manual": Color(0.3, 0.5, 0.8, 1),
	"import_url": Color(0.3, 0.7, 0.4, 1),
	"import_file": Color(0.9, 0.6, 0.2, 1),
	"ai_summary": Color(0.6, 0.3, 0.9, 1),
}


func _ready() -> void:
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)


func setup(note: NoteResource, tag_colors: Dictionary = {}) -> void:
	file_path = note.file_path

	# 第一行 — 日期（居中，白色，30号）
	date_label.text = note.created
	date_label.add_theme_color_override("font_color", Color(1, 1, 1))

	# 第二行 — 标题（自动缩放字号，最大 40，最小 18）
	title_label.text = note.title
	_auto_fit_title(note.title)

	# 第三行 — 词条标签（一行 3 个，满了换行）
	for child in tag_container.get_children():
		child.queue_free()
	if note.tags.size() > 0:
		for tag in note.tags:
			tag_container.add_child(_make_tag_chip(tag, note.tag_color, tag_colors))
		tag_container.show()
	else:
		tag_container.hide()

	# 左侧彩色边条
	accent_bar.color = _source_colors.get(note.source, Color(0.3, 0.5, 0.8, 1))
	_accent_original = accent_bar.color


func _on_hover() -> void:
	hover_sound.play()
	var sb := get_theme_stylebox("panel").duplicate()
	sb.bg_color = _hover_bg
	add_theme_stylebox_override("panel", sb)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.025, 1.025), 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(accent_bar, "color", _accent_original * 1.4, 0.15)


func _on_unhover() -> void:
	var sb := get_theme_stylebox("panel").duplicate()
	sb.bg_color = _normal_bg
	add_theme_stylebox_override("panel", sb)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(accent_bar, "color", _accent_original, 0.2)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		KnowledgeBase.pending_note_path = file_path
		get_tree().change_scene_to_file("res://scenes/main/NoteScene.tscn")


func _auto_fit_title(text: String) -> void:
	var max_size: int = 40
	var min_size: int = 18
	# 卡片 300px - accent 4px - 左右 margin 各 14px = 268px 可用
	const AVAILABLE_W: float = 268.0

	var font := get_theme_default_font()
	if not font:
		# fallback: 中文每字约 font_size * 0.9 宽
		var fs: int = max_size
		var char_count := text.length()
		while fs > min_size and char_count * fs * 0.9 > AVAILABLE_W:
			fs -= 2
		title_label.add_theme_font_size_override("font_size", fs)
		return

	var fs: int = max_size
	while fs > min_size:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw <= 0:  # 默认字体无法测量，用估算
			while fs > min_size and text.length() * fs * 0.85 > AVAILABLE_W:
				fs -= 2
			break
		if tw <= AVAILABLE_W:
			break
		fs -= 2
	title_label.add_theme_font_size_override("font_size", fs)


func _make_tag_chip(tag: String, default_color: Color, tag_colors: Dictionary) -> Panel:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(80, 28)
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_right = 2
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.text = tag
	label.add_theme_font_size_override("font_size", 14)
	# 全局配色优先
	var font_color := default_color
	var bg_color := Color(0.2, 0.35, 0.6, 0.5)
	if tag_colors.has(tag):
		var tc: Dictionary = tag_colors[tag]
		if tc.has("font"):
			font_color = Color(tc.font)
		if tc.has("bg"):
			bg_color = Color(tc.bg)
	sb.bg_color = bg_color
	var font_size := 14
	if tag_colors.has(tag) and tag_colors[tag].has("size"):
		font_size = int(tag_colors[tag]["size"])
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	return chip
