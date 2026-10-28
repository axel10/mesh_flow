import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 地形预设参数，控制网格悬崖与驻波模态形态。
class TerrainPreset {
  const TerrainPreset({required this.p, required this.r, this.hardEdge = false});

  /// 悬崖位置相位（6个浮点数），索引与 `r` 一一对应：
  ///
  /// `p[0]`→r[8]，`p[1]`→r[9]，`p[2]`→r[10]，`p[3]`→r[11]，`p[4]`→r[3]，`p[5]`→r[4]
  ///
  /// 每个相位按 `sin(p)` 映射折痕位置：横向折痕落在 `v = 0.5 + 0.30·sin(p)`，
  /// 纵向折痕落在 `u = 0.5 + 0.36·sin(p)`，对角折痕落在 `u±v = 1 + 0.47·sin(p)`。
  final List<double> p;

  /// 模态/悬崖幅值（12个浮点数），索引含义：
  ///
  /// - `r[0]`、`r[1]`、`r[2]`：x 向山坡模态（m1 / m2 / m4）
  /// - `r[3]`：纵向折痕的 x 位移（0.10 权重）
  /// - `r[4]`：纵向折痕的 y 位移（0.12 权重）
  /// - `r[5]`、`r[6]`、`r[7]`：y 向山坡模态（m1 / m3 / m4）
  /// - `r[8]`：横向折痕的 x 位移（0.10 权重）
  /// - `r[9]`：对角折痕的 x 位移（0.06 权重）
  /// - `r[10]`：横向折痕的 y 位移（0.12 权重）
  /// - `r[11]`：对角折痕的 y 位移（0.06 权重）
  ///
  /// 折痕边缘的"清晰度"取决于贴图雅可比在折痕处被压缩到多小：
  /// 只加大 `r[8]~r[11]` 往往不够（它们在四边被 m1 包络衰减），
  /// 还需要 `r[1]`、`r[2]` 这类 2π 高频模态把 `1 + ∂dx/∂u` 压到接近 0，
  /// 两者相乘才会出现刀锋般的硬边（参考 #1/#2/#4）。
  /// 
  /// 如果用户抱怨有锯齿就把r[1]和r[2]调的距离0近一点，不要调太多，调太多就没有明显边缘了，加减0.02这样一点点调
  ///
  /// ---
  ///
  /// ### 硬边缘调参指南（位置 / 走向 / 长度 / 形状 / 抗锯齿）
  ///
  /// 由于 32×32 封面纹理经过 4 轮盒式模糊后本身完全平滑，要在任意封面上切出像 `#22`～`#29` 那样
  /// 肉眼清晰可见的刀锋硬边，核心机制是**让网格在局部发生受控的单向折叠（`det J < 0`，主要是
  /// `1 + ∂dy/∂v < 0`）**：下半张网格向上折返并覆盖在上半张网格之上，折返边界即形成锋利的色彩断崖。
  ///
  /// #### 1. 硬边的「开关与锐度」（怎么让硬边真正显形）
  /// - **纵向折叠主引擎**：
  ///   - `r[10]`（横向折痕 y 位移）取强负值（`-0.85 ~ -0.96`），在折痕线 `v_fold` 处产生强烈纵向压缩与折返。
  ///   - `r[6]`（`m3 = sin(πu)sin(2πv)`）取正值（`0.55 ~ 0.85`）。在 `v ∈ [0.40, 0.70]` 区间内 `cos(2πv) < 0`，
  ///     正的 `r[6]` 会与负的 `r[10]` 同相叠加，把 `1 + ∂dy/∂v` 压到负数（产生折叠覆叠）。
  /// - **跨折痕色彩错位（相位锁定，让硬边两侧色差最大化）**：
  ///   - 令 `p[0] + p[2] ≈ π`（如 `#22` 中 `p[0]=0.45, p[2]=2.69`，满足 `sin(p[0]) ≈ sin(p[2])`），
  ///     将 `dx` 的横向剪切悬崖（`r[8]`）与 `dy` 的纵向折叠悬崖（`r[10]`）锁在同一条水平线 `v_fold` 上。
  ///   - 同时给 `r[8]` 较大绝对值（`0.50 ~ 0.88`），使硬边上下两侧不仅纵向采样跨度大（`Δv ≈ 0.25`），
  ///     横向也错开采样封面不同区域（`Δu ≈ 0.20`），即使封面整体色调相近也能切出鲜明分界。
  ///
  /// #### 2. 控制硬边的「位置」（上下高度 & 左右分区）
  /// - **上下垂直位置（屏幕 Y 落点）**：
  ///   由相位 `p[2]`（及锁定的 `p[0] = π - p[2]`）与整体下沉模态 `r[5]` 共同决定，基准线为
  ///   `v_fold = 0.5 + 0.30·sin(p[2])`：
  ///   - 中腰偏下（`Y ≈ 0.56~0.68`）：取 `p[0] ≈ 0.30, p[2] ≈ 2.84`（`v_fold ≈ 0.59`）；
  ///   - 下半屏黄金区（`Y ≈ 0.60~0.76`，如 `#22`/`#24`）：取 `p[0] ≈ 0.45, p[2] ≈ 2.69`（`v_fold ≈ 0.63`）；
  ///   - 底部深谷控件区（`Y ≈ 0.65~0.83`，如 `#26`/`#27`）：取 `p[0] ≈ 0.78, p[2] ≈ 2.36`（`v_fold ≈ 0.71`）；
  ///   - `r[5]`（`m1` 的 y 位移）越大（`0.50 → 0.90`），整条硬边在屏幕上的实际位置 `Y = v + dy` 越往下沉。
  /// - **左右水平位置（左半屏 / 右半屏 / 居中横贯）**：
  ///   主要由 `r[7]`（四象限模态 `m4 = sin(2πu)sin(2πv)`）与纵向折痕 `p[5]` + `r[4]` 控制。
  ///   在下半屏（`cos(2πv) < 0`），`sin(2πu)` 在左半屏（`u < 0.5`）为正、右半屏（`u > 0.5`）为负：
  ///   - **硬边在左半屏**（右半区完全柔和，如 `#22`/`#26`/`#28`）：取 `r[7] > 0`（`+0.20 ~ +0.55`），
  ///     同时把纵向折痕中心 `cy = 0.5 + 0.36·sin(p[5])` 放在偏右（`p[5] ∈ [1.6, 2.5]`，`cy ≈ 0.72~0.86`），
  ///     并取 `r[4] < 0`（`-0.75 ~ -0.85`），使 `u < cy` 区域恒为正位移下压，左半屏折叠最强。
  ///   - **硬边在右半屏**（左半区完全柔和，如 `#24`/`#27`/`#29`）：取 `r[7] < 0`（`-0.20 ~ -0.55`），
  ///     同时把 `cy` 放在偏左（`p[5] ∈ [4.8, 5.6]`，`cy ≈ 0.14~0.28`），并取 `r[4] > 0`（`+0.75 ~ +0.85`）。
  ///   - **硬边居中横贯**（如 `#25`）：取 `r[7] ≈ 0`（`-0.05 ~ +0.05`），左右不偏袒。
  ///
  /// #### 3. 控制硬边的「走向 / 倾角」（正斜 `\` vs 反斜 `/` vs 水平 `──`）
  /// - 因为包络 `m1 = sin(πu)sin(πv)` 在左右两侧边缘（`u = 0, 1`）为 `0`、在屏幕中线（`u = 0.5`）最大（`1.0`），
  ///   当折痕处净纵向位移 `dy > 0`（向下推）时，越靠近屏幕中线 `u = 0.5` 硬边被推得越低，越靠近左右边缘越高：
  ///   - 左半屏（`u: 0.12 → 0.50`）天然呈 **左上 → 右下（`\` 顺斜，如 `#22`）** 走向；
  ///   - 右半屏（`u: 0.50 → 0.88`）天然呈 **左下 → 右上（`/` 逆斜，如 `#24`）** 走向。
  /// - **调节倾斜角度的陡缓**：
  ///   - **更陡（约 45° 飞刃，如 `#22`/`#24`）**：加大 `|r[7]|`（`0.45 ~ 0.55`），并把纵向折痕中心 `cy` 往中线收拢
  ///     （左刃取 `p[5] ≈ 2.43` 即 `cy ≈ 0.73`；右刃取 `p[5] ≈ 5.57` 即 `cy ≈ 0.27`），让高度落差集中在半屏内释放。
  ///   - **更平缓（宽斩或水平长弧，如 `#25`/`#28`/`#29`）**：减小 `|r[7]|`（`0.00 ~ 0.20`），并把 `cy` 推向远端边界
  ///     （左刃取 `p[5] ≈ 1.57~1.68` 即 `cy ≈ 0.86`；右刃取 `p[5] ≈ 4.71~4.82` 即 `cy ≈ 0.14`）。
  ///
  /// #### 4. 控制硬边的「长度 / 跨度」
  /// 硬边长度取决于满足 `1 + ∂dy/∂v < 0` 的横向区间宽度：
  /// - **短刃（`0.25 ~ 0.35` 屏宽）**：`|r[10]|` 偏小（`-0.70 ~ -0.80`）或 `|r[7]|` 偏大，仅单侧峰值区突破折叠阈值。
  /// - **中长斜刃（`0.40 ~ 0.45` 屏宽，如 `#22`/`#24`/`#26`/`#27`）**：`r[10] ≈ -0.85 ~ -0.90`，`r[6] ≈ 0.55 ~ 0.60`，
  ///   `|r[7]| ≈ 0.45 ~ 0.50`，硬边干净占满单侧半屏、不过中线。
  /// - **跨中线超长刃 / 宽幅长虹（`0.50 ~ 0.65` 屏宽，如 `#25`/`#28`/`#29`）**：拉大 `r[6]`（`0.64 ~ 0.85`）与
  ///   `|r[10]|`（`-0.90 ~ -0.96`），同时把 `|r[7]|` 压小到 `0.00 ~ 0.20`、把 `cy` 推到最外侧（`sin(p[5]) ≈ ±1`），
  ///   折叠区即可跨越中线延伸到另一侧。
  ///
  /// #### 5. 控制硬边的「形状 / 曲率」与「左右镜像公式」
  /// - **直线斜切（Slash） vs 弯月托弧（Crescent / Valley）**：
  ///   - 直线感强：靠 `r[4]`（纵向 `tanh`）和 `r[9]`/`r[11]`（对角 `tanh`）主导斜率，呈近似直线的斜切刀锋（如 `#22`/`#24`）。
  ///   - 月弧感强：提高 `r[5]` 与 `r[6]`（正弦驻波 `sin(πu)` 占比变大），利用正弦波在中段圆润拱起的特性，
  ///     呈现向下兜底的深谷托弧（如 `#25`/`#26`/`#27`）。
  /// - **左右精确镜像转换公式**（把任意左侧硬边一键镜像到右侧，如 `#22 → #24`、`#26 → #27`、`#28 → #29`）：
  ///   - 相位 `p`：`p[0]`、`p[2]`、`p[3]` 不变；`p[4]` 和 `p[5]` 各加 `π`（`+3.14`）；`p[1]` 从 `4.67` 改为 `1.57`。
  ///   - 幅值 `r`：将 `r[0]`、`r[4]`、`r[7]`、`r[8]`、`r[9]` 取反，其余（`r[1]`、`r[2]`、`r[3]`、`r[5]`、`r[6]`、`r[10]`、`r[11]`）符号不变。
  ///
  /// #### 6. 控制「抗锯齿 / 平滑度」（避免 1px 台阶走样）
  /// - 锯齿来自横向高频模态 `r[1]`（`m2`）和 `r[2]`（`m4` 的 x 分量）把横向雅可比 `1 + ∂dx/∂u` 压得过窄（亚像素跳变）。
  /// - 保持 `|r[1]| ≤ 0.40`、`|r[2]| ≤ 0.42` 且横向不折返（`1 + ∂dx/∂u > 0`），即可在保留纵向折叠硬边锐度的同时，
  ///   在 `test/terrain_jaggedness_test.dart` 中稳定达到 `< 5%` 的「干净」无锯齿标准。
  final List<double> r;

