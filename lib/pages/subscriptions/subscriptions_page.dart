import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/settings.dart';
import '../../models/image.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/paging.dart';
import '../../widgets/states.dart';
import '../videos/videos_page.dart';

/// 关注的作者发布的新视频 / 新图片。
class SubscriptionsPage extends ConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final loading = ref.watch(authProvider).isLoading;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('关注动态'),
          bottom: me == null
              ? null
              : const TabBar(
                  tabAlignment: TabAlignment.fill,
                  tabs: [Tab(text: '视频'), Tab(text: '图片')],
                ),
        ),
        body: me == null
            ? (loading
                ? const LoadingView()
                : EmptyView(
                    text: '登录后查看关注作者的最新作品',
                    icon: Icons.subscriptions_outlined,
                    action: FilledButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('去登录'),
                    ),
                  ))
            : const TabBarView(children: [
                VideoFeed(sort: SortType.date, subscribed: true),
                _SubscribedImages(),
              ]),
      ),
    );
  }
}

class _SubscribedImages extends ConsumerStatefulWidget {
  const _SubscribedImages();

  @override
  ConsumerState<_SubscribedImages> createState() => _SubscribedImagesState();
}

class _SubscribedImagesState extends ConsumerState<_SubscribedImages>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<GalleryImage> controller = PagingController(
    (page) => ref.read(apiProvider).images(
          sort: 'date',
          rating: ref.read(settingsProvider).rating,
          page: page,
          subscribed: true,
        ),
    dedupeKey: (i) => i.id,
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
    ref.listen(settingsProvider.select((s) => s.rating), (_, _) {
      controller.refresh();
    });
    return PagedView<GalleryImage>(
      controller: controller,
      layout: kImageGridLayout,
      emptyText: '关注的作者还没有发布图片',
      itemBuilder: (_, img, _) => ImageCard(img),
    );
  }
}
