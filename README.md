# Sawad Loan Universal

Flutter app for a Thai loan-application (**สมัครสินเชื่อ**) flow.

**Deployment model:** this is built as a **Flutter web** app and embedded inside
a separate **native Flutter app** via
[`flutter_inappwebview`](https://pub.dev/packages/flutter_inappwebview) (the
native host opens this web build in a WebView). The Android/iOS/desktop
scaffolding still exists, but the **web build is what ships**.

> Status: **mostly UI-only** — the loan wizard renders from mock data and a
> customer profile the native host will provide (no submit/draft backend yet).
> The one live integration is the **NDID identity-verification** flow, which
> calls the local NDID Node proxy. UI text/data is Thai; code comments are English.

## Build & run

```sh
flutter pub get
flutter analyze --no-pub                      # only pre-existing flutter_lints infos
flutter test                                  # widget smoke test
flutter build web --release --pwa-strategy=none
```

- Output is in `build/web/`. Serve that wherever the native host points its
  WebView.
- Build web with **`--pwa-strategy=none`** so the Flutter service worker doesn't
  serve a stale build inside the WebView.

## Launch parameter

The native host launches the web URL with a hashed Thai ID:

```
https://<host>/?hashThaiId=<hash>
```

`main.dart` reads it into `AppState.hashThaiId`. The intended (TODO) flow is to
fetch the customer profile by that hash and seed `AppState.customerDetail`, so
step 1 of the wizard auto-fills.

The host may also override the NDID proxy endpoints (see below):

```
https://<host>/?hashThaiId=<hash>&ndidBaseUrl=<url>&ndidCallbackUrl=<url>
```

`ndidBaseUrl` → `AppState.ndidBaseUrl` (default `http://localhost:7088`),
`ndidCallbackUrl` → `AppState.ndidCallbackUrl` (empty ⇒ status is polled only).

## The wizard

A 5-step loan-register flow under `lib/loan_register/`:

1. **ข้อมูลลูกค้า** — customer info (auto-filled from the profile)
2. **ข้อมูลหลักประกัน** — collateral info (+ document/OCR capture)
3. **ข้อมูลสินเชื่อ / ข้อมูลการโอนเงิน** — loan & transfer info
4. **จำนวนงวด** — installment picker
5. **ประเภทการโอน** — transfer-type picker

## NDID identity verification

Step 1 (**ข้อมูลลูกค้า**) has a **การยืนยันตัวตน NDID** card that launches a full
NDID/DAP identity-verification flow (`lib/ndid/ndid_verify_page.dart`). The
result (`ACCEPTED`/`REJECTED`/…) is written back onto the wizard form
(`LoanRegisterForm.ndidStatus`, `form.ndidVerified`).

```dart
// lib/services/ndid_service.dart  (RP role)
final svc = NdidService(baseUrl: AppState().ndidBaseUrl);
final idps   = await svc.listIdps(identifier: '<13-digit-id>');   // POST /idp/list
final result = await svc.verify(identifier: '...', idpIdList: [...]); // POST /rp/verify
final status = await svc.checkStatus(result.referenceId);         // GET  /rp/verify/{ref}
await svc.close(result.referenceId);                              // POST /rp/verify/{ref}/close
```

- **It calls the local NDID Node proxy** (`server.js`, default
  `http://localhost:7088`), *not* the DAP proxy directly — the node owns the RSA
  token, so the app never signs or sends a token. See
  `dap/NDID_Local_API.postman_collection.json` and
  `dap/NDID_Proxy_Specification_V4.0.pdf`.
- **Flow:** list IdPs for the citizen id → pick one → `verify` (returns
  `reference_id` + `ndid_request_id`) → **poll** status every 4s until a terminal
  state; a "ยกเลิกคำขอ" button closes a pending request. Override the endpoint at
  launch with `?ndidBaseUrl=` / `?ndidCallbackUrl=` (see *Launch parameter*).
- The proxy must allow CORS from the WebView origin (that's the node's concern).

## Document / OCR capture (web ↔ native camera)

The web build has **no camera**; the document photo is captured by the **native
host's** camera so it gets a proper masked camera UI. The web asks for a capture
via `flutter_inappwebview`'s `callHandler` and awaits the result:

```dart
// lib/services/native_bridge.dart  (web impl in native_bridge_web.dart)
final base64 = await NativeCameraBridge.captureDocument('collateral');
// -> window.flutter_inappwebview.callHandler('openCamera', 'collateral')
```

`captureDocument` returns `Uint8List?` (`null` = cancelled). It's a no-op outside
the WebView host (`NativeCameraBridge.isSupported` is `false` in a plain
browser, so the UI shows a "ใช้ได้เฉพาะในแอป" message).

### Native host implementation

The embedding app registers an `openCamera` JS handler that opens its camera for
the requested mask type and **returns the photo as a base64 string** — that
value resolves the awaited Promise on the web side:

```dart
webViewController.addJavaScriptHandler(
  handlerName: 'openCamera',
  callback: (args) async {
    final action = args.isNotEmpty ? '${args.first}' : ''; // 'collateral', 'idcard', ...
    final bytes = await openNativeCamera(action);          // your masked camera
    if (bytes == null) return null;                        // user cancelled
    return base64Encode(bytes);                            // resolves the JS Promise
  },
);
```

Tips for the host:
- Return a plain `String` (or `null`) — not a `Uint8List`.
- The `async` callback is fine; the Promise resolves when the `Future` completes.
- Compress the photo (~1280px / JPEG ~80) before base64 to keep the bridge fast.
- Camera permission is needed by the **host app** (Android `CAMERA`, iOS
  `NSCameraUsageDescription`) — not WebView `getUserMedia`, since the camera is
  native.

The full handler example also lives in the doc comment of
`lib/services/native_bridge.dart`.

## Project layout

```
lib/
  main.dart                     app entry; reads ?hashThaiId / ?ndidBaseUrl; home = list page
  app_state.dart                ChangeNotifier singleton; persists CustomerDetail
  models/
    customer_detail.dart        plain-Dart API model (snake_case JSON)
    ndid_models.dart            NDID/DAP models (IdP, verify result, status enum)
  services/
    native_bridge.dart          public entry (conditional import)
    native_bridge_web.dart      web impl (flutter_inappwebview callHandler)
    native_bridge_stub.dart     non-web stub (throws / isSupported=false)
    ndid_service.dart           NDID/DAP REST client (http -> local node proxy)
  ndid/
    ndid_verify_page.dart       NDID identity-verification flow (4 stages)
  loan_register/
    *_page.dart                 the wizard steps & pickers
    models/loan_register_form.dart   in-memory wizard model (+ mock data)
    components/                  shared field rows, styles, step indicator, etc.
```

See [CLAUDE.md](CLAUDE.md) for the full architecture notes, conventions, and
known quirks.
</content>
