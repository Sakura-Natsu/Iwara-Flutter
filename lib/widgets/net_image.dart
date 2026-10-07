import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/urls.dart';
import '../models/user.dart';

class NetImage extends StatefulWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholderIcon = Icons.image_outlined,
    this.borderRadius,
    this.memCacheWidth,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final IconData placeholderIcon;
  final BorderRadius? borderRadius;
  final int? memCacheWidth;

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  /// 失败后清除缓存重试的次数（缓存里可能存了被截断/损坏的文件）。
  int _retries = 0;

  void _retry() {
    final url = widget.url;
    if (url == null) return;
    CachedNetworkImage.evictFromCache(url);
    if (mounted) setState(() => _retries++);
  }

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _retries = 0;
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget fallback({bool tappable = false}) => GestureDetector(
          onTap: tappable ? _retry : null,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.placeholderIcon,
                color: Theme.of(context).hintColor),
          ),
        );
    final url = widget.url;
    Widget child = url == null
        ? fallback()
        : CachedNetworkImage(
            key: ValueKey('$url#$_retries'),
            imageUrl: url,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            memCacheWidth: widget.memCacheWidth,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => Container(color: bg),
            errorWidget: (_, _, _) {
              // 首次失败自动清缓存重试一次，之后点按可再试
              if (_retries == 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _retry());
              }
              return fallback(tappable: true);
            },
          );
    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar(this.user, {super.key, this.size = 36, this.onTap});

  final User? user;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = IwaraUrls.avatar(user);
    final scheme = Theme.of(context).colorScheme;
    final initial = (user?.name.isNotEmpty ?? false)
        ? user!.name.characters.first.toUpperCase()
        : '?';
    final letter = Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(initial,
          style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w600)),
    );
    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? letter
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).round(),
                errorWidget: (_, _, _) {
                  CachedNetworkImage.evictFromCache(url);
                  return letter;
                },
              ),
      ),
    );
    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }
}
