## 知识库核心管理器 — 文件CRUD、JSON索引、全文搜索
## Autoload 单例，供所有 UI 组件调用
extends Node

const INDEX_FILE: String = "index.json"
const NOTES_DIR: String = "notes"
const KB_DIR_NAME: String = "knowledge_base"

## mcp_bridge.py 内嵌源码 — 单 exe 部署时直接写出，不依赖 PCK 资源提取
const MCP_BRIDGE_PY := '#!/usr/bin/env python3
"""MCP 桥接 — 将知识库 TCP API 包装为 MCP 协议，供 Claude Code 调用。"""
import json, socket, sys

TCP_HOST = "127.0.0.1"
TCP_PORT = 8090


def call_kb(method: str, params: dict = None) -> dict:
    """发送 JSON 到知识库 TCP 服务，返回结果。"""
    req = {"method": method, "params": params or {}}
    try:
        s = socket.create_connection((TCP_HOST, TCP_PORT), timeout=5)
        s.sendall((json.dumps(req) + "\\n").encode())
        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\\n" in data:
                break
        s.close()
        return json.loads(data.decode().strip())
    except Exception as e:
        return {"error": str(e)}


def handle_request(request: dict):
    """处理 MCP JSON-RPC 请求。"""
    req_id = request.get("id")
    method = request.get("method")

    if method == "initialize":
        return {
            "jsonrpc": "2.0", "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "knowledge-base", "version": "0.2.6"}
            }
        }

    if method == "notifications/initialized":
        return None  # 无需回复

    if method == "tools/list":
        return {
            "jsonrpc": "2.0", "id": req_id,
            "result": {"tools": [
                {
                    "name": "search_knowledge",
                    "description": "搜索知识库笔记，返回匹配的标题、路径和标签",
                    "inputSchema": {
                        "type": "object",
                        "properties": {"query": {"type": "string", "description": "搜索关键词"}},
                        "required": ["query"]
                    }
                },
                {
                    "name": "get_note",
                    "description": "读取一篇笔记的完整内容",
                    "inputSchema": {
                        "type": "object",
                        "properties": {"file_path": {"type": "string", "description": "笔记路径，如 notes/20260115-godot.md"}},
                        "required": ["file_path"]
                    }
                },
                {
                    "name": "list_notes",
                    "description": "列出所有笔记的摘要信息",
                    "inputSchema": {"type": "object", "properties": {}}
                },
                {
                    "name": "get_tags",
                    "description": "获取所有标签及其计数",
                    "inputSchema": {"type": "object", "properties": {}}
                },
                {
                    "name": "create_summary",
                    "description": "创建一篇 AI 总结笔记",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string", "description": "笔记标题"},
                            "content": {"type": "string", "description": "原始内容"},
                            "tags": {"type": "array", "items": {"type": "string"}, "description": "标签列表"},
                            "summary": {"type": "string", "description": "AI 生成的总结"}
                        },
                        "required": ["title", "summary"]
                    }
                },
            ]}
        }

    if method == "tools/call":
        tool_name = request["params"]["name"]
        args = request["params"].get("arguments", {})

        kb_methods = {
            "search_knowledge": "search",
            "get_note": "get_note",
            "list_notes": "list_notes",
            "get_tags": "get_tags",
            "create_summary": "create_summary",
        }
        kb_method = kb_methods.get(tool_name)

        if not kb_method:
            return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"}}

        result = call_kb(kb_method, args)
        if "error" in result:
            return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32000, "message": result["error"]}}

        return {"jsonrpc": "2.0", "id": req_id, "result": {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}]}}


def main():
    """MCP stdio 主循环 — 从 stdin 读请求，写回复到 stdout。"""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            resp = handle_request(req)
            if resp:
                sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\\n")
                sys.stdout.flush()
        except json.JSONDecodeError:
            pass


if __name__ == "__main__":
    main()
