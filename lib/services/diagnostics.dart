import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_environment.dart';

/// On-device diagnostics: a breadcrumb trail that survives a reload, plus a
/// readable error screen in place of Flutter's blank grey one.
///
/// **Why this exists.** iOS testers reported the WebView "going white", and we
/// had no way to tell which of two very different things had happened:
///
/// * a **Dart exception** during `build` — in a release build Flutter paints
///   `RenderErrorBox`, a textless `0xF0C0C0C0` rectangle that is
///   indistinguishable from a dead WebView; or
/// * the **WKWebView content process being killed**, after which no Flutter code
///   runs at all.
///
/// Neither was observable: `isInspectable` defaults to false on iOS 16.4+ so
/// Safari Web Inspector cannot attach, the host's `onConsoleMessage` output goes
/// to a Xcode console the tester does not have, and the report arrives as a
/// screenshot of a white rectangle.
///
/// So the screen itself has to carry the evidence. [installHandlers] replaces
/// the grey box with [DiagnosticsErrorView], which names the exception and shows
/// the last [_maxCrumbs] breadcrumbs. That makes the two cases tell themselves
/// apart from a single screenshot:
///
/// | Tester sees | Conclusion |
/// | --- | --- |
/// | this error screen, with a message | a Dart exception — the trail says where |
/// | a blank white screen, nothing on it | the content process died; no Dart ran |
///
/// And because breadcrumbs are persisted, the *next* boot can still show what
/// the previous session was doing when it stopped — a trail that ends at
/// `lifecycle hidden` with no `ERROR` crumb after it is the signature of a
/// process kill rather than a crash.
///
/// Reachable in the UI by tapping the `(UAT ver…)` tag in any AppBar
/// ([showDiagnosticsSheet]). Hidden on prod, like the tag itself.
abstract final class Diagnostics {
  /// This run's trail. Rewritten on every breadcrumb, so kept deliberately small.
  static const String _prefsKey = 'sl_diagnostics_trail';

  /// The run before this one, and the one before that.
  ///
  /// **Two are kept, not one, because a reload eats a slot.** The failure we are
  /// chasing destroys the JS context and the page comes back through a full
  /// initial load — which is itself a new run. With a single slot, the run that
  /// died is demoted to "previous" and then overwritten by the very next reload,
  /// so the evidence expires before a tester can be asked to look at it. Two
  /// slots survive one reload.
  ///
  /// Two keys are enough for three runs: this one lives in [_prefsKey], and each
  /// boot copies that into [_prefsKeyPrev] before starting fresh — so a boot reads
  /// run N-1 from the first key and run N-2 from the second.
  static const String _prefsKeyPrev = 'sl_diagnostics_trail_prev';

  /// Ring-buffer size. Enough to cover an entire P-Loan Extra run (a dozen route
  /// changes plus lifecycle transitions) without letting a poll loop that logs
  /// push the interesting part out.
  static const int _maxCrumbs = 40;

  static final List<String> _crumbs = <String>[];

  /// Breadcrumbs recovered from the run before this one. Empty on a first boot,
  /// or after [clear].
  static List<String> previousRun = const <String>[];

  /// The run before [previousRun]. See [_prefsKeyPrev2] for why this exists.
  static List<String> previousRun2 = const <String>[];

  /// The most recent error this run, as `"<exception>"`. Null until one happens.
  static String? lastError;

  /// First few frames of [lastError]'s stack. Truncated on purpose: the whole
  /// thing would not fit on a phone screen and is not what identifies the bug.
  static String? lastStack;

  static SharedPreferences? _prefs;
  static bool _installed = false;

  /// Current run's trail, oldest first.
  static List<String> get trail => List<String>.unmodifiable(_crumbs);

