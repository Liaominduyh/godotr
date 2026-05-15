## 全局事件总线 — 跨场景解耦通信
extends Node

## 笔记变更
signal note_created(note_path: String)
signal note_updated(note_path: String)
signal note_deleted(note_path: String)

## 知识库就绪
signal knowledge_base_ready
