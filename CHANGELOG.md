## Unreleased

性能优化（视觉输出与优化前逐像素一致）：

* `MeshFlow` 改为 `CustomPainter.repaint` 驱动，动画不再每帧 `setState` 重建 widget 子树；
  网格绘制被 `RepaintBoundary` 隔离，上层歌词/控件不再被带着逐帧重绘。
* `WarpGrid` 顶点生成：驻波正弦改查表、`sin(p[i])` 等整帧常量与逐行/逐列的折痕项提到循环外、
  纹理坐标整帧复用。单帧 0.20ms → 0.14ms（Debug VM）。
* `CoverProcessor` 补上 `ui.Image` / `Codec` / `Picture` / `ImmutableBuffer` 的释放，
  反复切歌不再积压 GPU 纹理。
* 新增 `MeshFlowFrame`、`MeshFlowPainter.frameBuilder` / `repaint`，支持外部只触发重绘而不重建。

## 0.0.1

* TODO: Describe initial release.
