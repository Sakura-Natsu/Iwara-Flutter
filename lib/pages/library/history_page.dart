import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../services/local_db.dart';
import '../../widgets/cards.dart';
import '../../widgets/paging.dart';

/// 观看历史（同步自网站）。
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('观看历史'),
          bottom: const TabBar(
            tabAlignment: TabAlignment.fill,
            tabs: [Tab(text: '视频'), Tab(text: '图片')],
          ),
        ),
        body: const TabBarView(children: [
          _HistoryList(type: 'video'),
          _HistoryList(type: 'image'),
        ]),
      ),
    );
  }
}

class _HistoryList extends ConsumerStatefulWidget {
  const _HistoryList({required this.type});

  final String type;

  @override
  ConsumerState<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<_HistoryList>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<HistoryEntry> controller = PagingController(
    (page) {
      final me = ref.read(meProvider);
      if (me == null) throw StateError('请先登录');
      return ref.read(apiProvider).history(me.user.id, widget.type, page: page);
    },
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isVideo = widget.type == 'video';
    return PagedView<HistoryEntry>(
      controller: controller,
      layout: isVideo ? const ListLayout() : kImageGridLayout,
      padding: isVideo ? EdgeInsets.zero : const EdgeInsets.all(8),
      emptyText: '还没有观看记录',
      emptyIcon: Icons.history,
      itemBuilder: (context, e, _) {
        if (e.video != null) {
          return _VideoHistoryTile(entry: e);
        }
        if (e.image != null) return ImageCard(e.image!);
        return const SizedBox.shrink();
      },
    );
  }
}

class _VideoHistoryTile extends StatelessWidget {
  const _VideoHistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final v = entry.video!;
    return FutureBuilder(
      future: LocalDb.instance.progress(v.id),
      builder: (context, snap) {
        var sub = '观看于 ${formatAgo(entry.createdAt)}';
        final p = snap.data;
        if (p != null) {
          final (pos, dur) = p;
          sub += ' · 看到 ${formatDuration(pos)}/${formatDuration(dur)}';
        }
        return VideoTile(v, subtitle: sub);
      },
    );
  }
}
