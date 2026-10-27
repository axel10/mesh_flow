import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

void main() {
  test('WarpGrid generates valid vertices and indices for all presets', () {
    for (int i = 0; i < kTerrainPresets.length; ++i) {
      final vertices = WarpGrid.buildVertices(
        width: 400,
        height: 800,
        textureWidth: 32,
        textureHeight: 32,
        presetIndex: i,
      );
      expect(vertices, isNotNull);
    }
  });

  test('CoverProcessor generates fallback and draws with drawVertices', () async {
    final image = await CoverProcessor.createFallbackImage(const ui.Color(0xFF2196F3));
    expect(image.width, 4);
    expect(image.height, 4);

    final vertices = WarpGrid.buildVertices(
      width: 400,
      height: 800,
      textureWidth: image.width.toDouble(),
      textureHeight: image.height.toDouble(),
      presetIndex: 0,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final matrix4 = Float64List(16);
    matrix4[0] = 1.0;
    matrix4[5] = 1.0;
    matrix4[10] = 1.0;
    matrix4[15] = 1.0;

    final shader = ui.ImageShader(
      image,
      ui.TileMode.mirror,
      ui.TileMode.mirror,
      matrix4,
      filterQuality: ui.FilterQuality.medium,
    );

    final paint = ui.Paint()..shader = shader;
    canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);

    final picture = recorder.endRecording();
    final output = await picture.toImage(400, 800);
    expect(output.width, 400);
    expect(output.height, 800);
  });

  testWidgets('MeshFlow widget mounts and renders without errors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshFlow(
            fallbackColor: Colors.blueGrey,
            child: Center(child: Text('Playing Music')),
          ),
        ),
      ),
    );

    expect(find.text('Playing Music'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
