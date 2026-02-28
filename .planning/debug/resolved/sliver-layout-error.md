---
status: resolved
trigger: "SliverPersistentHeader throws assertion: layoutExtent (40.0) exceeds paintExtent (39.0). The maxExtent is set to 40.0 but the actual rendered height is only 39.0."
created: 2026-02-28T00:00:00Z
updated: 2026-02-28T00:00:05Z
---

## Current Focus

hypothesis: CategoryHeaderDelegate 的 build 方法返回的 Widget 高度小于 maxExtent/minExtent (40.0)，导致 SliverPersistentHeader 的 layoutExtent > paintExtent

**根因确认**: Container 使用 padding vertical: 8 (总共16)，内部 Icon 高度 18，Text 高度约14-16，总计约34-36，不足40。SliverPersistentHeader 要求返回的 widget 高度必须严格等于 maxExtent。

**修复状态**: 已完成
- 代码已使用 SizedBox 包裹 Container，强制高度为 maxExtent (40.0)
- flutter analyze 通过，无错误

test: 等待用户验证修复效果
expecting: 打开应用，进入词库页面，切换到分组视图，不再出现 SliverGeometry 错误
next_action: 用户验证后确认修复成功

## Symptoms

expected: 分组视图正常显示，吸顶标题正确固定在顶部，没有错误
actual: Flutter 渲染错误导致应用显示红色错误屏幕
errors: |
  SliverGeometry is not valid: The "layoutExtent" exceeds the "paintExtent".
  The paintExtent is 39.0, but the layoutExtent is 40.0.
  The RenderSliver that returned the offending geometry was: _RenderSliverPinnedPersistentHeaderForWidgets
  geometry: SliverGeometry(scrollExtent: 40.0, paintExtent: 39.0, layoutExtent: 40.0, maxPaintExtent: 40.0, hasVisualOverflow: true, cacheExtent: 40.0)
reproduction: 打开应用，进入词库页面，切换到分组视图就报错
timeline: 刚完成 Phase 01 后就出现

## Eliminated

## Evidence

- timestamp: 2026-02-28T00:00:00Z
  checked: CategoryHeaderDelegate 代码
  found: maxExtent 和 minExtent 都设置为 40，但 Container 使用 padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)
  implication: Container 的高度 = 内容高度 + padding.vertical(16)，如果内容高度是 24，总高度就是 40

- timestamp: 2026-02-28T00:00:01Z
  checked: Container 内部结构分析
  found: |
    - padding: vertical: 8 (上下各8，总共16)
    - Row 内部: Icon(size: 18) + SizedBox(width: 8) + Text + Container(padding: vertical: 3)
    - Row 默认 crossAxisAlignment: CrossAxisAlignment.center
    - 最高元素是 Icon(18) 或 Text(约14-16)，加上 padding(16) 可能不足40
  implication: 内容高度可能小于24，导致总高度不足40

- timestamp: 2026-02-28T00:00:02Z
  checked: SliverPersistentHeader 约束机制
  found: |
    SliverPersistentHeader 要求 delegate 返回的 widget 必须恰好等于 maxExtent 高度
    如果 widget 实际渲染高度小于 maxExtent，就会出现 paintExtent < layoutExtent 的错误
  implication: 需要确保 build 返回的 widget 高度严格等于 maxExtent

## Resolution

root_cause: CategoryHeaderDelegate 的 build 方法返回的 Container 实际高度小于 maxExtent (40.0)。Container 使用 padding vertical: 8 (总共16)，内部 Icon 高度 18，Text 高度约14-16，总计约34-36。SliverPersistentHeader 要求返回的 widget 高度必须严格等于 maxExtent，否则会出现 layoutExtent > paintExtent 的错误。

fix: 使用 SizedBox 包裹 Container，强制高度为 maxExtent (40.0)

verification:
- flutter analyze: 通过（2个 info 级别问题在 tools/ 目录，与本修复无关）
- 代码修复: 使用 SizedBox(height: maxExtent) 包裹 Container
- 需要人工验证：打开应用，进入词库页面，切换到分组视图，确认不再报错

files_changed:
- lib/presentation/screens/tag_library_page/widgets/grouped_view/category_header.dart
