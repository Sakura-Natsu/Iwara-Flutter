import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/paging.dart';
import '../../widgets/states.dart';

/// 某个用户的播放列表；查看自己的列表时可新建、重命名、删除。
class UserPlaylistsPage extends ConsumerStatefulWidget {
  const UserPlaylistsPage({super.key, required this.userId, this.name});

  final String userId;
  final String? name;

  @override
  ConsumerState<UserPlaylistsPage> createState() => _UserPlaylistsPageState();
}

class _UserPlaylistsPageState extends ConsumerState<UserPlaylistsPage> {
  late final PagingController<Playlist> controller = PagingController(
    (page) => ref.read(apiProvider).playlists(widget.userId, page: page),
    dedupeKey: (p) => p.id,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = await promptText(context, '新建播放列表', hint: '名称');
    if (title == null || title.isEmpty || !mounted) return;
    try {
      await ref.read(apiProvider).createPlaylist(title);
      if (!mounted) return;
      showToast(context, '已创建「$title」');
      controller.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename(Playlist p) async {
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
      controller.updateWhere((e) => e.id == p.id, (e) => _withTitle(e, title));
      showToast(context, '已重命名');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Playlist p) async {
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
      controller.removeWhere((e) => e.id == p.id);
      showToast(context, '已删除');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// 进入播放列表详情；返回后同步第一页（详情页中可能已重命名、移除视频或删除）。
  Future<void> _open(Playlist p, bool mine) async {
    final deleted = await context.push<bool>('/playlist/${p.id}');
    if (!mounted || !mine) return;
    if (deleted == true) {
      controller.removeWhere((e) => e.id == p.id);
      return;
    }
    try {
      final res = await ref.read(apiProvider).playlists(widget.userId);
      for (final n in res.results) {
        controller.updateWhere((e) => e.id == n.id, (_) => n);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final mine = me != null && me.user.id == widget.userId;
    final name = widget.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          mine
              ? '我的播放列表'
              : (name == null || name.isEmpty ? '播放列表' : '$name 的播放列表'),
        ),
      ),
      floatingActionButton: mine
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            )
          : null,
      body: PagedView<Playlist>(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
        emptyText: mine ? '还没有播放列表，点击右下角新建' : '还没有播放列表',
        emptyIcon: Icons.playlist_play,
        itemBuilder: (context, p, _) => PlaylistTile(
          p,
          onTap: () => _open(p, mine),
          trailing: mine
              ? PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (k) => k == 'rename' ? _rename(p) : _delete(p),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

Playlist _withTitle(Playlist p, String title) => Playlist(
  id: p.id,
  title: title,
  numVideos: p.numVideos,
  user: p.user,
  thumbnailVideo: p.thumbnailVideo,
);
