import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'core/proxy.dart';
import 'core/settings.dart';
import 'player/audio_handler.dart';
import 'player/pip.dart';
import 'providers.dart';
import 'services/download_service.dart';
import 'services/local_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings.load(prefs);
  AppHttpOverrides.install();
  AppHttpOverrides.proxy = settings.proxyAddress;

  final client = ApiClient();
  await client.loadSession();
  await LocalDb.init();
  Pip.init();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 不阻塞首屏
  IwaraAudioHandler.init();
  DownloadService.init(proxy: settings.proxyAddress);

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(client),
    ],
    retry: (_, _) => null,
    child: const IwaraApp(),
  ));
}
