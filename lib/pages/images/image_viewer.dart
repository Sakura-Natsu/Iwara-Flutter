import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../api/urls.dart';
import '../../models/common.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import 'image_saver.dart';

/// 打开全屏图片查看器。[onPageChanged] 用于同步详情页的翻页位置。
Future<void> showImageViewer(
  BuildContext context, {
  required List<IwaraFile> files,
  int initialIndex = 0,
  String? heroPrefix,
  ValueChanged<int>? onPageChanged,
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => ImageViewerPage(
      files: files,
      initialIndex: initialIndex,
      heroPrefix: heroPrefix,
      onPageChanged: onPageChanged,
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

/// 全屏查看器：黑底、可缩放、左右滑动，顶部显示页码与保存按钮。
class ImageViewerPage extends ConsumerStatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.files,
    this.initialIndex = 0,
    this.heroPrefix,
    this.onPageChanged,
  });

  final List<IwaraFile> files;
  final int initialIndex;

  /// 与详情页图片共享的 Hero tag 前缀，为 null 时不使用 Hero 动画。
  final String? heroPrefix;
  final ValueChanged<int>? onPageChanged;

  @override
  ConsumerState<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<ImageViewerPage> {
  late final PageController controller =
      PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;
  bool showBar = true;
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || widget.files.isEmpty) return;
    final f = widget.files[index];
    setState(() => saving = true);
    try {
      if (!await ensureGalleryAccess()) {
        if (mounted) showToast(context, '没有相册权限，无法保存');
        return;
      }
      if (!mounted) return;
      showToast(context, '正在保存原图…');
      await saveOriginalToGallery(ref.read(apiClientProvider), f);
      if (mounted) showToast(context, '已保存到相册');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  PhotoViewGalleryPageOptions _page(BuildContext context, int i) {
    final f = widget.files[i];
    final url = IwaraUrls.file('large', f);
    final hero = widget.heroPrefix == null
        ? null
        : PhotoViewHeroAttributes(tag: '${widget.heroPrefix}${f.id}');
    const broken = Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
    );
    if (url == null) {
      return PhotoViewGalleryPageOptions.customChild(
        child: broken,
        heroAttributes: hero,
        disableGestures: true,
      );
    }
    return PhotoViewGalleryPageOptions(
      imageProvider: CachedNetworkImageProvider(url),
      heroAttributes: hero,
      minScale: PhotoViewComputedScale.contained,
      initialScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      onTapUp: (_, _, _) => setState(() => showBar = !showBar),
      errorBuilder: (_, _, _) => broken,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.files.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PhotoViewGallery.builder(
              itemCount: total,
              pageController: controller,
              builder: _page,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (_, event) {
                final expected = event?.expectedTotalBytes;
                return Center(
                  child: CircularProgressIndicator(
                    color: Colors.white70,
                    value: expected == null || expected <= 0
                        ? null
                        : event!.cumulativeBytesLoaded / expected,
                  ),
                );
              },
              onPageChanged: (i) {
                setState(() => index = i);
                widget.onPageChanged?.call(i);
              },
            ),
            // 顶部栏：返回、页码、保存
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: !showBar,
                child: AnimatedOpacity(
                  opacity: showBar ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 8, 12),
                        child: Row(children: [
                          IconButton(
                            tooltip: '返回',
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            total == 0 ? '0/0' : '${index + 1}/$total',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white54,
                            ),
                            onPressed: saving || total == 0 ? null : _save,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white70),
                                  )
                                : const Icon(Icons.download_outlined),
                            label: const Text('保存'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
