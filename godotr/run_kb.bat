@echo off
set "SCRIPT_DIR=%~dp0"
echo ========================================
echo   知识库 - 本地知识管理系统
echo ========================================
echo.
echo 首次启动将自动创建:
echo   - godotr\knowledge_base\ 文件夹（存储知识）
echo   - .claude\mcp.json（MCP 服务配置）
echo.
echo 启动后点击工具栏 [MCP] 按钮开启 AI 接入服务
echo.

:: 优先查找同目录下的 Godot 可执行文件
if exist "%SCRIPT_DIR%runtime\python\Godot_v4.6.1-stable_win64_console.exe" (
    set "GODOT=%SCRIPT_DIR%runtime\python\Godot_v4.6.1-stable_win64_console.exe"
) else if exist "%SCRIPT_DIR%Godot_v4.6.1-stable_win64_console.exe" (
    set "GODOT=%SCRIPT_DIR%Godot_v4.6.1-stable_win64_console.exe"
) else if exist "%SCRIPT_DIR%knowledge_base.exe" (
    set "GODOT=%SCRIPT_DIR%knowledge_base.exe"
    :: 导出 exe 也需要 --godotr-dir，确保数据放在 godotr/ 内
    start "" "%GODOT%" --godotr-dir "%SCRIPT_DIR%"
    goto :end
) else (
    echo 错误: 未找到可执行文件，请将知识库 exe 放到此脚本同目录
    pause
    exit /b 1
)

:: --godotr-dir 告诉引擎数据文件（knowledge_base/ 等）应放在 godotr/ 目录
start "" "%GODOT%" --path "%SCRIPT_DIR%" --godotr-dir "%SCRIPT_DIR%"
:end
