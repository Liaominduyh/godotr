## 轻量测试运行器 — 无外部依赖
extends Node

var _passed := 0
var _failed := 0
var _errors: Array[String] = []


func _ready() -> void:
	print("=".repeat(60))
	print("知识库 测试套件")
	print("=".repeat(60))

	_run_file("NoteResource 模型", "res://tests/test_note_resource.gd")
	_run_file("NoteIndex 索引", "res://tests/test_note_index.gd")
	_run_file("KnowledgeBase 核心", "res://tests/test_knowledge_base.gd")

	print("")
	print("=".repeat(60))
	print("共 %d 通过, %d 失败" % [_passed, _failed])
	print("=".repeat(60))

	if not _errors.is_empty():
		for err in _errors:
			printerr("  FAIL: ", err)

	get_tree().quit(_failed)


func _run_file(label: String, res_path: String) -> void:
	print("")
	print("--- %s ---" % label)
	var script := load(res_path)
	var tester: RefCounted = script.new()
	for method: Dictionary in tester.get_method_list():
		var mname: String = method["name"]
		if mname.begins_with("test_"):
			var ok: bool = tester.call(mname)
			if ok:
				_passed += 1
				print("  PASS  %s" % mname)
			else:
				_failed += 1
				_errors.append("%s::%s" % [label, mname])
				printerr("  FAIL  %s" % mname)
