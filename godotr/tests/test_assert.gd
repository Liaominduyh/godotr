## 测试断言工具 — RefCounted，可被所有测试文件安全实例化
extends RefCounted


func eq(actual, expected, msg := "") -> bool:
	if actual == expected:
		return true
	printerr("    预期: ", expected, "  实际: ", actual, "  ", msg)
	return false


func ok(cond: bool, msg := "") -> bool:
	if cond:
		return true
	printerr("    条件为假  ", msg)
	return false


func contains(text: String, fragment: String, msg := "") -> bool:
	if fragment in text:
		return true
	printerr("    \"", text, "\" 中未找到 \"", fragment, "\"  ", msg)
	return false
