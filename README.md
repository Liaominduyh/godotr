# 知识库 — 本地知识管理系统

基于 Godot 4.6 构建的桌面端个人知识库。面向游戏开发者，以 Markdown + YAML frontmatter 为数据格式，支持全文搜索、标签管理、外部导入和 AI 总结。

## 快速开始

1. 用 Godot 4.6 打开项目目录
2. 按 `F5` 运行（主场景 `scenes/main/LibraryScene.tscn`）
3. 点击「+ 新建笔记」开始使用

### 运行测试

```
godot --headless --path . tests/test_runner.tscn
```

或在编辑器中右键 `tests/test_runner.tscn` → 设为主场景 → F5。

## 功能

| 模块 | 说明 |
|------|------|
| 笔记编辑 | 创建、查看、编辑、删除。Markdown 渲染（标题、粗斜体、代码块、链接、图片、列表） |
| 标签系统 | 多标签、标签云、标签 + 关键词组合筛选 |
| 全文搜索 | 标题/标签/摘要搜索，相关性排序，结果关键词高亮 |
| 导入 | URL 抓取、本地文件（.md/.txt/.json）、粘贴 Markdown |
| AI 总结 | 手动模式 + API 调用（OpenAI 兼容接口，自动提取标题/标签/摘要） |
| 代码高亮 | GDScript / C# 关键字着色，注释、字符串、数字区分颜色 |
| 编辑器 | 行号显示、字数行数统计、2 秒无操作自动保存 |
| 快捷键 | Esc 返回、Ctrl+S 保存、Ctrl+D 删除 |
| 未保存提示 | 编辑后离开或删除时弹出确认对话框 |
| 设置 | API 地址 / Key / 模型配置，持久化到 user://settings.json |

## 项目结构

```
godotr/
├── project.godot                  # 引擎配置，autoload: EventBus, KnowledgeBase
├── README.md
├── docs/
│   ├── godot-knowledge-base-prd.md  # 产品需求文档
│   └── adr.md                       # 架构决策记录
├── scenes/
│   ├── main/
│   │   ├── LibraryScene.tscn       # 主界面 — Steam 风格卡片网格
│   │   └── NoteScene.tscn          # 查看/编辑场景
│   └── components/
│       └── NoteCard.tscn           # 笔记卡片组件
├── scripts/
│   ├── autoload/
│   │   ├── EventBus.gd             # 全局信号总线（10 行）
│   │   └── KnowledgeBase.gd        # 核心管理器 — CRUD/搜索/导入/索引（301 行）
│   ├── models/
│   │   ├── NoteResource.gd         # 笔记数据模型 — YAML frontmatter 解析（117 行）
│   │   └── NoteIndex.gd            # 内存索引 — 搜索/标签统计（192 行）
│   └── ui/
│       ├── LibraryScene.gd         # 主界面逻辑 — 卡片渲染/标签筛选/导入/AI（587 行）
│       ├── NoteScene.gd            # 编辑场景逻辑 — Markdown 渲染/自动保存（343 行）
│       └── NoteCard.gd             # 卡片组件 — 悬停效果/来源标识（128 行）
└── tests/
    ├── test_runner.gd / .tscn      # 轻量测试运行器（无外部依赖）
    ├── test_assert.gd              # 断言工具
    ├── test_note_resource.gd       # 数据模型测试 — 15 项
    ├── test_note_index.gd          # 索引/搜索测试 — 25 项
    └── test_knowledge_base.gd      # 核心逻辑测试 — 19 项
```

**总计：** 12 个 GDScript 文件（2402 行）+ 4 个 .tscn 场景 + 59 个单元测试

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

- **数据格式**：Markdown + YAML frontmatter，存储路径见下方「数据存储」
- **索引**：`index.json`，启动时加载，修改后增量更新
- **场景导航**：`get_tree().change_scene_to_file()` + `KnowledgeBase.pending_note_path` 传递状态
- **信号总线**：`EventBus` 解耦跨场景通信（note_created/updated/deleted、knowledge_base_ready）

## 数据存储

项目支持三种运行模式，路径决策由 `knowledge_a.gd` 中的 `--godotr-dir` 命令行参数控制：

| 模式 | 笔记/索引路径 | 设置文件 | 说明 |
|------|-------------|---------|------|
| 编辑器 (F5) | `user://knowledge_base/` | `user://settings.json` | Godot 编辑器直接运行 |
| 项目包 (run_kb.bat) | `godotr/knowledge_base/` | `godotr/settings.json` | 项目根目录下 `.claude/mcp.json` 自动创建 |
| 单 exe | `<exe_dir>/godotr/knowledge_base/` | `<exe_dir>/godotr/settings.json` | 便携部署，数据跟随 exe |

编辑器模式下 `user://` 在 Windows 的实际路径：`%APPDATA%/Godot/app_userdata/知识库/`

## 许可

MIT
