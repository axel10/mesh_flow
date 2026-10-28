import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

const int kW = 240;
const int kH = 400;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('分桶看跳变强度', () async {
    final cover = await _cover();
    for (final idx in [14, 17, 18, 20, 21]) {
      final img = await _render(cover, idx);
      final buf = StringBuffer('#$idx  桶(按u) : 平均跳变  最大跳变\n');
      // 12 个桶
      for (int b = 0; b < 12; ++b) {
        final double lo = b / 12, hi = (b + 1) / 12;
        double sum = 0;
        double mx = 0;
        int n = 0;
        for (int y = 4; y < kH - 4; ++y) {
          for (int x = (lo * kW).floor() + 2; x < (hi * kW).floor() - 2; ++x) {
            final double d = _jump(img, x, y);
            sum += d;
            if (d > mx) mx = d;
            ++n;
          }
        }
        buf.writeln('   ${lo.toStringAsFixed(2)}-${hi.toStringAsFixed(2)}  '
            '${(sum / n).toStringAsFixed(1).padLeft(7)}  ${mx.toStringAsFixed(0).padLeft(6)}');
      }
      // ignore: avoid_print
      print(buf.toString());
    }
    expect(true, isTrue);
  });
}

Future<ui.Image> _cover() async {
  final file = File(
      '/Volumes/Untitled/projects/vibe_flow/mesh_flow/example/assets/yugu - No Smile No Life - Cover.jpg');
  return CoverProcessor.processBytes(await file.readAsBytes(), targetSize: 32);
}

Future<Uint8List> _render(ui.Image cover, int idx) async {
  final vertices = WarpGrid.buildVertices(
    width: kW.toDouble(),
    height: kH.toDouble(),
    textureWidth: 32,
    textureHeight: 32,
    presetIndex: idx,
  );
  final m = Float64List(16)
    ..[0] = 1.0
    ..[5] = 1.0
    ..[10] = 1.0
    ..[15] = 1.0;
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawVertices(
    vertices,
    ui.BlendMode.srcOver,
    ui.Paint()
      ..shader = ui.ImageShader(cover, ui.TileMode.mirror, ui.TileMode.mirror, m,
          filterQuality: ui.FilterQuality.medium),
  );
  final img = await rec.endRecording().toImage(kW, kH);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

double _jump(Uint8List b, int x, int y) {
  int at(int xx, int ch) => b[((y * kW + xx) * 4) + ch];
  double l = 0, r = 0;
  for (int k = 1; k <= 2; ++k) {
    for (int ch = 0; ch < 3; ++ch) {
      l += at(x - k, ch);
      r += at(x + k - 1, ch);
    }
  }
  return (l - r).abs();
}