'

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
	# 首次运行：从 PCK 解出 Python 运行时到 godotr/runtime/python/
	_extract_python_runtime()
	# .mcp.json → project_root/.mcp.json（Claude Code MCP 配置在项目根目录）
	var mcp_path := project_root.path_join(".mcp.json")
	if not FileAccess.file_exists(mcp_path):
		_setup_mcp_config(mcp_path)
	# runtime/fonts/ → _godotr_dir/runtime/fonts/
	var fonts_dir := _godotr_dir.path_join("runtime/fonts")
	if not DirAccess.dir_exists_absolute(fonts_dir):
		DirAccess.make_dir_recursive_absolute(fonts_dir)


func _extract_python_runtime() -> void:
	## 从 PCK 中解出 Python 运行时到 godotr/runtime/python/（单 exe 首次运行）
	var py_exe := _godotr_dir.path_join("runtime/python/python.exe")
	if FileAccess.file_exists(py_exe):
		return  # 已解出或便携包自带，无需操作

	var src_dir := DirAccess.open("res://runtime/python/")
	if not src_dir:
		return  # PCK 中无 Python 运行时（非 embed_pck 或导出时没包含）

	var dst_dir := _godotr_dir.path_join("runtime/python")
	DirAccess.make_dir_recursive_absolute(dst_dir)

	src_dir.list_dir_begin()
	var file_name := src_dir.get_next()
	while not file_name.is_empty():
		if not src_dir.current_is_dir():
			_copy_from_pck("res://runtime/python/".path_join(file_name), dst_dir.path_join(file_name))
		file_name = src_dir.get_next()
	src_dir.list_dir_end()


func _copy_from_pck(src: String, dst: String) -> void:
	var f := FileAccess.open(src, FileAccess.READ)
	if not f:
		return
	var data := f.get_buffer(f.get_length())
	f = FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_buffer(data)


func _write_bridge_file(bridge_path: String) -> void:
	## 写出 mcp_bridge.py，优先用内嵌源码，PCK 资源为回退
	if FileAccess.file_exists(bridge_path):
		return
	var content := MCP_BRIDGE_PY
	if content.is_empty():
		var source := FileAccess.open("res://mcp_bridge.py", FileAccess.READ)
		if not source:
			return
		content = source.get_as_text()
	else:
		var lines: PackedStringArray = content.split("\n")
		for i in lines.size():
			lines[i] = lines[i].trim_prefix("\t")
		content = "\n".join(lines)
	var dest := FileAccess.open(bridge_path, FileAccess.WRITE)
	if dest:
		dest.store_string(content)


func _setup_mcp_config(mcp_path: String) -> void:
	var rel := _godotr_dir.get_file()
	var py_path := project_root.path_join(rel.path_join("runtime/python/python.exe"))
	var bridge_path := project_root.path_join(rel.path_join("mcp_bridge.py"))

	# 写出 mcp_bridge.py（内嵌源码，无需依赖 PCK）
	_write_bridge_file(bridge_path)

	if FileAccess.file_exists(py_path):
		# 自带 Python（便携包或首次运行已解出）
		_write_mcp_json(mcp_path, rel.path_join("runtime/python/python.exe"), [rel.path_join("mcp_bridge.py")])
	else:
		# 回退：尝试使用系统 Python
		_setup_system_python_mcp(mcp_path, rel, bridge_path)


func _setup_system_python_mcp(mcp_path: String, rel: String, bridge_path: String) -> void:
	# get system Python full path, write bridge, generate .mcp.json
	var output: Array = []
	var python_path := ""
	for cmd in ["python", "python3"]:
		output.clear()
		var ec := OS.execute(cmd, PackedStringArray(["-c", "import sys; print(sys.executable)"]), output, true)
		if ec == 0 and not output.is_empty():
			python_path = output[0].strip_edges()
			if not python_path.is_empty():
				break
	if python_path.is_empty():
		push_warning("MCP config failed: no system Python (python/python3)")
		return

	_write_bridge_file(bridge_path)
	if not FileAccess.file_exists(bridge_path):
		push_warning("MCP config failed: cannot write mcp_bridge.py")
		return

	_write_mcp_json(mcp_path, python_path, [rel.path_join("mcp_bridge.py")])


func _write_mcp_json(path: String, command: String, args: Array) -> void:
	var mcp_config := JSON.stringify({
		"mcpServers": {
			"knowledge-base": {
				"type": "stdio",
				"command": command,
				"args": args
			}
		}
	}, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(mcp_config)


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
