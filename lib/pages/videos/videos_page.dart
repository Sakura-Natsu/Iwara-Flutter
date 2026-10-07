import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/settings.dart';
import '../../models/common.dart';
import '../../models/video.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/paging.dart';
import 'content_filter.dart';

class VideosPage extends ConsumerWidget {
  const VideosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(videoFilterProvider);
    final rating = ref.watch(settingsProvider).rating;
    final filtered = !filter.isEmpty || rating != Rating.all;
    return DefaultTabController(
      length: SortType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Iwara',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          actions: [
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => context.push('/search?type=videos'),
            ),
            IconButton(
              tooltip: '筛选',
              icon: Badge(
                isLabelVisible: filtered,
                smallSize: 8,
                child: const Icon(Icons.tune),
              ),
              onPressed: () => showFilterSheet(context, ref, videoFilterProvider),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final s in SortType.values) Tab(text: s.label)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final s in SortType.values) VideoFeed(key: PageStorageKey(s), sort: s),
          ],
        ),
      ),
    );
  }
}

/// 某个排序下的视频流，响应筛选与分级变化。
class VideoFeed extends ConsumerStatefulWidget {
  const VideoFeed({super.key, required this.sort, this.subscribed = false});

  final SortType sort;
  final bool subscribed;

  @override
  ConsumerState<VideoFeed> createState() => _VideoFeedState();
}

class _VideoFeedState extends ConsumerState<VideoFeed>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<Video> controller =
      PagingController(_fetch, dedupeKey: (v) => v.id);

  @override
  bool get wantKeepAlive => true;

  Future<PageResult<Video>> _fetch(int page) {
    final filter =
        widget.subscribed ? const ContentFilter() : ref.read(videoFilterProvider);
    return ref.read(apiProvider).videos(
          sort: widget.sort.value,
          rating: ref.read(settingsProvider).rating,
          page: page,
          tags: filter.tags,
          date: filter.date,
          subscribed: widget.subscribed,
        );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(videoFilterProvider, (_, _) {
      if (!widget.subscribed) controller.refresh();
    });
    ref.listen(settingsProvider.select((s) => s.rating), (_, _) {
      controller.refresh();
    });
    return PagedView<Video>(
      controller: controller,
      layout: kVideoGridLayout,
      itemBuilder: (context, v, _) => VideoCard(v),
    );
  }
}
