import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/urls.dart';
import '../../models/social.dart';
import '../../models/video.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/states.dart';

/// 播放列表详情。所有者可移除视频、重命名、删除（删除后 pop(true)）。
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  Playlist? playlist;

  late final PagingController<Video> controller = PagingController((
    page,
  ) async {
    final (p, res) = await ref
        .read(apiProvider)
        .playlist(widget.id, page: page);
    if (page == 0 && mounted) setState(() => playlist = p);
    return res;
  }, dedupeKey: (v) => v.id);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Playlist _copy(Playlist p, {String? title, int? numVideos}) => Playlist(
    id: p.id,
    title: title ?? p.title,
    numVideos: numVideos ?? p.numVideos,
    user: p.user,
    thumbnailVideo: p.thumbnailVideo,
  );

  Future<void> _remove(Video v) async {
    try {
      await ref.read(apiProvider).removeFromPlaylist(widget.id, v.id);
      if (!mounted) return;
      controller.removeWhere((e) => e.id == v.id);
      final p = playlist;
      if (p != null) {
        setState(
          () => playlist = _copy(
            p,
            numVideos: (p.numVideos - 1).clamp(0, 1 << 30),
          ),
        );
      }
      showToast(context, '已从播放列表移除');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename() async {
    final p = playlist;
    if (p == null) return;
    final title = await promptText(
      context,
      '重命名播放列表',
      initial: p.title,
      hint: '名称',
    );
    if (title == null || title.isEmpty || title == p.title || !mounted) return;
    try {
      await ref.read(apiProvider).renamePlaylist(p.id, title);
      if (!mounted) return;
      setState(() => playlist = _copy(playlist ?? p, title: title));
      showToast(context, '已重命名');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete() async {
    final p = playlist;
    if (p == null) return;
    if (!await confirm(
      context,
      '删除播放列表「${p.title}」？',
      content: '删除后无法恢复，列表中的视频不受影响。',
      okText: '删除',
      danger: true,
    )) {
      return;
    }
    try {
      await ref.read(apiProvider).deletePlaylist(p.id);
      if (!mounted) return;
      showToast(context, '已删除播放列表');
      context.pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _onMenu(String key) async {
    final url = IwaraUrls.playlistPage(widget.id);
    final title = playlist?.title ?? '播放列表';
    switch (key) {
      case 'rename':
        await _rename();
      case 'delete':
        await _delete();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showToast(context, '链接已复制');
      case 'share':
        await SharePlus.instance.share(
          ShareParams(text: '$title\n$url', subject: title),
        );
      case 'browser':
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    final me = ref.watch(meProvider);
    final mine = p?.user != null && me != null && p!.user!.id == me.user.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.title ?? '播放列表'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMenu,
            itemBuilder: (_) => [
              if (mine) ...const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除播放列表')),
                PopupMenuDivider(),
              ],
              const PopupMenuItem(value: 'copy', child: Text('复制链接')),
              const PopupMenuItem(value: 'share', child: Text('分享')),
              const PopupMenuItem(value: 'browser', child: Text('在浏览器中打开')),
            ],
          ),
        ],
      ),
      body: PagedView<Video>(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 8),
        emptyText: '播放列表是空的',
        emptyIcon: Icons.playlist_play,
        headerSlivers: [
          if (p != null) SliverToBoxAdapter(child: _Header(playlist: p)),
        ],
        itemBuilder: (context, v, _) => VideoTile(
          v,
          trailing: mine
              ? PopupMenuButton<String>(
                  tooltip: '更多',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (_) => _remove(v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'remove', child: Text('从播放列表移除')),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

/// 头部：封面、标题、所有者、视频数。
class _Header extends StatelessWidget {
  const _Header({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = playlist.user;
    final cover = playlist.thumbnailVideo == null
        ? null
        : IwaraUrls.videoThumbnail(playlist.thumbnailVideo!);
    void openUser() {
      if (user != null) context.push('/profile/${user.username}');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: NetImage(
                    cover,
                    borderRadius: BorderRadius.circular(8),
                    placeholderIcon: Icons.playlist_play,
                    memCacheWidth: 400,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.numVideos} 个视频',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (user != null) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: openUser,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    UserAvatar(user, size: 32),
                    const SizedBox(width: 8),
                    Expanded(
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.hintColor),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }
}
