import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_exception.dart';
import '../../api/iwara_api.dart';
import '../../api/urls.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../models/video.dart';
import '../../player/fullscreen.dart';
import '../../player/pip.dart';
import '../../player/player_controller.dart';
import '../../player/player_view.dart';
import '../../providers.dart';
import '../../services/download_service.dart';
import '../../services/local_db.dart';
import '../../widgets/cards.dart';
import '../../widgets/net_image.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';
import '../comments/comment_section.dart';
import '../playlist/add_to_playlist_sheet.dart';
import 'content_filter.dart';

class VideoDetailPage extends ConsumerStatefulWidget {
  const VideoDetailPage({super.key, required this.id, this.initial});

  final String id;
  final Video? initial;

  @override
  ConsumerState<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends ConsumerState<VideoDetailPage>
    with WidgetsBindingObserver {
  final _playerKey = GlobalKey();
  late final IwaraPlayerController player = IwaraPlayerController(
    title: widget.initial?.title ?? '',
    videoId: widget.id,
    videoOutput: ref.read(settingsProvider).videoOutput,
  );

  Video? video;
  Object? loadError;
  Object? sourceError;
  bool loadingSources = false;
  List<VideoSource> sources = const [];
  List<Video>? related;
  bool fullscreen = false;
  bool inPip = false;
  int? commentCount;
  bool likeBusy = false;

  /// 详情接口已返回（列表传入的数据缺少收藏、关注状态）。
  bool detailLoaded = false;
  bool followBusy = false;

  final _subs = <StreamSubscription>[];
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _viewSent = false;

  @override
  void initState() {
    super.initState();
    video = widget.initial;
    commentCount = widget.initial?.numComments;
    WidgetsBinding.instance.addObserver(this);
    Pip.inPip.addListener(_onPipChanged);
    player.addListener(_onPlayerChanged);
    _subs.add(player.player.stream.position.listen(_onPosition));
    _subs.add(player.player.stream.playing.listen(_onPlaying));
    _subs.add(
      player.player.stream.completed.listen((done) {
        if (done) LocalDb.instance.clearProgress(widget.id);
      }),
    );
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Pip.inPip.removeListener(_onPipChanged);
    final active = PlayerRegistry.active;
    if (active == null || active == player) Pip.setAutoEnter(false);
    for (final s in _subs) {
      s.cancel();
    }
    _saveProgress(force: true);
    if (fullscreen) exitFullscreen();
    player.dispose();
    super.dispose();
  }

  // ---------------- 数据加载 ----------------

  Future<void> _load() async {
    setState(() => loadError = null);
    final api = ref.read(apiProvider);
    try {
      final v = await api.video(widget.id);
      if (!mounted) return;
      setState(() {
        video = v;
        detailLoaded = true;
        commentCount = v.numComments;
      });
      player
        ..title = v.title
        ..artist = v.user?.name
        ..artUri = Uri.tryParse(IwaraUrls.videoThumbnail(v) ?? '');
      _loadRelated();
      if (!v.isExternal) await _loadSources();
    } catch (e) {
      if (mounted) setState(() => loadError = e);
    }
  }

  Future<void> _loadSources() async {
    final v = video;
    if (v == null) return;
    setState(() {
      loadingSources = true;
      sourceError = null;
    });
    final settings = ref.read(settingsProvider);
    try {
      final list = await ref.read(apiProvider).videoSources(v);
      Duration? start;
      if (settings.resumePlayback) {
        final saved = await LocalDb.instance.progress(v.id);
        if (saved != null) {
          final (pos, dur) = saved;
          if (pos.inSeconds > 5 && (dur - pos).inSeconds > 10) start = pos;
        }
      }
      if (!mounted) return;
      sources = list;
      await player.openSources(
        list,
        preferred: settings.defaultQuality,
        start: start,
        play: settings.autoPlay,
      );
      if (mounted && start != null) {
        showToast(context, '已从 ${formatDuration(start)} 继续播放');
      }
    } catch (e) {
      if (mounted) setState(() => sourceError = e);
    } finally {
      if (mounted) setState(() => loadingSources = false);
    }
  }

  Future<void> _loadRelated() async {
    try {
      final list = await ref.read(apiProvider).relatedVideos(widget.id);
      if (mounted) setState(() => related = list);
    } catch (_) {
      if (mounted) setState(() => related = const []);
    }
  }

  // ---------------- 播放状态 ----------------

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  void _onPosition(Duration pos) {
    if (DateTime.now().difference(_lastSave).inSeconds >= 5) _saveProgress();
  }

  void _saveProgress({bool force = false}) {
    final s = player.player.state;
    if (s.duration == Duration.zero || s.position.inSeconds < 3) return;
    if (s.completed) return;
    _lastSave = DateTime.now();
    LocalDb.instance.saveProgress(widget.id, s.position, s.duration);
  }

  void _onPlaying(bool playing) {
    final settings = ref.read(settingsProvider);
    final (w, h) = _videoSize();
    // 被其他页面的播放器顶掉而暂停时，不要覆盖全局的自动画中画开关
    final active = PlayerRegistry.active;
    if (playing || active == null || active == player) {
      Pip.setAutoEnter(playing && settings.autoPip, width: w, height: h);
    }
    if (playing && !_viewSent) {
      _viewSent = true;
      ref
          .read(apiProvider)
          .sendView(ContentType.video, widget.id)
          .catchError((_) {});
    }
  }

  (int, int) _videoSize() {
    final s = player.player.state;
    final w = s.width ?? video?.file?.width ?? 16;
    final h = s.height ?? video?.file?.height ?? 9;
    return (w <= 0 ? 16 : w, h <= 0 ? 9 : h);
  }

  void _onPipChanged() {
    final v = Pip.inPip.value;
    if (!mounted) return;
    setState(() => inPip = v);
    if (!v) {
      // 关闭画中画窗口时 Activity 不会回到前台，此时暂停播放
      Future.delayed(const Duration(milliseconds: 400), () {
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
      _saveProgress(force: true);
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
      final (w, h) = _videoSize();
      setState(() => fullscreen = true);
      await enterFullscreen(landscape: w >= h);
    }
  }

  Future<void> _enterPip() async {
    final (w, h) = _videoSize();
    final ok = await Pip.enter(width: w, height: h);
    if (!ok && mounted) showToast(context, '当前设备不支持画中画');
  }

  // ---------------- 交互 ----------------

  Future<void> _toggleLike() async {
    final v = video;
    if (v == null || likeBusy || !requireLogin(context, ref)) return;
    if (!detailLoaded) {
      showToast(context, '正在加载，请稍候');
      return;
    }
    setState(() {
      likeBusy = true;
      video = v.copyWith(
        liked: !v.liked,
        numLikes: v.numLikes + (v.liked ? -1 : 1),
      );
    });
    try {
      final api = ref.read(apiProvider);
      v.liked
          ? await api.unlike(ContentType.video, v.id)
          : await api.like(ContentType.video, v.id);
      if (mounted) showToast(context, v.liked ? '已取消收藏' : '已收藏');
    } catch (e) {
      if (mounted) {
        setState(
          () => video = video?.copyWith(liked: v.liked, numLikes: v.numLikes),
        );
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => likeBusy = false);
    }
  }

  Future<void> _toggleFollow() async {
    final v = video;
    final u = v?.user;
    if (v == null || u == null || followBusy || !requireLogin(context, ref)) {
      return;
    }
    if (!detailLoaded) {
      showToast(context, '正在加载，请稍候');
      return;
    }
    setState(() {
      followBusy = true;
      video = v.copyWith(user: u.copyWith(following: !u.following));
    });
    try {
      final api = ref.read(apiProvider);
      u.following ? await api.unfollow(u.id) : await api.follow(u.id);
    } catch (e) {
      if (mounted) {
        final cur = video;
        setState(
          () => video = cur?.copyWith(
            user: cur.user?.copyWith(following: u.following),
          ),
        );
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  Future<void> _download() async {
    final v = video;
    if (v == null) return;
    if (sources.isEmpty) {
      showToast(context, '播放源尚未加载');
      return;
    }
    final src = await showModalBottomSheet<VideoSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选择下载清晰度', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final s in sources.where((s) => s.name != 'preview'))
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(s.label),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (src == null) return;
    final ok = await DownloadService.enqueue(v, src);
    if (!mounted) return;
    showToast(context, ok ? '已加入下载队列' : '该视频已在下载列表中');
  }

  void _share() {
    final v = video;
    if (v == null) return;
    SharePlus.instance.share(
      ShareParams(
        text: '${v.title}\n${IwaraUrls.videoPage(v.id)}',
        subject: v.title,
      ),
    );
  }

  // ---------------- 构建 ----------------

  Widget _playerArea() {
    final v = video;
    Widget? overlay;
    if (loadError != null) {
      overlay = _PlayerMessage(
        message: ApiException.from(loadError!).message,
        onRetry: _load,
      );
    } else if (v != null && v.isExternal) {
      overlay = _ExternalVideo(video: v);
    } else if (sourceError != null) {
      overlay = _PlayerMessage(
        message: '播放源获取失败：${ApiException.from(sourceError!).message}',
        onRetry: _loadSources,
      );
    } else if (player.lastError != null && sources.isNotEmpty) {
      overlay = _PlayerMessage(
        message: '播放出错：${player.lastError}',
        onRetry: _loadSources,
      );
    } else if (v != null && player.current == null) {
      overlay = Stack(
        fit: StackFit.expand,
        children: [
          NetImage(
            IwaraUrls.videoThumbnail(v, size: 'large'),
            fit: BoxFit.contain,
          ),
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }
    final settings = ref.watch(settingsProvider);
    return PlayerView(
      key: _playerKey,
      controller: player,
      fullscreen: fullscreen,
      showControls: !inPip && overlay == null,
      onToggleFullscreen: _toggleFullscreen,
      onBack: () => fullscreen ? _toggleFullscreen() : context.pop(),
      onPip: _enterPip,
      longPressSpeed: settings.longPressSpeed,
      overlay: overlay == null
          ? null
          : Stack(
              fit: StackFit.expand,
              children: [
                overlay,
                if (!fullscreen && !inPip)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 全屏 / 画中画时页面主树保持挂载（Tab、评论、滚动位置不丢失），
    // 播放器通过 GlobalKey 移到全屏覆盖层。
    final immersive = fullscreen || inPip;
    final playerWidget = _playerArea();
    final v = video;
    final page = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              ColoredBox(
                color: Colors.black,
                child: SafeArea(
                  bottom: false,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: immersive ? const SizedBox.expand() : playerWidget,
                  ),
                ),
              ),
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: TabBar(
                  tabAlignment: TabAlignment.fill,
                  tabs: [
                    const Tab(text: '简介'),
                    Tab(text: '评论 ${commentCount ?? ''}'),
                  ],
                ),
              ),
              Expanded(
                child: v == null
                    ? (loadError != null
                          ? ErrorView.from(loadError!, onRetry: _load)
                          : const LoadingView())
                    : TabBarView(
                        children: [
                          _infoTab(v),
                          CommentSection(
                            type: ContentType.video,
                            id: v.id,
                            ownerId: v.user?.id,
                            onCountChanged: (n) {
                              if (mounted && n != commentCount) {
                                setState(() => commentCount = n);
                              }
                            },
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && fullscreen) _toggleFullscreen();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: immersive,
            child: TickerMode(enabled: !immersive, child: page),
          ),
          if (immersive) Material(color: Colors.black, child: playerWidget),
        ],
      ),
    );
  }

  Widget _infoTab(Video v) {
    final theme = Theme.of(context);
    final user = v.user;
    final me = ref.watch(meProvider);
    final isMe = me != null && user?.id == me.user.id;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 作者
                if (user != null)
                  Row(
                    children: [
                      UserAvatar(
                        user,
                        size: 40,
                        onTap: () => context.push('/profile/${user.username}'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () =>
                              context.push('/profile/${user.username}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                '@${user.username}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!isMe)
                        user.following
                            ? OutlinedButton(
                                onPressed: followBusy ? null : _toggleFollow,
                                child: const Text('已关注'),
                              )
                            : FilledButton.icon(
                                onPressed: followBusy ? null : _toggleFollow,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('关注'),
                              ),
                    ],
                  ),
                const SizedBox(height: 12),
                SelectableText(
                  v.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DefaultTextStyle(
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: theme.hintColor,
                  ),
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (v.isR18) const R18Badge(),
                      Text('${formatCount(v.numViews)} 播放'),
                      Text(formatDateTime(v.createdAt)),
                      if (v.isPrivate) const Text('私密'),
                      if (v.unlisted) const Text('不公开'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _actions(v),
                if ((v.body ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _Description(text: v.body!),
                ],
                if (v.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in v.tags)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(t.id),
                          onPressed: () {
                            ref
                                .read(videoFilterProvider.notifier)
                                .set(ContentFilter(tags: [t.id]));
                            context.go('/videos');
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text('相关推荐', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        ),
        if (related == null)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(24), child: LoadingView()),
          )
        else if (related!.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: EmptyView(text: '暂无相关推荐'),
            ),
          )
        else
          SliverList.builder(
            itemCount: related!.length,
            itemBuilder: (_, i) => VideoTile(related![i]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _actions(Video v) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _ActionButton(
          icon: v.liked ? Icons.favorite : Icons.favorite_border,
          color: v.liked ? Colors.pinkAccent : null,
          label: formatCount(v.numLikes),
          onTap: _toggleLike,
        ),
        _ActionButton(
          icon: Icons.playlist_add,
          label: '播放列表',
          onTap: () {
            if (requireLogin(context, ref)) {
              showAddToPlaylistSheet(context, v.id);
            }
          },
        ),
        _ActionButton(
          icon: Icons.download_outlined,
          label: '下载',
          onTap: v.isExternal ? null : _download,
        ),
        _ActionButton(icon: Icons.share_outlined, label: '分享', onTap: _share),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (k) async {
            final url = IwaraUrls.videoPage(v.id);
            switch (k) {
              case 'browser':
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              case 'copy':
                await Clipboard.setData(ClipboardData(text: url));
                if (mounted) showToast(context, '链接已复制');
              case 'refresh':
                _loadSources();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'refresh', child: Text('重新加载播放源')),
            PopupMenuItem(value: 'copy', child: Text('复制链接')),
            PopupMenuItem(value: 'browser', child: Text('在浏览器中打开')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                Icon(
                  Icons.more_horiz,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                Text('更多', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = onTap == null
        ? theme.disabledColor
        : color ?? theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

class _Description extends StatefulWidget {
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final long =
        widget.text.length > 200 || '\n'.allMatches(widget.text).length > 5;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: !long || expanded ? double.infinity : 110,
              ),
              // 折叠时用不可滚动的 ScrollView 裁剪内容，避免溢出报错
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: RichBody(
                  widget.text,
                  style: theme.textTheme.bodySmall,
                  selectable: true,
                ),
              ),
            ),
          ),
          if (long)
            Center(
              child: TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(expanded ? '收起' : '展开'),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerMessage extends StatelessWidget {
  const _PlayerMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ExternalVideo extends StatelessWidget {
  const _ExternalVideo({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      NetImage(
        IwaraUrls.videoThumbnail(video, size: 'large'),
        fit: BoxFit.contain,
      ),
      Container(color: Colors.black45),
      Center(
        child: FilledButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(video.embedUrl!),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('外链视频，点击在浏览器中观看'),
        ),
      ),
    ],
  );
}
