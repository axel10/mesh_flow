import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// 封面图像微型低清纹理预处理器。
///
/// 复刻 QueMusic C++ 的 `decodeCover` 与 `boxBlur`：
/// 1. 降采样至 32×32 微型贴图
/// 2. 透明边框填充均值色（避免圆角封面产生黑边）
/// 3. 色彩非线性拉伸（压缩边缘向均值收敛 + 饱和度放大 + 对比度放大）
/// 4. 4 轮可分离盒式模糊（Box Blur）
class CoverProcessor {
  static const int defaultTargetSize = 32;

  /// 从编码的图像字节流（JPEG/PNG/WebP 等）异步处理为平滑流体纹理。
  static Future<ui.Image> processBytes(
    Uint8List bytes, {
    int targetSize = defaultTargetSize,
    double saturation = 2.6,
    double contrast = 1.4,
  }) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetSize,
      targetHeight: targetSize,
    );
    try {
      final frame = await codec.getNextFrame();
      final rawImg = frame.image;
      try {
        return await processUiImage(
          rawImg,
          targetSize: targetSize,
          saturation: saturation,
          contrast: contrast,
        );
      } finally {
        // 解码出来的原始帧只在本函数内使用，必须显式释放，
        // 否则每换一首歌都会留一张 GPU 纹理等 GC。
        rawImg.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// 从 [ui.Image]（任意尺寸）处理为平滑流体纹理。
  ///
  /// [image] 的所有权仍归调用方，本方法不会释放它。
  static Future<ui.Image> processUiImage(
    ui.Image image, {
    int targetSize = defaultTargetSize,
    double saturation = 2.6,
    double contrast = 1.4,
  }) async {
    ui.Image imgScaled = image;
    bool ownsScaled = false;
    if (image.width != targetSize || image.height != targetSize) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetSize.toDouble(), targetSize.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      imgScaled = await picture.toImage(targetSize, targetSize);
      picture.dispose();
      ownsScaled = true;
    }

    try {
      final byteData = await imgScaled.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        // 读不回来就退化为原图，所有权转交给调用方
        ownsScaled = false;
        return imgScaled;
      }

      final Uint8List pixels = Uint8List.fromList(byteData.buffer.asUint8List());
      _applyColorTuningAndBlur(
        pixels,
        targetSize,
        targetSize,
        saturation: saturation,
        contrast: contrast,
      );

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        targetSize,
        targetSize,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return completer.future;
    } finally {
      if (ownsScaled) {
        imgScaled.dispose();
      }
    }
  }

  /// 从 Flutter 的 [ImageProvider] 异步解析并处理封面。
  static Future<ui.Image> processImageProvider(
    ImageProvider provider, {
    ImageConfiguration configuration = ImageConfiguration.empty,
    int targetSize = defaultTargetSize,
    double saturation = 2.6,
    double contrast = 1.4,
  }) async {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(configuration);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) async {
        stream.removeListener(listener);
        try {
          final processed = await processUiImage(
            info.image,
            targetSize: targetSize,
            saturation: saturation,
            contrast: contrast,
          );
          completer.complete(processed);
        } catch (e, st) {
          completer.completeError(e, st);
        }
      },
      onError: (dynamic error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// 根据主题调色盘 [palette] 生成平滑渐变低清贴图。
  static Future<ui.Image> createPaletteImage(
    List<ui.Color> palette, {
    int targetSize = defaultTargetSize,
  }) async {
    if (palette.isEmpty) {
      return createFallbackImage(const ui.Color(0xFF101014), size: targetSize);
    }
    if (palette.length == 1) {
      return createFallbackImage(palette.first, size: targetSize);
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final rect = ui.Rect.fromLTWH(0, 0, targetSize.toDouble(), targetSize.toDouble());

    final gradient = ui.Gradient.linear(
      rect.topLeft,
      rect.bottomRight,
      palette,
      List.generate(palette.length, (i) => i / (palette.length - 1)),
    );

    canvas.drawRect(rect, ui.Paint()..shader = gradient);
    final picture = recorder.endRecording();
    final img = await picture.toImage(targetSize, targetSize);
    picture.dispose();
    try {
      return await processUiImage(img, targetSize: targetSize);
    } finally {
      img.dispose();
    }
  }

  /// 生成单色降级微型纹理（用于无封面时的备选）。
  static Future<ui.Image> createFallbackImage(
    ui.Color color, {
    int size = 4,
  }) async {
    final pixels = Uint8List(size * size * 4);
    for (int i = 0; i < size * size; ++i) {
      pixels[i * 4 + 0] = (color.r * 255.0).round().clamp(0, 255);
      pixels[i * 4 + 1] = (color.g * 255.0).round().clamp(0, 255);
      pixels[i * 4 + 2] = (color.b * 255.0).round().clamp(0, 255);
      pixels[i * 4 + 3] = (color.a * 255.0).round().clamp(0, 255);
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static void _applyColorTuningAndBlur(
    Uint8List pixels,
    int w,
    int h, {
    required double saturation,
    required double contrast,
  }) {
    // 1. 均值色合成：若有透明/半透明像素，合成到全图均值色，避免产生黑边
    double sr = 0, sg = 0, sb = 0, sw = 0;
    int minA = 255;
    for (int i = 0; i < w * h; ++i) {
      final int offset = i * 4;
      final int a = pixels[offset + 3];
      if (a < minA) minA = a;
      final double alpha = a / 255.0;
      sr += pixels[offset + 0] * alpha;
      sg += pixels[offset + 1] * alpha;
      sb += pixels[offset + 2] * alpha;
      sw += alpha;
    }

    if (minA < 255) {
      final double mr = sw > 0 ? sr / sw : 0.0;
      final double mg = sw > 0 ? sg / sw : 0.0;
      final double mb = sw > 0 ? sb / sw : 0.0;
      for (int i = 0; i < w * h; ++i) {
        final int offset = i * 4;
        final double a = pixels[offset + 3] / 255.0;
        pixels[offset + 0] = (mr + (pixels[offset + 0] - mr) * a).round().clamp(0, 255);
        pixels[offset + 1] = (mg + (pixels[offset + 1] - mg) * a).round().clamp(0, 255);
        pixels[offset + 2] = (mb + (pixels[offset + 2] - mb) * a).round().clamp(0, 255);
        pixels[offset + 3] = 255;
      }
    }

    // 2. 颜色非线性拉伸（先压缩对比度向均值收敛，再放大饱和度与对比度）
    const double kPreContrast = 0.5;
    const double kBright = 0.8;

    for (int i = 0; i < w * h; ++i) {
      final int offset = i * 4;
      double r = pixels[offset + 0].toDouble();
      double g = pixels[offset + 1].toDouble();
      double b = pixels[offset + 2].toDouble();

      r = (r - 128.0) * kPreContrast + 128.0;
      g = (g - 128.0) * kPreContrast + 128.0;
      b = (b - 128.0) * kPreContrast + 128.0;

      final double gray = r * 0.3 + g * 0.59 + b * 0.11;
      r = gray + (r - gray) * saturation;
      g = gray + (g - gray) * saturation;
      b = gray + (b - gray) * saturation;

      r = (r - 128.0) * contrast + 128.0;
      g = (g - 128.0) * contrast + 128.0;
      b = (b - 128.0) * contrast + 128.0;

      r *= kBright;
      g *= kBright;
      b *= kBright;

      pixels[offset + 0] = (r + 0.5).round().clamp(0, 255);
      pixels[offset + 1] = (g + 0.5).round().clamp(0, 255);
      pixels[offset + 2] = (b + 0.5).round().clamp(0, 255);
      pixels[offset + 3] = 255;
    }

    // 3. 可分离盒式模糊（4 轮，半径 2）
    _boxBlur(pixels, w, h, radius: 2, iterations: 4);
  }

  static void _boxBlur(Uint8List pixels, int w, int h, {required int radius, required int iterations}) {
    final int cnt = radius * 2 + 1;
    final buffer = Uint8List(w * h * 4);

    for (int it = 0; it < iterations; ++it) {
      // 水平通道
      for (int y = 0; y < h; ++y) {
        final int rowStart = y * w * 4;
        for (int x = 0; x < w; ++x) {
          int r = 0, g = 0, b = 0;
          for (int k = -radius; k <= radius; ++k) {
            final int xx = (x + k).clamp(0, w - 1);
            final int p = rowStart + xx * 4;
            r += pixels[p + 0];
            g += pixels[p + 1];
            b += pixels[p + 2];
          }
          final int o = rowStart + x * 4;
          buffer[o + 0] = r ~/ cnt;
          buffer[o + 1] = g ~/ cnt;
          buffer[o + 2] = b ~/ cnt;
          buffer[o + 3] = 255;
        }
      }

      // 垂直通道
      for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
          int r = 0, g = 0, b = 0;
          for (int k = -radius; k <= radius; ++k) {
            final int yy = (y + k).clamp(0, h - 1);
            final int p = (yy * w + x) * 4;
            r += buffer[p + 0];
            g += buffer[p + 1];
            b += buffer[p + 2];
          }
          final int o = (y * w + x) * 4;
          pixels[o + 0] = r ~/ cnt;
          pixels[o + 1] = g ~/ cnt;
          pixels[o + 2] = b ~/ cnt;
          pixels[o + 3] = 255;
        }
      }
    }
  }
}
