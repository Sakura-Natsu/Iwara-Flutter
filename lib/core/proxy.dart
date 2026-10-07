import 'dart:io';

/// 全局代理：所有基于 dart:io HttpClient 的请求（dio、图片缓存等）都会经过这里。
class AppHttpOverrides extends HttpOverrides {
  AppHttpOverrides._();

  static final instance = AppHttpOverrides._();

  /// 形如 `127.0.0.1:7890`，为空时直连（或交给系统 VPN）。
  static String? proxy;

  static void install() => HttpOverrides.global = instance;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final p = proxy;
      return p == null ? 'DIRECT' : 'PROXY $p';
    };
    return client;
  }
}
