import '../core/constants.dart';
import '../models/common.dart';
import '../models/image.dart';
import '../models/user.dart';
import '../models/video.dart';

/// i.iwara.tv 图片地址构造（与官方前端保持一致）。
abstract final class IwaraUrls {
  /// size: thumbnail / large / original / avatar / profileHeader
  static String? file(String size, IwaraFile? f) {
    if (f == null || f.name == null) return null;
    var name = f.name!;
    if (size != 'original') {
      final dot = name.lastIndexOf('.');
      name = '${dot > 0 ? name.substring(0, dot) : name}.jpg';
    }
    return '${IwaraConst.imageHost}/image/$size/${f.id}/$name';
  }

  static String? videoThumbnail(Video v, {String size = 'thumbnail'}) {
    if (v.customThumbnail != null) return file(size, v.customThumbnail);
    final f = v.file;
    if (f != null) {
      final n = v.thumbnail.toString().padLeft(2, '0');
      return '${IwaraConst.imageHost}/image/$size/${f.id}/thumbnail-$n.jpg';
    }
    final embed = v.embedUrl;
    if (embed != null) {
      final parsed = parseEmbed(embed);
      if (parsed != null) {
        return '${IwaraConst.imageHost}/image/embed/$size/${parsed.$1}/${parsed.$2}';
      }
    }
    return null;
  }

  /// 鼠标悬停预览动图。
  static String? videoPreview(Video v) => v.file?.animatedPreview == true
      ? '${IwaraConst.imageHost}/image/original/${v.file!.id}/preview.webp'
      : null;

  static String? imageThumbnail(GalleryImage img) =>
      file('thumbnail', img.thumbnail ?? (img.files.isEmpty ? null : img.files.first));

  static String? avatar(User? u) => file('avatar', u?.avatar);

  /// 解析外链视频，返回 (provider, id)。
  static (String, String)? parseEmbed(String url) {
    final yt = RegExp(
            r'(?:youtube\.com/(?:watch\?v=|embed/|shorts/)|youtu\.be/)([\w-]{6,})')
        .firstMatch(url);
    if (yt != null) return ('youtube', yt.group(1)!);
    return null;
  }

  static String videoPage(String id) => '${IwaraConst.siteUrl}/video/$id';
  static String imagePage(String id) => '${IwaraConst.siteUrl}/image/$id';
  static String profilePage(String username) =>
      '${IwaraConst.siteUrl}/profile/$username';
  static String playlistPage(String id) => '${IwaraConst.siteUrl}/playlist/$id';
  static String forumThreadPage(String section, String id) =>
      '${IwaraConst.siteUrl}/forum/$section/$id';
  static String postPage(String id) => '${IwaraConst.siteUrl}/post/$id';
}
