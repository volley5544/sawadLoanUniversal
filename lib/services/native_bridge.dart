/// Bridge between this web app and the native Flutter host that embeds it in a
/// `flutter_inappwebview` WebView.
///
/// The OCR/document camera lives on the **native** side (so it gets a proper
/// camera + framing mask). The web app asks for a capture; the native host
/// opens the camera, takes the photo, compresses it, and sends the image back
/// as base64.
///
/// ## Contract with the native host (`flutter_inappwebview` JS handler)
///
/// The web calls a JavaScript handler and `await`s its result — the captured
/// image comes straight back, no console-log / CustomEvent round trip:
///
/// ```js
/// // injected by flutter_inappwebview inside the WebView:
/// const base64 = await window.flutter_inappwebview.callHandler('openCamera', action);
/// ```
///
/// **Native host (Dart, in the app that embeds this web build):** register a
/// handler named `openCamera` that opens the camera for the requested mask,
/// and **return** the photo as a base64 string (raw or a
/// `data:image/...;base64,` URL — both decode here). Returning `null`/`''`
/// means "cancelled / no image" and resolves [captureDocument] with `null`.
///
/// ```dart
/// webViewController.addJavaScriptHandler(
///   handlerName: 'openCamera',
///   callback: (args) async {
///     final action = args.isNotEmpty ? args.first as String : '';
///     final bytes = await openNativeCamera(action); // your camera + mask
///     if (bytes == null) return null;               // user cancelled
///     return base64Encode(bytes);                    // -> resolves the JS Promise
///   },
/// );
/// ```
///
/// `action` is the mask type (e.g. `collateral`, `idcard`). Because the handler
/// is bidirectional, requests/responses are inherently correlated — no manual
/// id matching needed.
///
/// ## `openBranchPicker` — appointment branch selection (step 5)
///
/// The branch map (nearby search, GPS, Google Maps) also lives on the native
/// side. The web asks the host to open its branch-picker map; the host pushes
/// a selection-mode map page and **returns the chosen branch as a JSON
/// string**:
///
/// ```dart
/// webViewController.addJavaScriptHandler(
///   handlerName: 'openBranchPicker',
///   callback: (args) async {
///     final branch = await Navigator.push<BranchDetail>(
///         context, MaterialPageRoute(builder: (_) => BranchPickerPage()));
///     if (branch == null) return null; // user cancelled
///     return jsonEncode({
///       'branchName': branch.branchName,
///       'address': branch.brnachAddress,
///       'phone': branch.mobilePhoneNumber,
///       'lat': branch.latitude,
///       'lng': branch.longtitude,
///     });
///   },
/// );
/// ```
///
/// Returning `null`/`''` = cancelled (resolves with `null`). In a plain
/// browser (no host) the web falls back to its own searchable branch list.
///
/// ## `httpRequest` — CORS-free HTTP proxy (NDID API)
///
/// The NDID gateway sends no CORS headers and 401s browser preflights, so the
/// web can't fetch it directly. Inside the host, `NdidApi` sends every request
/// through this handler instead; the host performs it with native HTTP and
/// returns the result. The single argument and the return value are **JSON
/// strings**:
///
/// ```dart
/// webViewController.addJavaScriptHandler(
///   handlerName: 'httpRequest',
///   callback: (args) async {
///     final req = jsonDecode(args.first as String) as Map<String, dynamic>;
///     // req: {method: 'GET'|'POST', url, headers: {..}?, body: String?}
///     // SECURITY: only proxy allowlisted URL prefixes (the NDID gateway).
///     if (!allowedPrefixes.any('${req['url']}'.startsWith)) {
///       return jsonEncode({'status': 0, 'error': 'URL not allowed'});
///     }
///     final res = await doNativeHttp(req); // http.get/post + timeout
///     return jsonEncode({'status': res.statusCode, 'body': res.body});
///     // network failure -> {'status': 0, 'error': '...'}
///   },
/// );
/// ```
///
/// (Implemented in the srisawad host's `loan_universal_web_widget.dart`.)
///
/// ⚠ **The allowlist and the NDID gateway URL are coupled across two repos.**
/// `NdidApi.baseUrl()` now takes the gateway from `api_url['ndid_url_base']` in
/// the Firestore config, which anyone can edit without a build — but the host's
/// `_kHttpRequestAllowedPrefixes` is compiled into the **app**. Pointing that
/// key at a host the app doesn't allowlist makes every NDID call fail with
/// `URL not allowed`, and fixing it needs an app release, not a web deploy.
/// Keep the two in step.
///
/// ## `getAuthToken` — a currently-valid Firebase ID token
///
/// The host launches this build with the customer's token in the URL
/// (`?token=`), which `main.dart` reads once into `AppState.authToken`. That
/// cannot carry a whole session:
///
///   * Firebase ID tokens expire after **an hour**, and a P-Loan application
///     routinely runs longer — the tail of a long flow 401s, `/ploan` submit
///     included.
///   * Path URL strategy is on, so go_router replaces the whole location on
///     navigation: after step 1 the launch query is gone from
///     `window.location`. Every reload the host can trigger (stale-build
///     reload, iOS content-process reload, its retry button) therefore
///     re-boots this app with **no token at all**.
///
/// So the token is resolved per request through this handler
/// (`AuthToken.resolve`, `lib/services/auth_token.dart`), with the launch param
/// kept only as the fallback for a plain browser or an older host.
///
/// ```dart
/// webViewController.addJavaScriptHandler(
///   handlerName: 'getAuthToken',
///   // Ask the SDK, never a cached copy in storage: the cached one is only
///   // rewritten by an idTokenChanges listener and can be an hour stale.
///   callback: (args) async => await currentFirebaseToken(), // '' = signed out
/// );
/// ```
///
/// Return a plain **string**, and `''` — never `null` — when nobody is signed
/// in. An unregistered handler resolves its JS promise with `null`, so `null`
/// is how this side detects an outdated host; answering signed-out with `null`
/// too would make the two indistinguishable.
///
/// (Implemented in the srisawad host's `loan_universal_web_widget.dart`, which
/// also injects a fresh bearer onto mobile-API calls that come through
/// `httpRequest` — that covers a cached web build too old to call this handler,
/// but **not** the two direct uploads below, which is why this handler is the
/// actual fix.)
///
/// ## `httpMultipart` — CORS-free multipart upload
///
/// **No longer needed as of 2026-08-04, and never implemented.** It existed for
/// the old P-Loan save endpoint (`<:8082>/SavePloanContract`), which took
/// `multipart/form-data` and sent no CORS headers. That endpoint has been
/// retargeted to `POST <api_url_base>/ploan` — a JSON, bearer-authenticated call
/// on the mobile API base that goes through `httpRequest`/`package:http` like
/// every other mobile-API call — so nothing in this app now needs a multipart
/// bridge. The snippet below is kept only as the reference pattern should a
/// future file-upload endpoint appear: it takes the parts **base64-encoded
/// inside the JSON envelope** and lets the host assemble the real multipart
/// request natively.
///
/// ```dart
/// webViewController.addJavaScriptHandler(
///   handlerName: 'httpMultipart',
///   callback: (args) async {
///     final req = jsonDecode(args.first as String) as Map<String, dynamic>;
///     // req: {url, headers: {..}?, fields: {name: value},
///     //       files: [{field: 'carImage[]', filename, contentType, base64}]}
///     // SECURITY: allowlist the URL prefix, exactly as for httpRequest.
///     if (!allowedPrefixes.any('${req['url']}'.startsWith)) {
///       return jsonEncode({'status': 0, 'error': 'URL not allowed'});
///     }
///     final request = http.MultipartRequest('POST', Uri.parse('${req['url']}'))
///       ..headers.addAll(Map<String, String>.from(req['headers'] ?? {}))
///       ..fields.addAll(Map<String, String>.from(req['fields'] ?? {}));
///     for (final f in (req['files'] as List? ?? [])) {
///       request.files.add(http.MultipartFile.fromBytes(
///         '${f['field']}', base64Decode('${f['base64']}'),
///         filename: '${f['filename']}',
///         contentType: MediaType.parse('${f['contentType']}'),
///       ));
///     }
///     final res = await http.Response.fromStream(await request.send());
///     return jsonEncode({'status': res.statusCode, 'body': res.body});
///     // network failure -> {'status': 0, 'error': '...'}
///   },
/// );
/// ```
///
/// Do **not** set `Content-Type` from `headers` — `MultipartRequest` has to
/// append its own boundary.
library;

export 'native_bridge_stub.dart'
    if (dart.library.js_interop) 'native_bridge_web.dart';
