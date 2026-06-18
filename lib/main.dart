import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config/app_environment.dart';
import 'loan_register/loan_register_list_page.dart';

late AppState appState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Which Firebase Hosting environment this build targets (set at build time
  // via --dart-define=ENV=prod|uat; defaults to uat). See AppEnvironment.
  if (kDebugMode) {
    debugPrint('App environment: ${AppEnvironment.current.name}');
  }

  appState = AppState();
  await appState.initializePersistedState();

  // Launch param from the native WebView host, e.g.
  // https://.../#/?hashThaiId=abc123 — used to fetch the customer profile.
  appState.hashThaiId = Uri.base.queryParameters['hashThaiId'] ?? '';
  // TODO: if hashThaiId is set, call the profile API and
  // appState.setCustomerDetailFromJson(...) before/while the UI loads.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sawad Loan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LoanRegisterListPage(),
    );
  }
}
