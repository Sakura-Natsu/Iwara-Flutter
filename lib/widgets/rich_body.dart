import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'net_image.dart';

/// 渲染 Iwara 的 Markdown 正文（简介、评论、论坛帖子）。
class RichBody extends StatelessWidget {
  const RichBody(this.text,
      {super.key, this.style, this.selectable = false, this.linkColor});

  final String text;
  final TextStyle? style;
  final bool selectable;

  /// 链接颜色，默认主题色（在主题色背景上需要覆盖）。
  final Color? linkColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium!;
    return MarkdownBody(
      data: _linkify(text),
      selectable: selectable,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubWeb,
      onTapLink: (text, href, title) {
        if (href != null) openLink(context, href);
      },
      imageBuilder: (uri, title, alt) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: NetImage(uri.toString(),
              fit: BoxFit.contain, borderRadius: BorderRadius.circular(6)),
        ),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        a: base.copyWith(
          color: linkColor ?? theme.colorScheme.primary,
          decoration: linkColor == null ? null : TextDecoration.underline,
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        code: base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  /// 保证 Markdown 中的裸链接可点击；在 `<` 前转义避免被当作 HTML。
  static String _linkify(String s) => s.replaceAll('<', '&lt;');
}

/// 打开链接：iwara 站内链接跳转到 App 页面，其余用系统浏览器打开。
Future<void> openLink(BuildContext context, String href) async {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return;
  final route = iwaraRouteFor(uri);
  if (route != null) {
    context.push(route);
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 将 iwara 网址转换为 App 内路由，无法识别时返回 null。
String? iwaraRouteFor(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty && !host.endsWith('iwara.tv')) return null;
  if (host.isEmpty && uri.scheme.isNotEmpty) return null;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.isEmpty) return null;
  return switch (seg) {
    ['video' || 'videos' || 'v', final id, ...] => '/video/$id',
    ['image' || 'images' || 'i', final id, ...] => '/image/$id',
    ['profile' || 'p', final name, ...] => '/profile/$name',
    ['playlist', final id, ...] => '/playlist/$id',
    ['post', final id, ...] => '/post/$id',
    ['forum', final section, final id, ...] => '/forum/$section/$id',
    ['forum', final section] => '/forum/$section',
    _ => null,
  };
}
