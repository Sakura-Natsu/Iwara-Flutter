import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/social.dart';
import '../../widgets/net_image.dart';

/// 动态列表条目（用户主页、搜索结果）。
class PostTile extends StatelessWidget {
  const PostTile(this.post, {super.key, this.showUser = false, this.onTap});

  final Post post;

  /// 是否显示作者（用户主页内无需显示）。
  final bool showUser;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = post.user;
    final preview = plainPreview(post.body);
    final meta = [
      if (showUser && user != null) user.name,
      formatAgo(post.createdAt),
      '${formatCount(post.numViews)} 浏览',
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: onTap ?? () => context.push('/post/${post.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showUser) ...[
              UserAvatar(user, size: 36),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title.isEmpty ? '无标题' : post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 粗略去掉 Markdown 标记，生成单行预览文本。
String plainPreview(String? body, {int maxLength = 200}) {
  if (body == null || body.isEmpty) return '';
  var s = body
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // 图片
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      ) // 链接
      .replaceAll(RegExp(r'[#>*_`~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > maxLength) s = s.substring(0, maxLength);
  return s;
}
