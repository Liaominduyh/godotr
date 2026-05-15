## 知识库核心管理器 — 文件CRUD、JSON索引、全文搜索
## Autoload 单例，供所有 UI 组件调用
extends Node

const INDEX_FILE: String = "index.json"
const NOTES_DIR: String = "notes"
const KB_DIR_NAME: String = "knowledge_base"

var index: NoteIndex = NoteIndex.new()
var kb_dir: String = ""  # 实际知识库路径

var _godotr_dir: String = ""   # godotr/ 数据根目录（项目包部署=已有目录，单exe=自动创建）
var project_root: String = "" # 项目根目录 (.claude/ 所在位置)

## 场景导航状态 — 供 LibraryScene / NoteScene 之间传递
var pending_note_path: String = ""

var _ready_emitted: bool = false


func _ready() -> void:
	_resolve_paths()
	kb_dir = _get_kb_dir()
	_ensure_directories()
	_load_index()
	_ready_emitted = true
	EventBus.knowledge_base_ready.emit()


# --------------------------------------------------------------------------
#  CRUD
# --------------------------------------------------------------------------

func create_note(title: String, body: String = "", tags: Array[String] = [], source: String = "manual") -> NoteResource:
	var note := NoteResource.new()
	note.title = title
	note.body = body
	note.tags = tags.duplicate()
	note.source = source
	var now := Time.get_datetime_string_from_system().split("T")[0]
	note.created = now
	note.updated = now

	note.file_path = _assign_path(note)
	_save_note_file(note)
	index.add_note(note)
	_save_index()

	EventBus.note_created.emit(note.file_path)
	return note


func get_note(file_path: String) -> NoteResource:
	var cached := index.get_by_path(file_path)
	if cached:
		# 加载完整内容
		var full_path := "%s/%s" % [kb_dir, file_path]
		if FileAccess.file_exists(full_path):
			var text := _read_file(full_path)
			if text:
				return NoteResource.from_markdown(text, file_path)
		return cached
	return null


func get_all_notes() -> Array[NoteResource]:
	return index.notes.duplicate()


func update_note(note: NoteResource) -> void:
	note.updated = Time.get_datetime_string_from_system().split("T")[0]
	_save_note_file(note)
	index.add_note(note)
	_save_index()
	EventBus.note_updated.emit(note.file_path)


func delete_note(file_path: String) -> void:
	var full_path := "%s/%s" % [kb_dir, file_path]
	if FileAccess.file_exists(full_path):
		DirAccess.remove_absolute(full_path)
	index.remove_note(file_path)
	_save_index()
	EventBus.note_deleted.emit(file_path)


# --------------------------------------------------------------------------
#  搜索
# --------------------------------------------------------------------------

func search(query: String) -> Array[NoteResource]:
	return index.search(query)


func get_notes_by_tag(tag: String) -> Array[NoteResource]:
	return index.get_by_tag(tag)


func get_all_tags() -> Array[String]:
	return index.get_all_tags()


func get_tag_count(tag: String) -> int:
	return index.get_tag_count(tag)


# --------------------------------------------------------------------------
#  导入
# --------------------------------------------------------------------------

func import_markdown(text: String, source: String = "import_file") -> NoteResource:
	var note := NoteResource.from_markdown(text)
	if note.source == "manual":
		note.source = source
	return create_note(note.title, note.body, note.tags, note.source)


func import_from_url(url: String) -> Dictionary:
	## 返回 {success: bool, note: NoteResource, error: String}
	var http := HTTPRequest.new()
	add_child(http)

	var result := await _fetch_url(http, url)
	remove_child(http)

	if result.get("success"):
		var note := NoteResource.from_markdown(result.get("body", ""))
		note.source = "import_url"
		note.summary = "从 %s 导入" % [url]
		var saved := create_note(note.title, note.body, note.tags, note.source)
		return {"success": true, "note": saved}
	else:
		return {"success": false, "error": result.get("error", "未知错误")}


# --------------------------------------------------------------------------
#  AI 总结
# --------------------------------------------------------------------------

func create_ai_summary(content: String, title: String, tags: Array[String], summary: String, language: String = "zh") -> NoteResource:
	var note := NoteResource.new()
	note.title = title
	note.body = content
	note.tags = tags.duplicate()
	note.source = "ai_summary"
	note.summary = summary
	var now := Time.get_datetime_string_from_system().split("T")[0]
	note.created = now
	note.updated = now
	note.file_path = _assign_path(note)
	_save_note_file(note)
	index.add_note(note)
	_save_index()
	EventBus.note_created.emit(note.file_path)
	return note


func split_large_content(content: String, max_chars: int = 4000) -> Array[String]:
	## 大文档分片处理 — 按段落分割，每片不超过 max_chars
	var chunks: Array[String] = []
	var paragraphs := content.split("\n\n")
	var current: String = ""

	for para in paragraphs:
		if current.length() + para.length() + 2 > max_chars and not current.is_empty():
			chunks.append(current.strip_edges())
			current = ""
		if current.is_empty():
			current = para
		else:
			current += "\n\n" + para

	if not current.is_empty():
		chunks.append(current.strip_edges())

	return chunks


# --------------------------------------------------------------------------
#  内部方法
# --------------------------------------------------------------------------

