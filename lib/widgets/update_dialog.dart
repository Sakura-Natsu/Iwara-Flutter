import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../services/update_service.dart';
import 'rich_body.dart';
import 'states.dart';

/// 手动检查更新（设置页使用）。
Future<void> checkUpdateManually(BuildContext context, WidgetRef ref) async {
  showToast(context, '正在检查更新…');
  try {
    final release = await UpdateService.checkForUpdate();
    if (!context.mounted) return;
    if (release == null) {
      final v = await UpdateService.currentVersion();
      if (context.mounted) showToast(context, '已是最新版本（v$v）');
      return;
    }
    await showUpdateDialog(context, ref, release, manual: true);
  } catch (e) {
    if (context.mounted) {
      showToast(context, '检查更新失败：${ApiException.from(e).message}');
    }
  }
}

/// 启动时静默检查，有新版本且未被忽略时弹窗。
Future<void> checkUpdateSilently(BuildContext context, WidgetRef ref) async {
  try {
    final release = await UpdateService.checkForUpdate();
    if (release == null || !context.mounted) return;
    if (ref.read(settingsProvider).ignoredVersion == release.version) return;
    await showUpdateDialog(context, ref, release);
  } catch (_) {
    // 网络不可用等情况静默忽略
  }
}

Future<void> showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  ReleaseInfo release, {
  bool manual = false,
}) {
  final apk = release.apkForDevice();
  return showDialog(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final notes = (release.body ?? '').trim();
      return AlertDialog(
        title: Text('发现新版本 v${release.version}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (release.publishedAt != null || apk != null)
                  Text(
                    [
                      if (release.publishedAt != null)
                        '发布于 ${formatDate(release.publishedAt)}',
                      if (apk != null && apk.size > 0) formatBytes(apk.size),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                const SizedBox(height: 8),
                if (notes.isEmpty)
                  const Text('暂无更新说明')
                else
                  RichBody(notes, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        actions: [
          if (!manual)
            TextButton(
              onPressed: () {
                ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(ignoredVersion: release.version));
                Navigator.pop(ctx);
              },
              child: const Text('忽略此版本'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 直接下载匹配架构的 APK；找不到时打开发布页
              launchUrl(
                Uri.parse(apk?.url ?? release.htmlUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('下载更新'),
          ),
        ],
      );
    },
  );
}
