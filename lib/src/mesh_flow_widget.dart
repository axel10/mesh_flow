import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'cover_processor.dart';
import 'mesh_flow_painter.dart';
import 'warp_grid.dart';

/// 流体动态网格背景组件。
///
/// 移植自 QueMusic 播放页背景着色器与网格形变引擎：
/// - 自动将封面处理为 32×32 微型高饱和平滑贴图
/// - 采用 28×28 钉边驻波网格与 tanh 折叠面，四边永不漏空
/// - 支持封面切换时平滑淡入淡出过渡（Cross Fade）
/// - 支持流速调节、暂停/播放与切歌随机地形预设
class MeshFlow extends StatefulWidget {
  const MeshFlow({
    super.key,
    this.image,
    this.uiImage,
    this.coverBytes,
    this.coverKey,
    this.palette,
    this.presetIndex,
    this.speed = 1.0,
    double? flowSpeed,
    this.animating = true,
    double? vignette,
    this.vignetteAlpha = 0.35,
    this.textureSize = CoverProcessor.defaultTargetSize,
    this.saturation = 2.6,
    this.contrast = 1.4,
    this.fallbackColor = const Color(0xFF101014),
    this.crossFadeDuration = const Duration(milliseconds: 700),
    this.child,
  })  : effectiveSpeed = flowSpeed ?? speed,
        effectiveVignette = vignette ?? vignetteAlpha;

  /// 封面图像提供者（支持 [AssetImage], [NetworkImage], [FileImage], [MemoryImage] 等）。
  final ImageProvider? image;

  /// 直接传入已准备好的 [ui.Image]（如果已有解码纹理）。
  final ui.Image? uiImage;

  /// 原始图像字节数据（如 ID3 / 专辑封面字节流）。
  final Uint8List? coverBytes;

  /// 用于标识当前封面的唯一 Key（例如文件路径/URL），改变时触发平滑换曲过渡。
  final Object? coverKey;

  /// 调色盘主色列表（在无封面或图片解码前用作平滑渐变背景）。
  final List<Color>? palette;

  /// 指定地形预设索引（0 ~ 4）。若为 null，则在切歌时随机选取不重复的预设。
  final int? presetIndex;

  /// 流动速度倍率。
  final double speed;

  /// 兼容旧命名的流动速度。
  final double effectiveSpeed;

  /// 是否持续播放流动动画。
  final bool animating;

  /// 暗角强度（0.0 ~ 1.0）。
  final double vignetteAlpha;

  /// 兼容命名的暗角强度。
  final double effectiveVignette;

  /// 降采样微型贴图尺寸（默认 32×32）。
  final int textureSize;

  /// 饱和度增强倍率（默认 2.6）。
  final double saturation;

  /// 对比度增强倍率（默认 1.4）。
  final double contrast;

  /// 纹理未准备好时的背景底色。
  final Color fallbackColor;

  /// 切换封面时的平滑过渡时长。
  final Duration crossFadeDuration;

  /// 放置在背景之上的子组件（如歌词列表、播放控件等）。
  final Widget? child;

  @override
  State<MeshFlow> createState() => _MeshFlowState();
}

/// 兼容别名 [MeshFlowBackground]
typedef MeshFlowBackground = MeshFlow;

class _LayerState {
  _LayerState({
    required this.texture,
    required this.presetIndex,
  });

  final ui.Image texture;
  final int presetIndex;
  ui.Vertices? vertices;
  Size? verticesSize;

  void ensureVertices(Size size) {
    if (vertices == null || verticesSize != size) {
      verticesSize = size;
      vertices = WarpGrid.buildVertices(
        width: size.width,
        height: size.height,
        textureWidth: texture.width.toDouble(),
        textureHeight: texture.height.toDouble(),
        presetIndex: presetIndex,
      );
    }
  }

  void dispose() {
    texture.dispose();
  }
}

