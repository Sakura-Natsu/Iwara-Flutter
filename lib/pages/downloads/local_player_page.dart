import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings.dart';
import '../../player/fullscreen.dart';
import '../../player/pip.dart';
import '../../player/player_controller.dart';
import '../../player/player_view.dart';
import '../../services/local_db.dart';

/// 播放已下载的本地视频。
class LocalPlayerPage extends ConsumerStatefulWidget {
  const LocalPlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.videoId,
  });

  final String path;
  final String title;
  final String? videoId;

  @override
  ConsumerState<LocalPlayerPage> createState() => _LocalPlayerPageState();
}

class _LocalPlayerPageState extends ConsumerState<LocalPlayerPage>
    with WidgetsBindingObserver {
  late final IwaraPlayerController player = IwaraPlayerController(
    title: widget.title,
    videoId: widget.videoId,
    videoOutput: ref.read(settingsProvider).videoOutput,
  );
  final _playerKey = GlobalKey();
  bool fullscreen = false;
  bool inPip = false;
  Object? openError;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Pip.inPip.addListener(_onPip);
    player.addListener(_onPlayerChanged);
    _sub = player.player.stream.playing.listen((playing) {
      final s = player.player.state;
      // 被其他页面的播放器顶掉而暂停时，不覆盖全局开关
      final active = PlayerRegistry.active;
      if (!playing && active != null && active != player) return;
      Pip.setAutoEnter(
        playing && ref.read(settingsProvider).autoPip,
        width: s.width ?? 16,
        height: s.height ?? 9,
      );
    });
    _open();
  }

  Future<void> _open() async {
    setState(() => openError = null);
    try {
      if (!await File(widget.path).exists()) {
        throw StateError('文件不存在，可能已被删除');
      }
      Duration? start;
      final id = widget.videoId;
      if (id != null && ref.read(settingsProvider).resumePlayback) {
        final saved = await LocalDb.instance.progress(id);
        if (saved != null &&
            saved.$1.inSeconds > 5 &&
            (saved.$2 - saved.$1).inSeconds > 10) {
          start = saved.$1;
        }
      }
      if (!mounted) return;
      await player.openFile(widget.path, start: start);
    } catch (e) {
      if (mounted) setState(() => openError = e);
    }
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Pip.inPip.removeListener(_onPip);
    final active = PlayerRegistry.active;
    if (active == null || active == player) Pip.setAutoEnter(false);
    _sub?.cancel();
    _save();
    if (fullscreen) exitFullscreen();
    player.dispose();
    super.dispose();
  }

  void _save() {
    final id = widget.videoId;
    final s = player.player.state;
    if (id == null || s.duration == Duration.zero) return;
    LocalDb.instance.saveProgress(id, s.position, s.duration);
  }

  void _onPip() {
    final v = Pip.inPip.value;
    if (!mounted) return;
    setState(() => inPip = v);
    if (!v) {
      // 关闭画中画窗口时 Activity 不会回到前台，此时按设置暂停
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        final state = WidgetsBinding.instance.lifecycleState;
        if (state != AppLifecycleState.resumed &&
            !ref.read(settingsProvider).backgroundPlay) {
          player.player.pause();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _save();
      if (!ref.read(settingsProvider).backgroundPlay && !Pip.inPip.value) {
        player.player.pause();
      }
    }
  }

  Future<void> _toggleFullscreen() async {
    if (fullscreen) {
      setState(() => fullscreen = false);
      await exitFullscreen();
    } else {
      final s = player.player.state;
      setState(() => fullscreen = true);
      await enterFullscreen(landscape: (s.width ?? 16) >= (s.height ?? 9));
    }
  }

  Widget _player() {
    final err = openError ?? player.lastError;
    return PlayerView(
      key: _playerKey,
      controller: player,
      fullscreen: fullscreen,
      showControls: !inPip && err == null,
      overlay: err == null
          ? null
          : ColoredBox(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '播放失败：$err',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              ),
            ),
      longPressSpeed: ref.watch(settingsProvider).longPressSpeed,
      onToggleFullscreen: _toggleFullscreen,
      onBack: () => fullscreen ? _toggleFullscreen() : context.pop(),
      onPip: () {
        final s = player.player.state;
        Pip.enter(width: s.width ?? 16, height: s.height ?? 9);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (inPip || fullscreen) {
      return PopScope(
        canPop: !fullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(backgroundColor: Colors.black, body: _player()),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: _player()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '本地离线播放',
                        style: TextStyle(color: Colors.white54),
                      ),
                      if (widget.videoId != null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/video/${widget.videoId}'),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('打开在线页面'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
