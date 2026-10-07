import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/forum.dart' show Captcha;
import '../../providers.dart';

/// 验证码有效期（服务端约 110 秒，留出余量）。
const _captchaTtl = Duration(seconds: 100);

/// 弹出论坛回复面板，回复成功返回 true。
/// [draft] 由调用方持有，面板关闭后草稿保留。
Future<bool> showForumReplySheet(
  BuildContext context, {
  required String threadId,
  required TextEditingController draft,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReplySheet(threadId: threadId, draft: draft),
  );
  return ok ?? false;
}

class _ReplySheet extends ConsumerStatefulWidget {
  const _ReplySheet({required this.threadId, required this.draft});

  final String threadId;
  final TextEditingController draft;

  @override
  ConsumerState<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends ConsumerState<_ReplySheet> {
  final _answer = TextEditingController();
  final _answerFocus = FocusNode();

  Captcha? _captcha;
  Uint8List? _captchaBytes;
  DateTime? _captchaAt;
  bool _captchaLoading = true;
  Object? _captchaError;
  Timer? _expireTimer;

  bool _submitting = false;

  /// 面板内的错误提示（SnackBar 会被底部弹窗遮挡，故在面板内显示）。
  String? _error;

  bool get _expired =>
      _captchaAt != null &&
      DateTime.now().difference(_captchaAt!) > _captchaTtl;

  @override
  void initState() {
    super.initState();
    _fetchCaptcha();
  }

  @override
  void dispose() {
    _expireTimer?.cancel();
    _answer.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  /// 重新获取验证码（会清空已输入的答案）。
  void _refreshCaptcha() {
    if (_captchaLoading) return;
    setState(() {
      _captchaLoading = true;
      _captchaError = null;
    });
    _fetchCaptcha();
  }

  Future<void> _fetchCaptcha() async {
    _expireTimer?.cancel();
    try {
      final c = await ref.read(apiProvider).captcha();
      final bytes = base64Decode(c.dataUri.split(',').last);
      if (!mounted) return;
      setState(() {
        _captcha = c;
        _captchaBytes = bytes;
        _captchaAt = DateTime.now();
        _captchaLoading = false;
        _answer.clear();
      });
      // 到期后刷新界面，显示「已过期」遮罩
      _expireTimer = Timer(_captchaTtl + const Duration(seconds: 1), () {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _captchaError = e;
        _captchaLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final body = widget.draft.text.trim();
    final answer = _answer.text.trim();
    final c = _captcha;
    if (body.isEmpty) {
      setState(() => _error = '请输入回复内容');
      return;
    }
    if (c == null || _captchaLoading) {
      setState(() => _error = '验证码尚未加载');
      if (!_captchaLoading) _refreshCaptcha();
      return;
    }
    if (_expired) {
      setState(() => _error = '验证码已过期，已自动刷新，请重新输入');
      _refreshCaptcha();
      _answerFocus.requestFocus();
      return;
    }
    if (answer.isEmpty) {
      setState(() => _error = '请输入验证码');
      _answerFocus.requestFocus();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).replyForumThread(widget.threadId, body,
          captchaId: c.id, captchaAnswer: answer);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      final captchaWrong =
          (ex.code ?? '').toLowerCase().contains('captcha');
      setState(() {
        _submitting = false;
        _error = captchaWrong ? '验证码错误，请重新输入' : ex.message;
      });
      // 验证码只能使用一次，失败后一律刷新并清空答案
      _refreshCaptcha();
      if (captchaWrong) _answerFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('回复主题', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.draft,
                  autofocus: true,
                  enabled: !_submitting,
                  minLines: 4,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: '友善发言，理性讨论',
                    helperText: '支持 Markdown 格式',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _captchaBox(theme)),
                  IconButton(
                    tooltip: '换一张',
                    icon: const Icon(Icons.refresh),
                    onPressed: _captchaLoading || _submitting
                        ? null
                        : _refreshCaptcha,
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: _answer,
                  focusNode: _answerFocus,
                  enabled: !_submitting,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: '输入上方验证码',
                    isDense: true,
                    prefixIcon: Icon(Icons.verified_user_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: Listenable.merge([widget.draft, _answer]),
                  builder: (_, _) {
                    final ready = !_submitting &&
                        !_captchaLoading &&
                        _captcha != null &&
                        widget.draft.text.trim().isNotEmpty &&
                        _answer.text.trim().isNotEmpty;
                    return FilledButton.icon(
                      onPressed: ready ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send, size: 18),
                      label: Text(_submitting ? '提交中…' : '提交'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 验证码图片区域，点击刷新。
  Widget _captchaBox(ThemeData theme) {
    final Widget child;
    if (_captchaLoading) {
      child = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_captchaError != null || _captchaBytes == null) {
      child = Text(
        _captchaError == null
            ? '点击获取验证码'
            : '${ApiException.from(_captchaError!).message}，点击重试',
        maxLines: 2,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.error),
      );
    } else {
      child = Stack(fit: StackFit.expand, children: [
        Image.memory(_captchaBytes!, fit: BoxFit.contain, gaplessPlayback: true),
        if (_expired)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Text('已过期，点击刷新',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
      ]);
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _captchaLoading || _submitting ? null : _refreshCaptcha,
        child: SizedBox(height: 48, child: Center(child: child)),
      ),
    );
  }
}