func _resolve_paths() -> void:
	## 解析 godotr 数据目录和项目根目录
	## 优先级: --godotr-dir 命令行参数 > 单 exe 自动创建 (godotr/)
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--godotr-dir" and i + 1 < args.size():
			_godotr_dir = args[i + 1].trim_suffix("\\").trim_suffix("/")
			break

	if _godotr_dir.is_empty():
		# 没有命令行参数：单 exe 部署模式
		if not OS.has_feature("editor"):
			_godotr_dir = OS.get_executable_path().get_base_dir().path_join("godotr")

	if not _godotr_dir.is_empty():
		project_root = _godotr_dir.get_base_dir()


func get_godotr_dir() -> String:
	return _godotr_dir


func _get_kb_dir() -> String:
	if not _godotr_dir.is_empty():
		return _godotr_dir.path_join(KB_DIR_NAME)
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("user://%s" % KB_DIR_NAME)
	# 旧版兼容（正常情况下不会走到这里）
	return OS.get_executable_path().get_base_dir().path_join(KB_DIR_NAME)


func _ensure_directories() -> void:
	if not _godotr_dir.is_empty():
		# 部署模式（含项目包和单 exe）：确保 godotr/ 及子目录存在
		if not DirAccess.dir_exists_absolute(_godotr_dir):
			DirAccess.make_dir_recursive_absolute(_godotr_dir)
		if not DirAccess.dir_exists_absolute(kb_dir):
			DirAccess.make_dir_recursive_absolute(kb_dir + "/" + NOTES_DIR)
		_first_run_setup()
	elif OS.has_feature("editor"):
		var dir := DirAccess.open("user://")
		if not dir.dir_exists(KB_DIR_NAME):
			dir.make_dir(KB_DIR_NAME)
		if not dir.dir_exists("%s/%s" % [KB_DIR_NAME, NOTES_DIR]):
			dir.make_dir("%s/%s" % [KB_DIR_NAME, NOTES_DIR])


func _first_run_setup() -> void:
	# .claude/mcp.json → project_root/.claude/
	var claude_dir := project_root.path_join(".claude")
	if not DirAccess.dir_exists_absolute(claude_dir):
		DirAccess.make_dir_absolute(claude_dir)
	var mcp_path := claude_dir.path_join("mcp.json")
	if not FileAccess.file_exists(mcp_path):
		var rel := _godotr_dir.get_file()  # "godotr"
		var mcp_config := JSON.stringify({
			"mcpServers": {
				"knowledge-base": {
					"command": rel.path_join("runtime/python/python.exe"),
					"args": [rel.path_join("mcp_bridge.py")]
				}
			}
		}, "\t")
		var f := FileAccess.open(mcp_path, FileAccess.WRITE)
		if f:
			f.store_string(mcp_config)
	# runtime/fonts/ → _godotr_dir/runtime/fonts/
	var fonts_dir := _godotr_dir.path_join("runtime/fonts")
	if not DirAccess.dir_exists_absolute(fonts_dir):
		DirAccess.make_dir_recursive_absolute(fonts_dir)


func _load_index() -> void:
	var path := "%s/%s" % [kb_dir, INDEX_FILE]
	if not FileAccess.file_exists(path):
		index = NoteIndex.new()
		return

	var text := _read_file(path)
	if text.is_empty():
		index = NoteIndex.new()
		return

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("索引解析失败: %s，重建中" % json.get_error_message())
		_rebuild_index()
		return

	var data := json.data as Dictionary
	if data.is_empty():
		_rebuild_index()
		return

	index.deserialize(data)


func _save_index() -> void:
	if not index.dirty:
		return
	var path := "%s/%s" % [kb_dir, INDEX_FILE]
	var json_text := JSON.new().stringify(index.serialize(), "\t")
	_write_file(path, json_text)
	index.dirty = false


func _save_note_file(note: NoteResource) -> void:
	var dir := "%s/%s" % [kb_dir, NOTES_DIR]
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.open(kb_dir).make_dir(NOTES_DIR)
	var path := "%s/%s" % [dir, note.get_filename()]
	note.file_path = "%s/%s" % [NOTES_DIR, note.get_filename()]
	_write_file(path, note.to_markdown())


func _assign_path(note: NoteResource) -> String:
	return "%s/%s" % [NOTES_DIR, note.get_filename()]


func _rebuild_index() -> void:
	## 从文件系统重建索引
	index = NoteIndex.new()
	var notes_dir := "%s/%s" % [kb_dir, NOTES_DIR]
	if not DirAccess.dir_exists_absolute(notes_dir):
		return

	var dir := DirAccess.open(notes_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name:
		if file_name.ends_with(".md"):
			var path := "%s/%s" % [notes_dir, file_name]
			var text := _read_file(path)
			if text:
				var note := NoteResource.from_markdown(text, "%s/%s" % [NOTES_DIR, file_name])
				index.notes.append(note)
		file_name = dir.get_next()
	dir.list_dir_end()

	index._rebuild_tag_counts()
	_save_index()


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var text := file.get_as_text()
	return text


func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("无法写入文件: %s" % path)
		return
	file.store_string(content)


func _fetch_url(http: HTTPRequest, url: String) -> Dictionary:
	var err := http.request(url)
	if err != OK:
		return {"success": false, "error": "HTTP 请求失败: %s" % error_string(err)}

	var response: Array = await http.request_completed
	if response.size() < 4:
		return {"success": false, "error": "响应数据不完整"}

	var response_code: int = response[1] as int
	var body: PackedByteArray = response[3] as PackedByteArray

	if response_code != 200:
		return {"success": false, "error": "HTTP %d" % response_code}

	var text := body.get_string_from_utf8()
	if text.is_empty():
		return {"success": false, "error": "内容为空"}

	return {"success": true, "body": text}
