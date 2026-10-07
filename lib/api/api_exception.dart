import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});

  final String message;
  final int? status;

  /// 官方错误 key，如 errors.notFound
  final String? code;

  bool get isUnauthorized => status == 401;
  bool get isNotFound => status == 404;

  @override
  String toString() => message;

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final inner = e.error;
      if (inner is ApiException) return inner;
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String? code;
      if (data is Map) {
        code = data['message']?.toString();
        final errors = data['errors'];
        if ((code == null || code == 'errors.validationError') &&
            errors is List &&
            errors.isNotEmpty) {
          final first = errors.first;
          if (first is Map && first['message'] != null) {
            code = first['message'].toString();
          }
        }
      }
      final msg = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          '网络超时，请检查网络或代理设置',
        DioExceptionType.connectionError => '无法连接服务器，请检查网络或代理设置',
        DioExceptionType.badCertificate => '证书校验失败',
        DioExceptionType.cancel => '请求已取消',
        _ => translateError(code) ??
            (data is String && data.contains('Just a moment')
                ? '被 Cloudflare 拦截，请稍后重试或更换代理节点'
                : _statusMessage(status)),
      };
      return ApiException(msg, status: status, code: code);
    }
    return ApiException(e.toString());
  }

  static String _statusMessage(int? status) => switch (status) {
        null => '网络错误',
        401 => '登录已失效，请重新登录',
        403 => '没有权限访问',
        404 => '内容不存在或已被删除',
        429 => '请求过于频繁，请稍后再试',
        >= 500 => '服务器错误（$status），请稍后再试',
        _ => '请求失败（$status）',
      };
}

String? translateError(String? code) {
  if (code == null) return null;
  return _zhErrors[code] ?? (code.startsWith('errors.') ? null : code);
}

const _zhErrors = <String, String>{
  'errors.categoryRequired': '仅需要一个类别标签。',
  'errors.fieldRequired': '此字段是必需的。',
  'errors.forbidden': '您的帐户没有执行此操作所需的权限。',
  'errors.forbidden.sendFriendRequest': '受限帐户无法发送好友请求。',
  'errors.forbidden.startConversation': '受限帐户无法发起对话。',
  'errors.forbidden.createForumThread': '受限帐户无法创建论坛帖子。',
  'errors.gone': '内容已不存在。',
  'errors.incorrectPassword': '密码错误',
  'errors.invalidCaptcha': '验证码错误',
  'errors.invalidContent': '内容可能包含诈骗信息',
  'errors.invalidEmail': '邮箱不可用',
  'errors.invalidLogin': '账号或密码错误。',
  'errors.invalidPassword': '密码必须是6个字符或更长。',
  'errors.notFound': '未找到',
  'errors.privateVideo': '这是私人视频',
  'errors.serverError': '服务器祈祷中，请稍后再试。',
  'errors.tooLong': '内容太长',
  'errors.tooManyRequests': '服务器拥堵或请求过于频繁，请稍后再试。',
  'errors.userBanned': '你的账号已被封禁',
  'errors.validationError': '输入内容校验失败',
  'errors.differentSite': '此内容属于网络中的另一个站点。',
  'errors.notFriends': '你们还不是好友',
  'errors.cooldown': '操作太快了，请稍后再试',
};
