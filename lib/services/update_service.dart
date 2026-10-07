import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_exception.dart';
import '../core/constants.dart';

/// GitHub Release 信息。
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    this.name,
    this.body,
    this.publishedAt,
    this.assets = const [],
  });

  /// 去掉前缀 v 的版本号，如 1.2.0
  final String version;
  final String tagName;
  final String htmlUrl;
  final String? name;
  final String? body;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  /// 与当前设备 CPU 架构匹配的 APK，找不到时返回 null。
  ReleaseAsset? apkForDevice() {
    final abi = UpdateService.deviceAbi();
    final apks = assets.where((a) => a.name.endsWith('.apk')).toList();
    if (abi != null) {
      for (final a in apks) {
        if (a.name.contains(abi)) return a;
      }
    }
    return apks.length == 1 ? apks.first : null;
  }

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final tag = (j['tag_name'] ?? '').toString();
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      tagName: tag,
      htmlUrl: (j['html_url'] ?? AppRepo.releases).toString(),
      name: j['name'] as String?,
      body: j['body'] as String?,
      publishedAt: DateTime.tryParse((j['published_at'] ?? '').toString()),
      assets: (j['assets'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (a) => ReleaseAsset(
              name: (a['name'] ?? '').toString(),
              url: (a['browser_download_url'] ?? '').toString(),
              size: (a['size'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(),
    );
  }
}

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size = 0});

  final String name;
  final String url;
  final int size;
}

abstract final class UpdateService {
  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/vnd.github+json'},
    ),
  );

  static Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// 获取最新正式版（不含预发布/草稿）；仓库还没有发布时返回 null。
  static Future<ReleaseInfo?> fetchLatest() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        AppRepo.latestReleaseApi,
      );
      final data = res.data;
      return data == null ? null : ReleaseInfo.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.from(e);
    }
  }

  /// 有比当前版本新的发布时返回它，否则返回 null。
  static Future<ReleaseInfo?> checkForUpdate() async {
    final latest = await fetchLatest();
    if (latest == null) return null;
    final current = await currentVersion();
    return compareVersions(latest.version, current) > 0 ? latest : null;
  }

  /// 比较语义化版本号（忽略 +build 与 -pre 后缀）：a > b 返回正数。
  static int compareVersions(String a, String b) {
    List<int> parse(String v) => v
        .split(RegExp(r'[+-]'))
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final pa = parse(a), pb = parse(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  /// 当前设备的 CPU 架构（与 APK 文件名中的 ABI 一致）。
  static String? deviceAbi() {
    if (!Platform.isAndroid) return null;
    // Platform.version 形如：3.12.0 (stable) (...) on "android_arm64"
    final v = Platform.version;
    if (v.contains('android_arm64')) return 'arm64-v8a';
    if (v.contains('android_arm')) return 'armeabi-v7a';
    if (v.contains('android_x64')) return 'x86_64';
    if (v.contains('android_ia32')) return 'x86';
    return null;
  }
}
