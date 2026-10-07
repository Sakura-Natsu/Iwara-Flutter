import 'dart:math' as math;

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
import '../../models/image.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/net_image.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';
import '../comments/comment_section.dart';
import '../videos/content_filter.dart';
import 'image_saver.dart';
import 'image_viewer.dart';

class ImageDetailPage extends ConsumerStatefulWidget {
  const ImageDetailPage({super.key, required this.id, this.initial});

  final String id;
  final GalleryImage? initial;

  @override
  ConsumerState<ImageDetailPage> createState() => _ImageDetailPageState();
}

class _ImageDetailPageState extends ConsumerState<ImageDetailPage> {
  final _pageController = PageController();

  /// 每个页面实例唯一的 Hero 前缀，避免同一图集重复打开时 tag 冲突。
  late final String _heroPrefix = 'image-${identityHashCode(this)}-';

  GalleryImage? image;

  /// 详情接口是否已返回（列表传入的 initial 不含点赞/关注状态与文件列表）。
  bool loaded = false;
  Object? loadError;
  List<GalleryImage>? related;
  int? commentCount;
  int page = 0;
  bool likeBusy = false;
  bool followBusy = false;

  /// 批量保存进度（已处理张数），null 表示未在保存。
  int? savedCount;

  @override
  void initState() {
    super.initState();
    image = widget.initial;
    commentCount = widget.initial?.numComments;
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ---------------- 数据加载 ----------------

  Future<void> _load() async {
    if (loadError != null) setState(() => loadError = null);
    try {
      final img = await ref.read(apiProvider).image(widget.id);
      if (!mounted) return;
      setState(() {
        image = img;
        loaded = true;
        commentCount = img.numComments;
      });
      _loadRelated();
    } catch (e) {
      if (mounted) setState(() => loadError = e);
    }
  }

  Future<void> _loadRelated() async {
    try {
      final list = await ref.read(apiProvider).relatedImages(widget.id);
      if (mounted) {
        setState(() => related = list.where((e) => e.id != widget.id).toList());
      }
    } catch (_) {
      if (mounted) setState(() => related = const []);
    }
  }

  // ---------------- 交互 ----------------

  Future<void> _toggleLike() async {
    final img = image;
    if (img == null || !loaded || likeBusy || !requireLogin(context, ref)) {
      return;
    }
    setState(() {
      likeBusy = true;
      image = img.copyWith(
        liked: !img.liked,
        numLikes: img.numLikes + (img.liked ? -1 : 1),
      );
    });
    try {
      final api = ref.read(apiProvider);
      img.liked
          ? await api.unlike(ContentType.image, img.id)
          : await api.like(ContentType.image, img.id);
      if (mounted) showToast(context, img.liked ? '已取消收藏' : '已收藏');
    } catch (e) {
      if (mounted) {
        setState(() => image = img);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => likeBusy = false);
    }
  }

  Future<void> _toggleFollow() async {
    final img = image;
    final u = img?.user;
    if (img == null ||
        u == null ||
        !loaded ||
        followBusy ||
        !requireLogin(context, ref)) {
      return;
    }
    setState(() {
      followBusy = true;
      image = img.copyWith(user: u.copyWith(following: !u.following));
    });
    try {
      final api = ref.read(apiProvider);
      u.following ? await api.unfollow(u.id) : await api.follow(u.id);
    } catch (e) {
      if (mounted) {
        setState(() => image = img);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  /// 逐张下载原图保存到相册。
  Future<void> _saveAll() async {
    final img = image;
    if (img == null || savedCount != null) return;
    final files = img.files;
    if (files.isEmpty) {
      showToast(context, loaded ? '没有可保存的图片' : '图片尚未加载完成');
      return;
    }
    if (!await ensureGalleryAccess()) {
      if (mounted) showToast(context, '没有相册权限，无法保存');
      return;
    }
    if (!mounted) return;
    final client = ref.read(apiClientProvider);
    final total = files.length;
    setState(() => savedCount = 0);
    var ok = 0;
    Object? lastError;
    for (var i = 0; i < total; i++) {
      if (mounted) showToast(context, '正在保存 ${i + 1}/$total…');
      try {
        await saveOriginalToGallery(client, files[i]);
        ok++;
      } catch (e) {
        lastError = e;
      }
      if (mounted) setState(() => savedCount = i + 1);
    }
    if (!mounted) return;
    setState(() => savedCount = null);
    if (ok == total) {
      showToast(context, total == 1 ? '已保存到相册' : '已保存 $total 张图片到相册');
    } else {
      final reason = ApiException.from(lastError!).message;
      showToast(
        context,
        ok == 0 ? '保存失败：$reason' : '已保存 $ok 张，${total - ok} 张失败：$reason',
      );
    }
  }

  void _share() {
    final title = image?.title ?? '';
    final url = IwaraUrls.imagePage(widget.id);
    SharePlus.instance.share(
      ShareParams(
        text: title.isEmpty ? url : '$title\n$url',
        subject: title.isEmpty ? null : title,
      ),
    );
  }

  Future<void> _onMenu(String key) async {
    final url = IwaraUrls.imagePage(widget.id);
    switch (key) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showToast(context, '链接已复制');
      case 'browser':
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      case 'share':
        _share();
    }
  }

  void _openViewer(int index) {
    final files = image?.files ?? const [];
    if (files.isEmpty) return;
    showImageViewer(
      context,
      files: files,
      initialIndex: index,
      heroPrefix: _heroPrefix,
      onPageChanged: (i) {
        // 同步详情页翻页位置，返回时 Hero 动画能对上
        if (_pageController.hasClients) _pageController.jumpToPage(i);
      },
    );
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final img = image;
    final title = img?.title ?? '';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title.isEmpty ? '图片' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('复制链接')),
                PopupMenuItem(value: 'browser', child: Text('在浏览器中打开')),
                PopupMenuItem(value: 'share', child: Text('分享')),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: '详情'),
              Tab(text: '评论 ${commentCount ?? ''}'),
            ],
          ),
        ),
        body: img == null
            ? (loadError != null
                  ? ErrorView.from(loadError!, onRetry: _load)
                  : const LoadingView())
            : TabBarView(
                children: [
                  _KeepAlive(child: _detailTab(img)),
                  CommentSection(
                    type: ContentType.image,
                    id: widget.id,
                    ownerId: img.user?.id,
                    onCountChanged: (n) {
                      if (mounted && n != commentCount) {
                        setState(() => commentCount = n);
                      }
                    },
                  ),
                ],
              ),
      ),
    );
  }

  /// 图片翻页区：按第一张图的宽高比定高，最高约屏幕 60%。
  Widget _gallery(GalleryImage img) {
    final files = img.files;
    final size = MediaQuery.sizeOf(context);
    final ratio =
        (files.isNotEmpty
            ? files.first.aspectRatio
            : img.thumbnail?.aspectRatio) ??
        1;
    // 窗口很矮（分屏/小窗）时上界可能小于 160，先取 max 避免 clamp 抛异常
    final double height = (size.width / ratio)
        .clamp(160.0, math.max(160.0, size.height * 0.6))
        .toDouble();

    if (files.isEmpty) {
      // 详情尚未返回时先显示缩略图
      return SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(IwaraUrls.imageThumbnail(img), fit: BoxFit.contain),
            if (!loaded && loadError == null)
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
          ],
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: files.length,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (_, i) {
              final f = files[i];
              return GestureDetector(
                onTap: () => _openViewer(i),
                child: Hero(
                  tag: '$_heroPrefix${f.id}',
                  child: NetImage(
                    IwaraUrls.file('large', f),
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          if (files.length > 1)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${page + 1}/${files.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailTab(GalleryImage img) {
    final theme = Theme.of(context);
    final user = img.user;
    final me = ref.watch(meProvider);
    final isMe = me != null && user?.id == me.user.id;
    final imageCount = img.files.isNotEmpty ? img.files.length : img.numImages;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ColoredBox(color: Colors.black, child: _gallery(img)),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loadError != null)
                  _LoadErrorBar(error: loadError!, onRetry: _load),
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
                                onPressed: followBusy || !loaded
                                    ? null
                                    : _toggleFollow,
                                child: const Text('已关注'),
                              )
                            : FilledButton.icon(
                                onPressed: followBusy || !loaded
                                    ? null
                                    : _toggleFollow,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('关注'),
                              ),
                    ],
                  ),
                const SizedBox(height: 12),
                SelectableText(
                  img.title,
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
                      if (img.isR18) const R18Badge(),
                      Text('${formatCount(img.numViews)} 浏览'),
                      if (imageCount > 1) Text('$imageCount 张'),
                      Text(formatDateTime(img.createdAt)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _actions(img),
                if ((img.body ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _Description(text: img.body!),
                ],
                if (img.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in img.tags)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(t.id),
                          onPressed: () {
                            ref
                                .read(imageFilterProvider.notifier)
                                .set(ContentFilter(tags: [t.id]));
                            context.go('/images');
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text('相关图片', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (related == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: loadError != null && !loaded
                  ? const SizedBox.shrink()
                  : const LoadingView(),
            ),
          )
        else if (related!.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: EmptyView(text: '暂无相关图片'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: _relatedGrid(related!),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// 相关图片小网格（2~3 列）。
  Widget _relatedGrid(List<GalleryImage> list) {
    const spacing = 8.0;
    return SliverLayoutBuilder(
      builder: (_, constraints) {
        final width = constraints.crossAxisExtent;
        final cols = (width / 120).floor().clamp(2, 6);
        final itemW = (width - spacing * (cols - 1)) / cols;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: itemW + kImageGridLayout.extraHeight,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => ImageCard(list[i]),
        );
      },
    );
  }

  Widget _actions(GalleryImage img) {
    final saving = savedCount != null;
    final total = img.files.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _ActionButton(
          icon: img.liked ? Icons.favorite : Icons.favorite_border,
          color: img.liked ? Colors.pinkAccent : null,
          label: formatCount(img.numLikes),
          onTap: loaded ? _toggleLike : null,
        ),
        _ActionButton(
          icon: saving ? Icons.downloading : Icons.download_outlined,
          label: saving ? '$savedCount/$total' : (total > 1 ? '下载全部' : '下载'),
          onTap: saving || total == 0 ? null : _saveAll,
        ),
        _ActionButton(icon: Icons.share_outlined, label: '分享', onTap: _share),
      ],
    );
  }
}

/// 详情加载失败提示条（已有列表数据时显示）。
class _LoadErrorBar extends StatelessWidget {
  const _LoadErrorBar({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '详情加载失败：${ApiException.from(error).message}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
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

/// 让 TabBarView 中的详情页保持状态（滚动位置、翻页位置）。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