  /// 是否为「硬边」地形。
  ///
  /// 为 true 时贴图雅可比在折痕处被压到接近 0，画面上会出现刀锋般清晰的颜色分界线；
  /// 为 false 时只有平缓的山坡起伏，颜色过渡柔和、没有可见边界。
  ///
  /// 该标记不参与几何计算，仅用于对外描述地形风格，并由单元测试守住
  /// 「硬边多于柔和」的预设池配比。
  final bool hardEdge;
}

/// 精选的 30 组地形预设池，涵盖峭壁、光棱、峡谷、地平线与深海等不同风格，每次切歌随机抽取一组（避免连续重复）。
///
/// 其中 23 组带刀锋般的颜色分界线（[TerrainPreset.hardEdge]），7 组只有平缓山坡。
/// 硬边组刻意偏多：随机切歌时约有四分之三的机会抽到硬边，保留冲击力。
///
/// 硬边的**横向与纵向落点**由参数本身决定：
/// - #0~#10 的刀锋锁在画面中线附近（u ≈ 0.48~0.66）；
/// - #14~#18 靠纵向折痕把刀锋推到画面右侧（u ≈ 0.66~0.77），偏右但不贴边，刀锋完整落在画面里；
/// - #19~#29 为针对移动端音乐播放页优化的下半幅/底部硬边（v ≈ 0.56~0.84），避开上半屏居中封面遮挡，在歌名、歌词与播放控件区后方拉出富有张力的斜刃、深谷与长弧。
const List<TerrainPreset> kTerrainPresets = [
  // #0: 柔和斜波流（Soft Diagonal Wave）
  TerrainPreset(
    p: [4.67, 2.70, 4.24, 1.59, 0.00, 0.00],
    r: [
      -0.62, 0.70, -0.12, 0.00, 0.00, -0.48, 0.41, 0.75, -0.55, -0.91, -0.37, 0.87,
    ],
  ),
  // #1: 光棱锐折（Prism Edge）- 右下方锐利明亮折角
  TerrainPreset(
    p: [5.36, 5.68, 5.32, 2.82, 0.00, 0.00],
    r: [
      -0.70, 0.39, -0.09, 0.00, 0.00, 0.61, 0.98, -0.53, 0.16, 0.67, 0.87, 0.01,
    ],
    hardEdge: true,
  ),
  // #2: 纵向峭壁（Vertical Ridge）- 垂直大悬崖，层次立体
  TerrainPreset(
    p: [1.47, 0.65, 2.70, 5.10, 0.00, 0.00],
    r: [
      0.65, 0.65, 0.98, 0.00, 0.00, 0.20, -0.15, 0.82, -0.49, -0.58, -0.87, -0.68,
    ],
    hardEdge: true,
  ),
  // #3: 舒缓洋流（Gentle Current）- 广阔平坦大波澜
  TerrainPreset(
    p: [6.21, 3.60, 0.28, 3.30, 0.00, 0.00],
    r: [
      -0.96, 0.24, -0.69, 0.00, 0.00, 0.32, 0.48, -0.82, 0.30, 0.40, 0.49, -0.43,
    ],
  ),
  // #4: 裂隙断层（Chasm Fault）- 中央下沉深邃断崖
  TerrainPreset( // 适合移动端
    p: [0.59, 1.55, 1.01, 0.91, 0.00, 0.00],
    r: [
      -0.27, 0.78, -0.70, 0.00, 0.00, -0.61, -0.68, 0.49, -0.41, -0.18, -0.82, -0.79,
    ],
    hardEdge: true,
  ),
  // #5: 对角光棱（Diagonal Prism）- 对角刀锋折光边缘，贴图在折痕处被压成一条硬边
  TerrainPreset(
    p: [2.40, 1.80, 5.00, 2.10, 0.00, 0.00],
    r: [
      -0.50, 0.55, 0.95, 0.00, 0.00, 0.55, 0.85, -0.40, 0.25, 0.85, 0.90, -0.30,
    ],
    hardEdge: true,
  ),
  // #6: 弧月断崖（Crescent Ridge）- 立体鲜明的月弧悬崖断层分界线
  TerrainPreset(
    p: [4.80, 0.50, 2.20, 4.50, 0.00, 0.00],
    r: [
      0.60, 0.95, 0.70, 0.00, 0.00, -0.40, -0.20, 0.75, 0.80, -0.40, -0.92, 0.70,
    ],
    hardEdge: true,
  ),
  // #7: 双峰峡谷（Twin Peaks Canyon）- 左右双峰夹峙，中央通光走廊
  TerrainPreset(
    p: [4.10, 2.30, 3.80, 1.20, 0.00, 0.00],
    r: [
      0.17, 0.38, -0.30, 0.00, 0.00, -0.21, 0.47, 0.38, 0.38, -0.47, -0.55, 0.47,
    ],
  ),
  // #8: 深海极境（Deep Calm）- 极简安宁的大曲率微澜
  TerrainPreset(
    p: [0.00, 1.00, 2.00, 3.00, 0.00, 0.00],
    r: [
      0.45, 0.15, -0.20, 0.00, 0.00, 0.35, 0.20, -0.15, 0.25, -0.20, 0.30, 0.20,
    ],
  ),
  // #9: 水平光断（Horizon Rift）- 横向刀锋折光，画面被一条水平亮带截成上下两层
  TerrainPreset(
    p: [1.48, 1.28, 5.86, 3.33, 0.00, 0.00],
    r: [
      -0.79, -0.14, 0.09, 0.00, 0.00, 0.50, 0.72, -0.28, 0.49, -0.38, -0.68, 0.02,
    ],
    hardEdge: true,
  ),
  // #10: 侧棱裂崖（Side Blade）- 右侧纵向折棱把色彩压成一条陡立光刃
  //
  // `r[1]`/`r[2]` 曾取 0.38 / -0.77，折痕斜率过陡，边缘被压到亚像素宽，
  // 斜向段落因此出现 1px 台阶（见 test/terrain_jaggedness_test.dart）。
  // 按 0.8 倍收敛到 0.30 / -0.62 后台阶行占比从 10.3% 降到 0%，光刃依旧锐利。
  TerrainPreset( // 直下的硬边缘，适合移动端
    p: [0.39, 0.86, 6.12, 4.08, 0.00, 0.00],
    r: [
      0.81, 0.35, -0.70, 0.00, 0.00, -0.77, -0.77, 0.03, 0.36, -0.98, 0.19, -0.66,
    ],
    hardEdge: true,
  ),
  // #11: 潮汐横涌（Tidal Swell）- 横向长波缓缓推涌，颜色过渡柔软
  TerrainPreset(
    p: [2.90, 4.10, 1.60, 5.20, 0.00, 0.00],
    r: [
      0.30, 0.00, 0.10, 0.00, 0.00, 0.45, 0.95, 0.18, 0.45, -0.20, 0.35, 0.15,
    ],
  ),
  // #12: 对角缓流（Diagonal Drift）- 斜向大缓坡，色带平缓推移
  TerrainPreset(
    p: [5.40, 1.10, 3.30, 2.60, 0.00, 0.00],
    r: [
      0.78, 0.32, 0.00, 0.00, 0.00, 0.68, 0.00, 0.30, 0.50, 0.50, 0.35, -0.30,
    ],
  ),
  // #13: 穹顶微澜（Dome Ripple）- 中央缓隆、四周微澜
  TerrainPreset(
    p: [0.90, 3.20, 5.80, 4.30, 0.00, 0.00],
    r: [
      0.85, 0.00, 0.00, 0.00, 0.00, -0.70, 0.00, 0.00, 0.40, -0.25, 0.35, 0.22,
    ],
  ),
  // #14: 右岸宽刃（Broad Right Edge）- 刀锋落在 u≈0.77，离右边缘最远、最显眼的一条纵刃
  TerrainPreset(
    p: [5.56, 2.96, 4.49, 2.75, 2.20, 0.95],
    r: [
      0.44, -0.76, 0.29, -0.55, -0.30, -0.68, 0.57, -0.67, 0.77, -0.57, -0.46, 0.01,
    ],
    hardEdge: true,
  ),
  // #15: 右肩折叠（Upper Right Shoulder）- 刀锋落在 u≈0.68 的上半幅，右边缘还留五分之一画宽
  TerrainPreset(
    p: [4.01, 4.75, 2.56, 4.46, 0.65, 1.12],
    r: [
      0.51, -0.72, 0.81, -0.86, 0.74, -0.38, -0.61, -0.64, -0.25, 0.32, -0.45, -0.55,
    ],
    hardEdge: true,
  ),
  // #16: 右下缓刃（Lower Right Drift）- 刀锋 u≈0.67 压在下半幅，转折比 #15 圆缓
  TerrainPreset( // 右下硬边缘，适合移动端
    p: [3.57, 3.62, 4.56, 1.26, 0.61, 2.89],
    r: [
      0.86, 0.25, 0.06, -0.93, -0.46, 0.56, 0.46, -0.52, 0.70, 0.71, -0.13, -0.01,
    ],
    hardEdge: true,
  ),
  // #17: 右中斜崖（Mid Right Fold）- 刀锋 u≈0.70 贯穿中段，纵向覆盖最完整的一组长刃
  TerrainPreset( // 右中硬边缘，适合移动端
    p: [0.90, 4.22, 5.70, 0.45, 2.55, 2.21],
    r: [
      0.30, -0.29, -0.71, -0.65, -0.90, -0.78, -0.04, -0.63, -0.94, -0.05, -0.72, -0.80,
    ],
    hardEdge: true,
  ),
  // #18: 右岸垂帘（Right Curtain）- 刀锋 u≈0.77 从下半幅垂下，边缘贴着中右而不再贴边
  TerrainPreset(
    p: [3.45, 5.41, 2.03, 3.79, 2.55, 0.50],
    r: [
      0.58, -0.05, 0.93, -0.45, 0.39, 0.74, 0.76, -0.40, 0.42, 0.55, -0.70, 0.02,
    ],
    hardEdge: true,
  ),
  // #19: 底部平刃（Bottom Horizon Shelf）- 水平横切断崖，刀锋落在 v≈0.72 横贯下半幅，托起歌词和播放控制栏
  TerrainPreset(
    p: [0.85, 1.20, 0.90, 3.14, 0.00, 0.00],
    r: [
      0.20, 0.35, -0.25, 0.00, 0.00, 0.40, 0.75, -0.30, 0.45, 0.20, -0.85, 0.15,
    ],
    hardEdge: true,
  ),

  // #20: 下沉帷幕（Bottom Curtain Drift）- 纵横结合的重力下垂帷幕，在 v≈0.78 处铺展刀锋
  TerrainPreset( // 右下硬边缘，适合移动端
    p: [1.25, 1.80, 1.20, 4.50, 1.57, 1.57],
    r: [
      0.30, -0.40, 0.35, -0.55, -0.70, 0.45, 0.85, -0.50, 0.70, 0.35, -0.88, 0.25,
    ],
    hardEdge: true,
  ),
  // #21: 底座月弧（Base Crescent Ridge）- 下半幅呈微向上弯的月弧悬崖，v≈0.70~0.80 优美包裹底部
  // TerrainPreset( // 硬边缘在左边，由于音乐播放器基本上看不到所以去掉
  //   p: [0.70, 0.60, 0.85, 3.80, 0.00, 0.00],
  //   r: [
  //     -0.50, 0.50, 0.60, 0.00, 0.00, -0.45, 0.90, 0.60, 0.75, 0.65, -0.85, 0.50,
  //   ],
  //   hardEdge: true,
  // ),
  // #22: 左下飞刃（Lower Left Steep Slash）- 约45°斜向陡斜光棱，斜穿左下半区（约0.45屏宽），右半区完全柔和
  // 由于硬边缘在左侧，会被封面挡住，不适合桌面端
  TerrainPreset( // 硬边缘在左下，对移动端音乐播放器来说效果最好的一组（上方是封面，下方是控件区，硬边缘在上方会被封面挡住，最好在下方并且有一定长度）
    p: [0.45, 4.67, 2.69, 2.48, 2.46, 2.43],
    r: [
      -0.50, 0.60, -0.65, 0.20, -0.75, 0.50, 0.55, 0.50, 0.50, -0.80, -0.85, -0.40,
    ],
    hardEdge: true,
  ),
  // #23: 右下折角（Bottom Right L-Notch）- 纵横双向交汇成锐折L型短角标，刚好像框一样包围右下角控制按键区
  TerrainPreset( // 下方边缘，适合移动端
    p: [0.85, 3.50, 0.90, 2.10, 2.30, 1.05],
    r: [
      0.35, -0.30, 0.35, -0.70, -0.45, 0.40, 0.78, -0.25, 0.50, 0.30, -0.82, -0.20,
    ],
    hardEdge: true,
  ),
  // #24: 右下飞刃（Lower Right Steep Slash）- #22 的镜像姊妹款，约45°陡斜光棱斜穿右下半区（x≈0.50~0.88, y≈0.58~0.75），左半区完全柔和
  TerrainPreset( // 适合移动端
    p: [0.45, 1.57, 2.69, 2.48, 5.60, 5.57],
    r: [
      0.50, 0.40, -0.42, 0.20, 0.75, 0.50, 0.55, -0.50, -0.55, 0.80, -0.85, -0.40,
    ],
    hardEdge: true,
  ),
  // #25: 下幅长虹（Lower Wide Horizon Arc）- 横贯下半幅中段（x≈0.16~0.72, y≈0.64~0.74）的宽幅微弧长刃，在居中封面与底部控件区之间拉出舒展分界
    // 由于硬边缘在左侧，会被封面挡住，不适合桌面端
  TerrainPreset(  // 适合移动端
    p: [0.48, 4.67, 2.66, 2.48, 1.57, 1.57],
    r: [
      -0.25, 0.25, -0.20, 0.10, -0.25, 0.90, 0.85, -0.05, 0.88, -0.75, -0.96, -0.50,
    ],
    hardEdge: true,
  ),
  // #26: 左下深谷（Lower Left Deep Valley）- 比 #22 更靠底（x≈0.14~0.56, y≈0.64~0.82），刀锋沉入左下播放控制栏与歌词区后方
    // 由于硬边缘在左侧，会被封面挡住，不适合桌面端
  TerrainPreset( // 适合移动端
    p: [0.78, 4.67, 2.36, 2.48, 2.25, 2.22],
    r: [
      -0.48, 0.30, -0.30, 0.20, -0.78, 0.68, 0.58, 0.45, 0.58, -0.80, -0.90, -0.45,
    ],
    hardEdge: true,
  ),
  // #27: 右下深谷（Lower Right Deep Valley）- 压在右下半幅深处（x≈0.44~0.86, y≈0.64~0.82），从底部中央向右上扬起长弧托住右下控件区
  TerrainPreset(  // 适合移动端
    p: [0.78, 1.57, 2.36, 2.48, 5.39, 5.36],
    r: [
      0.48, 0.36, -0.36, 0.20, 0.78, 0.68, 0.58, -0.45, -0.58, 0.80, -0.90, -0.45,
    ],
    hardEdge: true,
  ),
  // #28: 左下宽斩（Lower Left Broad Slash）- 倾角比 #22 更舒展、横向跨度更宽（x≈0.14~0.64, y≈0.62~0.78），从左腰一路斜贯过中线
    // 由于硬边缘在左侧，会被封面挡住，不适合桌面端
  TerrainPreset(  // 适合移动端
    p: [0.55, 4.67, 2.59, 2.48, 1.68, 1.65],
    r: [
      -0.40, 0.34, -0.32, 0.18, -0.82, 0.66, 0.64, 0.20, 0.68, -0.82, -0.90, -0.45,
    ],
    hardEdge: true,
  ),
  // #29: 右下宽斩（Lower Right Broad Slash）- 倾角舒展、横向跨度更宽（x≈0.36~0.86, y≈0.62~0.78），从底部中左一路逆斜延伸至右腰
  TerrainPreset(  // 适合移动端
    p: [0.55, 1.57, 2.59, 2.48, 4.82, 4.79],
    r: [
      0.40, 0.34, -0.32, 0.18, 0.82, 0.66, 0.64, -0.20, -0.68, 0.82, -0.90, -0.45,
    ],
    hardEdge: true,
  ),
];

