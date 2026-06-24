import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/customer_detail.dart';

/// Global, app-wide state. Singleton — `AppState()` always returns the same
/// instance, so it can be read/written from anywhere in the app.
///
/// Usage (in `main.dart`):
/// ```dart
/// final appState = AppState();
/// await appState.initializePersistedState();
/// ```
///
/// Anywhere else:
/// ```dart
/// AppState().customerDetail;                  // read
/// AppState().customerDetail = parsed;         // write (persists + notifies)
/// ```
class AppState extends ChangeNotifier {
  static AppState _instance = AppState._internal();

  factory AppState() {
    return _instance;
  }

  AppState._internal();

  static void reset() {
    _instance = AppState._internal();
  }

  late SharedPreferences prefs;

  /// Hashed Thai ID passed in by the native WebView host as a launch query
  /// param (`?hashThaiId=...`). Used to fetch the customer profile on startup.
  String hashThaiId = '';

  /// Base URL of the local NDID Node proxy (`server.js`) the app calls for the
  /// identity-verification flow. Defaults to the Postman collection's
  /// `localhost:7088`; the native host can override it at launch with
  /// `?ndidBaseUrl=...` (read in `main.dart`). No trailing slash.
  String ndidBaseUrl = 'http://localhost:7088';

  /// Callback URL the host registers with DAP for status push (optional). When
  /// empty the verify flow falls back to polling. Override with `?ndidCallbackUrl=`.
  String ndidCallbackUrl = '';

  Future initializePersistedState() async {
    prefs = await SharedPreferences.getInstance();
    _safeInit(() {
      if (prefs.containsKey('ff_customerDetail')) {
        final serialized = prefs.getString('ff_customerDetail') ?? '{}';
        _customerDetail = CustomerDetail.fromJson(
          jsonDecode(serialized) as Map<String, dynamic>,
        );
      }
    });
  }

  /// Wrap mutations so listeners rebuild, e.g.
  /// `AppState().update(() => AppState().customerDetail = parsed);`
  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  // --- CustomerDetail --------------------------------------------------------

  CustomerDetail _customerDetail = const CustomerDetail();
  CustomerDetail get customerDetail => _customerDetail;
  set customerDetail(CustomerDetail value) {
    _customerDetail = value;
    prefs.setString('ff_customerDetail', jsonEncode(value.toJson()));
  }

  /// Parse a raw API map straight into the global [customerDetail].
  void setCustomerDetailFromJson(Map<String, dynamic> json) {
    customerDetail = CustomerDetail.fromJson(json);
  }

  /// Mutate the current customer in place via [copyWith], then persist.
  void updateCustomerDetail(
    CustomerDetail Function(CustomerDetail current) updateFn,
  ) {
    customerDetail = updateFn(_customerDetail);
  }

  /// Clear the persisted customer (e.g. on logout).
  void clearCustomerDetail() {
    _customerDetail = const CustomerDetail();
    prefs.remove('ff_customerDetail');
  }
}

void _safeInit(Function() initializeField) {
  try {
    initializeField();
  } catch (e) {
    debugPrint("Can't decode persisted data type. Error: $e.");
  }
}
