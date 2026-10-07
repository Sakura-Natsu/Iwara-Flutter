import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';

import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../api/urls.dart';
import '../../models/common.dart';

/// 确保拥有写入相册的权限，必要时向用户申请。
Future<bool> ensureGalleryAccess() async {
  try {
    if (await Gal.hasAccess(toAlbum: true)) return true;
    return await Gal.requestAccess(toAlbum: true);
  } catch (_) {
    return false;
  }
}

/// 下载原图并保存到相册「Iwara」。失败时抛出 [ApiException]（中文信息）。
///
/// 传入 [ApiClient] 而非 ref，页面关闭后批量保存仍可继续。
Future<void> saveOriginalToGallery(ApiClient client, IwaraFile f) async {
  final url = IwaraUrls.file('original', f);
  if (url == null) throw ApiException('图片地址无效');
  try {
    final res = await client.dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        extra: {'noAuth': true},
      ),
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) throw ApiException('下载失败：内容为空');
    await Gal.putImageBytes(Uint8List.fromList(bytes),
        album: 'Iwara', name: 'iwara_${f.id}');
  } on GalException catch (e) {
    throw ApiException(switch (e.type) {
      GalExceptionType.accessDenied => '没有相册权限，请在系统设置中允许',
      GalExceptionType.notEnoughSpace => '存储空间不足',
      GalExceptionType.notSupportedFormat => '不支持的图片格式',
      GalExceptionType.unexpected => '保存失败',
    });
  } catch (e) {
    throw ApiException.from(e);
  }
}
