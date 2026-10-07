import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/proxy.dart';
import '../models/video.dart';
import 'audio_handler.dart';

/// 封装 media_kit 播放器：清晰度切换、代理、后台媒体通知。
class IwaraPlayerController extends ChangeNotifier {
  IwaraPlayerController({
    required this.title,
    this.videoId,
    this.artist,
    this.artUri,
    String videoOutput = 'gpu',
  }) {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Iwara',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    videoController = VideoController(
      player,
      configuration: switch (videoOutput) {
        'gpu-sw' => const VideoControllerConfiguration(
            enableHardwareAcceleration: false),
        'mediacodec' => const VideoControllerConfiguration(
            vo: 'mediacodec_embed', hwdec: 'mediacodec'),
        _ => const VideoControllerConfiguration(),
      },
    );
    _subs.add(player.stream.error.listen((e) {
      lastError = e;
      notifyListeners();
    }));
    // mpv 会上报可恢复的错误（如网络重连），播放继续推进时清除
    _subs.add(player.stream.position.listen((_) {
      if (lastError != null && player.state.playing) {
        lastError = null;
        notifyListeners();
      }
    }));
    _subs.add(player.stream.playing.listen((playing) {
      if (playing) PlayerRegistry.activate(this);
    }));
  }

  late final Player player;
  late final VideoController videoController;
  final _subs = <StreamSubscription>[];

  String title;
  String? videoId;
  String? artist;
  Uri? artUri;

  List<VideoSource> sources = const [];
  VideoSource? current;
  String? lastError;
  bool _disposed = false;
  bool get disposed => _disposed;

  bool loop = false;

  Future<void> _applyProxy() async {
    final p = AppHttpOverrides.proxy;
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('http-proxy', p == null ? '' : 'http://$p');
      // 网络流缓存，减少卡顿
      await native.setProperty('cache', 'yes');
      await native.setProperty('demuxer-max-back-bytes', '${32 * 1024 * 1024}');
    }
  }

  /// 打开在线视频。preferred 为首选清晰度名称（Source/540/360）。
  Future<void> openSources(
    List<VideoSource> list, {
    String preferred = 'Source',
    Duration? start,
    bool play = true,
  }) async {
    sources = list.where((s) => s.name != 'preview').toList();
    if (sources.isEmpty) sources = list;
    current = sources.firstWhere((s) => s.name == preferred,
        orElse: () => _closestTo(preferred));
    lastError = null;
    notifyListeners();
    await _applyProxy();
    await player.open(Media(current!.viewUrl, start: start), play: play);
  }

  VideoSource _closestTo(String preferred) {
    int rank(String n) => switch (n) {
          'Source' => 10000,
          'preview' => 0,
          _ => int.tryParse(n) ?? 1,
        };
    final target = rank(preferred);
    final sorted = [...sources]
      ..sort((a, b) =>
          (rank(a.name) - target).abs().compareTo((rank(b.name) - target).abs()));
    return sorted.first;
  }

  Future<void> switchSource(VideoSource source) async {
    if (source.viewUrl == current?.viewUrl) return;
    final pos = player.state.position;
    final playing = player.state.playing;
    current = source;
    notifyListeners();
    await player.open(Media(source.viewUrl, start: pos), play: playing);
  }

  Future<void> openFile(String path, {Duration? start}) async {
    lastError = null;
    await player.open(Media(path, start: start));
  }

  Future<void> setLoop(bool value) async {
    loop = value;
    await player.setPlaylistMode(value ? PlaylistMode.single : PlaylistMode.none);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    PlayerRegistry.deactivate(this);
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// 同一时间只允许一个播放器处于播放状态，并把它绑定到系统媒体通知。
abstract final class PlayerRegistry {
  static IwaraPlayerController? _active;
  static IwaraPlayerController? get active => _active;

  static void activate(IwaraPlayerController c) {
    if (_active == c) return;
    final prev = _active;
    _active = c;
    if (prev != null && !prev.disposed) prev.player.pause();
    IwaraAudioHandler.instance?.attach(c);
  }

  static void deactivate(IwaraPlayerController c) {
    if (_active != c) return;
    _active = null;
    IwaraAudioHandler.instance?.detach();
  }
}