  /// Appends one breadcrumb. Cheap and never throws — call it freely.
  ///
  /// Also `print`s, so a session that *can* reach a console gets the trail
  /// interleaved with the app's other logging.
  static void log(String event) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    _crumbs.add('$stamp $event');
    if (_crumbs.length > _maxCrumbs) _crumbs.removeAt(0);
    // ignore: avoid_print — intentional: surface in the WebView console.
    print('[SawadLoanUniversal] $event');
    _persist();
  }

  /// Installs the error hooks. Call as early as possible in `main()` — before
  /// anything that can throw, and before `runApp`.
  ///
  /// Safe to call twice; the second call is a no-op.
  static void installHandlers() {
    if (_installed) return;
    _installed = true;

    // The one that matters for the white screen: this is what Flutter renders in
    // place of a widget whose build threw. The default is RenderErrorBox.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      _record(details.exception, details.stack);
      return DiagnosticsErrorView(
        message: details.exceptionAsString(),
        trail: trail,
      );
    };

    FlutterError.onError = (FlutterErrorDetails details) {
      _record(details.exception, details.stack);
      // Keep the framework's own console output — this hook replaces it.
      FlutterError.presentError(details);
    };

    // Uncaught *asynchronous* errors, which never reach FlutterError.onError.
    // Returning true marks them handled: on web they would not tear the app down
    // anyway, and swallowing them here is what keeps the trail intact for the
    // screen that is about to be reported.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _record(error, stack);
      return true;
    };

    // Lifecycle transitions are the signal for the process-kill case: Flutter web
    // drives these from page visibility, so a trail ending in `lifecycle hidden`
    // says the WebView was backgrounded before it stopped — which is when iOS
    // reclaims a WebContent process.
    //
    // Deliberately not held in a field and never disposed: it must observe for
    // the whole process, and a field would only ever be written, never read.
    AppLifecycleListener(
      onStateChange: (AppLifecycleState state) => log('lifecycle ${state.name}'),
    );
  }

  /// Loads the previous run's trail into [previousRun] and starts this run's.
  ///
  /// Call after `SharedPreferences` is available (i.e. after
  /// `AppState.initializePersistedState`). Never throws.
  static Future<void> restorePrevious() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      // Shift the window: what was current becomes previous, previous becomes
      // previous-2, and the oldest falls off. Done here rather than at shutdown
      // because the failure we are chasing gives us no shutdown to run code in.
      previousRun = prefs.getStringList(_prefsKey) ?? const <String>[];
      previousRun2 = prefs.getStringList(_prefsKeyPrev) ?? const <String>[];
      await prefs.setStringList(_prefsKeyPrev, previousRun);
    } catch (e) {
      // ignore: avoid_print
      print('[SawadLoanUniversal] diagnostics: could not read trail — $e');
      previousRun = const <String>[];
      previousRun2 = const <String>[];
    }

    if (previousRun.isNotEmpty) {
      final endedOnError = previousRun.last.contains('ERROR');
      // ignore: avoid_print — intentional: surface in the WebView console.
      print('[SawadLoanUniversal] previous run ended '
          '${endedOnError ? 'on an error' : 'without an error'} at '
          '"${previousRun.last}" (${previousRun.length} steps)');
    }

    _crumbs.clear();
    log('boot env=${AppEnvironment.current.name} ver=$kWebVersion '
        'url=${Uri.base.path}');
  }

  /// Drops both trails. Exposed on the diagnostics sheet so a tester can start a
  /// clean run before reproducing.
  static Future<void> clear() async {
    _crumbs.clear();
    previousRun = const <String>[];
    previousRun2 = const <String>[];
    lastError = null;
    lastStack = null;
    await _prefs?.remove(_prefsKey);
    await _prefs?.remove(_prefsKeyPrev);
  }

  /// Launch params that must never appear in a copied report.
  ///
  /// This report is written to be pasted into a chat, so it is a distribution
  /// channel — and the launch URL carries the customer's Firebase bearer token
  /// and their hashed citizen id. A tester sent one before this was masked, which
  /// is exactly the leak the redaction exists to prevent. The lengths are kept so
  /// "the token was missing" and "the token was present" stay distinguishable,
  /// which is the only thing a report actually needs from them.
  static const Set<String> _redactedParams = <String>{'token', 'hashThaiId'};

  /// [Uri.base] with [_redactedParams] masked.
  static String get _safeUrl {
    final base = Uri.base;
    final query = base.queryParameters;
    if (query.isEmpty) return base.toString();
    return base
        .replace(
          queryParameters: query.map(
            (String k, String v) => MapEntry<String, String>(
              k,
              _redactedParams.contains(k) ? '<redacted:${v.length} chars>' : v,
            ),
          ),
        )
        .toString();
  }

  /// Everything a bug report needs, as one block of text.
  static String report() => <String>[
        'SawadLoanUniversal ${AppEnvironment.current.name} ver$kWebVersion',
        'url: $_safeUrl',
        if (lastError != null) ...<String>['', 'error: $lastError'],
        ?lastStack,
        '',
        '--- this run ---',
        ..._crumbs,
        if (previousRun.isNotEmpty) ...<String>[
          '',
          '--- previous run (-1) ---',
          ...previousRun,
        ],
        if (previousRun2.isNotEmpty) ...<String>[
          '',
          '--- previous run (-2) ---',
          ...previousRun2,
        ],
      ].join('\n');

  static void _record(Object error, StackTrace? stack) {
    lastError = error.toString();
    if (stack != null) {
      lastStack = stack.toString().split('\n').take(8).join('\n');
    }
    // Guard against an error inside the error path looping forever: log() itself
    // only touches a list and prefs, but the exception string can be huge.
    final short = lastError!.split('\n').first;
    log('ERROR ${short.length > 200 ? '${short.substring(0, 200)}…' : short}');
  }

  /// Fire-and-forget write. A dropped breadcrumb is not worth an await on every
  /// route change, and the next one rewrites the whole list anyway.
  static void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.setStringList(_prefsKey, _crumbs).catchError((_) => false));
  }
}

