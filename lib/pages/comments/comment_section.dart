import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/iwara_api.dart';
import '../../core/format.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';

/// 需要登录时跳转登录页，返回是否已登录。
bool requireLogin(BuildContext context, WidgetRef ref) {
  if (ref.read(meProvider) != null) return true;
  showToast(context, '请先登录');
  context.push('/login');
  return false;
}

/// 评论区：分页列表 + 底部输入栏。
class CommentSection extends ConsumerStatefulWidget {
  const CommentSection({
    super.key,
    required this.type,
    required this.id,
    this.ownerId,
    this.onCountChanged,
  });

  final ContentType type;
  final String id;

  /// 内容作者 id，用于显示「作者」标记。
  final String? ownerId;
  final ValueChanged<int>? onCountChanged;

  @override
  ConsumerState<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<CommentSection>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<Comment> controller = PagingController(
    (page) async {
      final res = await ref
          .read(apiProvider)
          .comments(widget.type, widget.id, page: page);
      if (page == 0 && res.count != null) widget.onCountChanged?.call(res.count!);
      return res;
    },
    dedupeKey: (c) => c.id,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _compose() async {
    if (!requireLogin(context, ref)) return;
    final text = await showComposer(context, hint: '发一条友善的评论');
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final c = await ref
          .read(apiProvider)
          .createComment(widget.type, widget.id, text);
      if (!mounted) return;
      showToast(context, '评论成功');
      if (c != null) {
        controller.insert(0, c);
      } else {
        controller.refresh();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: PagedView<Comment>(
            controller: controller,
            padding: EdgeInsets.zero,
            emptyText: '还没有评论，来抢沙发吧',
            emptyIcon: Icons.chat_bubble_outline,
            layout: const ListLayout(separated: true),
            itemBuilder: (context, c, _) => CommentTile(
              comment: c,
              type: widget.type,
              contentId: widget.id,
              ownerId: widget.ownerId,
              onChanged: controller.refresh,
            ),
          ),
        ),
        CommentInputBar(onTap: _compose),
      ],
    );
  }
}

class CommentInputBar extends StatelessWidget {
  const CommentInputBar({super.key, required this.onTap, this.hint = '发一条友善的评论'});

  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 16, color: theme.hintColor),
                const SizedBox(width: 8),
                Text(hint, style: TextStyle(color: theme.hintColor)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条评论。
class CommentTile extends ConsumerWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.type,
    required this.contentId,
    this.ownerId,
    this.onChanged,
    this.showReplies = true,
  });

  final Comment comment;
  final ContentType type;
  final String contentId;
  final String? ownerId;
  final VoidCallback? onChanged;
  final bool showReplies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = comment.user;
    final me = ref.watch(meProvider);
    final mine = me != null && user?.id == me.user.id;
    return InkWell(
      onLongPress: () => _menu(context, ref, mine),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(user,
                size: 34,
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
                    if (user != null && user.id == ownerId) ...[
                      const SizedBox(width: 4),
                      _Tag(text: '作者', color: theme.colorScheme.primary),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  RichBody(comment.body),
                  Row(children: [
                    Text(
                      formatAgo(comment.createdAt) + (comment.edited ? ' · 已编辑' : ''),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                    const Spacer(),
                    if (showReplies)
                      TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: () => showRepliesSheet(context,
                            type: type,
                            contentId: contentId,
                            parent: comment,
                            ownerId: ownerId),
                        child: Text(comment.numReplies > 0
                            ? '${comment.numReplies} 条回复'
                            : '回复'),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: Icon(Icons.more_horiz, color: theme.hintColor),
                      onPressed: () => _menu(context, ref, mine),
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

  Future<void> _menu(BuildContext context, WidgetRef ref, bool mine) async {
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
          if (mine) ...[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('删除',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    final api = ref.read(apiProvider);
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: comment.body));
        if (context.mounted) showToast(context, '已复制');
      case 'edit':
        final text = await showComposer(context,
            initial: comment.body, hint: '编辑评论', sendText: '保存');
        if (text == null || text.isEmpty) return;
        try {
          await api.updateComment(comment.id, text);
          onChanged?.call();
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
      case 'delete':
        if (!await confirm(context, '删除这条评论？', danger: true, okText: '删除')) {
          return;
        }
        try {
          await api.deleteComment(comment.id);
          onChanged?.call();
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 9, height: 1.2)),
      );
}

/// 楼中楼回复面板。
Future<void> showRepliesSheet(
  BuildContext context, {
  required ContentType type,
  required String contentId,
  required Comment parent,
  String? ownerId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _RepliesSheet(
          type: type, contentId: contentId, parent: parent, ownerId: ownerId),
    ),
  );
}

class _RepliesSheet extends ConsumerStatefulWidget {
  const _RepliesSheet({
    required this.type,
    required this.contentId,
    required this.parent,
    this.ownerId,
  });

  final ContentType type;
  final String contentId;
  final Comment parent;
  final String? ownerId;

  @override
  ConsumerState<_RepliesSheet> createState() => _RepliesSheetState();
}

class _RepliesSheetState extends ConsumerState<_RepliesSheet> {
  late final PagingController<Comment> controller = PagingController(
    (page) => ref.read(apiProvider).comments(widget.type, widget.contentId,
        page: page, parentId: widget.parent.id),
    dedupeKey: (c) => c.id,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _reply() async {
    if (!requireLogin(context, ref)) return;
    final text = await showComposer(context,
        hint: '回复 @${widget.parent.user?.name ?? ''}');
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await ref.read(apiProvider).createComment(
          widget.type, widget.contentId, text,
          parentId: widget.parent.id);
      if (!mounted) return;
      showToast(context, '回复成功');
      controller.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('评论详情', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Expanded(
        child: PagedView<Comment>(
          controller: controller,
          padding: EdgeInsets.zero,
          emptyText: '暂无回复',
          layout: const ListLayout(separated: true),
          headerSlivers: [
            SliverToBoxAdapter(
              child: CommentTile(
                comment: widget.parent,
                type: widget.type,
                contentId: widget.contentId,
                ownerId: widget.ownerId,
                showReplies: false,
              ),
            ),
            const SliverToBoxAdapter(child: Divider(thickness: 6, height: 6)),
          ],
          itemBuilder: (context, c, _) => Padding(
            padding: const EdgeInsets.only(left: 24),
            child: CommentTile(
              comment: c,
              type: widget.type,
              contentId: widget.contentId,
              ownerId: widget.ownerId,
              showReplies: false,
              onChanged: controller.refresh,
            ),
          ),
        ),
      ),
      CommentInputBar(onTap: _reply, hint: '回复 @${widget.parent.user?.name ?? ''}'),
    ]);
  }
}

/// 文本输入面板，返回输入内容（取消返回 null）。
Future<String?> showComposer(
  BuildContext context, {
  String? initial,
  String hint = '说点什么',
  String sendText = '发送',
  int maxLength = 2000,
}) {
  final ctrl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: maxLength,
                decoration: InputDecoration(
                  hintText: hint,
                  helperText: '支持 Markdown 格式',
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: ctrl,
                builder: (_, v, _) => FilledButton.icon(
                  onPressed: v.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(ctx, v.text.trim()),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(sendText),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
