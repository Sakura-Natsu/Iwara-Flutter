import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/iwara_api.dart';
import '../../api/urls.dart';
import '../../core/format.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';
import '../comments/comment_section.dart';

/// 动态详情：正文 + 评论。
class PostPage extends ConsumerStatefulWidget {
  const PostPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<PostPage> {
  Post? post;
  Object? error;
  int? commentCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final p = await ref.read(apiProvider).post(widget.id);
      if (mounted) setState(() => post = p);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  /// 下拉刷新正文，失败时仅提示。
  Future<void> _reload() async {
    try {
      final p = await ref.read(apiProvider).post(widget.id);
      if (mounted) setState(() => post = p);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _onMenu(String key) async {
    final url = IwaraUrls.postPage(widget.id);
    final title = post?.title ?? '动态';
    switch (key) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showToast(context, '链接已复制');
      case 'share':
        await SharePlus.instance.share(
          ShareParams(text: '$title\n$url', subject: title),
        );
      case 'browser':
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = post;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('动态'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('复制链接')),
                PopupMenuItem(value: 'share', child: Text('分享')),
                PopupMenuItem(value: 'browser', child: Text('在浏览器中打开')),
              ],
            ),
          ],
          bottom: p == null
              ? null
              : TabBar(
                  tabs: [
                    const Tab(text: '正文'),
                    Tab(text: '评论 ${commentCount ?? ''}'.trim()),
                  ],
                ),
        ),
        body: p == null
            ? (error != null
                  ? ErrorView.from(error!, onRetry: _load)
                  : const LoadingView())
            : TabBarView(
                children: [
                  _PostBody(post: p, onRefresh: _reload),
                  CommentSection(
                    type: ContentType.post,
                    id: p.id,
                    ownerId: p.user?.id,
                    onCountChanged: (n) {
                      if (mounted && n != commentCount) {
                        setState(() => commentCount = n);
                      }
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _PostBody extends StatelessWidget {
  const _PostBody({required this.post, required this.onRefresh});

  final Post post;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = post.user;
    final body = post.body?.trim() ?? '';
    void openUser() {
      if (user != null) context.push('/profile/${user.username}');
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('post_body'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SelectableText(
            post.title.isEmpty ? '无标题' : post.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // 作者
          Row(
            children: [
              UserAvatar(user, size: 40, onTap: user == null ? null : openUser),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: user == null ? null : openUser,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? '已注销用户',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: user?.premium == true
                              ? Colors.amber.shade700
                              : null,
                        ),
                      ),
                      if (user != null)
                        Text(
                          '@${user.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: theme.textTheme.labelMedium!.copyWith(
              color: theme.hintColor,
            ),
            child: Wrap(
              spacing: 12,
              children: [
                if (post.createdAt != null)
                  Text(formatDateTime(post.createdAt)),
                Text('${formatCount(post.numViews)} 浏览'),
              ],
            ),
          ),
          const Divider(height: 24),
          if (body.isEmpty)
            Text('（无正文）', style: TextStyle(color: theme.hintColor))
          else
            RichBody(body, selectable: true),
        ],
      ),
    );
  }
}
