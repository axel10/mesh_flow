import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

const int kW = 240;
const int kH = 400;
const double kStepWidthPx = 1.5;

Future<ui.Image> hardEdgeTexture() {
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

/// 返回 [行数, 中位宽度, 台阶占比, 最窄宽度]
Future<List<double>> measure(ui.Image tex, List<double> p, List<double> r) async {
  final vertices = WarpGrid.buildVerticesWithParams(
    width: kW.toDouble(),
    height: kH.toDouble(),
    textureWidth: 32,
    textureHeight: 32,
    p: p,
    r: r,
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
        tex,
        ui.TileMode.mirror,
        ui.TileMode.mirror,
        matrix,
        filterQuality: ui.FilterQuality.medium,
      ),
  );
  final image = await recorder.endRecording().toImage(kW, kH);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  image.dispose();

  double tone(int i) {
    final double rr = bytes[i] - 45.0;
    final double gg = bytes[i + 1] - 91.0;
    final double bb = bytes[i + 2] - 255.0;
    return (rr * 200.0 + gg * 134.0 + bb * -195.0) / (200.0 * 200.0 + 134.0 * 134.0 + 195.0 * 195.0);
  }

  final widths = <double>[];
  for (int y = 1; y < kH - 1; ++y) {
    int cross = -1;
    for (int x = 1; x < kW; ++x) {
      if (tone((y * kW + x - 1) * 4) < 0.5 && tone((y * kW + x) * 4) >= 0.5) {
        cross = x;
        break;
      }
    }
    if (cross < 6 || cross > kW - 6) continue;
    int lo = cross;
    int hi = cross;
    while (lo > 0 && tone((y * kW + lo) * 4) > 0.2) {
      lo--;
    }
    while (hi < kW - 1 && tone((y * kW + hi) * 4) < 0.8) {
      hi++;
    }
    widths.add((hi - lo).toDouble());
  }
  if (widths.isEmpty) return <double>[0, 0, 0, 0];
  final sorted = List<double>.from(widths)..sort();
  final median = sorted[sorted.length ~/ 2];
  final narrowest = sorted[0];
  final steps = widths.where((e) => e <= kStepWidthPx).length / widths.length;
  return <double>[widths.length.toDouble(), median, steps, narrowest];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('细化扫描：找最小的 r[1]/r[2] 扰动', () async {
    final tex = await hardEdgeTexture();
    final buf = StringBuffer();

    for (int idx = 0; idx < kTerrainPresets.length; ++idx) {
      final preset = kTerrainPresets[idx];
      if (!preset.hardEdge) continue;
      buf.writeln('== #$idx  r1=${preset.r[1]}  r2=${preset.r[2]}');
      buf.writeln('   scale   r1      r2      台阶占比   中位宽   最窄');

      for (final s in <double>[1.00, 0.98, 0.97, 0.96, 0.95, 0.94, 0.93, 0.92, 0.90, 0.88]) {
        final r = List<double>.from(preset.r);
        r[1] *= s;
        r[2] *= s;
        final st = await measure(tex, preset.p, r);
        buf.writeln('   ${s.toStringAsFixed(2)}    '
            '${r[1].toStringAsFixed(3).padLeft(6)}  '
            '${r[2].toStringAsFixed(3).padLeft(6)}  '
            '${"${(st[2] * 100).toStringAsFixed(1)}%".padLeft(9)}  '
            '${st[1].toStringAsFixed(2).padLeft(7)}  '
            '${st[3].toStringAsFixed(0).padLeft(4)}');
      }
    }
    // ignore: avoid_print
    print(buf.toString());
    expect(true, isTrue);
  });
}
