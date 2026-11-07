import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/local_store.dart';
import 'core/settings_store.dart';
import 'core/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final settings = await SettingsStore.open();
  final store = await LocalStore.open();
  settings.deviceId; // create the permanent UUID on first launch

  final container = ProviderContainer(
    overrides: [settingsProvider.overrideWithValue(settings), localStoreProvider.overrideWithValue(store)],
  );

  // `harb://server?url=https://pc.tailnet.ts.net` sets the server link.
  if (!kIsWeb) {
    final links = AppLinks();
    Future<void> handle(Uri? uri) async {
      final url = uri?.queryParameters['url'];
      if (uri != null && uri.scheme == 'harb' && url != null && url.isNotEmpty) {
        await settings.setServerUrl(url);
        unawaited(container.read(syncProvider).sync());
      }
    }

    unawaited(links.getInitialLink().then(handle).catchError((_) {}));
    links.uriLinkStream.listen(handle, onError: (_) {});
  }

  // send what was played offline, fetch new questions; silent if the server is off
  unawaited(container.read(syncProvider).sync());

  runApp(UncontrolledProviderScope(container: container, child: const HarbApp()));
}