double _fastTanh(double x) {
  if (x > 20.0) return 1.0;
  if (x < -20.0) return -1.0;
  final e2x = math.exp(2.0 * x);
  return (e2x - 1.0) / (e2x + 1.0);
}

/// 扭曲网格几何生成器。
///
/// 采用 96×96 单元格（97×97 = 9409 个顶点，18432 个三角形）。
/// 高细分网格能在悬崖（cliff）强对比边缘处提供平滑连续的曲面采样，显著削弱粗网格三角形引起的边缘阶梯走样。
/// 单帧构建约 0.46ms（Debug VM），相比 48 细分只多 0.34ms，GPU 侧顶点量依然可以忽略。
/// 利用正弦模态 sin(nπu)sin(mπv) 在四边天然为零的特性，确保网格无论怎样变形四边都不会露空拉胶。
class WarpGrid {
  static const int kCells = 96;
  static const int kVerts = kCells + 1; // 97
  static const int vertexCount = kVerts * kVerts; // 9409
  static const int triangleIndexCount = kCells * kCells * 6; // 55296

  static final Uint16List _staticIndices = _buildIndices();

  static Uint16List _buildIndices() {
    final indices = Uint16List(triangleIndexCount);
    int i = 0;
    for (int y = 0; y < kCells; ++y) {
      for (int x = 0; x < kCells; ++x) {
        final int a = y * kVerts + x;
        indices[i++] = a;
        indices[i++] = a + kVerts;
        indices[i++] = a + 1;
        indices[i++] = a + 1;
        indices[i++] = a + kVerts;
        indices[i++] = a + kVerts + 1;
      }
    }
    return indices;
  }