/// Records every route change as a breadcrumb.
///
/// Reads `RouteSettings.name`, which go_router sets to the route's path
/// (`go_router/src/builder.dart:397`), so a crumb reads `push /pLoan/conclusion`.
class DiagnosticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    Diagnostics.log('push ${_name(route)}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    Diagnostics.log('pop ${_name(route)} -> ${_name(previousRoute)}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    Diagnostics.log('replace ${_name(oldRoute)} -> ${_name(newRoute)}');
  }

  /// A label for the trail. Prefers go_router's path, falls back to the kind of
  /// route it is.
  ///
  /// The fallback matters: modal sheets and dialogs are pushed without a name, and
  /// a trail full of bare `?` entries could not distinguish the three PDF consent
  /// sheets from a confirm dialog — which is most of the step-6 activity. Tested
  /// by class *category*, not `runtimeType`, because dart2js minifies type names
  /// in a release build; `ModalBottomSheetRoute` and `DialogRoute` are both
  /// [PopupRoute], and that survives minification.
  static String _name(Route<dynamic>? route) {
    if (route == null) return '-';
    final String? name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    if (route is PopupRoute) return 'sheet/dialog';
    return 'unnamed page';
  }
}

/// The screen shown in place of Flutter's blank grey error box.
///
/// **Built from the plainest widgets on purpose.** `ErrorWidget.builder` can fire
/// for a widget above `MaterialApp`, where there is no `Theme`, `Material` or
/// `MediaQuery` to inherit from — anything fancier here would throw inside the
/// error path and put the blank rectangle back. Hence the explicit
/// [Directionality] and no `Scaffold`.
class DiagnosticsErrorView extends StatelessWidget {
  const DiagnosticsErrorView({
    super.key,
    required this.message,
    required this.trail,
  });

  final String message;
  final List<String> trail;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontSize: 11,
      height: 1.45,
      color: Color(0xFF3C4043),
      fontFamily: 'monospace',
      fontFamilyFallback: <String>['Courier'],
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFFFFF6F4),
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'เกิดข้อผิดพลาด',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC5221F),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'กรุณาถ่ายภาพหน้าจอนี้ส่งให้ทีมพัฒนา',
                style: TextStyle(fontSize: 12, color: Color(0xFF5F6368)),
              ),
              const SizedBox(height: 16),
              Text(
                '${AppEnvironment.current.name} ver$kWebVersion',
                style: mono,
              ),
              const SizedBox(height: 12),
              Text(message, style: mono),
              if (trail.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                const Text(
                  'ลำดับเหตุการณ์ก่อนเกิดข้อผิดพลาด',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3C4043),
                  ),
                ),
                const SizedBox(height: 6),
                Text(trail.reversed.join('\n'), style: mono),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the breadcrumb trail as a bottom sheet. Wired to the `(UAT ver…)` tag.
///
/// Unlike [DiagnosticsErrorView] this always runs inside `MaterialApp`, so it can
/// use Material widgets freely.
Future<void> showDiagnosticsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (BuildContext _, ScrollController scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'ข้อมูลสำหรับแจ้งปัญหา',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: Diagnostics.report()),
                        );
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('คัดลอกแล้ว')),
                          );
                        }
                      },
                      child: const Text('คัดลอก'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Diagnostics.clear();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      child: const Text('ล้าง'),
                    ),
                  ],
                ),
                const Divider(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: SelectableText(
                      Diagnostics.report(),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontFamily: 'monospace',
                        fontFamilyFallback: <String>['Courier'],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
