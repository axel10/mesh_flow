import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

/// 硬边"锯齿"的量化体检。
///
/// 结论先行：这里的锯齿**不是**网格分面造成的（96 与 192 细分的渲染结果逐像素几乎相同），
/// 而是**亚像素宽的颜色跳变**——颜色在不到一个像素内从 A 跳到 B，光栅化时每个像素只采一个样，
/// 抗锯齿无从下手，斜向段落就会露出 1px 的阶梯。所以加密网格永远治不好它，
/// 只能靠"别把边缘压得太窄"。
///
/// 判据只看一个量：**边缘过渡带在屏幕上的宽度**（0.2→0.8 的色差跨多少像素）。
/// 用 32×32 的双色贴图（中间一条 1 纹素宽的硬边）过真实渲染管线，
/// 逐行找交点、量宽度，统计宽度 ≤ [kStepWidthPx] 的行占比，即"台阶行占比"。
///
/// - 0%：边缘至少跨 2px，抗锯齿生效，肉眼看不到台阶（当前 #0/#1/#3/#7/#8/#9/#11/#12/#13）。
/// - 1~10%：局部有极窄段落，缩放到 1:1 能看到轻微台阶。
/// - >10%：折痕被压得过狠，斜向段落成片出台阶（#10 修前 10.3%）。
///
/// 这套测量与观感对得上：`#1`（用户认可的"锐而不刺")= 0%，`#10`（反馈有锯齿）= 10.3%。
/// 过渡宽度不超过这个值就算"一个像素内跳完"，抗锯齿失效 → 出台阶。
const double kStepWidthPx = 1.5;

/// 建议上限：超出的地形在 1:1 缩放下能看到台阶。
const double kRecommendedMax = 0.05;

/// 红线：超出的地形斜向段落会成片出台阶。
const double kHardCap = 0.25;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('每组地形预设的硬边锯齿体检', () async {
    final texture = await _hardEdgeTexture();
    final buf = StringBuffer()
      ..writeln('idx  类型   边缘行数  中位宽度px  台阶行占比  判定');

    final offenders = <String>[];
    for (int i = 0; i < kTerrainPresets.length; ++i) {
      final preset = kTerrainPresets[i];
      final stats = await _measure(texture, i);
      final ratio = stats.stepRatio;

      final String verdict;
      if (stats.rows == 0) {
        verdict = '无硬边';
      } else if (ratio <= kRecommendedMax) {
        verdict = '干净';
      } else if (ratio <= kHardCap) {
        verdict = '局部台阶';
        offenders.add('#$i ${(ratio * 100).toStringAsFixed(1)}%');
      } else {
        verdict = '成片台阶';
        offenders.add('#$i ${(ratio * 100).toStringAsFixed(1)}% (!)');
      }

      buf.writeln('${i.toString().padLeft(3)}  '
          '${(preset.hardEdge ? "HARD" : "soft").padRight(5)}  '
          '${stats.rows.toString().padLeft(8)}  '
          '${stats.medianWidth.toStringAsFixed(2).padLeft(10)}  '
          '${"${(ratio * 100).toStringAsFixed(1)}%".padLeft(10)}  '
          '$verdict');
    }
    // ignore: avoid_print
    print(buf.toString());

    // 反向守卫：任何预设都不许悄悄退化到"成片台阶"。
    expect(
      offenders.where((e) => e.contains('(!)')).toList(),
      isEmpty,
      reason: '这些地形叠台阶超过 ${(kHardCap * 100).round()}%，需要降低 r[1]/r[2]：$offenders',
    );
  });
}

class _Stats {
  _Stats(this.rows, this.medianWidth, this.stepRatio);

  final int rows;
  final double medianWidth;
  final double stepRatio;
}

/// 32×32 双色贴图：左蓝右黄，中间是一条 1 纹素宽的硬边。
Future<ui.Image> _hardEdgeTexture() {
  const int n = 32;
  final pixels = Uint8List(n * n * 4);
  for (int y = 0; y < n; ++y) {
    for (int x = 0; x < n; ++x) {
      final int i = (y * n + x) * 4;
      final bool right = x >= n ~/ 2;
      pixels[i] = right ? 0xF5 : 0x2D;
      pixels[i + 1] = right ? 0xE1 : 0x5B;
      pixels[i + 2] = right ? 0x3C : 0xFF;
      pixels[i + 3] = 255;
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, n, n, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// 沿每行找 0.5 交点，量 0.2→0.8 的过渡宽度。
Future<_Stats> _measure(ui.Image texture, int presetIndex) async {
  const int w = 240;
  const int h = 400;

  final vertices = WarpGrid.buildVertices(
    width: w.toDouble(),
    height: h.toDouble(),
    textureWidth: 32,
    textureHeight: 32,
    presetIndex: presetIndex,
  );

  final matrix = Float64List(16)
    ..[0] = 1.0
    ..[5] = 1.0
    ..[10] = 1.0
    ..[15] = 1.0;

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawVertices(
    vertices,
    ui.BlendMode.srcOver,
    ui.Paint()
      ..shader = ui.ImageShader(
        texture,
        ui.TileMode.mirror,
        ui.TileMode.mirror,
        matrix,
        filterQuality: ui.FilterQuality.medium,
      ),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  image.dispose();

  // 蓝 → 黄 轴上的投影，0 = 纯蓝，1 = 纯黄。
  double tone(int i) {
    final double r = bytes[i] - 45.0;
    final double g = bytes[i + 1] - 91.0;
    final double b = bytes[i + 2] - 255.0;
    return (r * 200.0 + g * 134.0 + b * -195.0) / (200.0 * 200.0 + 134.0 * 134.0 + 195.0 * 195.0);
  }

  final widths = <double>[];
  for (int y = 1; y < h - 1; ++y) {
    int cross = -1;
    for (int x = 1; x < w; ++x) {
      if (tone((y * w + x - 1) * 4) < 0.5 && tone((y * w + x) * 4) >= 0.5) {
        cross = x;
        break;
      }
    }
    if (cross < 6 || cross > w - 6) continue;

    int lo = cross;
    int hi = cross;
    while (lo > 0 && tone((y * w + lo) * 4) > 0.2) {
      lo--;
    }
    while (hi < w - 1 && tone((y * w + hi) * 4) < 0.8) {
      hi++;
    }
    widths.add((hi - lo).toDouble());
  }

  if (widths.isEmpty) return _Stats(0, 0, 0);
  final sorted = List<double>.from(widths)..sort();
  final median = sorted[sorted.length ~/ 2];
  final steps = widths.where((e) => e <= kStepWidthPx).length / widths.length;
  return _Stats(widths.length, median, steps);
}
