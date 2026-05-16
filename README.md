# godotr

基于 Godot 4.6 构建的本地知识库管理系统。面向游戏开发者，以 Markdown + YAML frontmatter 为数据格式，支持全文搜索、标签管理、外部导入，AI集成开发知识库。

- 笔记自动保存，2 秒无操作即存，随手记录不丢失
- MCP 协议桥接，Claude Code 可直接检索和读写知识库
- 数据全本地存储，无需网络，无需注册
- 开发时长一坤年

## 快速开始

**桌面应用**
- 下载 `knowledge_base.exe`，放到任意项目文件夹根目录，双击运行（自动检测Python环境）

**便携软件包**
- 下载便携软件包，解压到项目根目录，进入 `godotr/` 双击 `run_kb.bat` 运行（自带Python环境）

### 运行测试

```
godot --headless --path . tests/test_runner.tscn
```


## 特色

- **Markdown + YAML**：笔记以 `.md` 文件存储，YAML frontmatter 记录标题、标签、来源、创建/更新时间等元数据
- **全文搜索**：基于内存索引的实时搜索，覆盖标题、标签、摘要，结果按相关性排序，<500ms 响应
- **标签系统**：多标签筛选、标签云、右键菜单（改颜色、调字号），按标签 + 关键词组合过滤
- **Markdown 渲染**：标题、粗斜体、代码块（GDScript / C# 语法高亮）、链接、图片、列表
- **AI 总结**：粘贴文档或 URL，一键生成结构化笔记（标题 + 摘要 + 标签 + 正文），大文档自动分片
- **外部导入**：URL 抓取、本地文件（`.md` / `.txt` / `.json`）导入
- **自动保存**：编辑后 2 秒无操作自动保存，离开或删除时未保存提示
- **快捷键**：`Esc` 返回、`Ctrl+S` 保存、`Ctrl+D` 删除
- **悬停音效**：卡片 hover 时播放短促提示音，视觉缩放 + 强调色动效

## 快速释放

- [godotr 桌面应用]() — 单 exe，即下即用
- [便携软件包]() — 含 Python 运行时，支持 MCP AI 接入

## 操作指南

1. 启动后进入主界面，卡片网格展示所有笔记
2. 点击右上角「+ 新建笔记」创建第一篇笔记，输入标题和 Markdown 正文
3. 标签栏输入标签（逗号分隔），左侧标签云点击筛选
4. 顶部搜索框输入关键词，实时过滤笔记卡片
5. 点击卡片进入查看/编辑，工具栏可切换查看/编辑模式
6. 「导入」按钮支持 URL 抓取和本地文件导入
7. 点击「MCP」按钮开启 AI 接入服务，Claude Code 可通过 MCP 直接检索知识库
8. 「设置」中可更换界面字体

## 架构

```
┌─────────────────────────────────────┐
│  UI 层 (scenes/ + scripts/ui/)      │
│  LibraryScene ←→ NoteScene ← NoteCard │
│        │              │              │
│  Autoload: EventBus (跨场景信号)      │
│  Autoload: KnowledgeBase (CRUD/搜索) │
│        │              │              │
│  Model:  NoteResource    NoteIndex   │
│        │              │              │
│  Storage: .md 文件  +  index.json    │
│        (YAML frontmatter)            │
└─────────────────────────────────────┘
```

## 数据存储

| 运行模式 | 笔记/索引路径 | 设置文件 |
|---------|-------------|---------|
| 便携软件包 (run_kb.bat) | `godotr/knowledge_base/` | `godotr/settings.json` |
| 桌面应用 (exe) | `<exe_dir>/godotr/knowledge_base/` | `<exe_dir>/godotr/settings.json` |


## 支持平台

当前仅支持 Windows。未来计划支持 Linux。

## 许可

MIT
