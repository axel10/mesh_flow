import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'cover_processor.dart';
import 'mesh_flow_painter.dart';
import 'warp_grid.dart';

/// 提供给自定义地形预设选择器 [MeshFlowPresetSelector] 的环境信息。
class MeshFlowTerrainContext {
  const MeshFlowTerrainContext({
    required this.size,
    required this.aspectRatio,
    required this.lastPresetIndex,
    required this.edgeStyle,
    required this.presets,
  });

  /// 容器或屏幕尺寸。
  final Size size;

  /// 宽高比（width / height）。
  final double aspectRatio;

  /// 上一次播放或过渡的地形预设索引。
  final int lastPresetIndex;

  /// 当前组件配置的边缘风格。
  final MeshFlowEdgeStyle edgeStyle;

  /// 全局地形预设列表。
  final List<TerrainPreset> presets;
}

/// 自定义地形预设选择器回调函数。
typedef MeshFlowPresetSelector = int Function(MeshFlowTerrainContext context);

/// 流体动态网格背景组件。
///
/// 移植自 QueMusic 播放页背景着色器与网格形变引擎：
/// - 自动将封面处理为 32×32 微型高饱和平滑贴图
/// - 采用 28×28 钉边驻波网格与 tanh 折叠面，四边永不漏空
/// - 切换封面时，网格地形与双纹理色彩在 GPU 端实现平滑形变插值（Morphing & Blend）
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
    this.edgeStyle = MeshFlowEdgeStyle.random,
    this.adaptiveTerrain = true,
    this.presetSelector,
    this.speed = 1.0,
    double? flowSpeed,
    this.animating = true,
    double? vignette,
    this.vignetteAlpha = 0.35,
    this.textureSize = CoverProcessor.defaultTargetSize,
    this.saturation = 2.6,
    this.contrast = 1.4,
    this.fallbackColor = const Color(0xFF101014),
    this.crossFadeDuration = const Duration(milliseconds: 1200),
    this.fastCrossFadeDuration,
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

  /// 指定地形预设索引（0 ~ [kTerrainPresets].length - 1）。若为 null，则根据 [edgeStyle] 随机选取。
  final int? presetIndex;

  /// 地形分界边缘风格（随机交替 / 柔和弥散 / 棱角光刃）。
  final MeshFlowEdgeStyle edgeStyle;

  /// 是否根据屏幕/容器尺寸自适应选择地形预设（默认 true）。
  ///
  /// - 横屏时自动避开 [TerrainSuitability.portraitOnly] 等会被封面遮挡的竖屏专用硬边；
  /// - 竖屏时大幅提升针对移动端下半幅控件区优化的硬边抽取概率。
  final bool adaptiveTerrain;

  /// 自定义地形预设选择器回调。
  ///
  /// 若提供此项，在 [presetIndex] 为空时的地形选取将交由调用方全权接管。
  final MeshFlowPresetSelector? presetSelector;

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

  /// 切换封面时的色彩与网格平滑过渡动画时长（默认 1200ms）。
  final Duration crossFadeDuration;

  /// 快速连续切换封面时的平滑过渡动画时长（默认自适应为约 450ms）。
  ///
  /// 当在上一次过渡尚未完成便再次切换封面时（例如快速连点切歌），自动启用此快速过渡时长，
  /// 兼顾平滑无跳变的色彩混合与跟手响应性，避免背景颜色大幅跳变或迟滞。
  final Duration? fastCrossFadeDuration;

  /// 放置在背景之上的子组件（如歌词列表、播放控件等）。
  final Widget? child;

  @override
  State<MeshFlow> createState() => _MeshFlowState();
}

/// 兼容别名 [MeshFlowBackground]
typedef MeshFlowBackground = MeshFlow;

