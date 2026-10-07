import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/states.dart';
import 'common.dart';

/// 私信会话。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversationId, this.initial});

  final String conversationId;
  final Conversation? initial;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scroll = ScrollController();
  final _input = TextEditingController();

  /// 按 createdAt 升序（最新在末尾），列表 reverse 显示。
  final List<Message> _messages = [];
  final Set<String> _ids = {};
  int _nextPage = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOlder());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  // ---------------- 数据 ----------------

  /// 合并消息：按 id 去重后按时间升序排列。
  void _merge(Iterable<Message> list) {
    for (final m in list) {
      if (_ids.add(m.id)) _messages.add(m);
    }
    _messages.sort(_compare);
  }

  static int _compare(Message a, Message b) {
    final ta = a.createdAt, tb = b.createdAt;
    if (ta != null && tb != null) {
      final c = ta.compareTo(tb);
      if (c != 0) return c;
    } else if (ta != null || tb != null) {
      // 没有时间的视为最新
      return ta == null ? 1 : -1;
    }
    return a.id.compareTo(b.id);
  }

  /// 加载更早一页。
  Future<void> _loadOlder() async {
    if (_loading || !_hasMore || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final page = _nextPage;
    try {
      final res = await ref
          .read(apiProvider)
          .messages(widget.conversationId, page: page);
      if (!mounted) return;
      final limit = res.limit > 0 ? res.limit : IwaraConst.pageSize;
      setState(() {
        _merge(res.results);
        _nextPage = page + 1;
        _hasMore = res.results.length >= limit;
      });
      // 进入会话后服务端会标记已读
      if (page == 0) ref.invalidate(countsProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 内容不足一屏时继续加载，保证能滚动触发翻页。
  void _fillViewport() {
    if (!mounted || !_hasMore || _error != null || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent <= 0) _loadOlder();
  }

  /// 重新拉取第一页并合并（用于发送后 / 手动刷新）。
  Future<void> _reloadLatest() async {
    if (_messages.isEmpty) {
      // 尚无消息时按首次加载处理
      if (_loading) return;
      setState(() {
        _nextPage = 0;
        _hasMore = true;
        _error = null;
      });
      await _loadOlder();
      return;
    }
    try {
      final res = await ref
          .read(apiProvider)
          .messages(widget.conversationId, page: 0);
      if (mounted) setState(() => _merge(res.results));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _onScroll() {
    final p = _scroll.position;
    // reverse 列表：maxScrollExtent 为顶部（更早的消息）
    if (p.pixels >= p.maxScrollExtent - 300 && _error == null) _loadOlder();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // ---------------- 操作 ----------------

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await ref
          .read(apiProvider)
          .sendMessage(widget.conversationId, text);
      if (!mounted) return;
      // 发送期间输入框内容未变时才清空
      if (_input.text.trim() == text) _input.clear();
      if (msg != null) {
        final me = ref.read(meProvider)?.user;
        setState(() => _merge([
              Message(
                id: msg.id,
                body: msg.body.isEmpty ? text : msg.body,
                user: msg.user ?? me,
                createdAt: msg.createdAt ?? DateTime.now(),
              ),
            ]));
      } else {
        await _reloadLatest();
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onLongPress(Message m, bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制'),
            onTap: () => Navigator.pop(ctx, 'copy'),
          ),
          if (mine)
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('删除',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) showToast(context, '已复制');
      case 'delete':
        if (!await confirm(context, '删除这条消息？', danger: true, okText: '删除')) {
          return;
        }
        if (!mounted) return;
        // 乐观删除，失败回滚
        setState(() {
          _messages.removeWhere((e) => e.id == m.id);
          _ids.remove(m.id);
        });
        try {
          await ref.read(apiProvider).deleteMessage(m.id);
        } catch (e) {
          if (!mounted) return;
          setState(() => _merge([m]));
          showError(context, e);
        }
    }
  }

  // ---------------- 界面 ----------------

  /// 对方用户：优先取会话参与者，否则从消息中推断。
  User? _other(String? myId) {
    final fromInitial = widget.initial?.otherParticipant(myId);
    if (fromInitial != null) return fromInitial;
    for (final m in _messages) {
      if (m.user != null && m.user!.id != myId) return m.user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    if (me == null) {
      return const LoginRequiredScaffold(
          title: '私信', text: '登录后查看私信', icon: Icons.mail_outline);
    }
    final theme = Theme.of(context);
    final other = _other(me.user.id);
    final convTitle = widget.initial?.title ?? '';
    final title = other?.name ?? (convTitle.isNotEmpty ? convTitle : '私信');
    final subtitle = other != null && convTitle.isNotEmpty ? convTitle : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
          ],
        ),
        actions: [
          if (other != null && other.username.isNotEmpty)
            IconButton(
              tooltip: '查看主页',
              icon: const Icon(Icons.person_outline),
              onPressed: () => context.push('/profile/${other.username}'),
            ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reloadLatest,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: _buildList(me.user.id)),
        _InputBar(controller: _input, sending: _sending, onSend: _send),
      ]),
    );
  }

  Widget _buildList(String myId) {
    if (_messages.isEmpty) {
      if (_error != null) return ErrorView.from(_error!, onRetry: _loadOlder);
      if (_loading || _hasMore) return const LoadingView();
      return const EmptyView(
          text: '还没有消息，打个招呼吧', icon: Icons.forum_outlined);
    }
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length + 1,
      itemBuilder: (context, i) {
        if (i == _messages.length) return _buildTopIndicator();
        final idx = _messages.length - 1 - i;
        final m = _messages[idx];
        final older = idx > 0 ? _messages[idx - 1] : null;
        final newer = idx < _messages.length - 1 ? _messages[idx + 1] : null;
        final mine = m.user?.id == myId;
        return _MessageBubble(
          message: m,
          mine: mine,
          // 同一发送者、同一分钟内的连续消息合并显示头像和时间
          showAvatar: older == null || !_sameGroup(older, m),
          showTime: newer == null || !_sameGroup(m, newer),
          onLongPress: () => _onLongPress(m, mine),
        );
      },
    );
  }

  Widget _buildTopIndicator() {
    final hint = Theme.of(context).hintColor;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: _loadOlder,
          icon: const Icon(Icons.refresh),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Text('— 没有更早的消息了 —',
              style: TextStyle(color: hint, fontSize: 12)),
        ),
      );
    }
    return const SizedBox(height: 48);
  }

  static bool _sameGroup(Message a, Message b) {
    if (a.user?.id != b.user?.id) return false;
    final ta = a.createdAt, tb = b.createdAt;
    if (ta == null || tb == null) return false;
    return ta.year == tb.year &&
        ta.month == tb.month &&
        ta.day == tb.day &&
        ta.hour == tb.hour &&
        ta.minute == tb.minute;
  }
}

