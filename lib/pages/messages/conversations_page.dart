import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import 'common.dart';
import 'new_conversation_page.dart';

/// 私信会话列表。
class ConversationsPage extends ConsumerWidget {
  const ConversationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) {
      return const LoginRequiredScaffold(
        title: '私信',
        text: '登录后查看私信',
        icon: Icons.mail_outline,
      );
    }
    return _ConversationsView(key: ValueKey(me.user.id), myId: me.user.id);
  }
}

class _ConversationsView extends ConsumerStatefulWidget {
  const _ConversationsView({super.key, required this.myId});

  final String myId;

  @override
  ConsumerState<_ConversationsView> createState() => _ConversationsViewState();
}

class _ConversationsViewState extends ConsumerState<_ConversationsView> {
  late final PagingController<Conversation> controller = PagingController(
    (page) => ref.read(apiProvider).conversations(widget.myId, page: page),
    dedupeKey: (c) => c.id,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// 从会话页返回后刷新列表和未读计数。
  void _afterReturn() {
    if (!mounted) return;
    controller.refresh();
    ref.invalidate(countsProvider);
  }

  Future<void> _open(Conversation c) async {
    await context.push('/messages/${c.id}', extra: c);
    _afterReturn();
  }

  Future<void> _compose() async {
    if (await startConversation(context, ref)) _afterReturn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('私信')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('新消息'),
      ),
      body: PagedView<Conversation>(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 88),
        layout: const ListLayout(separated: true),
        emptyText: '还没有私信',
        emptyIcon: Icons.mail_outline,
        itemBuilder: (context, c, _) =>
            _ConversationTile(conversation: c, myId: widget.myId, onTap: () => _open(c)),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.myId,
    required this.onTap,
  });

  final Conversation conversation;
  final String myId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = conversation;
    final other = c.otherParticipant(myId);
    return ListTile(
      onTap: onTap,
      leading: UserAvatar(other, size: 44),
      title: Row(children: [
        Expanded(
          child: Text(
            other?.name ?? '未知用户',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: c.unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatAgo(c.updatedAt),
          style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
        ),
      ]),
      subtitle: Row(children: [
        Expanded(
          child: Text(
            c.title.isEmpty ? '（无标题）' : c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: c.unread
                ? TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface)
                : null,
          ),
        ),
        if (c.unread) ...[const SizedBox(width: 8), const UnreadDot()],
      ]),
    );
  }
}
