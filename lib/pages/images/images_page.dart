import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/settings.dart';
import '../../models/common.dart';
import '../../models/image.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/paging.dart';
import '../videos/content_filter.dart';

class ImagesPage extends ConsumerWidget {
  const ImagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(imageFilterProvider);
    final rating = ref.watch(settingsProvider).rating;
    final filtered = !filter.isEmpty || rating != Rating.all;
    return DefaultTabController(
      length: SortType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('图片'),
          actions: [
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => context.push('/search?type=images'),
            ),
            IconButton(
              tooltip: '筛选',
              icon: Badge(
                isLabelVisible: filtered,
                smallSize: 8,
                child: const Icon(Icons.tune),
              ),
              onPressed: () => showFilterSheet(context, ref, imageFilterProvider),
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
            for (final s in SortType.values) ImageFeed(key: PageStorageKey(s), sort: s),
          ],
        ),
      ),
    );
  }
}

/// 某个排序下的图片流，响应筛选与分级变化。
class ImageFeed extends ConsumerStatefulWidget {
  const ImageFeed({super.key, required this.sort, this.subscribed = false});

  final SortType sort;
  final bool subscribed;

  @override
  ConsumerState<ImageFeed> createState() => _ImageFeedState();
}

class _ImageFeedState extends ConsumerState<ImageFeed>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<GalleryImage> controller =
      PagingController(_fetch, dedupeKey: (img) => img.id);

  @override
  bool get wantKeepAlive => true;

  Future<PageResult<GalleryImage>> _fetch(int page) {
    final filter =
        widget.subscribed ? const ContentFilter() : ref.read(imageFilterProvider);
    return ref.read(apiProvider).images(
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
    ref.listen(imageFilterProvider, (_, _) {
      if (!widget.subscribed) controller.refresh();
    });
    ref.listen(settingsProvider.select((s) => s.rating), (_, _) {
      controller.refresh();
    });
    return PagedView<GalleryImage>(
      controller: controller,
      layout: kImageGridLayout,
      itemBuilder: (context, img, _) => ImageCard(img),
    );
  }
}
