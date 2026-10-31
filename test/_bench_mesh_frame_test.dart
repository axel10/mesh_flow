// 顶点生成的性能基线 + 视觉回归守卫。
//
// 用法：任何对 WarpGrid 几何数学的改动，都在这里同时验证
//   1) 渲染结果与「改造前算法」像素级完全一致；
//   2) 单帧耗时没有退化。
//
// 运行：flutter test test/_bench_mesh_frame_test.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

const int _cells = WarpGrid.kCells;
const int _verts = WarpGrid.kVerts;

/// 改造前的原始实现，逐字保留作为参照，不要跟着 lib 一起改。
Float32List refPositions(List<double> p, List<double> r, double time, double w, double h) {
  final List<double> amp = time == 0.0
      ? r
      : List<double>.generate(
          r.length,
          (i) => r[i] * (1.0 + 0.20 * math.sin(time * 2.0 + i * 1.7)),
          growable: false,
        );

  final positions = Float32List(_verts * _verts * 2);
  final vFoldX = Float64List(_verts);
  final vFoldY = Float64List(_verts);
  if (p.length > 5 && (amp[3] != 0.0 || amp[4] != 0.0)) {
    final double cx = 0.5 + 0.36 * math.sin(p[4]);
    final double cy = 0.5 + 0.36 * math.sin(p[5]);
    for (int xi = 0; xi < _verts; ++xi) {
      final double u = xi / _cells;
      if (amp[3] != 0.0) vFoldX[xi] = 0.10 * amp[3] * _refTanh(6.0 * (u - cx));
      if (amp[4] != 0.0) vFoldY[xi] = 0.12 * amp[4] * _refTanh(6.0 * (u - cy));
    }
  }

  int posIndex = 0;
  const double kPi = math.pi;
  for (int yi = 0; yi < _verts; ++yi) {
    final double v = yi / _cells;
    for (int xi = 0; xi < _verts; ++xi) {
      final double u = xi / _cells;
      final double m1 = math.sin(kPi * u) * math.sin(kPi * v);
      final double m2 = math.sin(2.0 * kPi * u) * math.sin(kPi * v);
      final double m3 = math.sin(kPi * u) * math.sin(2.0 * kPi * v);
      final double m4 = math.sin(2.0 * kPi * u) * math.sin(2.0 * kPi * v);
      final double dx = 0.12 * (amp[0] * m1 + amp[1] * m2 + amp[2] * m4) +
          0.10 * amp[8] * _refTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[0]))) * m1 +
          0.06 * amp[9] * _refTanh(6.0 * ((u + v) * 0.7 - 0.7 - 0.33 * math.sin(p[1]))) * m1 +
          vFoldX[xi] * m1;
      final double dy = 0.12 * (amp[5] * m1 + amp[6] * m3 + amp[7] * m4) +
          0.12 * amp[10] * _refTanh(6.0 * (v - 0.5 - 0.30 * math.sin(p[2]))) * m1 +
          0.06 * amp[11] * _refTanh(6.0 * ((u - v) * 0.7 - 0.7 + 0.33 * math.sin(p[3]))) * m1 +
          vFoldY[xi] * m1;
      positions[posIndex++] = (u + dx) * w;
      positions[posIndex++] = (v + dy) * h;
    }
  }
  return positions;
}

double _refTanh(double x) {
  if (x > 20.0) return 1.0;
  if (x < -20.0) return -1.0;
  final e2x = math.exp(2.0 * x);
  return (e2x - 1.0) / (e2x + 1.0);
}

ui.Vertices refVertices(List<double> p, List<double> r, double time, double w, double h) {
  final uv = Float32List(_verts * _verts * 2);
  int q = 0;
  for (int yi = 0; yi < _verts; ++yi) {
    for (int xi = 0; xi < _verts; ++xi) {
      uv[q++] = (xi / _cells) * 32.0;
      uv[q++] = (yi / _cells) * 32.0;
    }
  }
  return ui.Vertices.raw(
    ui.VertexMode.triangles,
    refPositions(p, r, time, w, h),
    textureCoordinates: uv,
    indices: WarpGrid.indices,
  );
}

Future<Uint8List> _render(ui.Vertices v, ui.Image tex, int w, int h) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  final m = Float64List(16);
  m[0] = 1;
  m[5] = 1;
  m[10] = 1;
  m[15] = 1;
  final paint = ui.Paint()
    ..shader = ui.ImageShader(tex, ui.TileMode.mirror, ui.TileMode.mirror, m,
        filterQuality: ui.FilterQuality.medium)
    ..filterQuality = ui.FilterQuality.medium;
  canvas.drawVertices(v, ui.BlendMode.srcOver, paint);
  final img = await rec.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}

void main() {
  test('全部预设：渲染结果与改造前逐像素一致', () async {
    final tex = await CoverProcessor.createPaletteImage(const [
      ui.Color(0xFF2244AA),
      ui.Color(0xFFFFAA33),
      ui.Color(0xFF22AA88),
    ]);

    for (int idx = 0; idx < kTerrainPresets.length; idx++) {
      final p = kTerrainPresets[idx].p;
      final r = kTerrainPresets[idx].r;
      for (final time in [0.0, 3.7]) {
        final a = await _render(refVertices(p, r, time, 400, 800), tex, 400, 800);
        final b = await _render(
          WarpGrid.buildVerticesWithParams(
            width: 400,
            height: 800,
            textureWidth: 32,
            textureHeight: 32,
            p: p,
            r: r,
            time: time,
          ),
          tex,
          400,
          800,
        );
        int diffPx = 0;
        for (int i = 0; i < a.length; i += 4) {
          final d = (a[i] - b[i]).abs() +
              (a[i + 1] - b[i + 1]).abs() +
              (a[i + 2] - b[i + 2]).abs();
          if (d > 0) diffPx++;
        }
        expect(diffPx, 0, reason: 'preset #$idx t=$time 有 $diffPx 个像素不同');
      }
    }
  });

  test('单帧耗时', () {
    final p = kTerrainPresets[22].p;
    final r = kTerrainPresets[22].r;
    const int n = 500;

    void refRun() => refVertices(p, r, 1.0, 400, 800);
    void newRun() => WarpGrid.buildVerticesWithParams(
          width: 400,
          height: 800,
          textureWidth: 32,
          textureHeight: 32,
          p: p,
          r: r,
          time: 1.0,
        );

    double time(void Function() f) {
      final sw = Stopwatch()..start();
      for (int i = 0; i < n; i++) {
        f();
      }
      sw.stop();
      return sw.elapsedMicroseconds / n / 1000;
    }

    for (int i = 0; i < 200; i++) {
      refRun();
      newRun();
    }

    // A/B 交替多轮，避免单次测量的 JIT 抖动
    double refTotal = 0;
    double newTotal = 0;
    for (int round = 0; round < 3; round++) {
      refTotal += time(refRun);
      newTotal += time(newRun);
      refTotal += time(refRun);
      newTotal += time(newRun);
    }
    final refMs = refTotal / 6;
    final nowMs = newTotal / 6;
    // ignore: avoid_print
    print('改造前 ${refMs.toStringAsFixed(3)} ms/帧 | '
        '当前 ${nowMs.toStringAsFixed(3)} ms/帧 | '
        '${(refMs / nowMs).toStringAsFixed(2)}x');
  });
}
