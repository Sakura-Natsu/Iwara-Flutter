import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/iwara_api.dart';
import '../../api/urls.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../models/image.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../models/video.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';
import '../comments/comment_section.dart';
import '../posts/post_tile.dart';

// 头部各部分高度（展开高度据此计算）。
const _kCoverHeight = 140.0;
const _kActionRowHeight = 52.0;
const _kEntryRowHeight = 36.0;
const _kNameSize = 20.0;
const _kUsernameSize = 13.0;
const _kStatusSize = 12.0;

/// 好友关系。
enum _Friend { none, friends, outgoing, incoming }

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.username});

  final String username;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _scroll = ScrollController();

  Profile? profile;
  Object? error;
  bool followBusy = false;
  bool blocked = false;

  // 折叠状态：封面滚出后顶栏变为实色；名字滚出后显示标题
  bool _solidBar = false;
  bool _showTitle = false;

  String get _uid => profile!.user.id;

  // 各 Tab 的分页数据保存在页面 State 中，切换 Tab 不会丢失也不会重新加载。
  late final _videos = PagingController<Video>(
    (page) => ref
        .read(apiProvider)
        .videos(
          userId: _uid,
          sort: 'date',
          rating: ref.read(settingsProvider).rating,
          page: page,
        ),
    dedupeKey: (v) => v.id,
  );
  late final _images = PagingController<GalleryImage>(
    (page) => ref
        .read(apiProvider)
        .images(
          userId: _uid,
          sort: 'date',
          rating: ref.read(settingsProvider).rating,
          page: page,
        ),
    dedupeKey: (i) => i.id,
  );
  late final _posts = PagingController<Post>(
    (page) => ref.read(apiProvider).posts(userId: _uid, page: page),
    dedupeKey: (p) => p.id,
  );
  late final _playlists = PagingController<Playlist>(
    (page) => ref.read(apiProvider).playlists(_uid, page: page),
    dedupeKey: (p) => p.id,
  );
  late final _comments = PagingController<Comment>(
    (page) =>
        ref.read(apiProvider).comments(ContentType.profile, _uid, page: page),
    dedupeKey: (c) => c.id,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _videos.dispose();
    _images.dispose();
    _posts.dispose();
    _playlists.dispose();
    _comments.dispose();
    super.dispose();
  }

  /// 根据外层滚动位置更新顶栏状态，返回是否有变化。
  bool _updateBarState() {
    if (!_scroll.hasClients) return false;
    final o = _scroll.offset;
    final solid = o >= _kCoverHeight - kToolbarHeight;
    final title =
        o >= _kCoverHeight + _kActionRowHeight + _kNameSize - kToolbarHeight;
    if (solid == _solidBar && title == _showTitle) return false;
    _solidBar = solid;
    _showTitle = title;
    return true;
  }

  void _onScroll() {
    // 滚动位置可能在布局阶段被修正，此时推迟到帧结束再 setState
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _updateBarState()) setState(() {});
      });
    } else if (_updateBarState()) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final p = await ref.read(apiProvider).profile(widget.username);
      if (mounted) setState(() => profile = p);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  /// 下拉刷新：刷新主页信息和当前 Tab。
  Future<void> _refresh(int tab) async {
    Future<void> reloadProfile() async {
      try {
        final p = await ref.read(apiProvider).profile(widget.username);
        if (mounted) setState(() => profile = p);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }

    await Future.wait([
      reloadProfile(),
      switch (tab) {
        0 => _videos.refresh(),
        1 => _images.refresh(),
        2 => _posts.refresh(),
        3 => _playlists.refresh(),
        5 => _comments.refresh(),
        _ => Future<void>.value(),
      },
    ]);
  }

  // ---------------- 交互 ----------------

  Future<void> _toggleFollow() async {
    final p = profile;
    if (p == null || followBusy || !requireLogin(context, ref)) return;
    final u = p.user;
    setState(() {
      followBusy = true;
      profile = p.copyWith(user: u.copyWith(following: !u.following));
    });
    try {
      final api = ref.read(apiProvider);
      u.following ? await api.unfollow(u.id) : await api.follow(u.id);
      if (mounted) showToast(context, u.following ? '已取消关注' : '已关注');
    } catch (e) {
      if (mounted) {
        setState(() => profile = p);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  void _openFollows(User u, {required bool following}) {
    context.push(
      '/user/${u.id}/follows'
      '?tab=${following ? 'following' : 'followers'}'
      '&name=${Uri.encodeComponent(u.name)}',
    );
  }

  Future<void> _sendMessage() async {
    final u = profile?.user;
    if (u == null || !requireLogin(context, ref)) return;
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _MessageDialog(name: u.name),
    );
    if (res == null || !mounted) return;
    try {
      final id = await ref
          .read(apiProvider)
          .createConversation(u.id, res.$1, res.$2);
      if (!mounted) return;
      showToast(context, '私信已发送');
      context.push(id == null ? '/messages' : '/messages/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// 查询好友关系；状态未区分方向时，通过好友请求列表判断是否为对方发来。
  Future<_Friend> _friendState(IwaraApi api, String uid, String myId) async {
    final s = (await api.friendStatus(uid)).toLowerCase();
    if (s.startsWith('friend') || s == 'accepted') return _Friend.friends;
    if (s.contains('incoming') || s.contains('receiv')) return _Friend.incoming;
    if (s.contains('outgoing') || s.contains('sent')) return _Friend.outgoing;
    if (s.contains('pending') || s.contains('request')) {
      try {
        final reqs = await api.friendRequests(myId);
        if (reqs.results.any((r) => r.user.id == uid && r.target.id == myId)) {
          return _Friend.incoming;
        }
      } catch (_) {}
      return _Friend.outgoing;
    }
    return _Friend.none;
  }

  Future<void> _friendMenu() async {
    final u = profile?.user;
    if (u == null || !requireLogin(context, ref)) return;
    final me = ref.read(meProvider)!;
    final api = ref.read(apiProvider);
    final _Friend state;
    try {
      state = await _friendState(api, u.id, me.user.id);
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final (desc, options) = switch (state) {
      _Friend.none => (
        '你们还不是好友',
        [('add', Icons.person_add_alt_1_outlined, '添加好友')],
      ),
      _Friend.friends => (
        '你们已是好友',
        [('remove', Icons.person_remove_outlined, '删除好友')],
      ),
      _Friend.outgoing => (
        '已发送好友请求，等待对方确认',
        [('remove', Icons.undo, '撤回好友请求')],
      ),
      _Friend.incoming => (
        '对方向你发送了好友请求',
        [('add', Icons.check, '接受好友请求'), ('remove', Icons.close, '拒绝好友请求')],
      ),
    };
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(desc, style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (key, icon, label) in options)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, key),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (state == _Friend.friends &&
        !await confirm(
          context,
          '删除好友 ${u.name}？',
          okText: '删除',
          danger: true,
        )) {
      return;
    }
    try {
      action == 'add'
          ? await api.addFriend(u.id)
          : await api.removeFriend(u.id);
      if (!mounted) return;
      showToast(context, switch ((state, action)) {
        (_Friend.incoming, 'add') => '已添加为好友',
        (_Friend.incoming, _) => '已拒绝好友请求',
        (_Friend.friends, _) => '已删除好友',
        (_Friend.outgoing, _) => '已撤回好友请求',
        _ => '已发送好友请求',
      });
      if (state == _Friend.incoming) ref.invalidate(countsProvider);
      final p = profile;
      if (p != null &&
          (state == _Friend.incoming || state == _Friend.friends)) {
        setState(
          () => profile = p.copyWith(
            user: p.user.copyWith(
              friend: state == _Friend.incoming && action == 'add',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleBlock() async {
    final u = profile?.user;
    if (u == null || !requireLogin(context, ref)) return;
    if (!blocked &&
        !await confirm(
          context,
          '屏蔽 ${u.name}？',
          content: '屏蔽后将不再看到对方的内容，对方也无法与你互动。',
          okText: '屏蔽',
          danger: true,
        )) {
      return;
    }
    try {
      final api = ref.read(apiProvider);
      blocked ? await api.unblockUser(u.id) : await api.blockUser(u.id);
      if (!mounted) return;
      showToast(context, blocked ? '已取消屏蔽' : '已屏蔽该用户');
      setState(() => blocked = !blocked);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _onMenu(String key) async {
    final u = profile?.user;
    if (u == null) return;
    final url = IwaraUrls.profilePage(u.username);
    switch (key) {
      case 'message':
        await _sendMessage();
      case 'friend':
        await _friendMenu();
      case 'block':
        await _toggleBlock();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showToast(context, '链接已复制');
      case 'share':
        await SharePlus.instance.share(
          ShareParams(text: '${u.name}\n$url', subject: u.name),
        );
      case 'browser':
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _composeComment() async {
    if (profile == null || !requireLogin(context, ref)) return;
    final text = await showComposer(context, hint: '给 TA 留言');
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final c = await ref
          .read(apiProvider)
          .createComment(ContentType.profile, _uid, text);
      if (!mounted) return;
      showToast(context, '留言成功');
      if (c != null) {
        _comments.insert(0, c);
      } else {
        _comments.refresh();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ---------------- 构建 ----------------

  /// 头部内容高度（不含状态栏与 TabBar），随系统字体缩放。
  double _headerContentHeight(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);
    return _kCoverHeight +
        _kActionRowHeight +
        ts.scale(_kNameSize) * 1.3 +
        2 +
        ts.scale(_kUsernameSize) * 1.4 +
        4 +
        ts.scale(_kStatusSize) * 1.4 +
        8 +
        _kEntryRowHeight +
        12;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider.select((s) => s.rating), (_, _) {
      if (profile == null) return;
      _videos.refresh();
      _images.refresh();
    });
    final p = profile;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.username}')),
        body: error != null
            ? ErrorView.from(error!, onRetry: _load)
            : const LoadingView(),
      );
    }
    final me = ref.watch(meProvider);
    final isMe = me != null && me.user.id == p.user.id;
    final top = MediaQuery.paddingOf(context).top;
    const tabBar = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(text: '视频'),
        Tab(text: '图片'),
        Tab(text: '动态'),
        Tab(text: '播放列表'),
        Tab(text: '关于'),
        Tab(text: '留言'),
      ],
    );
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        // 下拉刷新放在最外层：Tab 内列表的顶部被折叠头部遮住，内部的刷新指示器不可见。
        // 只响应 Tab 内纵向列表的通知（经过 TabBarView 与外层两个 Viewport，depth 为 2）。
        body: Builder(
          builder: (context) => RefreshIndicator(
            edgeOffset: top + kToolbarHeight,
            notificationPredicate: (n) =>
                n.depth == 2 && n.metrics.axis == Axis.vertical,
            onRefresh: () => _refresh(DefaultTabController.of(context).index),
            child: _buildScrollView(p, isMe, top, tabBar),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollView(Profile p, bool isMe, double top, TabBar tabBar) {
    final u = p.user;
    return NestedScrollView(
      controller: _scroll,
      headerSliverBuilder: (context, innerScrolled) => [
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          sliver: SliverAppBar(
            pinned: true,
            expandedHeight:
                _headerContentHeight(context) + tabBar.preferredSize.height,
            forceElevated: innerScrolled,
            foregroundColor: _solidBar ? null : Colors.white,
            systemOverlayStyle: _solidBar ? null : SystemUiOverlayStyle.light,
            title: AnimatedOpacity(
              opacity: _showTitle ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(u.name),
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  if (!isMe) ...[
                    const PopupMenuItem(value: 'message', child: Text('发私信')),
                    PopupMenuItem(
                      value: 'friend',
                      child: Text(u.friend ? '好友管理' : '加好友'),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text(blocked ? '取消屏蔽' : '屏蔽用户'),
                    ),
                    const PopupMenuDivider(),
                  ],
                  const PopupMenuItem(value: 'copy', child: Text('复制主页链接')),
                  const PopupMenuItem(value: 'share', child: Text('分享')),
                  const PopupMenuItem(value: 'browser', child: Text('在浏览器中打开')),
                ],
              ),
            ],
            flexibleSpace: _CollapsingHeader(
              topPadding: top,
              child: _ProfileHeader(
                profile: p,
                topPadding: top,
                isMe: isMe,
                followBusy: followBusy,
                onFollow: _toggleFollow,
                onMessage: _sendMessage,
                onFollowing: () => _openFollows(u, following: true),
                onFollowers: () => _openFollows(u, following: false),
              ),
            ),
            bottom: tabBar,
          ),
        ),
      ],
      body: TabBarView(
        children: [
          PagedView<Video>(
            key: const PageStorageKey('profile_videos'),
            controller: _videos,
            primary: true,
            enableRefresh: false,
            layout: kVideoGridLayout,
            headerSlivers: const [_HeaderInjector()],
            emptyText: '还没有发布视频',
            emptyIcon: Icons.movie_outlined,
            itemBuilder: (context, v, _) => VideoCard(v),
          ),
          PagedView<GalleryImage>(
            key: const PageStorageKey('profile_images'),
            controller: _images,
            primary: true,
            enableRefresh: false,
            layout: kImageGridLayout,
            headerSlivers: const [_HeaderInjector()],
            emptyText: '还没有发布图片',
            emptyIcon: Icons.image_outlined,
            itemBuilder: (context, img, _) => ImageCard(img),
          ),
          PagedView<Post>(
            key: const PageStorageKey('profile_posts'),
            controller: _posts,
            primary: true,
            enableRefresh: false,
            padding: EdgeInsets.zero,
            layout: const ListLayout(separated: true),
            headerSlivers: const [_HeaderInjector()],
            emptyText: '还没有动态',
            emptyIcon: Icons.dynamic_feed_outlined,
            itemBuilder: (context, post, _) => PostTile(post),
          ),
          PagedView<Playlist>(
            key: const PageStorageKey('profile_playlists'),
            controller: _playlists,
            primary: true,
            enableRefresh: false,
            padding: const EdgeInsets.symmetric(vertical: 4),
            headerSlivers: [
              const _HeaderInjector(),
              if (isMe)
                SliverToBoxAdapter(
                  child: ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('管理我的播放列表'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      '/user/${u.id}/playlists'
                      '?name=${Uri.encodeComponent(u.name)}',
                    ),
                  ),
                ),
            ],
            emptyText: '还没有播放列表',
            emptyIcon: Icons.playlist_play,
            itemBuilder: (context, pl, _) => PlaylistTile(pl),
          ),
          _AboutTab(key: const PageStorageKey('profile_about'), profile: p),
          Column(
            children: [
              Expanded(
                child: PagedView<Comment>(
                  key: const PageStorageKey('profile_comments'),
                  controller: _comments,
                  primary: true,
                  enableRefresh: false,
                  padding: EdgeInsets.zero,
                  layout: const ListLayout(separated: true),
                  headerSlivers: const [_HeaderInjector()],
                  emptyText: '还没有留言',
                  emptyIcon: Icons.chat_bubble_outline,
                  itemBuilder: (context, c, _) => CommentTile(
                    comment: c,
                    type: ContentType.profile,
                    contentId: u.id,
                    ownerId: u.id,
                    onChanged: _comments.refresh,
                  ),
                ),
              ),
              CommentInputBar(onTap: _composeComment, hint: '给 TA 留言'),
            ],
          ),
        ],
      ),
    );
  }
}

/// 注入 NestedScrollView 头部遮挡高度，避免 Tab 内容被折叠头部挡住。
///
/// 注意：各 Tab 不使用 keep-alive（NestedScrollView 会同步滚动所有存活的内部列表），
/// 数据由页面持有的 PagingController 保留，滚动位置由 PageStorageKey 恢复。
class _HeaderInjector extends StatelessWidget {
  const _HeaderInjector();

  @override
  Widget build(BuildContext context) => SliverOverlapInjector(
    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
  );
}

/// 折叠头部：内容随滚动整体上移；封面滚出顶栏时，顶栏背景渐变为实色。
class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({required this.topPadding, required this.child});

  final double topPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (s == null) return child;
    final shrink = s.maxExtent - s.currentExtent;
    final solid = (shrink / (_kCoverHeight - kToolbarHeight)).clamp(0.0, 1.0);
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            top: -shrink,
            left: 0,
            right: 0,
            height: s.maxExtent,
            child: child,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + kToolbarHeight,
            child: IgnorePointer(
              child: ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: solid),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 主页头部：封面、头像、名字、状态、关注按钮与关注/粉丝入口。
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.topPadding,
    required this.isMe,
    required this.followBusy,
    required this.onFollow,
    required this.onMessage,
    required this.onFollowing,
    required this.onFollowers,
  });

  final Profile profile;
  final double topPadding;
  final bool isMe;
  final bool followBusy;
  final VoidCallback onFollow;
  final VoidCallback onMessage;
  final VoidCallback onFollowing;
  final VoidCallback onFollowers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final u = profile.user;
    final headerUrl = IwaraUrls.file('profileHeader', profile.header);

    final status = [
      if (u.isOnline)
        '在线'
      else if (u.seenAt != null)
        '最后活跃 ${formatAgo(u.seenAt)}',
      if (u.createdAt != null) '${formatDate(u.createdAt)} 加入',
    ].join(' · ');

    return ColoredBox(
      color: scheme.surface,
      // 内容超出时裁剪而不是报溢出（极端字体缩放下）
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      // 封面
                      SizedBox(
                        height: topPadding + _kCoverHeight,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (headerUrl != null)
                              NetImage(headerUrl, fit: BoxFit.cover)
                            else
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [scheme.primary, scheme.tertiary],
                                  ),
                                ),
                              ),
                            // 顶部阴影，保证状态栏和按钮可见
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0, 0.6],
                                  colors: [Colors.black54, Colors.transparent],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 操作按钮
                      SizedBox(
                        height: _kActionRowHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(112, 8, 12, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                IconButton.outlined(
                                  tooltip: '发私信',
                                  onPressed: onMessage,
                                  icon: const Icon(
                                    Icons.mail_outline,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                u.following
                                    ? OutlinedButton(
                                        onPressed: followBusy ? null : onFollow,
                                        child: const Text('已关注'),
                                      )
                                    : FilledButton.icon(
                                        onPressed: followBusy ? null : onFollow,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('关注'),
                                      ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 头像（压在封面底边）
                  Positioned(
                    left: 16,
                    top: topPadding + _kCoverHeight - 43,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: UserAvatar(u, size: 80),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: _kNameSize,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: u.premium
                                  ? Colors.amber.shade700
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                        if (u.premium) ...[
                          const SizedBox(width: 6),
                          _Mark(text: '会员', color: Colors.amber.shade700),
                        ],
                        if (u.creatorProgram) ...[
                          const SizedBox(width: 6),
                          _Mark(text: '创作者', color: scheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '@${u.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: _kUsernameSize,
                              height: 1.4,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                        if (!isMe && u.followedBy) ...[
                          const SizedBox(width: 6),
                          _Mark(
                            text: u.following ? '互相关注' : '关注了你',
                            color: scheme.secondary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (u.isOnline) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: _kStatusSize,
                              height: 1.4,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: _kEntryRowHeight,
                      child: Row(
                        children: [
                          _EntryButton(label: '关注', onTap: onFollowing),
                          const SizedBox(width: 8),
                          _EntryButton(label: '粉丝', onTap: onFollowers),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, height: 1.3),
    ),
  );
}

class _EntryButton extends StatelessWidget {
  const _EntryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「关于」Tab：基本信息 + 个人简介。
class _AboutTab extends StatelessWidget {
  const _AboutTab({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = profile.user;
    final body = profile.body?.trim() ?? '';
    final label = theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(k, style: label)),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
    return CustomScrollView(
      primary: true,
      slivers: [
        const _HeaderInjector(),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          sliver: SliverList.list(
            children: [
              row('昵称', u.name),
              row('用户名', '@${u.username}'),
              if (u.createdAt != null) row('注册时间', formatDateTime(u.createdAt)),
              if (u.seenAt != null)
                row('最后活跃', u.isOnline ? '在线' : formatDateTime(u.seenAt)),
              const SizedBox(height: 12),
              Text('个人简介', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (body.isEmpty)
                Text('这个人很懒，什么都没写', style: label)
              else
                RichBody(body, selectable: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// 发私信对话框，返回 (标题, 内容)。
class _MessageDialog extends StatefulWidget {
  const _MessageDialog({required this.name});

  final String name;

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('私信 ${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: '内容'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_title, _body]),
          builder: (context, _) {
            final t = _title.text.trim(), b = _body.text.trim();
            return FilledButton(
              onPressed: t.isEmpty || b.isEmpty
                  ? null
                  : () => Navigator.pop(context, (t, b)),
              child: const Text('发送'),
            );
          },
        ),
      ],
    );
  }
}
