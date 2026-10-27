import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 地形预设参数，控制网格悬崖与驻波模态形态。
class TerrainPreset {
  const TerrainPreset({required this.p, required this.r, this.hardEdge = false});

  /// 悬崖位置相位（4个浮点数），分别对应 r[8]、r[9]、r[10]、r[11] 的折痕位置
  final List<double> p;

  /// 模态/悬崖幅值（12个浮点数），索引含义：
  ///
  /// - `r[0]`、`r[1]`、`r[2]`：x 向山坡模态（m1 / m2 / m4）
  /// - `r[3]`、`r[4]`：当前未参与计算，保留占位
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
  final List<double> r;

  /// 是否为「硬边」地形。
  ///
  /// 为 true 时贴图雅可比在折痕处被压到接近 0，画面上会出现刀锋般清晰的颜色分界线；
  /// 为 false 时只有平缓的山坡起伏，颜色过渡柔和、没有可见边界。
  ///
  /// 该标记不参与几何计算，仅用于对外描述地形风格，并由单元测试守住
  /// 「硬边 : 柔和 = 1 : 1」的预设池配比。
  final bool hardEdge;
}

/// 精选的 14 组地形预设池，涵盖峭壁、光棱、峡谷、地平线与深海等不同风格，每次切歌随机抽取一组（避免连续重复）。
///
/// 池子刻意维持「硬边 : 柔和 = 1 : 1」的配比：7 组带刀锋般的颜色分界线（[TerrainPreset.hardEdge]），
/// 另外 7 组只有平缓山坡。随机切歌时硬边与柔和各有五成机会，既保留冲击力，又不会每首歌都「裂」一次。
const List<TerrainPreset> kTerrainPresets = [
  // #0: 柔和斜波流（Soft Diagonal Wave）
  TerrainPreset(
    p: [4.67, 2.70, 4.24, 1.59],
    r: [
      -0.62, 0.70, -0.12, 0.41, 0.49, -0.48, 0.41, 0.75, -0.55, -0.91, -0.37, 0.87,
    ],
  ),
  // #1: 光棱锐折（Prism Edge）- 右下方锐利明亮折角
  TerrainPreset(
    p: [5.36, 5.68, 5.32, 2.82],
    r: [
      -0.70, 0.39, -0.09, -0.81, 0.72, 0.61, 0.98, -0.53, 0.16, 0.67, 0.87, 0.01,
    ],
    hardEdge: true,
  ),
  // #2: 纵向峭壁（Vertical Ridge）- 垂直大悬崖，层次立体
  TerrainPreset(
    p: [1.47, 0.65, 2.70, 5.10],
    r: [
      0.65, 0.65, 0.98, 0.72, 0.92, 0.20, -0.15, 0.82, -0.49, -0.58, -0.87, -0.68,
    ],
    hardEdge: true,
  ),
  // #3: 舒缓洋流（Gentle Current）- 广阔平坦大波澜
  TerrainPreset(
    p: [6.21, 3.60, 0.28, 3.30],
    r: [
      -0.96, 0.24, -0.69, 0.37, 0.20, 0.32, 0.48, -0.82, 0.30, 0.40, 0.49, -0.43,
    ],
  ),
  // #4: 裂隙断层（Chasm Fault）- 中央下沉深邃断崖
  TerrainPreset(
    p: [0.59, 1.55, 1.01, 0.91],
    r: [
      -0.27, 0.78, -0.70, 0.47, -0.26, -0.61, -0.68, 0.49, -0.41, -0.18, -0.82, -0.79,
    ],
    hardEdge: true,
  ),
  // #5: 对角光棱（Diagonal Prism）- 对角刀锋折光边缘，贴图在折痕处被压成一条硬边
  TerrainPreset(
    p: [2.40, 1.80, 5.00, 2.10],
    r: [
      -0.50, 0.55, 0.95, 0.0, 0.0, 0.55, 0.85, -0.40, 0.25, 0.85, 0.90, -0.30,
    ],
    hardEdge: true,
  ),
  // #6: 弧月断崖（Crescent Ridge）- 立体鲜明的月弧悬崖断层分界线
  TerrainPreset(
    p: [4.80, 0.50, 2.20, 4.50],
    r: [
      0.60, 0.95, 0.70, 0.0, 0.0, -0.40, -0.20, 0.75, 0.80, -0.40, -0.92, 0.70,
    ],
    hardEdge: true,
  ),
  // #7: 双峰峡谷（Twin Peaks Canyon）- 左右双峰夹峙，中央通光走廊
  TerrainPreset(
    p: [4.10, 2.30, 3.80, 1.20],
    r: [
      0.17, 0.38, -0.30, 0.0, 0.0, -0.21, 0.47, 0.38, 0.38, -0.47, -0.55, 0.47,
    ],
  ),
  // #8: 深海极境（Deep Calm）- 极简安宁的大曲率微澜
  TerrainPreset(
    p: [0.00, 1.00, 2.00, 3.00],
    r: [
      0.45, 0.15, -0.20, 0.0, 0.0, 0.35, 0.20, -0.15, 0.25, -0.20, 0.30, 0.20,
    ],
  ),
  // #9: 水平光断（Horizon Rift）- 横向刀锋折光，画面被一条水平亮带截成上下两层
  TerrainPreset(
    p: [1.48, 1.28, 5.86, 3.33],
    r: [
      -0.79, -0.17, 0.11, 0.0, 0.0, 0.50, 0.72, -0.28, 0.49, -0.38, -0.68, 0.02,
    ],
    hardEdge: true,
  ),
  // #10: 侧棱裂崖（Side Blade）- 右侧纵向折棱把色彩压成一条陡立光刃
  TerrainPreset(
    p: [0.39, 0.86, 6.12, 4.08],
    r: [
      0.81, 0.38, -0.77, 0.0, 0.0, -0.77, -0.77, 0.03, 0.36, -0.98, 0.19, -0.66,
    ],
    hardEdge: true,
  ),
  // #11: 潮汐横涌（Tidal Swell）- 横向长波缓缓推涌，颜色过渡柔软
  TerrainPreset(
    p: [2.90, 4.10, 1.60, 5.20],
    r: [
      0.30, 0.0, 0.10, 0.0, 0.0, 0.45, 0.95, 0.18, 0.45, -0.20, 0.35, 0.15,
    ],
  ),
  // #12: 对角缓流（Diagonal Drift）- 斜向大缓坡，色带平缓推移
  TerrainPreset(
    p: [5.40, 1.10, 3.30, 2.60],
    r: [
      0.78, 0.32, 0.0, 0.0, 0.0, 0.68, 0.0, 0.30, 0.50, 0.50, 0.35, -0.30,
    ],
  ),
  // #13: 穹顶微澜（Dome Ripple）- 中央缓隆、四周微澜
  TerrainPreset(
    p: [0.90, 3.20, 5.80, 4.30],
    r: [
      0.85, 0.0, 0.0, 0.0, 0.0, -0.70, 0.0, 0.0, 0.40, -0.25, 0.35, 0.22,
    ],
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
      4,
      (i) => fromPreset.p[i] + (toPreset.p[i] - fromPreset.p[i]) * t,
    );
    final r = List<double>.generate(
      12,
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
        final double dx = 0.12 * (amp[0] * m1 + amp[1] * m2 + amp[2] * m4) +
            0.10 * amp[8] * _fastTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[0]))) * m1 +
            0.06 * amp[9] * _fastTanh(6.0 * ((u + v) * 0.7 - 0.7 - 0.33 * math.sin(p[1]))) * m1;

        final double dy = 0.12 * (amp[5] * m1 + amp[6] * m3 + amp[7] * m4) +
            0.12 * amp[10] * _fastTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[2]))) * m1 +
            0.06 * amp[11] * _fastTanh(6.0 * ((u - v) * 0.7 - 0.7 + 0.33 * math.sin(p[3]))) * m1;

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
