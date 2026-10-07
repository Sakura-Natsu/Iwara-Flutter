/// 站点相关常量。
abstract final class IwaraConst {
  static const siteHost = 'www.iwara.tv';
  static const siteUrl = 'https://www.iwara.tv';
  static const apiBase = 'https://api.iwara.tv/';
  static const imageHost = 'https://i.iwara.tv';

  /// 视频直链签名盐值。官方前端更新后可能变化，失效时会尝试从前端 JS 重新提取。
  static const defaultVideoSalt = 'mSvL05GfEmeEmsEYfGCnVpEjYgTJraJN';

  /// 与 Dart 默认 UA 保持一致：Cloudflare 会拦截部分浏览器/curl 的 UA。
  static const userAgent = 'Dart/3.12 (dart:io)';

  static const pageSize = 32;
}

/// 排序方式。
enum SortType {
  trending('trending', '流行'),
  date('date', '最新'),
  popularity('popularity', '人气'),
  views('views', '最多观看'),
  likes('likes', '最多赞');

  const SortType(this.value, this.label);
  final String value;
  final String label;
}

/// 内容分级。
enum Rating {
  all('all', '全部'),
  general('general', '全年龄'),
  ecchi('ecchi', 'R-18');

  const Rating(this.value, this.label);
  final String value;
  final String label;

  static Rating parse(String? v) =>
      Rating.values.firstWhere((e) => e.value == v, orElse: () => Rating.all);
}

/// 官方分类标签。
const kCategoryTags = <(String, String)>[
  ('mikumikudance', 'MMD'),
  ('koikatsu', '恋活'),
  ('honey_select', 'Honey Select'),
  ('blender', 'Blender'),
  ('sfm', 'SFM'),
  ('hmv', 'HMV'),
  ('ai_generated', 'AI 生成'),
  ('uncategorized', '未分类'),
];
