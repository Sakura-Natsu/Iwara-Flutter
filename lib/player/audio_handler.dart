import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'player_controller.dart';

/// 系统媒体通知 / 锁屏控制，转发给当前活动的播放器。
class IwaraAudioHandler extends BaseAudioHandler with SeekHandler {
  IwaraAudioHandler._();

  static IwaraAudioHandler? instance;

  static Future<void> init() async {
    try {
      instance = await AudioService.init(
        builder: IwaraAudioHandler._,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'io.github.iwara.iwara_flutter.playback',
          androidNotificationChannelName: '视频播放',
          androidNotificationIcon: 'drawable/ic_notification',
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('AudioService 初始化失败: $e');
    }
  }

  IwaraPlayerController? _c;
  final _subs = <StreamSubscription>[];

  void attach(IwaraPlayerController c) {
    if (_c == c) return;
    _cancel();
    _c = c;
    final p = c.player;
    mediaItem.add(MediaItem(
      id: c.videoId ?? c.title,
      title: c.title,
      artist: c.artist,
      artUri: c.artUri,
      duration: p.state.duration,
    ));
    _subs
      ..add(p.stream.playing.listen((_) => _broadcast()))
      ..add(p.stream.buffering.listen((_) => _broadcast()))
      ..add(p.stream.completed.listen((_) => _broadcast()))
      ..add(p.stream.duration.listen((d) {
        final item = mediaItem.value;
        if (item != null) mediaItem.add(item.copyWith(duration: d));
      }))
      ..add(p.stream.position
          .distinct((a, b) => a.inSeconds == b.inSeconds)
          .listen((_) => _broadcast()));
    _broadcast();
  }

  void detach() {
    _cancel();
    _c = null;
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _broadcast() {
    final c = _c;
    if (c == null || c.disposed) return;
    final s = c.player.state;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        s.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: s.completed
          ? AudioProcessingState.completed
          : s.buffering
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
      playing: s.playing,
      updatePosition: s.position,
      bufferedPosition: s.buffer,
      speed: s.rate,
    ));
  }

  @override
  Future<void> play() async => _c?.player.play();

  @override
  Future<void> pause() async => _c?.player.pause();

  @override
  Future<void> seek(Duration position) async => _c?.player.seek(position);

  @override
  Future<void> rewind() async {
    final p = _c?.player;
    if (p == null) return;
    final t = p.state.position - const Duration(seconds: 10);
    await p.seek(t < Duration.zero ? Duration.zero : t);
  }

  @override
  Future<void> fastForward() async {
    final p = _c?.player;
    if (p == null) return;
    await p.seek(p.state.position + const Duration(seconds: 10));
  }

  @override
  Future<void> stop() async {
    final c = _c;
    await c?.player.pause();
    if (c != null) {
      PlayerRegistry.deactivate(c);
    } else {
      detach();
    }
  }
}