class _MeshFlowState extends State<MeshFlow> with TickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0.0;
  Duration _lastElapsed = Duration.zero;

  ui.Image? _currentTexture;
  ui.Image? _previousTexture;

  late TerrainPreset _fromTerrain;
  late TerrainPreset _toTerrain;
  int _lastPreset = -1;
  int _activeLoadToken = 0;

  ui.Vertices? _cachedVertices;
  Size? _lastSize;
  double _lastVerticesProgress = 1.0;
  double _lastVerticesTime = 0.0;

  late final AnimationController _fadeController;
  late final CurvedAnimation _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.animating) {
      _ticker.start();
    }

    final initialPresetIdx = _selectNextPreset();
    _lastPreset = initialPresetIdx;
    _fromTerrain = kTerrainPresets[initialPresetIdx];
    _toTerrain = kTerrainPresets[initialPresetIdx];

    _fadeController = AnimationController(
      vsync: this,
      duration: widget.crossFadeDuration,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOutCubic,
    )..addListener(() {
        if (mounted) setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _previousTexture?.dispose();
          _previousTexture = null;
          _fromTerrain = _toTerrain;
          if (mounted) setState(() {});
        }
      });

    _isInitialized = true;
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

    if (widget.crossFadeDuration != oldWidget.crossFadeDuration) {
      if (!_fadeController.isAnimating) {
        _fadeController.duration = widget.crossFadeDuration;
      }
    }

    final bool edgeStyleChanged = widget.edgeStyle != oldWidget.edgeStyle;
    final bool adaptiveChanged = widget.adaptiveTerrain != oldWidget.adaptiveTerrain ||
        widget.presetSelector != oldWidget.presetSelector;

    final bool coverChanged = widget.coverKey != oldWidget.coverKey ||
        widget.image != oldWidget.image ||
        widget.uiImage != oldWidget.uiImage ||
        !listEquals(widget.coverBytes, oldWidget.coverBytes) ||
        !listEquals(widget.palette, oldWidget.palette) ||
        widget.presetIndex != oldWidget.presetIndex ||
        edgeStyleChanged ||
        adaptiveChanged ||
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

  bool _isInitialized = false;
  Size? _currentSize;

  Size? get _effectiveSize {
    if (_currentSize != null && _currentSize!.width > 0 && _currentSize!.height > 0) {
      return _currentSize;
    }
    if (_isInitialized && mounted) {
      return MediaQuery.maybeSizeOf(context);
    }
    return null;
  }

  int _selectNextPreset({Size? size}) {
    if (widget.presetIndex != null) {
      return widget.presetIndex!.clamp(0, kTerrainPresets.length - 1);
    }

    final effSize = size ?? _effectiveSize ?? const Size(400, 800);
    final double ratio = effSize.height > 0 ? effSize.width / effSize.height : 1.0;

    if (widget.presetSelector != null) {
      final customIdx = widget.presetSelector!(
        MeshFlowTerrainContext(
          size: effSize,
          aspectRatio: ratio,
          lastPresetIndex: _lastPreset,
          edgeStyle: widget.edgeStyle,
          presets: kTerrainPresets,
        ),
      );
      final safeIdx = customIdx.clamp(0, kTerrainPresets.length - 1);
      _lastPreset = safeIdx;
      return safeIdx;
    }

    final next = WarpGrid.selectPresetIndex(
      size: effSize,
      aspectRatio: ratio,
      edgeStyle: widget.edgeStyle,
      adaptiveTerrain: widget.adaptiveTerrain,
      lastPresetIndex: _lastPreset,
    );
    _lastPreset = next;
    return next;
  }

  /// 将当前屏幕上正在混合的双纹理状态合成为单张微型纹理，作为下一次过渡的无缝起始纹理。
  ui.Image _captureCurrentBlendedTexture(int size) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());

    if (_previousTexture != null) {
      final prevSrc = Rect.fromLTWH(
        0,
        0,
        _previousTexture!.width.toDouble(),
        _previousTexture!.height.toDouble(),
      );
      canvas.drawImageRect(
        _previousTexture!,
        prevSrc,
        rect,
        Paint()..filterQuality = ui.FilterQuality.medium,
      );
    }

    if (_currentTexture != null) {
      final currSrc = Rect.fromLTWH(
        0,
        0,
        _currentTexture!.width.toDouble(),
        _currentTexture!.height.toDouble(),
      );
      final double alpha = _fadeController.isAnimating
          ? _fadeAnimation.value.clamp(0.0, 1.0)
          : 1.0;
      canvas.drawImageRect(
        _currentTexture!,
        currSrc,
        rect,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, alpha)
          ..filterQuality = ui.FilterQuality.medium,
      );
    }

    final picture = recorder.endRecording();
    return picture.toImageSync(size, size);
  }

  Future<void> _loadCover() async {
    final int token = ++_activeLoadToken;

    ui.Image? newTexture;
    try {
      if (widget.uiImage != null) {
        newTexture = await CoverProcessor.processUiImage(
          widget.uiImage!,
          targetSize: widget.textureSize,
          saturation: widget.saturation,
          contrast: widget.contrast,
        );
      } else if (widget.coverBytes != null && widget.coverBytes!.isNotEmpty) {
        newTexture = await CoverProcessor.processBytes(
          widget.coverBytes!,
          targetSize: widget.textureSize,
          saturation: widget.saturation,
          contrast: widget.contrast,
        );
      } else if (widget.image != null) {
        newTexture = await CoverProcessor.processImageProvider(
          widget.image!,
          targetSize: widget.textureSize,
          saturation: widget.saturation,
          contrast: widget.contrast,
        );
      } else if (widget.palette != null && widget.palette!.isNotEmpty) {
        newTexture = await CoverProcessor.createPaletteImage(
          widget.palette!,
          targetSize: widget.textureSize,
        );
      } else {
        newTexture = await CoverProcessor.createFallbackImage(widget.fallbackColor);
      }
    } catch (_) {
      newTexture = await CoverProcessor.createFallbackImage(widget.fallbackColor);
    }

    if (!mounted || token != _activeLoadToken) {
      newTexture.dispose();
      return;
    }

    final int nextPreset = _selectNextPreset(size: _effectiveSize);

    if (_currentTexture == null) {
      // 首次加载完成：直接上屏
      setState(() {
        _currentTexture = newTexture;
        _toTerrain = kTerrainPresets[nextPreset];
        _fromTerrain = _toTerrain;
        _cachedVertices = null;
      });
      return;
    }

    final bool isRapidSwitch = _fadeController.isAnimating;

    if (isRapidSwitch && _previousTexture != null && _currentTexture != null) {
      final double progress = _fadeAnimation.value;
      if (progress < 0.999) {
        // 快速连续切换：捕获当前屏幕已渲染的双纹理融合结果，作为新过渡的底图，避免色彩剧烈跳变
        final blended = _captureCurrentBlendedTexture(widget.textureSize);
        _previousTexture?.dispose();
        _currentTexture?.dispose();
        _previousTexture = blended;

        // 顶点地形在当前插值形态上连续过渡，避免网格几何突变拉扯
        final currentP = List<double>.generate(
          _fromTerrain.p.length,
          (i) => _fromTerrain.p[i] + (_toTerrain.p[i] - _fromTerrain.p[i]) * progress,
        );
        final currentR = List<double>.generate(
          _fromTerrain.r.length,
          (i) => _fromTerrain.r[i] + (_toTerrain.r[i] - _fromTerrain.r[i]) * progress,
        );
        _fromTerrain = TerrainPreset(p: currentP, r: currentR);
      } else {
        _previousTexture?.dispose();
        _previousTexture = _currentTexture;
        _fromTerrain = _toTerrain;
      }
    } else {
      _previousTexture?.dispose();
      _previousTexture = _currentTexture;
      _fromTerrain = _toTerrain;
    }

    _currentTexture = newTexture;
    _toTerrain = kTerrainPresets[nextPreset];
    _cachedVertices = null;

    final Duration duration = isRapidSwitch
        ? (widget.fastCrossFadeDuration ??
            Duration(
              milliseconds: (widget.crossFadeDuration.inMilliseconds * 0.38)
                  .round()
                  .clamp(300, 600),
            ))
        : widget.crossFadeDuration;

    _fadeAnimation.curve = isRapidSwitch ? Curves.easeOutCubic : Curves.easeInOutCubic;
    _fadeController.duration = duration;
    _fadeController.forward(from: 0.0);
  }

  /// 网格几何随 [time] 持续流变，因此只要时间在走就需要重建。
  /// 停顿（[MeshFlow.animating] 为 false）时复用缓存，不再空转。
  ui.Vertices _getOrBuildVertices(Size size, double progress) {
    final bool needRebuild = _cachedVertices == null ||
        _lastSize != size ||
        _lastVerticesTime != _time ||
        (_fadeController.isAnimating &&
            (_lastVerticesProgress - progress).abs() > 0.015);

    if (needRebuild) {
      _lastSize = size;
      _lastVerticesProgress = progress;
      _lastVerticesTime = _time;

      final double texW = _currentTexture?.width.toDouble() ?? 32.0;
      final double texH = _currentTexture?.height.toDouble() ?? 32.0;

      if (progress >= 1.0) {
        _cachedVertices = WarpGrid.buildVerticesWithParams(
          width: size.width,
          height: size.height,
          textureWidth: texW,
          textureHeight: texH,
          p: _toTerrain.p,
          r: _toTerrain.r,
          time: _time,
        );
      } else {
        _cachedVertices = WarpGrid.buildMorphedVerticesBetweenPresets(
          width: size.width,
          height: size.height,
          textureWidth: texW,
          textureHeight: texH,
          fromPreset: _fromTerrain,
          toPreset: _toTerrain,
          progress: progress,
          time: _time,
        );
      }
    }
    return _cachedVertices!;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fadeController.dispose();
    _currentTexture?.dispose();
    _previousTexture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_currentSize == null && size.width > 0 && size.height > 0) {
          _currentSize = size;
          if (_currentTexture == null) {
            final initialPreset = _selectNextPreset(size: size);
            _fromTerrain = kTerrainPresets[initialPreset];
            _toTerrain = kTerrainPresets[initialPreset];
          }
        } else {
          _currentSize = size;
        }
        final double progress = _fadeController.isAnimating ? _fadeAnimation.value : 1.0;

        ui.Vertices? vertices;
        if (size.width > 0 && size.height > 0 && _currentTexture != null) {
          vertices = _getOrBuildVertices(size, progress);
        }

        final content = CustomPaint(
          size: Size.infinite,
          painter: MeshFlowPainter(
            vertices: vertices,
            texture: _currentTexture,
            previousTexture: _previousTexture,
            transitionProgress: progress,
            time: _time,
            vignetteAlpha: widget.effectiveVignette,
            fallbackColor: widget.fallbackColor,
          ),
        );

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
