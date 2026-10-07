import 'package:flutter_test/flutter_test.dart';
import 'package:iwara_flutter/services/update_service.dart';

void main() {
  group('compareVersions', () {
    test('按数字逐段比较', () {
      expect(UpdateService.compareVersions('1.1.0', '1.0.2'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(UpdateService.compareVersions('2.0.0', '10.0.0'), lessThan(0));
      expect(UpdateService.compareVersions('1.2', '1.2.0'), 0);
    });

    test('忽略 build 号与预发布后缀', () {
      expect(UpdateService.compareVersions('1.1.0+5', '1.1.0'), 0);
      expect(UpdateService.compareVersions('1.1.0-beta', '1.1.0'), 0);
    });
  });

  test('解析 GitHub Release', () {
    final r = ReleaseInfo.fromJson({
      'tag_name': 'v1.1.0',
      'name': 'v1.1.0',
      'html_url': 'https://github.com/a/b/releases/tag/v1.1.0',
      'body': '更新说明',
      'published_at': '2026-10-08T00:00:00Z',
      'assets': [
        {
          'name': 'Iwara-1.1.0-arm64-v8a.apk',
          'browser_download_url': 'https://example.com/arm64.apk',
          'size': 1024,
        },
        {
          'name': 'Iwara-1.1.0-armeabi-v7a.apk',
          'browser_download_url': 'https://example.com/v7a.apk',
          'size': 1000,
        },
      ],
    });
    expect(r.version, '1.1.0');
    expect(r.assets, hasLength(2));
    expect(r.assets.first.size, 1024);
    expect(r.publishedAt, isNotNull);
  });
}
