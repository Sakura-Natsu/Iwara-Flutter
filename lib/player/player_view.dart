import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../core/format.dart';
import '../models/video.dart' show VideoSource;
import 'player_controller.dart';

/// 视频画面 + 自定义手势控制层。
class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.onBack,
    this.onPip,
    this.showControls = true,
    this.longPressSpeed = 2.0,
    this.overlay,
  });

  final IwaraPlayerController controller;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onBack;
  final VoidCallback? onPip;
  final bool showControls;
  final double longPressSpeed;

  /// 播放器上方额外叠加的内容（如加载/错误提示）。
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: controller.videoController,
            controls: NoVideoControls,
            fit: BoxFit.contain,
            pauseUponEnteringBackgroundMode: false,
            wakelock: true,
          ),
          ?overlay,
          if (showControls)
            PlayerControls(
              controller: controller,
              fullscreen: fullscreen,
              onToggleFullscreen: onToggleFullscreen,
              onBack: onBack,
              onPip: onPip,
              longPressSpeed: longPressSpeed,
            ),
        ],
      ),
    );
  }
}

enum _DragKind { none, seek, volume, brightness }

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.onBack,
    this.onPip,
    this.longPressSpeed = 2.0,
  });

  final IwaraPlayerController controller;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onBack;
  final VoidCallback? onPip;
  final double longPressSpeed;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  IwaraPlayerController get c => widget.controller;

  final _subs = <StreamSubscription>[];
  bool playing = false;
  bool buffering = true;
  bool completed = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration buffer = Duration.zero;
  double rate = 1.0;

  bool visible = true;
  bool locked = false;
  Timer? _hideTimer;

  // 拖动状态
  _DragKind drag = _DragKind.none;
  Duration? seekTarget;
  double _dragStartX = 0;
  Duration _dragStartPos = Duration.zero;
  double _level = 0; // 音量/亮度 0~1
  double _levelStart = 0;
  double _dragStartY = 0;

  // 长按倍速
  bool speeding = false;
  double _rateBeforeSpeed = 1.0;

  // 滑块拖动
  double? sliderValue;

  @override
  void initState() {
    super.initState();
    final s = c.player.state;
    playing = s.playing;
    buffering = s.buffering;
    position = s.position;
    duration = s.duration;
    buffer = s.buffer;
    rate = s.rate;
    final st = c.player.stream;
    _subs.addAll([
      st.playing.listen((v) {
        setState(() => playing = v);
        if (v) _scheduleHide();
      }),
      st.buffering.listen((v) => setState(() => buffering = v)),
      st.completed.listen((v) => setState(() => completed = v)),
      st.position.listen((v) {
        if (mounted) setState(() => position = v);
      }),
      st.duration.listen((v) => setState(() => duration = v)),
      st.buffer.listen((v) => buffer = v),
      st.rate.listen((v) => setState(() => rate = v)),
    ]);
    c.addListener(_onController);
    FlutterVolumeController.updateShowSystemUI(false);
    _scheduleHide();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    // 长按倍速期间控制层被移除（如进入画中画）时恢复原速
    if (speeding && !c.disposed) c.player.setRate(_rateBeforeSpeed);
    c.removeListener(_onController);
    _hideTimer?.cancel();
    FlutterVolumeController.updateShowSystemUI(true);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && playing && drag == _DragKind.none && sliderValue == null) {
        setState(() => visible = false);
      }
    });
  }

  void _toggleVisible() {
    setState(() => visible = !visible);
    if (visible) _scheduleHide();
  }

  void _showAndHideLater() {
    if (!visible) setState(() => visible = true);
    _scheduleHide();
  }

  // ---------------- 手势 ----------------

  void _onHDragStart(DragStartDetails d) {
    if (locked || duration == Duration.zero) return;
    drag = _DragKind.seek;
    _dragStartX = d.globalPosition.dx;
    _dragStartPos = position;
    seekTarget = position;
    setState(() {});
  }

  void _onHDragUpdate(DragUpdateDetails d, double width) {
    if (drag != _DragKind.seek) return;
    // 全宽拖动 ≈ 90 秒，长视频按比例放大
    final total = duration.inMilliseconds;
    final span = (total * 0.4).clamp(90000, 600000).toDouble();
    final dx = d.globalPosition.dx - _dragStartX;
    var ms = _dragStartPos.inMilliseconds + (dx / width * span).round();
    ms = ms.clamp(0, total);
    setState(() => seekTarget = Duration(milliseconds: ms));
  }

  void _onHDragEnd(DragEndDetails _) {
    if (drag != _DragKind.seek) return;
    final t = seekTarget;
    drag = _DragKind.none;
    seekTarget = null;
    if (t != null) c.player.seek(t);
    setState(() {});
    _showAndHideLater();
  }

  Future<void> _onVDragStart(DragStartDetails d, double width) async {
    if (locked) return;
    final left = d.localPosition.dx < width / 2;
    _dragStartY = d.globalPosition.dy;
    double start;
    try {
      start = left
          ? await ScreenBrightness.instance.application
          : (await FlutterVolumeController.getVolume() ?? 0.5);
    } catch (_) {
      start = 0.5;
    }
    if (!mounted) return;
    // 取到当前值后才进入拖动状态，避免首帧用旧值导致跳变
    _levelStart = start;
    _level = start;
    setState(() => drag = left ? _DragKind.brightness : _DragKind.volume);
  }

  void _onVDragUpdate(DragUpdateDetails d, double height) {
    if (drag != _DragKind.volume && drag != _DragKind.brightness) return;
    final dy = _dragStartY - d.globalPosition.dy;
    final v = (_levelStart + dy / (height * 0.8)).clamp(0.0, 1.0);
    _level = v;
    if (drag == _DragKind.brightness) {
      ScreenBrightness.instance.setApplicationScreenBrightness(v);
    } else {
      FlutterVolumeController.setVolume(v);
    }
    setState(() {});
  }

  void _onVDragEnd(DragEndDetails _) {
    drag = _DragKind.none;
    setState(() {});
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (locked || !playing) return;
    _rateBeforeSpeed = rate;
    speeding = true;
    c.player.setRate(widget.longPressSpeed);
    HapticFeedback.lightImpact();
    setState(() {});
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!speeding) return;
    speeding = false;
    c.player.setRate(_rateBeforeSpeed);
    setState(() {});
  }

  void _onDoubleTap() {
    if (locked) return;
    if (completed) {
      c.player.seek(Duration.zero);
      c.player.play();
    } else {
      c.player.playOrPause();
    }
    _showAndHideLater();
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final height = box.maxHeight;
      final showBars = visible && !locked;
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleVisible,
            onDoubleTap: _onDoubleTap,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onHorizontalDragStart: _onHDragStart,
            onHorizontalDragUpdate: (d) => _onHDragUpdate(d, width),
            onHorizontalDragEnd: _onHDragEnd,
            onVerticalDragStart: (d) => _onVDragStart(d, width),
            onVerticalDragUpdate: (d) => _onVDragUpdate(d, height),
            onVerticalDragEnd: _onVDragEnd,
            child: const SizedBox.expand(),
          ),
          // 中央提示
          Center(child: IgnorePointer(child: _centerIndicator())),
          if (speeding)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: _Pill(
                  icon: Icons.fast_forward_rounded,
                  text: '${widget.longPressSpeed}x 倍速中',
                ),
              ),
            ),
          // 顶栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Fade(visible: showBars, child: _topBar()),
          ),
          // 底栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _Fade(visible: showBars, child: _bottomBar()),
          ),
          // 锁定按钮（全屏）
          if (widget.fullscreen)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _Fade(
                  visible: visible,
                  child: IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                    color: Colors.white,
                    icon: Icon(locked ? Icons.lock : Icons.lock_open),
                    onPressed: () {
                      setState(() => locked = !locked);
                      _showAndHideLater();
                    },
                  ),
                ),
              ),
            ),
          // 暂停时的大播放按钮
          if (!playing && !buffering && showBars && drag == _DragKind.none)
            Center(
              child: IconButton.filled(
                iconSize: 40,
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                color: Colors.white,
                icon: Icon(completed ? Icons.replay : Icons.play_arrow_rounded),
                onPressed: _onDoubleTap,
              ),
            ),
        ],
      );
    });
  }

  Widget _centerIndicator() {
    switch (drag) {
      case _DragKind.seek:
        final t = seekTarget ?? position;
        final diff = t - _dragStartPos;
        final sign = diff.isNegative ? '-' : '+';
        return _Pill(
          text:
              '${formatDuration(t)} / ${formatDuration(duration)}\n$sign${diff.abs().inSeconds} 秒',
          big: true,
        );
      case _DragKind.volume:
      case _DragKind.brightness:
        return _LevelIndicator(
          icon: drag == _DragKind.volume
              ? (_level == 0 ? Icons.volume_off : Icons.volume_up)
              : Icons.brightness_6,
          value: _level,
        );
      case _DragKind.none:
        if (buffering && !completed) {
          return const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          );
        }
        return const SizedBox.shrink();
    }
  }

  Widget _topBar() {
    final pad = widget.fullscreen
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad.left + 4, 4, pad.right + 4, 12),
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                ),
              Expanded(
                child: widget.fullscreen
                    ? Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      )
                    : const SizedBox.shrink(),
              ),
              if (c.sources.length > 1) _qualityButton(),
              _speedButton(),
              if (widget.onPip != null)
                IconButton(
                  tooltip: '画中画',
                  icon: const Icon(Icons.picture_in_picture_alt_outlined),
                  onPressed: widget.onPip,
                ),
              _moreButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qualityButton() {
    return PopupMenuButton<VideoSource>(
      tooltip: '清晰度',
      onOpened: () => _hideTimer?.cancel(),
      onCanceled: _scheduleHide,
      onSelected: (s) {
        c.switchSource(s);
        _scheduleHide();
      },
      itemBuilder: (_) => [
        for (final s in c.sources)
          CheckedPopupMenuItem(
            value: s,
            checked: s.viewUrl == c.current?.viewUrl,
            child: Text(s.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(c.current?.label ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }

  Widget _speedButton() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    return PopupMenuButton<double>(
      tooltip: '倍速',
      onOpened: () => _hideTimer?.cancel(),
      onCanceled: _scheduleHide,
      onSelected: (v) {
        c.player.setRate(v);
        _scheduleHide();
      },
      itemBuilder: (_) => [
        for (final s in speeds)
          CheckedPopupMenuItem(
            value: s,
            checked: (rate - s).abs() < 0.01,
            child: Text('${s}x'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(rate == 1.0 ? '倍速' : '${rate}x',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }

  Widget _moreButton() {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onOpened: () => _hideTimer?.cancel(),
      onCanceled: _scheduleHide,
      onSelected: (v) {
        if (v == 'loop') c.setLoop(!c.loop);
        _scheduleHide();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'loop',
          checked: c.loop,
          child: const Text('循环播放'),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    final pad = widget.fullscreen
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    final total = duration.inMilliseconds.toDouble();
    final value = (sliderValue ??
            (seekTarget ?? position).inMilliseconds.toDouble())
        .clamp(0.0, total <= 0 ? 1.0 : total);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            pad.left + 4, 12, pad.right + 4, widget.fullscreen ? pad.bottom + 4 : 0),
        child: Row(
          children: [
            IconButton(
              color: Colors.white,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: _onDoubleTap,
            ),
            Text(
              formatDuration(Duration(milliseconds: value.round())),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  inactiveTrackColor: Colors.white24,
                  secondaryActiveTrackColor: Colors.white54,
                ),
                child: Slider(
                  max: total <= 0 ? 1.0 : total,
                  value: total <= 0 ? 0 : value,
                  secondaryTrackValue: total <= 0
                      ? null
                      : buffer.inMilliseconds.toDouble().clamp(0.0, total),
                  onChangeStart: (v) {
                    _hideTimer?.cancel();
                    setState(() => sliderValue = v);
                  },
                  onChanged: (v) => setState(() => sliderValue = v),
                  onChangeEnd: (v) {
                    c.player.seek(Duration(milliseconds: v.round()));
                    setState(() => sliderValue = null);
                    _scheduleHide();
                  },
                ),
              ),
            ),
            Text(
              formatDuration(duration),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            IconButton(
              color: Colors.white,
              icon: Icon(widget.fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded),
              onPressed: widget.onToggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.big = false});

  final String text;
  final IconData? icon;
  final bool big;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: big ? 18 : 12, vertical: big ? 10 : 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(big ? 10 : 20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 4),
          ],
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: big ? 16 : 13,
                  fontWeight: big ? FontWeight.w600 : null)),
        ]),
      );
}

class _LevelIndicator extends StatelessWidget {
  const _LevelIndicator({required this.icon, required this.value});

  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
            ),
          ),
        ]),
      );
}
