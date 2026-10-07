import 'package:flutter/material.dart';

import '../api/api_exception.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  ErrorView.from(Object error, {super.key, this.onRetry})
      : message = ApiException.from(error).message;

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.text = '这里什么都没有',
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).hintColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: color)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}

void showError(BuildContext context, Object error) =>
    showToast(context, ApiException.from(error).message);

Future<bool> confirm(BuildContext context, String title,
    {String? content, String okText = '确定', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content == null ? null : Text(content),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return res ?? false;
}

Future<String?> promptText(BuildContext context, String title,
    {String? initial, String? hint, String okText = '确定', int maxLines = 1}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v.trim()) : null,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(okText)),
      ],
    ),
  );
}
