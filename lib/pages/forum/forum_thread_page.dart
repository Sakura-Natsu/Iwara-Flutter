import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/urls.dart';
import '../../core/format.dart';
import '../../models/common.dart';
import '../../models/forum.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';
import '../comments/comment_section.dart' show CommentInputBar, requireLogin;
import 'forum_reply_sheet.dart';
import 'forum_widgets.dart';

/// 论坛主题详情：楼层列表 + 底部回复栏。
class ForumThreadPage extends ConsumerStatefulWidget {
  const ForumThreadPage(
      {super.key, required this.section, required this.threadId});

  final String section;
  final String threadId;

  @override
  ConsumerState<ForumThreadPage> createState() => _ForumThreadPageState();
}

class _ForumThreadPageState extends ConsumerState<ForumThreadPage> {
  late final PagingController<ForumPost> controller =
      PagingController(_fetch, dedupeKey: (p) => p.id);

  /// 回复草稿，关闭回复面板后保留。
  final _draft = TextEditingController();

  ForumThread? _thread;

  String get _url =>
      IwaraUrls.forumThreadPage(widget.section, widget.threadId);

  Future<PageResult<ForumPost>> _fetch(int page) async {
    final res = await ref
        .read(apiProvider)
        .forumThread(widget.section, widget.threadId, page: page);
    if (page == 0 && mounted) setState(() => _thread = res.thread);
    return PageResult(
      results: res.posts,
      count: res.count,
      limit: res.limit,
      page: res.page,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _reply({ForumPost? quote}) async {
    final t = _thread;
    if (t == null || t.locked) return;
    if (!requireLogin(context, ref)) return;
    if (quote != null) _appendQuote(quote);
    final ok = await showForumReplySheet(context,
        threadId: widget.threadId, draft: _draft);
    if (!ok || !mounted) return;
    _draft.clear();
    showToast(context, '回复成功');
    controller.refresh();
  }

  /// 把某楼内容以 Markdown 引用的形式追加到草稿。
  void _appendQuote(ForumPost p) {
    var body = p.body.trim();
    if (body.length > 300) body = '${body.substring(0, 300)}…';
    final floor = p.replyNum == 0 ? '楼主' : '#${p.replyNum + 1}';
    final quoted = [
      '> @${p.user?.username ?? ''} $floor',
      for (final line in body.split('\n')) '> $line',
    ].join('\n');
    final old = _draft.text.trimRight();
    _draft.text = old.isEmpty ? '$quoted\n\n' : '$old\n\n$quoted\n\n';
  }

  Future<void> _postMenu(ForumPost p) async {
    final canReply = _thread != null && !_thread!.locked;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制内容'),
            onTap: () => Navigator.pop(ctx, 'copy'),
          ),
          if (canReply)
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('引用回复'),
              onTap: () => Navigator.pop(ctx, 'quote'),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: p.body));
        if (mounted) showToast(context, '已复制');
      case 'quote':
        await _reply(quote: p);
    }
  }

  Future<void> _onMenu(String key) async {
    switch (key) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _url));
        if (mounted) showToast(context, '链接已复制');
      case 'browser':
        await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _thread;
    return Scaffold(
      appBar: AppBar(
        title: Text(forumSectionName(t?.section ?? widget.section)),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制链接')),
              PopupMenuItem(value: 'browser', child: Text('在浏览器中打开')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PagedView<ForumPost>(
            controller: controller,
            padding: EdgeInsets.zero,
            emptyText: '暂无帖子',
            emptyIcon: Icons.chat_bubble_outline,
            layout: const ListLayout(separated: true),
            headerSlivers: [
              if (t != null) ...[
                SliverToBoxAdapter(child: _ThreadHeader(thread: t)),
                const SliverToBoxAdapter(child: Divider(thickness: 6, height: 6)),
              ],
            ],
            itemBuilder: (context, p, _) => _PostTile(
              post: p,
              isAuthor: t?.user != null && p.user?.id == t!.user!.id,
              onLongPress: () => _postMenu(p),
            ),
          ),
        ),
        if (t != null)
          t.locked
              ? const _LockedBar()
              : CommentInputBar(onTap: () => _reply(), hint: '回复主题'),
      ]),
    );
  }
}

/// 主题头部：标记、标题、统计。
class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = thread;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => context.push('/forum/${t.section}'),
                child: ForumTag(forumSectionName(t.section),
                    icon: forumSectionIcon(t.section),
                    color: theme.colorScheme.secondary),
              ),
              if (t.sticky)
                ForumTag('置顶',
                    icon: Icons.push_pin, color: theme.colorScheme.primary),
              if (t.locked)
                ForumTag('已锁定',
                    icon: Icons.lock_outline, color: theme.colorScheme.error),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(t.title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            ForumStat(Icons.visibility_outlined,
                '${formatCount(t.numViews)} 浏览'),
            ForumStat(
                Icons.chat_bubble_outline, '${formatCount(t.numPosts)} 帖子'),
            if (t.createdAt != null)
              ForumStat(Icons.schedule, formatDateTime(t.createdAt)),
          ]),
        ],
      ),
    );
  }
}

/// 单个楼层。
class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    this.isAuthor = false,
    this.onLongPress,
  });

  final ForumPost post;

  /// 是否为主题发起人（楼主）。
  final bool isAuthor;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = post.user;
    final role = forumRoleLabel(user?.role);
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              UserAvatar(user,
                  size: 36,
                  onTap: user == null
                      ? null
                      : () => context.push('/profile/${user.username}')),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(user?.name ?? '已注销用户',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: user?.premium == true
                                    ? Colors.amber.shade700
                                    : theme.colorScheme.onSurfaceVariant)),
                      ),
                      if (isAuthor) ...[
                        const SizedBox(width: 4),
                        ForumTag('楼主', color: theme.colorScheme.primary),
                      ],
                      if (role != null) ...[
                        const SizedBox(width: 4),
                        ForumTag(role, color: theme.colorScheme.tertiary),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(formatAgo(post.createdAt),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(post.replyNum == 0 ? '楼主' : '#${post.replyNum + 1}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.hintColor)),
            ]),
            const SizedBox(height: 8),
            RichBody(post.body),
          ],
        ),
      ),
    );
  }
}

/// 锁定主题的底栏。
class _LockedBar extends StatelessWidget {
  const _LockedBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 16, color: theme.hintColor),
              const SizedBox(width: 6),
              Text('主题已锁定', style: TextStyle(color: theme.hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}
