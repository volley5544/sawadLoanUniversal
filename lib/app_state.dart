import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_config.dart';
import 'models/customer_address.dart';
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

  /// Firebase auth token passed in by the native WebView host as a launch
  /// query param (`?token=...`, appended by the สมัครสินเชื่อ button). Sent as
  /// `Authorization: Bearer` on the mobile API's address endpoint.
  String authToken = '';

  /// True while the startup profile + address fetch (`_loadCustomerProfile`
  /// in `main.dart`) is in flight. Step 1 shows a loading overlay while set so
  /// the user knows the auto-fill data is still on its way.
  bool _profileLoading = false;
  bool get profileLoading => _profileLoading;
  set profileLoading(bool value) {
    if (_profileLoading == value) return;
    _profileLoading = value;
    notifyListeners();
  }

  /// Customer address book fetched on startup (`UserApi.fetchAddressBook`).
  /// Null until loaded (or when the fetch failed). In-memory only — refetched
  /// each launch.
  CustomerAddressBook? _customerAddressBook;
  CustomerAddressBook? get customerAddressBook => _customerAddressBook;
  set customerAddressBook(CustomerAddressBook? value) {
    _customerAddressBook = value;
    notifyListeners();
  }

  /// Runtime config read from Firestore on startup (`AppConfigApi`), holding
  /// the `api_url` map the API clients resolve their base URL from. Null until
  /// the fetch lands; an empty [AppConfig] when it failed, in which case the
  /// clients fall back to the compile-time [AppEnvironment] endpoint.
  /// In-memory only — refetched each launch so a config change takes effect on
  /// the next load.
  AppConfig? _appConfig;
  AppConfig? get appConfig => _appConfig;
  set appConfig(AppConfig? value) {
    _appConfig = value;
    notifyListeners();
  }

  /// Optional launch parameters the P-Loan submission needs but nothing in
  /// the app can derive: the staff id raising the application and the
  /// marketing/source codes. Read from the launch URL in `main.dart`
  /// (`?empId=&mktChannel=&customerSource=`); empty when the host omits them,
  /// which surfaces in `PLoanSubmission.unresolvedFields` rather than being
  /// guessed. See `p_loan/application/models/p_loan_submission.dart`.
  String empId = '';
  String mktChannel = '';
  String customerSource = '';

  /// This web build's version stamp (from `--dart-define=WEB_VERSION`, set in
  /// `main.dart` to `kWebVersion`). Lets us detect a stale cached web build —
  /// see `config/app_environment.dart`.
  String webVersion = '0';

  /// A document photo recovered by the native host after the app was killed
  /// mid-capture (pushed in via the `onRecoveredCapture` event — see
  /// `services/native_bridge.dart`). Held here as base64 until the collateral
  /// page mounts and consumes it.
  String pendingDocImageBase64 = '';

  /// Stores a recovered document photo and notifies listeners (so a mounted
  /// collateral page picks it up immediately).
  void setRecoveredDocImage(String base64) {
    pendingDocImageBase64 = base64;
    notifyListeners();
  }

  /// Clears the recovered photo once a page has consumed it.
  void clearRecoveredDocImage() {
    pendingDocImageBase64 = '';
  }

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
