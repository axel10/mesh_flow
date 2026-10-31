import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 一帧需要绘制的数据快照。
///
/// 由提供的 [MeshFlowPainter.frameBuilder] 在每次 [MeshFlowPainter.paint] 时现算，
/// 这样网格可以只靠 `repaint` 通知逐帧刷新，不必让整个 widget 重建。
class MeshFlowFrame {
  const MeshFlowFrame({
    required this.vertices,
    required this.texture,
    this.previousTexture,
    this.transitionProgress = 1.0,
    required this.time,
    this.vignetteAlpha = 0.35,
    this.fallbackColor = Colors.black,
  });

  final ui.Vertices? vertices;
  final ui.Image? texture;
  final ui.Image? previousTexture;
  final double transitionProgress;

  /// 已按流速缩放的流逝时间。
  final double time;
  final double vignetteAlpha;
  final Color fallbackColor;
}

/// 扭曲网格流体背景绘制器。
///
/// 1. 利用 [ui.ImageShader] 实现 32×32 封面纹理的镜像平铺与极其缓慢的顺时针旋转。
/// 2. 使用 [Canvas.drawVertices] 将非线性驻波网格几何渲染出来，产生有机的流体形变。
/// 3. 在切换图片时，在同一变形网格上进行双纹理色彩平滑混合插值。
/// 4. 叠加径向渐变暗角遮罩，使视觉更柔和、更好衬托前景歌词。
///
/// 两种用法：
/// - 静态：构造时直接给 [vertices] / [texture] 等字段；
/// - 动态：给 [frameBuilder] + [repaint]，绘制时现取数据，widget 不必每帧重建。
class MeshFlowPainter extends CustomPainter {
  MeshFlowPainter({
    this.vertices,
    this.texture,
    this.previousTexture,
    this.transitionProgress = 1.0,
    this.time = 0.0,
    this.vignetteAlpha = 0.35,
    this.fallbackColor = Colors.black,
    this.frameBuilder,
    super.repaint,
  }) : assert(
          frameBuilder != null || vertices != null,
          '要么给 vertices，要么给 frameBuilder',
        );

  /// 贴图基础自转角速度（弧度/秒·单位流速）。
  ///
  /// [time] 已经按流速缩放，这里不能再乘一次，否则流速会被平方级压低。
  static const double kTextureSpinRate = 0.24;

  final ui.Vertices? vertices;
  final ui.Image? texture;
  final ui.Image? previousTexture;
  final double transitionProgress;

  /// 已按流速缩放的流逝时间。
  final double time;
  final double vignetteAlpha;
  final Color fallbackColor;

  /// 动态帧数据来源。非空时每次绘制都会调用它取最新的顶点与纹理。
  final MeshFlowFrame Function(Size size)? frameBuilder;

  MeshFlowFrame _resolve(Size size) {
    final builder = frameBuilder;
    if (builder != null) return builder(size);
    return MeshFlowFrame(
      vertices: vertices,
      texture: texture,
      previousTexture: previousTexture,
      transitionProgress: transitionProgress,
      time: time,
      vignetteAlpha: vignetteAlpha,
      fallbackColor: fallbackColor,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final frame = _resolve(size);
    final vertices = frame.vertices;
    final texture = frame.texture;
    final previousTexture = frame.previousTexture;
    final transitionProgress = frame.transitionProgress;
    final time = frame.time;
    final vignetteAlpha = frame.vignetteAlpha;
    final fallbackColor = frame.fallbackColor;

    final rect = Offset.zero & size;

    if (texture == null || vertices == null) {
      canvas.drawRect(rect, Paint()..color = fallbackColor);
      return;
    }

    // 1. 纹理旋转矩阵
    // 复刻 QueMusic: vec2 c = vUV - vec2(0.35); const float ang = -u_time * 0.24;
    final double ang = -time * kTextureSpinRate;
    final double texW = texture.width.toDouble();
    final double texH = texture.height.toDouble();

    final cosA = math.cos(ang);
    final sinA = math.sin(ang);

    // 旋转中心在 (0.35, 0.35)，输出偏移到 (0.5, 0.5)
    final double inCx = 0.35 * texW;
    final double inCy = 0.35 * texH;
    final double outCx = 0.50 * texW;
    final double outCy = 0.50 * texH;

    final matrix = Float64List(16);
    matrix[0] = cosA;
    matrix[1] = sinA;
    matrix[4] = -sinA;
    matrix[5] = cosA;
    matrix[10] = 1.0;
    matrix[12] = -inCx * cosA + inCy * sinA + outCx;
    matrix[13] = -inCx * sinA - inCy * cosA + outCy;
    matrix[15] = 1.0;

    // 2. 绘制扭曲网格
    if (previousTexture != null && transitionProgress < 1.0) {
      // 过渡状态：在同一个变形网格上，双纹理在 GPU 端进行色彩平滑混合
      final prevShader = ui.ImageShader(
        previousTexture,
        ui.TileMode.mirror,
        ui.TileMode.mirror,
        matrix,
        filterQuality: ui.FilterQuality.medium,
      );
      final prevPaint = Paint()
        ..shader = prevShader
        ..filterQuality = ui.FilterQuality.medium;
      canvas.drawVertices(vertices, BlendMode.srcOver, prevPaint);

      final nextShader = ui.ImageShader(
        texture,
        ui.TileMode.mirror,
        ui.TileMode.mirror,
        matrix,
        filterQuality: ui.FilterQuality.medium,
      );
      final nextPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, transitionProgress.clamp(0.0, 1.0))
        ..shader = nextShader
        ..filterQuality = ui.FilterQuality.medium;
      canvas.drawVertices(vertices, BlendMode.srcOver, nextPaint);
    } else {
      // 稳定状态：直接绘制当前纹理
      final shader = ui.ImageShader(
        texture,
        ui.TileMode.mirror,
        ui.TileMode.mirror,
        matrix,
        filterQuality: ui.FilterQuality.medium,
      );
      final meshPaint = Paint()
        ..shader = shader
        ..filterQuality = ui.FilterQuality.medium;
      canvas.drawVertices(vertices, BlendMode.srcOver, meshPaint);
    }

    // 3. 暗角（Vignette）
    if (vignetteAlpha > 0.0) {
      final center = Offset(size.width * 0.5, size.height * 0.5);
      final radius = math.max(size.width, size.height) * 0.707;

      final vignetteShader = ui.Gradient.radial(
        center,
        radius,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: vignetteAlpha),
        ],
        const [0.25, 0.95],
      );

      canvas.drawRect(
        rect,
        Paint()
          ..shader = vignetteShader
          ..blendMode = BlendMode.darken,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MeshFlowPainter oldDelegate) {
    // 动态模式下数据是现取的，widget 一旦重建就说明外部配置可能变了，直接重绘。
    if (frameBuilder != null || oldDelegate.frameBuilder != null) {
      return true;
    }
    return oldDelegate.vertices != vertices ||
        oldDelegate.texture != texture ||
        oldDelegate.previousTexture != previousTexture ||
        oldDelegate.transitionProgress != transitionProgress ||
        oldDelegate.time != time ||
        oldDelegate.vignetteAlpha != vignetteAlpha ||
        oldDelegate.fallbackColor != fallbackColor;
  }
}
