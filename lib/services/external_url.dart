/// Opening a page **outside** this WebView, and the one URL this app builds
/// for that purpose.
///
/// Everything here goes through the host's `openExternalUrl` JS handler, which
/// this build genuinely needs: `window.open` is inert inside the srisawad host
/// (no `onCreateWindow` is registered), so a tap would otherwise do nothing at
/// all. See `services/native_bridge.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../config/app_environment.dart';
import '../loan_register/components/loan_register_styles.dart';
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
///
/// On a failure a **non-prod** build also shows the URL it tried, with a copy
/// button. "ไม่สามารถเปิดเอกสารได้" on its own cannot distinguish a URL the
/// host refused as un-allowlisted from a popup a browser blocked, and those
/// have opposite fixes.
Future<void> openExternalDocument(BuildContext context, String url) async {
  final opened = await NativeCameraBridge.openExternalUrl(url);
  if (opened == true || !context.mounted) return;
  final message = opened == null
      ? 'เวอร์ชันแอปนี้ยังไม่รองรับการเปิดเอกสาร กรุณาอัปเดตแอป'
      : 'ไม่สามารถเปิดเอกสารได้ กรุณาลองใหม่อีกครั้ง';
  final why = opened == null ? 'unsupported' : 'failed';
  Diagnostics.log('openExternalUrl $why ${maskUrlSecrets(url)}');

  if (AppEnvironment.current.isProd) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  await _showUrlFailureDialog(context, message: message, url: url, why: why);
}

/// The URL with its credentials masked, for anything a human will read.
///
/// ⚠ **The application-status URL carries a live bearer token in its
/// fragment.** Printing it raw would put a working credential on screen and,
/// via the copy button, on the clipboard and into whatever chat the report is
/// pasted into. The length is kept so "no token" and "token present" stay
/// distinguishable — the same masking `Diagnostics.report` applies, and for
/// the same reason.
String maskUrlSecrets(String url) {
  var masked = url;
  // Fragment first: `#token=…` is how the status page takes it.
  masked = masked.replaceAllMapped(
    RegExp(r'([#&?]token=)([^&#]*)'),
    (m) => '${m[1]}<redacted:${m[2]!.length} chars>',
  );
  masked = masked.replaceAllMapped(
    RegExp(r'([?&]hashThaiId=)([^&#]*)'),
    (m) => '${m[1]}<redacted:${m[2]!.length} chars>',
  );
  return masked;
}

Future<void> _showUrlFailureDialog(
  BuildContext context, {
  required String message,
  required String url,
  required String why,
}) {
  final masked = maskUrlSecrets(url);
  final report = '$message\n\n$why\n$masked';
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        'เปิดเอกสารไม่สำเร็จ',
        style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              message,
              style: GoogleFonts.notoSansThai(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'URL ที่พยายามเปิด (สำหรับผู้พัฒนา)',
              style: GoogleFonts.notoSansThai(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: LoanRegisterStyles.primary,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              masked,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            Text(
              why == 'unsupported'
                  // The three states are worth spelling out: each has a
                  // different fix, and the message alone cannot separate them.
                  ? 'บริดจ์ openExternalUrl ยังไม่มีในแอปเวอร์ชันนี้ '
                      '— ต้องออกแอปใหม่'
                  : 'โฮสต์ปฏิเสธ URL นี้ (ไม่อยู่ใน allowlist หรือไม่ใช่ '
                      'https) หรือเบราว์เซอร์บล็อกป๊อปอัป',
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                height: 1.5,
                color: LoanRegisterStyles.label,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('คัดลอกแล้ว')),
            );
          },
          child: Text('คัดลอก', style: GoogleFonts.notoSansThai()),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
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
  // Config first, compile-time value as the degrade-to — the same order
  // `SrisawadApi.baseUrl()` uses. ⚠ On prod the fallback is currently the only
  // source: that project has no config document and no web app key to read one
  // with, so a config-only lookup would leave its status buttons dead.
  final config = await AppConfigApi.ensureLoaded();
  final base = config.checkApplicationStatus?.trim().isNotEmpty == true
      ? config.checkApplicationStatus!
      : AppEnvironment.current.checkApplicationStatusBase;
  if (base.trim().isEmpty) {
    // Only reachable if a future environment ships without either. Without
    // this the interpolation below would open a broken page with no
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
