import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 画中画（Android 原生实现，见 MainActivity.kt）。
abstract final class Pip {
  static const _channel = MethodChannel('iwara/pip');

  /// 当前是否处于画中画模式。
  static final inPip = ValueNotifier<bool>(false);

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        inPip.value = call.arguments == true;
      }
    });
  }

  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 立即进入画中画。
  static Future<bool> enter({int width = 16, int height = 9}) async {
    try {
      return await _channel.invokeMethod<bool>(
              'enter', _ratio(width, height)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 设置离开应用（按 Home 键）时是否自动进入画中画。
  static Future<void> setAutoEnter(bool enabled,
      {int width = 16, int height = 9}) async {
    try {
      await _channel.invokeMethod(
          'setAutoEnter', {'enabled': enabled, ..._ratio(width, height)});
    } catch (_) {}
  }

  /// Android 要求宽高比在 1:2.39 ~ 2.39:1 之间。
  static Map<String, int> _ratio(int w, int h) {
    if (w <= 0 || h <= 0) return {'width': 16, 'height': 9};
    final r = w / h;
    if (r > 2.39) return {'width': 239, 'height': 100};
    if (r < 1 / 2.39) return {'width': 100, 'height': 239};
    return {'width': w, 'height': h};
  }
}