  /// 获取共享的静态三角剖分索引。
  static Uint16List get indices => _staticIndices;

  /// 根据目标尺寸、纹理尺寸和预设索引生成 [ui.Vertices]。
  static ui.Vertices buildVertices({
    required double width,
    required double height,
    double textureWidth = 32.0,
    double textureHeight = 32.0,
    int presetIndex = 0,
    double time = 0.0,
  }) {
    final int safeIdx = presetIndex.clamp(0, kTerrainPresets.length - 1);
    final preset = kTerrainPresets[safeIdx];
    return buildVerticesWithParams(
      width: width,
      height: height,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
      p: preset.p,
      r: preset.r,
      time: time,
    );
  }

  /// 在两个预设索引之间平滑插值（Morphing）生成顶点。
  static ui.Vertices buildMorphedVertices({
    required double width,
    required double height,
    double textureWidth = 32.0,
    double textureHeight = 32.0,
    required int fromPresetIndex,
    required int toPresetIndex,
    required double progress,
    double time = 0.0,
  }) {
    final int fromIdx = fromPresetIndex.clamp(0, kTerrainPresets.length - 1);
    final int toIdx = toPresetIndex.clamp(0, kTerrainPresets.length - 1);
    return buildMorphedVerticesBetweenPresets(
      width: width,
      height: height,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
      fromPreset: kTerrainPresets[fromIdx],
      toPreset: kTerrainPresets[toIdx],
      progress: progress,
      time: time,
    );
  }