/// 消息气泡。
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showAvatar,
    required this.showTime,
    required this.onLongPress,
  });

  final Message message;
  final bool mine;
  final bool showAvatar;
  final bool showTime;
  final VoidCallback onLongPress;

  static const _avatarSize = 36.0;

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('HH:mm').format(t);
    }
    if (t.year == now.year) return DateFormat('MM-dd HH:mm').format(t);
    return DateFormat('yyyy-MM-dd HH:mm').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = message.user;
    final time = message.createdAt;

    final Widget avatar = showAvatar
        ? UserAvatar(user,
            size: _avatarSize,
            onTap: user == null || user.username.isEmpty
                ? null
                : () => context.push('/profile/${user.username}'))
        : const SizedBox(width: _avatarSize);

    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    Widget content = RichBody(message.body,
        style: theme.textTheme.bodyMedium?.copyWith(color: fg));
    if (mine) {
      // 主题色气泡上链接色改为前景色，避免看不清
      content = Theme(
        data: theme.copyWith(
            colorScheme: scheme.copyWith(primary: scheme.onPrimary)),
        child: content,
      );
    }

    const r = Radius.circular(16);
    const sharp = Radius.circular(4);
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: !mine && showAvatar ? sharp : r,
            topRight: mine && showAvatar ? sharp : r,
            bottomLeft: r,
            bottomRight: r,
          ),
        ),
        child: content,
      ),
    );

    final column = Flexible(
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bubble,
          if (showTime && time != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
              child: Text(
                _timeLabel(time),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(8, showAvatar ? 10 : 3, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: mine
            ? [const SizedBox(width: 48), column, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), column, const SizedBox(width: 48)],
      ),
    );
  }
}

/// 底部输入栏。
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '发送消息',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ListenableBuilder(
                listenable: controller,
                builder: (_, _) => IconButton.filled(
                  tooltip: '发送',
                  onPressed: sending || controller.text.trim().isEmpty
                      ? null
                      : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
