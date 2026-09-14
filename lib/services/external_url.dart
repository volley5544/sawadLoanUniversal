/// Opening a page **outside** this WebView, and the one URL this app builds
/// for that purpose.
///
/// Everything here goes through the host's `openExternalUrl` JS handler, which
/// this build genuinely needs: `window.open` is inert inside the srisawad host
/// (no `onCreateWindow` is registered), so a tap would otherwise do nothing at
/// all. See `services/native_bridge.dart`.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'app_config_api.dart';
import 'auth_token.dart';
import 'diagnostics.dart';
import 'native_bridge.dart';

/// Opens [url] outside this WebView, reporting the three outcomes the bridge
/// distinguishes.
///
/// `null` from the bridge means the **host has no handler** — an app build
/// predating it — which is a different message from a failure: telling a
/// customer on a current app to update it is worse than saying nothing useful.
Future<void> openExternalDocument(BuildContext context, String url) async {
  final opened = await NativeCameraBridge.openExternalUrl(url);
  if (opened == true || !context.mounted) return;
  final message = opened == null
      ? 'เวอร์ชันแอปนี้ยังไม่รองรับการเปิดเอกสาร กรุณาอัปเดตแอป'
      : 'ไม่สามารถเปิดเอกสารได้ กรุณาลองใหม่อีกครั้ง';
  Diagnostics.log(
      'openExternalUrl ${opened == null ? 'unsupported' : 'failed'}');
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Opens the **application-status** web page — the destination of the top-up
/// flow's ดูสถานะคำขอ / ดูสถานะการขอเพิ่มวงเงิน buttons.
///
/// `<check_application_status>/<hashThaiId>#token=<jwt>`, the shape the
/// srisawad app's ติดตามสถานะ menu item and LandAndHouseWeb's success screen
/// both use.
///
/// ⚠ **The token is a URL fragment, not a query parameter, and that is a
/// security property rather than a style choice.** Fragments are never sent to
/// the server, so the JWT stays out of web-server access logs and out of the
/// `Referer` of anything that page subsequently loads. Moving it to `?token=`
/// would leak a live credential into logs this app does not control.
///
/// The bearer is re-resolved through [AuthToken] rather than taken from the
/// launch param: a top-up routinely outlives the hour a Firebase ID token is
/// good for, and handing the status page a stale one sends the customer to a
/// screen that cannot load.
Future<void> openApplicationStatus(BuildContext context) async {
  final config = await AppConfigApi.ensureLoaded();
  final base = config.checkApplicationStatus;
  if (base == null || base.isEmpty) {
    // Without this the interpolation below would open a broken page with no
    // explanation — the source guards it the same way.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ไม่พบ URL สำหรับติดตามสถานะ')),
    );
    return;
  }
  final appState = AppState();
  final token = await AuthToken.resolve(appState.authToken);
  final url = applicationStatusUrl(
    base: base,
    hashThaiId: appState.hashThaiId,
    token: token,
  );
  if (!context.mounted) return;
  await openExternalDocument(context, url);
}

/// Builds the status URL. Separated from [openApplicationStatus] so the
/// fragment rule above is testable without a host or a network.
String applicationStatusUrl({
  required String base,
  required String hashThaiId,
  required String token,
}) {
  final trimmed = base.trim().replaceAll(RegExp(r'/+$'), '');
  final id = Uri.encodeComponent(hashThaiId.trim());
  // An empty token still yields a valid page URL — the status site can ask the
  // customer to sign in again. A bare `#token=` would be a claim of a
  // credential we do not have, so it is omitted entirely.
  final fragment = token.trim().isEmpty ? '' : '#token=${token.trim()}';
  return '$trimmed/$id$fragment';
}
