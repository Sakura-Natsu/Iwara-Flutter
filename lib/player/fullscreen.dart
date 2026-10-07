import 'package:flutter/services.dart';

/// 进入全屏：隐藏系统栏并按视频方向旋转屏幕。
Future<void> enterFullscreen({bool landscape = true}) async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations(landscape
      ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
      : const [DeviceOrientation.portraitUp]);
}

Future<void> exitFullscreen() async {
  // 先显式显示系统栏：沉浸模式（尤其经过画中画后）切回 edgeToEdge 时状态栏可能不恢复
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
      overlays: SystemUiOverlay.values);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp]);
}