  /// 在两个预设对象（或自定义插值参数）[fromPreset] 与 [toPreset] 之间平滑插值（Morphing）生成顶点。
  static ui.Vertices buildMorphedVerticesBetweenPresets({
    required double width,
    required double height,
    double textureWidth = 32.0,
    double textureHeight = 32.0,
    required TerrainPreset fromPreset,
    required TerrainPreset toPreset,
    required double progress,
    double time = 0.0,
  }) {
    if (progress <= 0.0) {
      return buildVerticesWithParams(
        width: width,
        height: height,
        textureWidth: textureWidth,
        textureHeight: textureHeight,
        p: fromPreset.p,
        r: fromPreset.r,
        time: time,
      );
    }
    if (progress >= 1.0) {
      return buildVerticesWithParams(
        width: width,
        height: height,
        textureWidth: textureWidth,
        textureHeight: textureHeight,
        p: toPreset.p,
        r: toPreset.r,
        time: time,
      );
    }

    final double t = progress.clamp(0.0, 1.0);
    final p = List<double>.generate(
      fromPreset.p.length,
      (i) => fromPreset.p[i] + (toPreset.p[i] - fromPreset.p[i]) * t,
    );
    final r = List<double>.generate(
      fromPreset.r.length,
      (i) => fromPreset.r[i] + (toPreset.r[i] - fromPreset.r[i]) * t,
    );

    return buildVerticesWithParams(
      width: width,
      height: height,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
      p: p,
      r: r,
      time: time,
    );
  }

