import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    final morphed = WarpGrid.buildMorphedVertices(
      width: 400,
      height: 800,
      textureWidth: 32,
      textureHeight: 32,
      fromPresetIndex: 0,
      toPresetIndex: 1,
      progress: 0.5,
    );
    expect(morphed, isNotNull);
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

  testWidgets('MeshFlow handles rapid continuous palette switching smoothly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshFlow(
            animating: false,
            palette: [Colors.red, Colors.orange],
            crossFadeDuration: Duration(milliseconds: 1000),
            fastCrossFadeDuration: Duration(milliseconds: 300),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Fast switch 1: red -> blue
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshFlow(
            animating: false,
            palette: [Colors.blue, Colors.cyan],
            crossFadeDuration: Duration(milliseconds: 1000),
            fastCrossFadeDuration: Duration(milliseconds: 300),
          ),
        ),
      ),
    );
    // Partially advance transition (e.g. 50ms into transition)
    await tester.pump(const Duration(milliseconds: 50));

    // Fast switch 2: interrupt before complete -> green
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshFlow(
            animating: false,
            palette: [Colors.green, Colors.lime],
            crossFadeDuration: Duration(milliseconds: 1000),
            fastCrossFadeDuration: Duration(milliseconds: 300),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Fast switch 3: interrupt again -> purple
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshFlow(
            animating: false,
            palette: [Colors.purple, Colors.deepPurple],
            crossFadeDuration: Duration(milliseconds: 1000),
            fastCrossFadeDuration: Duration(milliseconds: 300),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Fast switch 4: interrupt again -> yellow
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshFlow(
            animating: false,
            palette: [Colors.yellow, Colors.amber],
            crossFadeDuration: Duration(milliseconds: 1000),
            fastCrossFadeDuration: Duration(milliseconds: 300),
          ),
        ),
      ),
    );

    // Let it settle smoothly to the final color
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('地形预设池保持「硬边多于柔和」的配比', () {
    final int hardCount = kTerrainPresets.where((p) => p.hardEdge).length;
    final int softCount = kTerrainPresets.length - hardCount;

    // 按需求硬边组偏多（11 : 7），但不能一边倒——随机切歌仍要抽到柔和地形。
    expect(
      hardCount,
      greaterThan(softCount),
      reason: '硬边 $hardCount 组 / 柔和 $softCount 组，应为硬边偏多',
    );
    expect(
      softCount,
      greaterThanOrEqualTo(5),
      reason: '柔和只剩 $softCount 组，每几首就会连着「裂」',
    );

    for (final preset in kTerrainPresets) {
      expect(preset.p.length, 6);
      expect(preset.r.length, 12);
    }
  });

  test('WarpGrid buildMorphedVerticesBetweenPresets smoothly handles custom interpolated presets', () {
    const presetA = TerrainPreset(
      p: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
      r: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 0.5, 0.2],
    );
    const presetB = TerrainPreset(
      p: [2.0, 3.0, 4.0, 5.0, 0.5, 1.5],
      r: [-0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7, -0.8, -0.9, -1.0, -0.5, -0.2],
    );

    final vertices0 = WarpGrid.buildMorphedVerticesBetweenPresets(
      width: 300,
      height: 600,
      fromPreset: presetA,
      toPreset: presetB,
      progress: 0.0,
    );
    expect(vertices0, isNotNull);

    final verticesMid = WarpGrid.buildMorphedVerticesBetweenPresets(
      width: 300,
      height: 600,
      fromPreset: presetA,
      toPreset: presetB,
      progress: 0.5,
    );
    expect(verticesMid, isNotNull);

    final vertices1 = WarpGrid.buildMorphedVerticesBetweenPresets(
      width: 300,
      height: 600,
      fromPreset: presetA,
      toPreset: presetB,
      progress: 1.0,
    );
    expect(vertices1, isNotNull);
  });

  testWidgets('MeshFlow supports edgeStyle and initializes without errors', (tester) async {
    for (final style in MeshFlowEdgeStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeshFlow(
              edgeStyle: style,
              animating: false,
              palette: const [Colors.blue, Colors.purple],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(MeshFlow), findsOneWidget);
    }
  });

  test('WarpGrid.selectPresetIndex adapts to screen orientation', () {
    const landscapeSize = Size(1600, 900);
    const portraitSize = Size(400, 800);

    // 1. 横屏下彻底避开 portraitOnly 预设
    for (int i = 0; i < 500; i++) {
      final idx = WarpGrid.selectPresetIndex(
        size: landscapeSize,
        edgeStyle: MeshFlowEdgeStyle.sharp,
        adaptiveTerrain: true,
      );
      final preset = kTerrainPresets[idx];
      expect(
        preset.suitability,
        isNot(TerrainSuitability.portraitOnly),
        reason: '横屏下不应抽到 portraitOnly 地形 (#$idx)',
      );
    }

    // 2. 竖屏下增加 portraitOnly 与 portraitPreferred 的出现概率
    int portraitOptimizedHits = 0;
    const int trials = 1000;
    for (int i = 0; i < trials; i++) {
      final idx = WarpGrid.selectPresetIndex(
        size: portraitSize,
        edgeStyle: MeshFlowEdgeStyle.sharp,
        adaptiveTerrain: true,
      );
      final preset = kTerrainPresets[idx];
      if (preset.suitability == TerrainSuitability.portraitOnly ||
          preset.suitability == TerrainSuitability.portraitPreferred) {
        portraitOptimizedHits++;
      }
    }
    // 理论权重占比为 32/40 = 80%，实际采样应显著大于 65%
    expect(portraitOptimizedHits / trials, greaterThan(0.65));

    // 3. 关闭自适应时（adaptiveTerrain: false），横屏亦可正常抽中 portraitOnly
    int portraitOnlyHitsWithoutAdaptive = 0;
    for (int i = 0; i < trials; i++) {
      final idx = WarpGrid.selectPresetIndex(
        size: landscapeSize,
        edgeStyle: MeshFlowEdgeStyle.sharp,
        adaptiveTerrain: false,
      );
      if (kTerrainPresets[idx].suitability == TerrainSuitability.portraitOnly) {
        portraitOnlyHitsWithoutAdaptive++;
      }
    }
    expect(portraitOnlyHitsWithoutAdaptive, greaterThan(0));
  });

  testWidgets('MeshFlow supports custom presetSelector and adaptiveTerrain parameter', (tester) async {
    MeshFlowTerrainContext? capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 400,
              child: MeshFlow(
                animating: false,
                palette: const [Colors.teal, Colors.cyan],
                presetSelector: (context) {
                  capturedContext = context;
                  return 3;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));
    expect(capturedContext, isNotNull);
    expect(capturedContext!.aspectRatio, closeTo(2.0, 0.05));
    expect(find.byType(MeshFlow), findsOneWidget);
  });

  testWidgets('网格动画确实逐帧上屏（repaint 驱动而非 setState）', (tester) async {
    // 防止有人把逐帧重绘改回 setState 或者漏接 CustomPainter.repaint：
    // 那样画面会停在第一帧，这个断言会挂掉。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            child: MeshFlow(presetIndex: 22, child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final before = await _capture(tester);

    for (int i = 0; i < 20; ++i) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final after = await _capture(tester);

    int changed = 0;
    for (int i = 0; i < before.length; ++i) {
      if (before[i] != after[i]) changed++;
    }
    expect(changed, greaterThan(before.length ~/ 10), reason: '画面在 320ms 内几乎没变');
  });
}

/// 截取当前画面的原始像素。
Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  return bytes;
}
