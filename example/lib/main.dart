import 'package:flutter/material.dart';
import 'package:mesh_flow/mesh_flow.dart';

void main() {
  runApp(const MeshFlowExampleApp());
}

class SongItem {
  const SongItem({
    required this.title,
    required this.artist,
    required this.assetPath,
  });

  final String title;
  final String artist;
  final String assetPath;
}

const List<SongItem> kDemoSongs = [
  SongItem(
    title: 'No Smile No Life',
    artist: 'yugu',
    assetPath: 'assets/yugu - No Smile No Life - Cover.jpg',
  ),
  SongItem(
    title: '明晰メモリー',
    artist: 'ナナホシ管弦楽団',
    assetPath: 'assets/ナナホシ管弦楽団 - 明晰メモリー - Cover.jpg',
  ),
  SongItem(
    title: 'Summer drop',
    artist: 'ジョニ',
    assetPath: 'assets/ジョニ - Summer drop - Cover.jpg',
  ),
  SongItem(
    title: 'ハッピーラブソングトゥーユー',
    artist: 'あだちかすか',
    assetPath: 'assets/あだちかすか - ハッピーラブソングトゥーユー - Cover.jpg',
  ),
  SongItem(
    title: '恋はきっと急上昇☆-Rock Buster-',
    artist: 'のぼる↑, Haru.jpg',
    assetPath: 'assets/のぼる↑, Haru.jpg - 恋はきっと急上昇☆-Rock Buster- - Cover.jpg',
  ),
];

class MeshFlowExampleApp extends StatelessWidget {
  const MeshFlowExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshFlow Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white70,
        ),
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  int _currentSongIndex = 0;
  bool _isPlaying = true;
  double _flowSpeed = 1.0;
  double _vignetteAlpha = 0.35;
  int? _selectedPreset; // null = 切歌随机

  void _nextSong() {
    setState(() {
      _currentSongIndex = (_currentSongIndex + 1) % kDemoSongs.length;
    });
  }

  void _previousSong() {
    setState(() {
      _currentSongIndex =
          (_currentSongIndex - 1 + kDemoSongs.length) % kDemoSongs.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final song = kDemoSongs[_currentSongIndex];
    final imageProvider = AssetImage(song.assetPath);

    return Scaffold(
      body: MeshFlow(
        image: imageProvider,
        presetIndex: _selectedPreset,
        flowSpeed: _flowSpeed,
        animating: _isPlaying,
        vignetteAlpha: _vignetteAlpha,
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏操作区
              _buildTopBar(),
              const Spacer(),
              // 居中封面（带阴影与圆角）
              _buildCoverCard(imageProvider),
              const SizedBox(height: 36),
              // 歌曲与歌手信息
              Text(
                song.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                song.artist,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              // 播放器控制栏
              _buildPlaybackControls(),
              const SizedBox(height: 20),
              // 底部控制面板（流速、暗角、预设调节）
              _buildControlPanel(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Vynody / MeshFlow',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: Colors.white70,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => _showSettingsBottomSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverCard(ImageProvider imageProvider) {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Image(
            key: ValueKey<int>(_currentSongIndex),
            image: imageProvider,
            fit: BoxFit.cover,
            width: 260,
            height: 260,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            iconSize: 38,
            icon: const Icon(Icons.skip_previous_rounded),
            color: Colors.white,
            onPressed: _previousSong,
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 52,
              icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              color: Colors.white,
              onPressed: () {
                setState(() {
                  _isPlaying = !_isPlaying;
                });
              },
            ),
          ),
          IconButton(
            iconSize: 38,
            icon: const Icon(Icons.skip_next_rounded),
            color: Colors.white,
            onPressed: _nextSong,
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildChip(
            label: _selectedPreset == null ? '地形: 随机' : '地形: #$_selectedPreset',
            icon: Icons.terrain_rounded,
            onTap: () {
              setState(() {
                if (_selectedPreset == null) {
                  _selectedPreset = 0;
                } else if (_selectedPreset! < kTerrainPresets.length - 1) {
                  _selectedPreset = _selectedPreset! + 1;
                } else {
                  _selectedPreset = null;
                }
              });
            },
          ),
          _buildChip(
            label: '流速: ${_flowSpeed.toStringAsFixed(1)}x',
            icon: Icons.speed_rounded,
            onTap: () {
              setState(() {
                if (_flowSpeed >= 2.5) {
                  _flowSpeed = 0.5;
                } else {
                  _flowSpeed += 0.5;
                }
              });
            },
          ),
          _buildChip(
            label: '暗角: ${(_vignetteAlpha * 100).round()}%',
            icon: Icons.vignette_rounded,
            onTap: () {
              setState(() {
                if (_vignetteAlpha >= 0.6) {
                  _vignetteAlpha = 0.0;
                } else {
                  _vignetteAlpha += 0.15;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '背景参数调节',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text('流速: ${_flowSpeed.toStringAsFixed(2)}x'),
                  Slider(
                    value: _flowSpeed,
                    min: 0.1,
                    max: 3.0,
                    onChanged: (val) {
                      setModalState(() => _flowSpeed = val);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('暗角强度: ${(_vignetteAlpha * 100).round()}%'),
                  Slider(
                    value: _vignetteAlpha,
                    min: 0.0,
                    max: 0.8,
                    onChanged: (val) {
                      setModalState(() => _vignetteAlpha = val);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('选择歌曲'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(kDemoSongs.length, (idx) {
                      return ChoiceChip(
                        label: Text(kDemoSongs[idx].title),
                        selected: _currentSongIndex == idx,
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() => _currentSongIndex = idx);
                            setState(() {});
                          }
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