class _MeshFlowState extends State<MeshFlow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0.0;
  Duration _lastElapsed = Duration.zero;

  _LayerState? _currentLayer;
  _LayerState? _previousLayer;

  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;

  int _lastPreset = -1;
  int _activeLoadToken = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.animating) {
      _ticker.start();
    }
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant MeshFlow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.animating != oldWidget.animating) {
      if (widget.animating && !_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      } else if (!widget.animating && _ticker.isActive) {
        _ticker.stop();
      }
    }

    final bool coverChanged = widget.coverKey != oldWidget.coverKey ||
        widget.image != oldWidget.image ||
        widget.uiImage != oldWidget.uiImage ||
        !listEquals(widget.coverBytes, oldWidget.coverBytes) ||
        !listEquals(widget.palette, oldWidget.palette) ||
        widget.presetIndex != oldWidget.presetIndex ||
        widget.textureSize != oldWidget.textureSize ||
        widget.saturation != oldWidget.saturation ||
        widget.contrast != oldWidget.contrast;

    if (coverChanged) {
      _loadCover();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }

    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    if (dt > 0.0) {
      setState(() {
        _time += dt * widget.effectiveSpeed;
      });
    }
  }

  int _selectNextPreset() {
    if (widget.presetIndex != null) {
      return widget.presetIndex!.clamp(0, kTerrainPresets.length - 1);
    }
    final int count = kTerrainPresets.length;
    final random = math.Random();
    int next = random.nextInt(count);
    if (next == _lastPreset && count > 1) {
      next = (next + 1 + random.nextInt(count - 1)) % count;
    }
    _lastPreset = next;
    return next;
  }

  Future<void> _loadCover() async {
    final int token = ++_activeLoadToken;

    ui.Image? texture;
    try {
      if (widget.uiImage != null) {
        texture = await CoverProcessor.processUiImage(
          widget.uiImage!,
          targetSize: widget.textureSize,
          saturation: widget.saturation,
          contrast: widget.contrast,
        );
      } else if (widget.coverBytes != null && widget.coverBytes!.isNotEmpty) {
        texture = await CoverProcessor.processBytes(
          widget.coverBytes!,
          targetSize: widget.textureSize,
          saturation: widget.saturation,
          contrast: widget.contrast,
        );
      } else if (widget.image != null) {
        texture = await CoverProcessor.processImageProvider(
          widget.image!,
          targetSize: widget.textureSize,
          saturation: widget.saturation,
          contrast: widget.contrast,
        );
      } else if (widget.palette != null && widget.palette!.isNotEmpty) {
        texture = await CoverProcessor.createPaletteImage(
          widget.palette!,
          targetSize: widget.textureSize,
        );
      } else {
        texture = await CoverProcessor.createFallbackImage(widget.fallbackColor);
      }
    } catch (_) {
      texture = await CoverProcessor.createFallbackImage(widget.fallbackColor);
    }

    if (!mounted || token != _activeLoadToken) {
      texture.dispose();
      return;
    }

    final int nextPreset = _selectNextPreset();
    final newLayer = _LayerState(texture: texture, presetIndex: nextPreset);

    if (_currentLayer == null) {
      setState(() {
        _currentLayer = newLayer;
      });
      return;
    }

    // 开启平滑淡入淡出过渡
    _previousLayer?.dispose();
    _previousLayer = _currentLayer;
    _currentLayer = newLayer;

    _fadeController?.dispose();
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.crossFadeDuration,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController!,
      curve: Curves.easeInOut,
    )..addListener(() {
        if (mounted) setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _previousLayer?.dispose();
          _previousLayer = null;
          _fadeController?.dispose();
          _fadeController = null;
          _fadeAnimation = null;
          if (mounted) setState(() {});
        }
      });

    _fadeController!.forward();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fadeController?.dispose();
    _currentLayer?.dispose();
    _previousLayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        if (size.width > 0 && size.height > 0) {
          _currentLayer?.ensureVertices(size);
          _previousLayer?.ensureVertices(size);
        }

        final double fadeProgress = _fadeAnimation?.value ?? 1.0;

        Widget content = CustomPaint(
          size: Size.infinite,
          painter: _currentLayer == null
              ? null
              : MeshFlowPainter(
                  vertices: _currentLayer!.vertices,
                  texture: _currentLayer!.texture,
                  time: _time,
                  flowSpeed: widget.effectiveSpeed,
                  vignetteAlpha: widget.effectiveVignette,
                  fallbackColor: widget.fallbackColor,
                ),
        );

        if (_previousLayer != null && fadeProgress < 1.0) {
          content = Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: MeshFlowPainter(
                  vertices: _previousLayer!.vertices,
                  texture: _previousLayer!.texture,
                  time: _time,
                  flowSpeed: widget.effectiveSpeed,
                  vignetteAlpha: widget.effectiveVignette,
                  fallbackColor: widget.fallbackColor,
                ),
              ),
              Opacity(
                opacity: fadeProgress,
                child: content,
              ),
            ],
          );
        }

        if (widget.child != null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              content,
              widget.child!,
            ],
          );
        }

        return content;
      },
    );
  }
}
