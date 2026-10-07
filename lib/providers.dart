import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/iwara_api.dart';
import 'core/constants.dart';
import 'core/settings.dart';
import 'models/user.dart';

/// 在 main() 中创建并 override。
final apiClientProvider = Provider<ApiClient>(
  (ref) => throw UnimplementedError('apiClientProvider 未初始化'),
);

final apiProvider = Provider<IwaraApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return IwaraApi(
    client,
    saltProvider: () =>
        ref.read(settingsProvider).videoSalt ?? IwaraConst.defaultVideoSalt,
    onSaltUpdated: (salt) => ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(videoSalt: salt)),
  );
});

/// 当前登录用户；未登录时为 null。
class AuthNotifier extends AsyncNotifier<CurrentUser?> {
  @override
  Future<CurrentUser?> build() async {
    final client = ref.watch(apiClientProvider);
    client.onSessionExpired = () => state = const AsyncData(null);
    if (!client.hasSession) return null;
    try {
      return await ref.read(apiProvider).currentUser();
    } catch (e) {
      // token 失效时 client 会清除会话；网络错误时保留会话但显示为未登录信息不可用
      if (!client.hasSession) return null;
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    final api = ref.read(apiProvider);
    await api.login(email, password);
    final me = await api.currentUser();
    state = AsyncData(me);
  }

  Future<void> logout() async {
    await ref.read(apiClientProvider).clearSession();
    state = const AsyncData(null);
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => ref.read(apiProvider).currentUser());
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, CurrentUser?>(AuthNotifier.new);

/// 已登录用户（同步读取，未登录为 null）。
final meProvider = Provider<CurrentUser?>(
  (ref) => ref.watch(authProvider).value,
);

/// 未读计数，每 2 分钟刷新一次。
final countsProvider = FutureProvider<UserCounts>((ref) async {
  final me = ref.watch(meProvider);
  if (me == null) return const UserCounts();
  final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return await ref.read(apiProvider).counts();
  } catch (_) {
    return const UserCounts();
  }
});
