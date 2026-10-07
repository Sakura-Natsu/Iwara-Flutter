import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/forum.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import 'forum_widgets.dart';

/// 板块主题列表。
class ForumSectionPage extends ConsumerStatefulWidget {
  const ForumSectionPage({super.key, required this.section});

  final String section;

  @override
  ConsumerState<ForumSectionPage> createState() => _ForumSectionPageState();
}

class _ForumSectionPageState extends ConsumerState<ForumSectionPage> {
  late final PagingController<ForumThread> controller = PagingController(
    (page) => ref.read(apiProvider).forumThreads(widget.section, page: page),
    dedupeKey: (t) => t.id,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(forumSectionName(widget.section)),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search?type=forum_threads'),
          ),
        ],
      ),
      body: PagedView<ForumThread>(
        controller: controller,
        padding: EdgeInsets.zero,
        emptyText: '还没有主题',
        emptyIcon: Icons.forum_outlined,
        layout: const ListLayout(separated: true),
        itemBuilder: (context, t, _) => ForumThreadTile(thread: t),
      ),
    );
  }
}

/// 主题条目：标题、作者、回复/浏览数、最后回复。
class ForumThreadTile extends StatelessWidget {
  const ForumThreadTile({super.key, required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = thread;
    final user = t.user;
    final last = t.lastPost;
    final lastText = [
      if (last?.user != null) last!.user!.name,
      formatAgo(last?.createdAt ?? t.updatedAt),
    ].where((e) => e.isNotEmpty).join(' ');
    final hintStyle =
        theme.textTheme.labelSmall?.copyWith(color: theme.hintColor);
    return InkWell(
      onTap: () => context.push('/forum/${t.section}/${t.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  Text.rich(
                    TextSpan(children: [
                      if (t.sticky)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ForumTag('置顶',
                                icon: Icons.push_pin,
                                color: theme.colorScheme.primary),
                          ),
                        ),
                      if (t.locked)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.lock_outline,
                                size: 15, color: theme.hintColor),
                          ),
                        ),
                      TextSpan(text: t.title),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      user?.name ?? '已注销用户',
                      formatAgo(t.createdAt),
                    ].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hintStyle,
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    ForumStat(Icons.chat_bubble_outline, formatCount(t.numPosts)),
                    const SizedBox(width: 12),
                    ForumStat(Icons.visibility_outlined, formatCount(t.numViews)),
                    const SizedBox(width: 12),
                    // 最后回复人与时间
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          if (lastText.isNotEmpty) ...[
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(Icons.reply,
                                  size: 14, color: theme.hintColor),
                            ),
                            TextSpan(text: ' $lastText'),
                          ],
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: hintStyle,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
