import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config/app_environment.dart';
import 'router/app_router.dart';
import 'router/url_strategy.dart';
import 'services/app_config_api.dart';
import 'services/native_bridge.dart';
import 'services/ndid_api.dart';
import 'services/srisawad_api.dart';
import 'services/user_api.dart';

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
  print(
    '[SawadLoanUniversal] env=${AppEnvironment.current.name} '
    'webVersion=$kWebVersion',
  );
  // Machine-readable token parsed by the native WebView host to detect a stale
  // cached build (LoanUniversalWebWidget._kVersionToken). Keep this exact text.
  // ignore: avoid_print
  print('SawadLoanUniversalWebVersion:$kWebVersion');

  await appState.initializePersistedState();

  // If the native host recovered a document photo after the app was killed
  // mid-capture, it pushes it in here; stash it for the collateral page.
  NativeCameraBridge.listenForRecoveredCapture(
    (bytes) => appState.setRecoveredDocImage(base64Encode(bytes)),
  );

  // Launch params from the native WebView host, e.g.
  // https://.../?hashThaiId=abc123&token=eyJ... — hashThaiId keys the profile
  // + address lookups; token is the Firebase auth token the address endpoint
  // needs. (Path URL strategy is on, so the query is before any path.)
  appState.hashThaiId = Uri.base.queryParameters['hashThaiId'] ?? '';
  appState.authToken = Uri.base.queryParameters['token'] ?? '';
  // Optional; only the P-Loan submission uses these.
  appState.empId = Uri.base.queryParameters['empId'] ?? '';
  appState.mktChannel = Uri.base.queryParameters['mktChannel'] ?? '';
  appState.customerSource = Uri.base.queryParameters['customerSource'] ?? '';

  // Warm the runtime config (Firestore `application/config`) so the API
  // clients' base URL is ready before the user can reach a screen that calls
  // one. Not awaited — boot isn't blocked on it; SrisawadApi.baseUrl() awaits
  // the same memoised future, so a call that beats the fetch still gets the
  // right endpoint rather than the fallback.
  unawaited(_loadRuntimeConfig());

  // Fetch the customer profile + address book in the background so step 1
  // auto-fills. Deliberately not awaited: the UI boots on persisted/mock data
  // and re-seeds when the fetch lands (AppState notifies its listeners).
  unawaited(_loadCustomerProfile());

  runApp(const MyApp());
}

/// Loads the Firestore runtime config and publishes it on [AppState].
///
/// Never throws: [AppConfigApi] resolves to an empty config on any failure and
/// records the reason, which is logged here so a denied read is visible in the
/// WebView console instead of silently falling back.
Future<void> _loadRuntimeConfig() async {
  final config = await AppConfigApi.ensureLoaded();
  appState.appConfig = config;

  final error = AppConfigApi.lastError;
  if (error != null) {
    // ignore: avoid_print — intentional: surface in the WebView console.
    print('[SawadLoanUniversal] app config: $error '
        '(falling back to ${AppEnvironment.current.mobileApiBase})');
  } else {
    // ignore: avoid_print
    print('[SawadLoanUniversal] app config loaded from $kAppConfigPath');
  }

  // Log the endpoints as *resolved*, not just the raw config, and label whether
  // each came from the document or the compile-time default. A silent fallback
  // to the built-in gateway is what let NDID keep talking to the old node for a
  // whole uat cycle: the config read was being rejected by the host bridge, but
  // nothing on screen or in the console said which URL was actually in use.
  // ignore: avoid_print
  print('[SawadLoanUniversal] endpoints: '
      'mobile=${await SrisawadApi.baseUrl()}'
      '${config.apiUrlBase == null ? ' (default)' : ' (config)'} '
      'ndid=${await NdidApi.baseUrl()}'
      '${config.ndidUrlBase == null ? ' (default)' : ' (config)'}');
}

/// Loads the customer profile (`/user/detail`) and address book
/// (`/profile/address`) for the launch `hashThaiId`. Each failure is logged
/// and swallowed — the UI keeps its persisted/mock data.
Future<void> _loadCustomerProfile() async {
  final hash = appState.hashThaiId;
  if (hash.isEmpty) return;

  appState.profileLoading = true;
  try {
    try {
      final detail = await UserApi.fetchUserDetail(hash);
      appState.update(() => appState.customerDetail = detail);
    } catch (e) {
      // ignore: avoid_print — intentional: surface in the WebView console.
      print('[SawadLoanUniversal] user/detail fetch failed: $e');
    }

    try {
      appState.customerAddressBook = await UserApi.fetchAddressBook(
        hash,
        token: appState.authToken,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[SawadLoanUniversal] profile/address fetch failed: $e');
    }
  } finally {
    appState.profileLoading = false;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sawad Loan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      routerConfig: appRouter,
    );
  }
}
