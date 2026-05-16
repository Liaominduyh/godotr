#!/usr/bin/env python3
"""MCP 桥接 — 将知识库 TCP API 包装为 MCP 协议，供 Claude Code 调用。"""
import json, socket, sys

TCP_HOST = "127.0.0.1"
TCP_PORT = 8090


def call_kb(method: str, params: dict = None) -> dict:
    """发送 JSON 到知识库 TCP 服务，返回结果。"""
    req = {"method": method, "params": params or {}}
    try:
        s = socket.create_connection((TCP_HOST, TCP_PORT), timeout=5)
        s.sendall((json.dumps(req) + "\n").encode())
        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\n" in data:
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
                sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
                sys.stdout.flush()
        except json.JSONDecodeError:
            pass


if __name__ == "__main__":
    main()
