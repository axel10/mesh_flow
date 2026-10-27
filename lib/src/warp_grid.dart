import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 地形预设参数，控制网格悬崖与驻波模态形态。
class TerrainPreset {
  const TerrainPreset({required this.p, required this.r});

  /// 悬崖位置相位（4个浮点数）
  final List<double> p;

  /// 模态/悬崖幅值（12个浮点数）
  final List<double> r;
}

/// QueMusic 海选出的 5 组地形预设池，每次切歌随机抽取一组（避免连续重复）。
const List<TerrainPreset> kTerrainPresets = [
  TerrainPreset(
    p: [4.67, 2.70, 4.24, 1.59],
    r: [
      -0.62, 0.70, -0.12, 0.41, 0.49, -0.48, 0.41, 0.75, -0.55, -0.91, -0.37, 0.87,
    ],
  ),
  TerrainPreset(
    p: [5.36, 5.68, 5.32, 2.82],
    r: [
      -0.70, 0.39, -0.09, -0.81, 0.72, 0.61, 0.98, -0.53, 0.16, 0.67, 0.87, 0.01,
    ],
  ),
  TerrainPreset(
    p: [1.47, 0.65, 2.70, 5.10],
    r: [
      0.65, 0.65, 0.98, 0.72, 0.92, 0.20, -0.15, 0.82, -0.49, -0.58, -0.87, -0.68,
    ],
  ),
  TerrainPreset(
    p: [6.21, 3.60, 0.28, 3.30],
    r: [
      -0.96, 0.24, -0.69, 0.37, 0.20, 0.32, 0.48, -0.82, 0.30, 0.40, 0.49, -0.43,
    ],
  ),
  TerrainPreset(
    p: [0.59, 1.55, 1.01, 0.91],
    r: [
      -0.27, 0.78, -0.70, 0.47, -0.26, -0.61, -0.68, 0.49, -0.41, -0.18, -0.82, -0.79,
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
/// 采用 28×28 单元格（29×29 = 841 个顶点，1568 个三角形）。
/// 利用正弦模态 sin(nπu)sin(mπv) 在四边天然为零的特性，确保网格无论怎样变形四边都不会露空拉胶。
class WarpGrid {
  static const int kCells = 28;
  static const int kVerts = kCells + 1; // 29
  static const int vertexCount = kVerts * kVerts; // 841
  static const int triangleIndexCount = kCells * kCells * 6; // 4704

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
  ///
  /// [width] 与 [height] 为渲染目标宽高。
  /// [textureWidth] 与 [textureHeight] 为纹理像素尺寸（默认为 32.0 × 32.0）。
  /// [presetIndex] 预设索引 0..4，若为负则根据上次随机选取不重复的预设。
  static ui.Vertices buildVertices({
    required double width,
    required double height,
    double textureWidth = 32.0,
    double textureHeight = 32.0,
    int presetIndex = 0,
  }) {
    final int safeIdx = presetIndex.clamp(0, kTerrainPresets.length - 1);
    final preset = kTerrainPresets[safeIdx];
    final p = preset.p;
    final r = preset.r;

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
        final double dx = 0.12 * (r[0] * m1 + r[1] * m2 + r[2] * m4) +
            0.10 * r[8] * _fastTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[0]))) * m1 +
            0.06 * r[9] * _fastTanh(6.0 * ((u + v) * 0.7 - 0.7 - 0.33 * math.sin(p[1]))) * m1;

        final double dy = 0.12 * (r[5] * m1 + r[6] * m3 + r[7] * m4) +
            0.12 * r[10] * _fastTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[2]))) * m1 +
            0.06 * r[11] * _fastTanh(6.0 * ((u - v) * 0.7 - 0.7 + 0.33 * math.sin(p[3]))) * m1;

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
