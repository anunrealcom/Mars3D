Mars3D (火星3D)
================

Mars3D（中文名：火星3D）是一个 3D 创作套件，基于 Blender 源码改造，覆盖建模、绑定、
动画、仿真、渲染、合成、运动跟踪与视频剪辑的完整 3D 流程。

本仓库是“换壳”分支：界面名称、窗口标题、关于对话框、启动画面、应用图标与 Windows
文件属性均已改为 Mars3D，底层功能代码与文件格式保持与 Blender 兼容（`.blend`、
`bpy` Python API、`BLENDER_*` 环境变量与配置目录均未改动）。

- 项目主页：https://github.com/anunrealcom/Mars3D
- 许可证：GPL-2.0-or-later（见 `COPYING`），原始版权归 Blender Authors 所有

Building
--------

Windows 上使用仓库内置的 VS Code 任务（`.vscode/tasks.json`）：

1. `Mars3D: 重新配置 CMake (Debug)` —— 生成 `build_clion`
2. `Mars3D: 构建并安装 (Debug)` —— 全量编译并安装运行时文件
3. 按 `F5` 启动调试（产物：`build_clion/bin/mars3d.exe`）

依赖库 `lib/` 与构建目录不纳入版本管理，需要按 Blender 官方方式获取
（https://projects.blender.org/blender/lib-windows_x64）。
