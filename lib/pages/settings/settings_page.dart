import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_exception.dart';
import '../../core/constants.dart';
import '../../core/proxy.dart';
import '../../core/settings.dart';
import '../../providers.dart';
import '../../services/download_service.dart';
import '../../widgets/states.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _colors = <(int, String)>[
    (0xFF00BCD4, '青色'),
    (0xFF2196F3, '蓝色'),
    (0xFF673AB7, '紫色'),
    (0xFFE91E63, '粉色'),
    (0xFFFF5722, '橙色'),
    (0xFF4CAF50, '绿色'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(text,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          header('外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('深色模式'),
            trailing: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) =>
                  n.update((x) => x.copyWith(themeMode: v.first)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题色'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final (c, name) in _colors)
                    Tooltip(
                      message: name,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => n.update((x) => x.copyWith(seedColor: c)),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(c),
                          child: s.seedColor == c
                              ? const Icon(Icons.check,
                                  size: 18, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          header('网络'),
          SwitchListTile(
            secondary: const Icon(Icons.vpn_key_outlined),
            title: const Text('使用 HTTP 代理'),
            subtitle: Text(s.proxyEnabled
                ? '${s.proxyHost}:${s.proxyPort}'
                : '关闭时直连（可配合系统 VPN 使用）'),
            value: s.proxyEnabled,
            onChanged: (v) async {
              await n.update((x) => x.copyWith(proxyEnabled: v));
              await _applyProxy(ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('代理地址'),
            subtitle: Text('${s.proxyHost}:${s.proxyPort}'),
            onTap: () => _editProxy(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.network_check),
            title: const Text('测试连接'),
            subtitle: const Text('访问 api.iwara.tv 检查网络是否可用'),
            onTap: () => _testConnection(context, ref),
          ),
          header('内容'),
          ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: const Text('内容分级'),
            trailing: SegmentedButton<Rating>(
              showSelectedIcon: false,
              segments: [
                for (final r in Rating.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {s.rating},
              onSelectionChanged: (v) =>
                  n.update((x) => x.copyWith(rating: v.first)),
            ),
          ),
          header('播放'),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('默认清晰度'),
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'Source', label: Text('原画')),
                ButtonSegment(value: '540', label: Text('540P')),
                ButtonSegment(value: '360', label: Text('360P')),
              ],
              selected: {s.defaultQuality},
              onSelectionChanged: (v) =>
                  n.update((x) => x.copyWith(defaultQuality: v.first)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('自动播放'),
            subtitle: const Text('进入视频页后自动开始播放'),
            value: s.autoPlay,
            onChanged: (v) => n.update((x) => x.copyWith(autoPlay: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.history),
            title: const Text('断点续播'),
            subtitle: const Text('从上次观看的位置继续'),
            value: s.resumePlayback,
            onChanged: (v) => n.update((x) => x.copyWith(resumePlayback: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.headphones_outlined),
            title: const Text('后台播放'),
            subtitle: const Text('切到后台或锁屏后继续播放'),
            value: s.backgroundPlay,
            onChanged: (v) => n.update((x) => x.copyWith(backgroundPlay: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: const Text('自动画中画'),
            subtitle: const Text('播放中按 Home 键时进入小窗'),
            value: s.autoPip,
            onChanged: (v) => n.update((x) => x.copyWith(autoPip: v)),
          ),
          ListTile(
            leading: const Icon(Icons.fast_forward_outlined),
            title: const Text('长按倍速'),
            trailing: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1.5, label: Text('1.5x')),
                ButtonSegment(value: 2.0, label: Text('2x')),
                ButtonSegment(value: 3.0, label: Text('3x')),
              ],
              selected: {s.longPressSpeed},
              onSelectionChanged: (v) =>
                  n.update((x) => x.copyWith(longPressSpeed: v.first)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('视频输出'),
            subtitle: const Text('画面黑屏或花屏时尝试切换'),
            trailing: DropdownButton<String>(
              value: s.videoOutput,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'gpu', child: Text('默认（硬解）')),
                DropdownMenuItem(value: 'mediacodec', child: Text('MediaCodec 直出')),
                DropdownMenuItem(value: 'gpu-sw', child: Text('软件解码')),
              ],
              onChanged: (v) =>
                  n.update((x) => x.copyWith(videoOutput: v)),
            ),
          ),
          header('其他'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('视频签名'),
            subtitle: Text(
              '当前：${s.videoSalt ?? IwaraConst.defaultVideoSalt}\n播放源获取失败时会自动从官网更新',
            ),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: () => _refreshSalt(context, ref),
              child: const Text('立即更新'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清除图片缓存'),
            onTap: () async {
              await DefaultCacheManager().emptyCache();
              PaintingBinding.instance.imageCache.clear();
              if (context.mounted) showToast(context, '已清除');
            },
          ),
          FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => AboutListTile(
              icon: const Icon(Icons.info_outline),
              applicationName: 'Iwara',
              applicationVersion: snap.data?.version,
              applicationIcon:
                  Image.asset('assets/icon/icon.png', width: 48, height: 48),
              applicationLegalese: 'GPL-3.0 License',
              aboutBoxChildren: const [
                Text('iwara.tv 的第三方 Android 客户端，与 Iwara 官方无关。\n'
                    '应用图标中的初音未来形象 © Crypton Future Media, INC. www.piapro.net'),
              ],
              child: Text('关于 ${snap.data == null ? '' : 'v${snap.data!.version}'}'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('访问官网'),
            onTap: () => launchUrl(Uri.parse(IwaraConst.siteUrl),
                mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static Future<void> _applyProxy(WidgetRef ref) async {
    final addr = ref.read(settingsProvider).proxyAddress;
    AppHttpOverrides.proxy = addr;
    await DownloadService.applyProxy(addr);
  }

  Future<void> _editProxy(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final host = TextEditingController(text: s.proxyHost);
    final port = TextEditingController(text: '${s.proxyPort}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HTTP 代理'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: host,
            decoration: const InputDecoration(
                labelText: '主机', hintText: '127.0.0.1'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: port,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: '端口', hintText: '7890'),
          ),
          const SizedBox(height: 8),
          Text('Clash 等代理软件一般为 127.0.0.1:7890，模拟器访问电脑代理用 10.0.2.2',
              style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final p = int.tryParse(port.text.trim());
    if (host.text.trim().isEmpty || p == null || p <= 0 || p > 65535) {
      if (context.mounted) showToast(context, '地址或端口无效');
      return;
    }
    await ref.read(settingsProvider.notifier).update((x) =>
        x.copyWith(proxyHost: host.text.trim(), proxyPort: p, proxyEnabled: true));
    await _applyProxy(ref);
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    showToast(context, '正在测试…');
    final sw = Stopwatch()..start();
    try {
      await ref.read(apiClientProvider).get('config');
      if (context.mounted) {
        showToast(context, '连接成功（${sw.elapsedMilliseconds} ms）');
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, '连接失败：${ApiException.from(e).message}');
      }
    }
  }

  Future<void> _refreshSalt(BuildContext context, WidgetRef ref) async {
    showToast(context, '正在从官网获取…');
    final salt = await ref.read(apiProvider).fetchSaltFromSite();
    if (!context.mounted) return;
    if (salt == null) {
      showToast(context, '获取失败，请检查网络');
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(videoSalt: salt));
    if (context.mounted) showToast(context, '已更新');
  }
}
