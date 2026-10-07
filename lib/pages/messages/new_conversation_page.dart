import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/common.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/states.dart';
import 'common.dart';

/// 发起私信：未指定 [recipient] 时先搜索用户；创建成功后进入会话页。
/// 返回是否已发出（调用方可据此刷新列表）。
Future<bool> startConversation(BuildContext context, WidgetRef ref,
    {User? recipient}) async {
  final me = ref.read(meProvider);
  if (me == null) {
    showToast(context, '请先登录');
    context.push('/login');
    return false;
  }
  final created = await Navigator.of(context).push<_Created>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => NewConversationPage(recipient: recipient),
    ),
  );
  if (created == null) return false;
  if (!context.mounted) return true;
  final id = created.id;
  if (id == null) {
    showToast(context, '私信已发送');
    return true;
  }
  await context.push(
    '/messages/$id',
    extra: Conversation(
      id: id,
      title: created.title,
      participants: [me.user, created.recipient],
      updatedAt: DateTime.now(),
    ),
  );
  return true;
}

class _Created {
  const _Created({this.id, required this.title, required this.recipient});

  final String? id;
  final String title;
  final User recipient;
}

/// 新私信：搜索收件人 → 填写标题和内容。
class NewConversationPage extends ConsumerStatefulWidget {
  const NewConversationPage({super.key, this.recipient});

  /// 指定收件人时跳过搜索步骤。
  final User? recipient;

  @override
  ConsumerState<NewConversationPage> createState() =>
      _NewConversationPageState();
}

class _NewConversationPageState extends ConsumerState<NewConversationPage> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  Timer? _debounce;
  String _query = '';
  late User? _recipient = widget.recipient;
  bool _sending = false;

  late final PagingController<User> _results = PagingController(
    (page) {
      final q = _query;
      if (q.isEmpty) return Future.value(PageResult<User>(results: const []));
      return ref.read(apiProvider).search('users', q, User.fromJson, page: page);
    },
    dedupeKey: (u) => u.id,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _title.dispose();
    _body.dispose();
    _results.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _applyQuery(v));
  }

  void _applyQuery(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q == _query || !mounted) return;
    setState(() => _query = q);
    if (q.isNotEmpty) _results.refresh();
  }

  /// 标题留空时取内容第一行。
  String _defaultTitle(String body) {
    final line = body.split('\n').first.trim();
    return line.characters.length > 30
        ? '${line.characters.take(30)}…'
        : line;
  }

  Future<void> _send() async {
    final user = _recipient;
    if (user == null || _sending) return;
    final body = _body.text.trim();
    if (body.isEmpty) {
      showToast(context, '请输入消息内容');
      return;
    }
    var title = _title.text.trim();
    if (title.isEmpty) title = _defaultTitle(body);
    setState(() => _sending = true);
    try {
      final id = await ref
          .read(apiProvider)
          .createConversation(user.id, title, body);
      if (!mounted) return;
      Navigator.of(context)
          .pop(_Created(id: id, title: title, recipient: user));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipient = _recipient;
    final fromSearch = widget.recipient == null;
    return PopScope(
      // 从搜索结果选中后，返回键回到搜索
      canPop: recipient == null || !fromSearch,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_sending) setState(() => _recipient = null);
      },
      child: recipient == null ? _buildSearch() : _buildCompose(recipient),
    );
  }

  Widget _buildSearch() {
    final myId = ref.watch(meProvider)?.user.id;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索用户名或昵称',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
          onSubmitted: _applyQuery,
        ),
        actions: [
          ListenableBuilder(
            listenable: _search,
            builder: (_, _) => _search.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: '清除',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      _applyQuery('');
                    },
                  ),
          ),
        ],
      ),
      body: _query.isEmpty
          ? const EmptyView(
              text: '输入用户名或昵称，选择私信对象', icon: Icons.person_search)
          : PagedView<User>(
              controller: _results,
              padding: EdgeInsets.zero,
              emptyText: '没有找到相关用户',
              emptyIcon: Icons.person_off_outlined,
              itemBuilder: (context, u, _) {
                final self = u.id == myId;
                return UserListTile(
                  user: u,
                  enabled: !self,
                  subtitle: self ? '@${u.username}（你自己）' : null,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _recipient = u);
                  },
                );
              },
            ),
    );
  }

  Widget _buildCompose(User recipient) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('新消息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card.filled(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: UserAvatar(recipient, size: 40),
              title: Text(recipient.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('发送给 @${recipient.username}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: widget.recipient == null
                  ? TextButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() => _recipient = null),
                      child: const Text('更换'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            enabled: !_sending,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '选填，留空则取内容第一行',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _body,
            enabled: !_sending,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: '内容',
              alignLabelWithHint: true,
              helperText: '支持 Markdown 格式',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _body,
            builder: (_, _) => FilledButton.icon(
              onPressed:
                  _sending || _body.text.trim().isEmpty ? null : _send,
              icon: _sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: theme.disabledColor),
                    )
                  : const Icon(Icons.send, size: 18),
              label: Text(_sending ? '发送中' : '发送'),
            ),
          ),
        ],
      ),
    );
  }
}
