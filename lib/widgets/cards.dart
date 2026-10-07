import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/urls.dart';
import '../core/format.dart';
import '../models/image.dart';
import '../models/social.dart';
import '../models/video.dart';
import 'net_image.dart';
import 'paging.dart';

/// 网格视频卡片。
class VideoCard extends StatelessWidget {
  const VideoCard(this.video, {super.key, this.onLongPress, this.onTap});

  final Video video;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap ?? () => context.push('/video/${video.id}', extra: video),
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(IwaraUrls.videoThumbnail(video),
                      memCacheWidth: 480,
                      placeholderIcon: Icons.movie_outlined),
                  const _BottomShade(),
                  if (video.isR18)
                    const Positioned(top: 6, left: 6, child: R18Badge()),
                  if (video.isPrivate)
                    const Positioned(
                        top: 6, right: 6, child: _Badge(text: '私密')),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 4,
                    child: DefaultTextStyle(
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, height: 1.2),
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded,
                              size: 14, color: Colors.white),
                          Text(formatCount(video.numViews)),
                          const SizedBox(width: 6),
                          const Icon(Icons.favorite_rounded,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(formatCount(video.numLikes)),
                          const Spacer(),
                          if (video.isExternal)
                            const Icon(Icons.link, size: 14, color: Colors.white)
                          else
                            Text(formatSeconds(video.durationSeconds)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${video.user?.name ?? ''} · ${formatAgo(video.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 横向列表样式视频条目（相关推荐、播放列表、历史）。
class VideoTile extends StatelessWidget {
  const VideoTile(this.video,
      {super.key, this.trailing, this.subtitle, this.onTap, this.onLongPress});

  final Video video;
  final Widget? trailing;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap ?? () => context.push('/video/${video.id}', extra: video),
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(IwaraUrls.videoThumbnail(video),
                          memCacheWidth: 400,
                          placeholderIcon: Icons.movie_outlined),
                      if (video.isR18)
                        const Positioned(top: 4, left: 4, child: R18Badge()),
                      if (video.durationSeconds != null)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: _Badge(
                              text: formatSeconds(video.durationSeconds)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 150 * 9 / 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Text(video.user?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.hintColor)),
                    Text(
                      subtitle ??
                          '${formatCount(video.numViews)} 播放 · ${formatAgo(video.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 图片卡片（瀑布网格使用固定比例）。
class ImageCard extends StatelessWidget {
  const ImageCard(this.image, {super.key, this.onTap});

  final GalleryImage image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap ?? () => context.push('/image/${image.id}', extra: image),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(IwaraUrls.imageThumbnail(image), memCacheWidth: 480),
                  const _BottomShade(),
                  if (image.isR18)
                    const Positioned(top: 6, left: 6, child: R18Badge()),
                  if (image.numImages > 1)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _Badge(
                          text: '${image.numImages}',
                          icon: Icons.photo_library_outlined),
                    ),
                  Positioned(
                    left: 6,
                    bottom: 4,
                    child: Row(children: [
                      const Icon(Icons.visibility_outlined,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 2),
                      Text(formatCount(image.numViews),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                      const SizedBox(width: 6),
                      const Icon(Icons.favorite_rounded,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 2),
                      Text(formatCount(image.numLikes),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: Text(image.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${image.user?.name ?? ''} · ${formatAgo(image.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放列表卡片。
class PlaylistTile extends StatelessWidget {
  const PlaylistTile(this.playlist, {super.key, this.onTap, this.trailing});

  final Playlist playlist;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final thumb = playlist.thumbnailVideo == null
        ? null
        : IwaraUrls.videoThumbnail(playlist.thumbnailVideo!);
    return ListTile(
      onTap: onTap ?? () => context.push('/playlist/${playlist.id}'),
      leading: SizedBox(
        width: 96,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            NetImage(thumb,
                borderRadius: BorderRadius.circular(6),
                placeholderIcon: Icons.playlist_play),
            Positioned(
              right: 3,
              bottom: 3,
              child: _Badge(
                  text: '${playlist.numVideos}', icon: Icons.playlist_play),
            ),
          ]),
        ),
      ),
      title: Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${playlist.user?.name ?? ''} · ${playlist.numVideos} 个视频',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }
}

class R18Badge extends StatelessWidget {
  const R18Badge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('R-18',
            style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                height: 1.3)),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10, height: 1.3)),
        ]),
      );
}

class _BottomShade extends StatelessWidget {
  const _BottomShade();

  @override
  Widget build(BuildContext context) => const Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 36,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
      );
}

/// 视频网格布局参数（标题两行 + 作者行）。
const kVideoGridLayout =
    GridLayout(itemWidth: 190, aspectRatio: 16 / 9, extraHeight: 62);

/// 图片网格布局参数（正方形缩略图 + 两行文字）。
const kImageGridLayout =
    GridLayout(itemWidth: 160, aspectRatio: 1, extraHeight: 44);