  /// 站波幅值的时间调制系数：幅值按 `1 ± kPulse` 缓慢呼吸，产生持续的流变感。
  /// 设置为 0.20，兼顾丰富的有机流动感与网格几何拓扑的平滑防折叠。
  static const double kAmplitudePulse = 0.20;

  /// 时间调制的角频率（乘以由 `speed` 缩放后的时间）。
  static const double kPulseRate = 2.0;

  /// 按时间调制各模态幅值。
  ///
  /// 只缩放幅值、不改变模态本身的零点位置，因此四边依然被钉死在 u/v = 0、1 上，
  /// 网格既不会拉胶也不会露空。
  static List<double> _modulateAmplitudes(List<double> r, double time) {
    final double t = time * kPulseRate;
    return List<double>.generate(
      r.length,
      (i) => r[i] * (1.0 + kAmplitudePulse * math.sin(t + i * 1.7)),
      growable: false,
    );
  }

  /// 使用自定义地形参数 [p] 与 [r] 生成顶点。
  ///
  /// [time] 大于 0 时，驻波幅值会随时间缓慢调制，网格持续流变。
  static ui.Vertices buildVerticesWithParams({
    required double width,
    required double height,
    double textureWidth = 32.0,
    double textureHeight = 32.0,
    required List<double> p,
    required List<double> r,
    double time = 0.0,
  }) {
    final List<double> amp = time == 0.0
        ? r
        : _modulateAmplitudes(r, time);

    final positions = Float32List(vertexCount * 2);
    final texCoords = Float32List(vertexCount * 2);

    int posIndex = 0;
    int uvIndex = 0;

    const double kPi = math.pi;

    // 纵向折痕只随 u 变化，按列预计算一次（含幅值），避免逐顶点重复算 exp。
    // 幅值为 0 时整列保持 0，旧预设不承担任何额外开销。
    // 只有 6 相位的预设才启用纵向折痕：4 相位的旧参数保持原样（`r[3]`/`r[4]` 继续闲置）。
    final vFoldX = Float64List(kVerts);
    final vFoldY = Float64List(kVerts);
    if (p.length > 5 && (amp[3] != 0.0 || amp[4] != 0.0)) {
      final double cx = 0.5 + 0.36 * math.sin(p[4]);
      final double cy = 0.5 + 0.36 * math.sin(p[5]);
      for (int xi = 0; xi < kVerts; ++xi) {
        final double u = xi / kCells;
        if (amp[3] != 0.0) {
          vFoldX[xi] = 0.10 * amp[3] * _fastTanh(6.0 * (u - cx));
        }
        if (amp[4] != 0.0) {
          vFoldY[xi] = 0.12 * amp[4] * _fastTanh(6.0 * (u - cy));
        }
      }
    }

    for (int yi = 0; yi < kVerts; ++yi) {
      final double v = yi / kCells;
      for (int xi = 0; xi < kVerts; ++xi) {
        final double u = xi / kCells;

        // 钉边驻波模态：在 u=0,1 或 v=0,1 时正弦值恒为 0
        final double m1 = math.sin(kPi * u) * math.sin(kPi * v);
        final double m2 = math.sin(2.0 * kPi * u) * math.sin(kPi * v);
        final double m3 = math.sin(kPi * u) * math.sin(2.0 * kPi * v);
        final double m4 = math.sin(2.0 * kPi * u) * math.sin(2.0 * kPi * v);

        // 山坡（驻波模态叠加） + 悬崖（tanh 折叠面与中心包络向边缘渐隐）
        //
        // 折痕分三类：横向（只随 v）、对角（随 u±v）、纵向（只随 u）。
        // 纵向折痕是唯一能把刀锋硬边推到画面左侧/右侧的手段：m1/m2/m4 对 u 的
        // 导数极值只出现在 u = 0、0.5、1，没有纵向折痕时雅可比压缩带必然锁在画布中线。
        // 三类折痕统一乘 m1 做边缘包络，保证贴到边框时位移归零、网格不会拉胶。
        final double dx = 0.12 * (amp[0] * m1 + amp[1] * m2 + amp[2] * m4) +
            0.10 * amp[8] * _fastTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[0]))) * m1 +
            0.06 * amp[9] * _fastTanh(6.0 * ((u + v) * 0.7 - 0.7 - 0.33 * math.sin(p[1]))) * m1 +
            vFoldX[xi] * m1;

        final double dy = 0.12 * (amp[5] * m1 + amp[6] * m3 + amp[7] * m4) +
            0.12 * amp[10] * _fastTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[2]))) * m1 +
            0.06 * amp[11] * _fastTanh(6.0 * ((u - v) * 0.7 - 0.7 + 0.33 * math.sin(p[3]))) * m1 +
            vFoldY[xi] * m1;

        positions[posIndex++] = (u + dx) * width;
        positions[posIndex++] = (v + dy) * height;

        texCoords[uvIndex++] = u * textureWidth;
        texCoords[uvIndex++] = v * textureHeight;
      }
    }

    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: _staticIndices,
    );
  }
}
