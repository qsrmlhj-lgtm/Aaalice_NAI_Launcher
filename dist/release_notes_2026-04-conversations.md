## NAI Launcher 更新日志（对话迭代汇总）

统计范围：当前工作分支 `codex-qsrmlhj-sync-2026-04-24` 相对 `main` 的已成功提交（`17419966..HEAD`）。

### 生成与图像工作流

- 重建并补齐图生图与局部重绘流程，统一重绘编辑、遮罩与参数回填。
- 引入本地超分与导演工具工作流，并完成和历史图/预览图/源图的互通。
- 将本地常规超分模型与 SeedVR2 统一收口到 ComfyUI 路径，减少多后端分叉带来的行为不一致。
- 细化图像编辑与本地 Effects 功能，补充本地后处理链路。

### 反推、助手与提示词链路

- 新增反推入口与链路基础设施，支持 ONNX Tagger 与 LLM 任务协同。
- 补齐本地 Tagger 模型支持与插件式接入能力，打通反推结果注入。
- 完成助手任务路由强化：优化、翻译、反推、角色替换任务的配置与调用链路。
- 统一 LLM 非流式调用策略，移除温度/Top-P/Max Tokens 前端参数并回退云端默认值。
- 强化提示词框撤销重做行为，注入式改写进入统一历史栈，支持 `Ctrl+Y`。

### 画廊、拖拽与图片发送

- 修复本地画廊送图到图生图流程，补齐关键入口与动作分发。
- 完善图片详情与通用卡片的行为一致性，减少“卡片可用、详情不可用”的分裂路径。
- 增强拖拽链路和图片读取兼容性，覆盖更复杂的外部来源。
- 改进本地画廊检索、元数据匹配与删除缓存一致性。

### Vibe 库性能与稳定性

- 增加 Vibe 全链路性能诊断埋点（打开、导入、缓存构建等关键节点）。
- 去除导入路径里的全量重读取，改为按需查询，降低导入阶段卡顿概率。
- 推进轻量展示条目路径，减少列表态对完整条目的依赖。
- 新增展示缓存 `v2`，剥离大字段并采用懒加载缩略图，降低首开和重复打开负担。
- 增加批处理与 bundle 提取层面的性能优化，缩短高负载场景耗时。

### 设置、保护模式与稳定性增强

- 保护模式能力扩展为多子开关，覆盖拖拽净化、危险操作确认、边界提醒与高消耗警告。
- 修复 ComfyUI 地址与 WebSocket 规范化问题，避免“可连通但任务执行失败”。
- 收敛大体积本地缓存后台自动清理策略，避免超大 Hive 数据触发间歇性长卡顿。

### 本轮累计提交清单（按时间）

- `8690faec` feat(generation-workflow): rebuild img2img and inpaint pipeline
- `13491513` feat(prompt-metadata): align token counting and metadata behavior
- `8c4e747f` feat(vibe-workflow): improve vibe import, export, and library flows
- `de587590` perf(ui): reduce stutter and harden generation stability
- `dad56ee8` fix(prompt-metadata): refine token counting and image transfer metadata
- `ae02cb59` feat(gallery): improve incremental scan and cache invalidation
- `08209f27` feat(vibe-workflow): preserve raw imports and embedded export metadata
- `39390db4` feat(generation-workflow): add local upscale, director tools, and ComfyUI workflows
- `126ac46a` docs(release-notes): update changelog and ignore local artifacts
- `62778f77` fix(vibe-library): add lightweight display entry conversion
- `08466ddb` fix(comfyui): normalize server URL and WebSocket endpoint
- `beba6578` fix(gallery): improve metadata search and deletion cache
- `72e10fcb` perf(vibe-library): keep library reads lightweight
- `be8b22c0` chore(tags): refresh prebuilt tag database
- `69da0773` chore(vibe-library): add performance diagnostics
- `1e13d3f7` chore(vibe-library): complete import diagnostics
- `c6209ebf` perf(vibe-library): batch bundle extraction
- `a45e5b7a` fix(gallery): enable local image to img2img
- `5c7e10dd` feat(generation): add reverse prompt and local processing tools
- `65d122fc` feat(upscale): route local models through ComfyUI
- `17a21e71` feat(reverse-prompt): support local tagger workflow
- `a881b557` feat(prompt-assistant): harden LLM task flows
- `f41706f1` feat(gallery): improve image drag and detail actions
- `6c85f11c` feat(editor): add local effects workflow
- `079fd147` feat(settings): add protection mode controls
- `ee47b8b5` fix(vibe-library): avoid full reads during imports
- `5a0d3660` test(app): cover integrated workflow updates
- `8728dfd6` fix(vibe-library): shrink display cache and lazy load thumbnails
