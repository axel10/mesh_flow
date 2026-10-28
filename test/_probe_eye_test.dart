import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

/// 直接用渲染图量「眼睛看到的硬边在哪」：
/// 每行取横向相邻像素色差最大的位置（并对 3 像素做平滑，避免单像素噪声），
/// 统计这些位置的分位数。比雅可比更贴近观感——它不受贴图内容影响。
const int kW = 240;
const int kH = 400;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('渲染图上的硬边落点', () async {
    final cover = await _cover();
    final buf = StringBuffer()
      ..writeln('idx  p10    中位   p90    贴边行(>0.93)  左端(<0.15)');

    for (int idx = 14; idx < kTerrainPresets.length; ++idx) {
      final xs = await _edgeX(cover, idx);
      if (xs.isEmpty) {
        buf.writeln('#$idx 无硬边');
        continue;
      }
      xs.sort();
      final p10 = xs[(xs.length * 0.1).floor()];
      final med = xs[xs.length ~/ 2];
      final p90 = xs[(xs.length * 0.9).floor().clamp(0, xs.length - 1)];
      final border = xs.where((e) => e > 0.93).length / xs.length;
      final left = xs.where((e) => e < 0.15).length / xs.length;
      buf.writeln('#$idx  ${p10.toStringAsFixed(2)}   ${med.toStringAsFixed(2)}   '
          '${p90.toStringAsFixed(2)}   ${(border * 100).toStringAsFixed(0)}%'
          '            ${(left * 100).toStringAsFixed(0)}%');
    }
    // ignore: avoid_print
    print(buf.toString());
    expect(true, isTrue);
  });
}

/// 返回每行「最锐利横向跳变」的归一化位置 u。
Future<List<double>> _edgeX(ui.Image cover, int presetIndex) async {
  final vertices = WarpGrid.buildVertices(
    width: kW.toDouble(),
    height: kH.toDouble(),
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
        cover,
        ui.TileMode.mirror,
        ui.TileMode.mirror,
        matrix,
        filterQuality: ui.FilterQuality.medium,
      ),
  );
  final img = await recorder.endRecording().toImage(kW, kH);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  img.dispose();

  int at(int x, int y, int ch) => bytes[((y * kW + x) * 4) + ch];

  final out = <double>[];
  for (int y = 4; y < kH - 4; ++y) {
    double best = 0;
    int bestX = -1;
    for (int x = 6; x < kW - 6; ++x) {
      // 两侧各取 2 像素均值，抑制单像素噪点
      double l = 0, r = 0;
      for (int k = 1; k <= 2; ++k) {
        for (int ch = 0; ch < 3; ++ch) {
          l += at(x - k, y, ch);
          r += at(x + k - 1, y, ch);
        }
      }
      final double d = (l - r).abs();
      if (d > best) {
        best = d;
        bestX = x;
      }
    }
    // 只收「真的够跳」的行，避免纯渐变行给噪声位置
    if (bestX > 0 && best > 24) out.add(bestX / kW);
  }
  return out;
}

Future<ui.Image> _cover() async {
  final file = File(
      '/Volumes/Untitled/projects/vibe_flow/mesh_flow/example/assets/yugu - No Smile No Life - Cover.jpg');
  return CoverProcessor.processBytes(await file.readAsBytes(), targetSize: 32);
}
