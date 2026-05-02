## NAI Launcher v1.0.0-beta8 更新日志

本次版本相比 `v1.0.0-beta7`，重点补齐图生图/重绘、本地工作流、Vibe、词库搜索和图库稳定性。

### 新增

- **完整图生图与重绘链路**：补齐 `img2img`、局部重绘、变体、增强、Focused Inpaint 与点击式填充桶。
- **ComfyUI 本地工作流**：支持本地 ComfyUI、工作流导入、SeedVR2、RTX 与常规超分后端。
- **导演工具与反推入口**：新增导演工具页面，并打通历史图、预览图、图库图到增强/反推的入口。
- **提示词 Token 明细**：正向/负向提示词支持 Token 计数、组成明细和紧凑显示。
- **Vibe 导入导出增强**：支持非 PNG Vibe 导入、单个 Vibe 嵌入 PNG 导出，以及批量目录导出。
- **词库中文搜索反查**：中文搜索可通过翻译数据库找到对应英文 tag，并保留分类和热度排序。

### 改进

- **元数据兼容性更接近 NovelAI**：保存和解析逻辑更贴近 NovelAI 原生格式，网页端拖入更稳定。
- **复制/拖拽安全控制**：可选择复制或拖拽时移除元数据，同时不影响本地保存的完整元数据。
- **本地超分参数持久化**：ComfyUI/SeedVR2/RTX 等超分后端的模型和关键参数会按模块保存。
- **图库与历史记录更顺滑**：优化缩略图解码、拖拽预热、详情打开和大图预览路径，降低卡顿。
- **LLM 助手路由更完整**：优化、翻译、反推、角色替换等任务统一走更稳定的非流式请求链路。

### 修复

- **修复 Vibe 库周期性卡顿**：导入、展示缓存和缩略图读取改为更轻量的按需路径。
- **修复 ComfyUI 地址和工作流问题**：规范化 base URL/WebSocket 路径，并在队列前检查缺失节点。
- **修复 NovelAI/本地超分差异**：修正倍率、模型解析、结果排序和详情分辨率等问题。
- **修复 Anlas 估算偏差**：按订阅等级、请求尺寸和工作流模式重新计算消耗。
- **修复词库搜索框不同步**：工具栏重建后仍会显示当前搜索条件。
- **修复批量 Vibe PNG 嵌入误入口**：批量导出不再展示仅适用于单个 Vibe 的嵌入 PNG 选项。

### 验证

- 已通过目标测试：`test/app_test.dart`、`test/core/services/danbooru_tags_lazy_service_test.dart`、`test/core/utils/vibe_export_utils_test.dart`，共 76 个测试。
- Windows Release 构建通过，产物位于 `build/windows/x64/runner/Release`。

### 下载

- Windows 压缩包：`NAI_Launcher_Windows_1.0.0-beta8+11.zip`
