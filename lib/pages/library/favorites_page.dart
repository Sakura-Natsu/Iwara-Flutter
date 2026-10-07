import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/image.dart';
import '../../models/video.dart';
import '../../providers.dart';
import '../../widgets/cards.dart';
import '../../widgets/paging.dart';

/// 我的收藏（点赞过的视频与图片）。
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的收藏'),
          bottom: const TabBar(
            tabAlignment: TabAlignment.fill,
            tabs: [Tab(text: '视频'), Tab(text: '图片')],
          ),
        ),
        body: const TabBarView(children: [_FavVideos(), _FavImages()]),
      ),
    );
  }
}

class _FavVideos extends ConsumerStatefulWidget {
  const _FavVideos();

  @override
  ConsumerState<_FavVideos> createState() => _FavVideosState();
}

class _FavVideosState extends ConsumerState<_FavVideos>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<Video> controller = PagingController(
    (page) => ref.read(apiProvider).favoriteVideos(page: page),
    dedupeKey: (v) => v.id,
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
    return PagedView<Video>(
      controller: controller,
      layout: kVideoGridLayout,
      emptyText: '还没有收藏视频',
      emptyIcon: Icons.favorite_border,
      itemBuilder: (_, v, _) => VideoCard(v),
    );
  }
}

class _FavImages extends ConsumerStatefulWidget {
  const _FavImages();

  @override
  ConsumerState<_FavImages> createState() => _FavImagesState();
}

class _FavImagesState extends ConsumerState<_FavImages>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<GalleryImage> controller = PagingController(
    (page) => ref.read(apiProvider).favoriteImages(page: page),
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
    return PagedView<GalleryImage>(
      controller: controller,
      layout: kImageGridLayout,
      emptyText: '还没有收藏图片',
      emptyIcon: Icons.favorite_border,
      itemBuilder: (_, i, _) => ImageCard(i),
    );
  }
}
