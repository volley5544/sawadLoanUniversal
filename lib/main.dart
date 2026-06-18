import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config/app_environment.dart';
import 'router/app_router.dart';
import 'router/url_strategy.dart';

late AppState appState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean per-page URLs on web (e.g. /customerInfoPage instead of /#/...).
  // No-op off-web. Must run before runApp. See router/url_strategy.dart.
  configureUrlStrategy();

  // Stamp + log this build's version and environment on every boot (release
  // included). Surfaces in the browser / WebView console so we can spot a
  // client running a stale cached web build. See AppEnvironment / kWebVersion.
  appState = AppState();
  appState.webVersion = kWebVersion;
  // ignore: avoid_print — intentional: must reach console.log in release too.
  print('[SawadLoanUniversal] env=${AppEnvironment.current.name} '
      'webVersion=$kWebVersion');
  // Machine-readable token parsed by the native WebView host to detect a stale
  // cached build (LoanUniversalWebWidget._kVersionToken). Keep this exact text.
  // ignore: avoid_print
  print('SawadLoanUniversalWebVersion:$kWebVersion');

  await appState.initializePersistedState();

  // Launch param from the native WebView host, e.g.
  // https://.../?hashThaiId=abc123 — used to fetch the customer profile.
  // (Path URL strategy is on, so the query is before any path, not after a #.)
  appState.hashThaiId = Uri.base.queryParameters['hashThaiId'] ?? '';
  // TODO: if hashThaiId is set, call the profile API and
  // appState.setCustomerDetailFromJson(...) before/while the UI loads.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sawad Loan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      routerConfig: appRouter,
    );
  }
}
