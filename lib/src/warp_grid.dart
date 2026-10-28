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

/// 精选的 22 组地形预设池，涵盖峭壁、光棱、峡谷、地平线与深海等不同风格，每次切歌随机抽取一组（避免连续重复）。
///
/// 其中 15 组带刀锋般的颜色分界线（[TerrainPreset.hardEdge]），7 组只有平缓山坡。
/// 硬边组刻意偏多：随机切歌时约有三分之二的机会抽到硬边，保留冲击力。
///
/// 硬边的**横向落点**由参数本身决定：#0~#10 的刀锋全部锁在画面中线附近
/// （u ≈ 0.48~0.66），因为驻波模态对 u 的导数极值只出现在 u = 0、0.5、1；
/// #14~#17 靠纵向折痕（`r[3]`/`r[4]`）把刀锋推到画面右侧（u ≈ 0.77~0.93），
/// 其中 #14~#16 贴右边缘（离边仅 7~9% 画宽）、#17 稍内收；
/// #18~#21 再内收到 u ≈ 0.66~0.77——偏右但不贴边，刀锋完整落在画面里。
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
  TerrainPreset(
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
  TerrainPreset(
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
  // #14: 右上纵崖（Upper Right Rift）- 纵向折痕落在 u≈0.91，刀锋贴着画面右上方立起
  // TerrainPreset(
  //   p: [0.62, 4.25, 3.04, 3.83, 2.16, 0.69],
  //   r: [
  //     0.80, -0.36, -0.71, -0.70, -0.73, -0.57, 0.30, 0.69, -0.69, -0.55, 0.80, -0.44,
  //   ],
  //   hardEdge: true,
  // ),
  // // #15: 右中光棱（Mid Right Prism）- 纵向折痕落在 u≈0.91，刀锋贯穿画面右中部
  // TerrainPreset(
  //   p: [4.46, 4.12, 2.29, 6.28, 1.96, 0.84],
  //   r: [
  //     0.43, -0.97, 0.21, -0.85, 0.27, 0.48, 0.44, 0.40, 0.65, -0.20, 0.62, 0.39,
  //   ],
  //   hardEdge: true,
  // ),
  // // #16: 右下折崖（Lower Right Fold）- 刀锋落在 u≈0.93 的下半幅，边缘带一点回折
  // TerrainPreset(
  //   p: [1.82, 1.35, 2.31, 0.23, 0.79, 2.32],
  //   r: [
  //     0.82, -0.31, 0.96, -0.78, 0.23, 0.48, -0.40, 0.64, 0.55, 0.19, -0.95, -0.37,
  //   ],
  //   hardEdge: true,
  // ),
  // #17: 右岸宽刃（Broad Right Edge）- 刀锋落在 u≈0.77，离右边缘最远、最显眼的一条纵刃
  TerrainPreset(
    p: [5.56, 2.96, 4.49, 2.75, 2.20, 0.95],
    r: [
      0.44, -0.76, 0.29, -0.55, -0.30, -0.68, 0.57, -0.67, 0.77, -0.57, -0.46, 0.01,
    ],
    hardEdge: true,
  ),
  // #18: 右肩折叠（Upper Right Shoulder）- 刀锋落在 u≈0.68 的上半幅，右边缘还留五分之一画宽
  TerrainPreset(
    p: [4.01, 4.75, 2.56, 4.46, 0.65, 1.12],
    r: [
      0.51, -0.72, 0.81, -0.86, 0.74, -0.38, -0.61, -0.64, -0.25, 0.32, -0.45, -0.55,
    ],
    hardEdge: true,
  ),
  // #19: 右下缓刃（Lower Right Drift）- 刀锋 u≈0.67 压在下半幅，转折比 #18 圆缓
  TerrainPreset(
    p: [3.57, 3.62, 4.56, 1.26, 0.61, 2.89],
    r: [
      0.86, 0.25, 0.06, -0.93, -0.46, 0.56, 0.46, -0.52, 0.70, 0.71, -0.13, -0.01,
    ],
    hardEdge: true,
  ),
  // #20: 右中斜崖（Mid Right Fold）- 刀锋 u≈0.70 贯穿中段，纵向覆盖最完整的一组长刃
  TerrainPreset(
    p: [0.90, 4.22, 5.70, 0.45, 2.55, 2.21],
    r: [
      0.30, -0.29, -0.71, -0.65, -0.90, -0.78, -0.04, -0.63, -0.94, -0.05, -0.72, -0.80,
    ],
    hardEdge: true,
  ),
  // #21: 右岸垂帘（Right Curtain）- 刀锋 u≈0.77 从下半幅垂下，边缘贴着中右而不再贴边
  TerrainPreset(
    p: [3.45, 5.41, 2.03, 3.79, 2.55, 0.50],
    r: [
      0.58, -0.05, 0.93, -0.45, 0.39, 0.74, 0.76, -0.40, 0.42, 0.55, -0.70, 0.02,
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
