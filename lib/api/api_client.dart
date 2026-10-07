import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import '../core/proxy.dart';
import 'api_exception.dart';

/// 负责 HTTP、鉴权头与 token 刷新。
class ApiClient {
  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: IwaraConst.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'X-Site': IwaraConst.siteHost},
      responseType: ResponseType.json,
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final c = HttpClient();
        c.findProxy = (_) {
          final p = AppHttpOverrides.proxy;
          return p == null ? 'DIRECT' : 'PROXY $p';
        };
        return c;
      },
    );
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  late final Dio dio;
  final _storage = const FlutterSecureStorage();
  static const _kRefresh = 'iwara_refresh_token';

  String? _refreshToken;
  String? _accessToken;
  DateTime? _accessExpiry;
  Future<void>? _refreshing;

  /// 会话代号：登录/退出时递增，用于丢弃旧会话的刷新结果。
  int _session = 0;

  /// token 彻底失效（需重新登录）时回调。
  void Function()? onSessionExpired;

  bool get hasSession => _refreshToken != null;

  Future<void> loadSession() async {
    try {
      _refreshToken = await _storage.read(key: _kRefresh);
    } catch (_) {
      _refreshToken = null;
    }
  }

  Future<void> setRefreshToken(String token) async {
    _session++;
    _refreshing = null;
    _refreshToken = token;
    _accessToken = null;
    _accessExpiry = null;
    await _storage.write(key: _kRefresh, value: token);
  }

  Future<void> clearSession() async {
    _session++;
    _refreshing = null;
    _refreshToken = null;
    _accessToken = null;
    _accessExpiry = null;
    await _storage.delete(key: _kRefresh);
  }

  /// 当前可用的 access token（必要时刷新）。供播放器等外部请求使用。
  Future<String?> accessToken() async {
    if (_refreshToken == null) return null;
    if (_accessToken == null || _isExpiring) await _refreshAccessToken();
    return _accessToken;
  }

  bool get _isExpiring =>
      _accessExpiry != null &&
      _accessExpiry!.difference(DateTime.now()).inSeconds < 60;

  Future<void> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final rt = _refreshToken;
    final session = _session;
    if (rt == null) return;
    try {
      final res = await dio.post<Map<String, dynamic>>(
        'user/token',
        options: Options(
          headers: {'Authorization': 'Bearer $rt'},
          extra: {'noAuth': true},
        ),
      );
      if (session != _session) return; // 会话已切换
      final token = res.data?['accessToken'] as String?;
      if (token == null) throw ApiException('获取访问令牌失败');
      _accessToken = token;
      _accessExpiry = _jwtExpiry(token);
    } on DioException catch (e) {
      if (session != _session) return;
      // 只有服务端明确拒绝 refresh token 时才清除会话；
      // Cloudflare 拦截（403 + HTML）、网络错误等不应导致登出。
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final rejected = status == 401 ||
          (status == 403 && data is Map && data['message'] != null);
      if (rejected) {
        await clearSession();
        onSessionExpired?.call();
        throw ApiException('登录已失效，请重新登录', status: 401);
      }
      rethrow;
    }
  }

  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      return exp is int
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['noAuth'] == true || _refreshToken == null) {
      return handler.next(options);
    }
    try {
      final token = await accessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } catch (e) {
      // 刷新失败时以游客身份继续请求，失败由调用方处理。
      handler.next(options);
    }
  }

  Future<void> _onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (err.response?.statusCode == 401 &&
        _refreshToken != null &&
        req.extra['noAuth'] != true &&
        req.extra['retried'] != true) {
      try {
        _accessToken = null;
        await _refreshAccessToken();
        req.extra['retried'] = true;
        req.headers['Authorization'] = 'Bearer $_accessToken';
        final res = await dio.fetch(req);
        return handler.resolve(res);
      } catch (_) {
        // 继续抛出原错误
      }
    }
    handler.next(err);
  }

  // ---- 便捷方法：统一转换错误 ----

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get<T>(path, queryParameters: _clean(query)));

  Future<T> post<T>(String path,
          {Object? data, Map<String, String>? headers, bool noAuth = false}) =>
      _wrap(() => dio.post<T>(path,
          data: data,
          options: Options(headers: headers, extra: {'noAuth': noAuth})));

  Future<T> put<T>(String path, {Object? data}) =>
      _wrap(() => dio.put<T>(path, data: data));

  Future<T> delete<T>(String path, {Object? data}) =>
      _wrap(() => dio.delete<T>(path, data: data));

  Future<T> _wrap<T>(Future<Response<T>> Function() fn) async {
    try {
      final res = await fn();
      return res.data as T;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    return Map.fromEntries(q.entries.where((e) =>
        e.value != null && !(e.value is String && (e.value as String).isEmpty)));
  }
}
