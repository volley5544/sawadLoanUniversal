import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/native_bridge.dart';
import '../services/diagnostics.dart';
import '../services/ndid_api.dart';
import '../services/ndid_common_message.dart';
import 'components/env_version_tag.dart';
import 'components/loan_register_styles.dart';
import '../models/ndid_subject.dart';

/// ยืนยันตัวตน — NDID identity-verification waiting screen (screen #5 on
/// slide 8) followed by the ยืนยันตัวตนสำเร็จ success screen (final frame).
///
/// **Inside the native host** ([NativeCameraBridge.isSupported]) this drives
/// the real NDID flow: `POST /rp/verify` with the IdP chosen on the previous
/// page (`form.ndidIdpId`), then polls `GET /rp/verify/{referenceId}` while
/// the customer confirms in their bank app; `ACCEPTED` flips to the success
/// screen, `REJECTED`/`TIMEOUT`/`CANCELLED` shows the failure reason.
///
/// **In a plain browser** the hop stays simulated: a countdown timer runs and
/// a "จำลองยืนยันตัวตนสำเร็จ" button stands in for the IDP callback.
/// Confirming pops `true` back through the NDID flow either way.
class NdidVerifyPage extends StatefulWidget {
  const NdidVerifyPage({Key? key, this.form}) : super(key: key);

  /// The flow that launched this screen — the loan-register wizard's form or
  /// the P-Loan application's flow. Only [NdidSubject] is needed, which is why
  /// both can share these screens.
  final NdidSubject? form;

  @override
  State<NdidVerifyPage> createState() => _NdidVerifyPageState();
}

class _NdidVerifyPageState extends State<NdidVerifyPage> {
  /// Countdown for the customer to complete verification in their bank app.
  /// Matches the `request_timeout` sent on the real verify request.
  static const Duration _requestTimeout = Duration(hours: 1);

  /// Poll cadence, **shaped by the gateway's rate limit**.
  ///
  /// The NDID gateway allows **100 requests per 900 s** (`ratelimit-policy:
  /// 100;w=900`, shared across endpoints — `/rp/verify/{ref}` included). A flat
  /// 3 s poll is 300 per window: it spent the whole budget in the first 5
  /// minutes and was throttled for the remaining 10 of every window, leaving the
  /// page blind for roughly 40 of the 60 countdown minutes. A status flipped
  /// during a throttled stretch could not be seen until the window reset, which
  /// is what made an accepted request look like it was still pending.
  ///
  /// So: 3 s for the first [_fastPhase] — almost every real accept lands there,
  /// and a tester on the NDID console is quick — then 15 s. That is ~10 + 60 ≈ 70
  /// requests per window including `/idp/list` and the create call, comfortably
  /// under the limit for a full hour.
  ///
  /// The slower steady rate costs little, because detection no longer depends on
  /// the timer alone: [_lifecycle] polls the moment the page is visible again and
  /// ตรวจสอบสถานะ polls on demand.
  static const Duration _pollFast = Duration(seconds: 3);
  static const Duration _pollSteady = Duration(seconds: 15);
  static const Duration _fastPhase = Duration(seconds: 30);

  /// Cool-off after an HTTP 429.
  ///
  /// Fixed rather than read from `ratelimit-reset`: the host's `httpRequest`
  /// bridge returns only `{status, body}`, so response headers are not available
  /// to us inside the app. A minute is longer than the window's remainder
  /// usually is, and over-waiting is cheaper than being throttled again.
  static const Duration _pollAfter429 = Duration(seconds: 60);

  Duration _remaining = _requestTimeout;
  Timer? _timer;
  Timer? _pollTimer;

  bool _verified = false;

  /// Real-API state (native host only).
  bool get _useRealApi =>
      NativeCameraBridge.isSupported && widget.form?.ndidIdpId != null;
  bool _creating = false;
  String? _error;
  String? _referenceId;

  /// The customer-facing Transaction Ref for this request (NDID guideline
  /// p.38: digits only, 5-9 long).
  ///
  /// **Supplied by the gateway** as of 2026-08-31 — `transaction_ref` on the
  /// `POST /rp/verify` response, echoed on every poll — because the same
  /// gateway appends it to the Request Message the IdP app shows. One generator
  /// means this screen and the bank's app cannot quote different numbers, which
  /// is the failure NDID rejected the app review over. It is **not** derived
  /// from NDID's `reference_id`, which is a UUID and satisfies neither rule.
  String? _transactionRefValue;

  /// True while a [_pollStatus] call is in flight, so overlapping polls can't
  /// pile up — `Timer.periodic` fires on schedule regardless of whether the last
  /// request finished, and a slow poll (up to the 30 s API timeout) would
  /// otherwise stack ten deep.
  bool _polling = false;

  /// Consecutive failed polls. Surfaced in the UI from [_pollFailureThreshold]
  /// so a check that cannot reach the gateway stops looking exactly like a
  /// customer who has not approved yet — a single failure is still ignored,
  /// because one flaky response must not kill a live request.
  int _pollFailures = 0;
  static const int _pollFailureThreshold = 3;
  String? _pollWarning;

  /// Set while a manual ตรวจสอบสถานะ is running.
  bool _checkingNow = false;

  /// Delay to use for the *next* poll instead of the normal cadence, set when a
  /// poll came back 429.
  Duration? _nextPollDelay;

  String get _citizenId =>
      widget.form?.ndidThaiId ?? '';

  /// Polls once the moment the page becomes visible again.
  ///
  /// **This is the difference between "immediate" and "eventually" in practice.**
  /// Verifying means leaving this page — the bank's app for a customer, the NDID
  /// UAT console for a tester — and a backgrounded WebView has its JS timers
  /// throttled or suspended, so [_pollTimer] is not running while you are away.
  /// Without this, coming back means waiting on whatever the timer does next.
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    if (_useRealApi) {
      _startVerification();
      _lifecycle = AppLifecycleListener(onResume: () {
        if (_referenceId != null && !_verified) _pollStatus();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _remaining = _requestTimeout;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        t.cancel();
        // The two timers used to be independent, so polling outlived the
        // countdown and only stopped if NDID happened to report TIMEOUT. Say so
        // ourselves and stop asking.
        //
        // Gated on _referenceId, not `_pollTimer.isActive`: the poll timer is
        // single-shot now, so it is legitimately inactive between polls and that
        // check would have skipped the message half the time.
        if (_referenceId != null && !_verified) {
          _pollTimer?.cancel();
          setState(() {
            _pollWarning = null;
            _error = 'หมดเวลาการยืนยันตัวตน กรุณาทำรายการใหม่';
            _referenceId = null;
          });
        }
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  // ── Real NDID flow ─────────────────────────────────────────────────
  Future<void> _startVerification() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // No `transactionRef` argument: the gateway generates the Transaction Ref
      // and appends it to the IdP's Request Message itself, then hands it back
      // on the response below.
      final req = await NdidApi.createVerifyRequest(
        identifier: _citizenId,
        idpId: widget.form!.ndidIdpId!,
        requestTimeoutSeconds: _requestTimeout.inSeconds,
      );
      if (!mounted) return;
      setState(() {
        _creating = false;
        _referenceId = req.referenceId;
        _transactionRefValue = _acceptTransactionRef(req.transactionRef);
      });
      // The three ids that identify this request, in one line: the one the
      // customer and the IdP both see, and NDID's two. Chasing a failed
      // verification with NDID support means quoting theirs, and the customer
      // can only ever quote the Transaction Ref.
      Diagnostics.log(
          'ndid verify created txnRef=${_transactionRefValue ?? '-'} '
          'ref=${req.referenceId} ndidRequestId=${req.ndidRequestId ?? '-'}');
      _startCountdown();
      _scheduleNextPoll();
    } on NdidApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = e.message;
      });
    }
  }

  Future<void> _pollStatus() async {
    final ref = _referenceId;
    if (ref == null || _verified || _polling) return;
    _polling = true;
    final NdidVerifyStatus status;
    try {
      status = await NdidApi.getVerifyStatus(ref);
    } on NdidApiException catch (e) {
      // Keep polling — one flaky response must not kill a live request — but
      // stop hiding it. A silent failure here is indistinguishable from a
      // customer who hasn't approved yet, which is how a stalled check can look
      // like a normal countdown for a whole hour.
      if (e.statusCode == 429) {
        // Rate-limited: the gateway allows 100 requests per 900 s. Slow right
        // down instead of spending the rest of the window on refusals.
        _nextPollDelay = _pollAfter429;
        if (mounted) {
          setState(() => _pollWarning =
              'ระบบจำกัดจำนวนการตรวจสอบ กำลังรอสักครู่แล้วลองใหม่...');
        }
        return;
      }
      _pollFailures++;
      if (mounted && _pollFailures >= _pollFailureThreshold) {
        setState(() => _pollWarning =
            'ไม่สามารถตรวจสอบสถานะได้ (${e.message}) กำลังลองใหม่...');
      }
      return;
    } finally {
      _polling = false;
    }
    if (!mounted) return;
    if (_pollFailures != 0 || _pollWarning != null) {
      setState(() {
        _pollFailures = 0;
        _pollWarning = null;
      });
    }
    // Backstop for a create response that carried no `transaction_ref`: every
    // poll echoes it, so the reference can still appear a few seconds in rather
    // than staying a dash for the whole hour. Only when we have none — re-reading
    // it on all ~70 polls would log a "missing" breadcrumb per poll on a gateway
    // that never sends the field.
    if (_transactionRefValue == null && status.transactionRef != null) {
      final adopted = _acceptTransactionRef(status.transactionRef);
      if (adopted != null) setState(() => _transactionRefValue = adopted);
    }
    if (status.isPending) return;
    _pollTimer?.cancel();
    if (status.isAccepted) {
      // Record NDID's own reference before popping. The P-Loan submit sends it
      // as `ndid_reference_id` so the backend can confirm this verification
      // with NDID directly rather than trusting the client's success flag —
      // which is all `_verified` is. Only the real API path sets it: the
      // simulated hop below has no reference, and inventing one would claim a
      // verification that never happened.
      widget.form?.ndidReferenceId = ref;
      setState(() {
        _verified = true;
        _timer?.cancel();
      });
    } else {
      // The NDID Common Message standard, not wording of our own: the IdP/AS
      // error code picks the sentence, and the customer is told what happened
      // and what to do next. Free-text messages here were issue 3 of the
      // 2026-08-28 review rejection.
      Diagnostics.log('ndid verify failed status=${status.status} '
          'code=${status.errorCode ?? '-'}');
      setState(() {
        _error = NdidCommonMessage.forStatus(
          status.status,
          errorCode: status.errorCode,
          idpName: widget.form?.ndidIdpName ?? '',
        );
        _referenceId = null;
      });
    }
  }

  /// Queues the next poll, choosing its own delay.
  ///
  /// A single-shot timer that reschedules itself, rather than `Timer.periodic`,
  /// so the interval can change: fast at first, then steady, and backed off after
  /// a 429. Elapsed time comes from the countdown rather than a wall clock, since
  /// the countdown is already the authority on how long this request has run.
  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    if (!mounted || _verified || _referenceId == null) return;
    final elapsed = _requestTimeout - _remaining;
    final delay = _nextPollDelay ??
        (elapsed < _fastPhase ? _pollFast : _pollSteady);
    _nextPollDelay = null;
    _pollTimer = Timer(delay, () async {
      await _pollStatus();
      _scheduleNextPoll();
    });
  }

  /// Check now, rather than waiting for the next scheduled poll.
  Future<void> _checkNow() async {
    if (_checkingNow) return;
    setState(() => _checkingNow = true);
    await _pollStatus();
    if (!mounted) return;
    setState(() => _checkingNow = false);
    // Restart the cadence from here, so a manual check doesn't land right on top
    // of a scheduled one and spend two requests for one answer.
    _scheduleNextPoll();
  }

  void _cancel() {
    final ref = _referenceId;
    if (_useRealApi && ref != null) {
      NdidApi.closeVerifyRequest(ref); // fire and forget
    }
    context.pop(false);
  }

  String get _formattedTime {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_remaining.inHours)}:${two(_remaining.inMinutes % 60)}:${two(_remaining.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: const [EnvVersionTag()],
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text(_verified ? 'ผลการยืนยันตัวตน' : 'ยืนยันตัวตน',
            style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: _verified ? _successBody() : _waitingBody(),
    );
  }

  // ── Waiting (countdown) ────────────────────────────────────────────
  Widget _waitingBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: LoanRegisterStyles.padding, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 64, color: LoanRegisterStyles.primary),
                const SizedBox(height: 16),
                Text(
                  'ยืนยันตัวตน',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Icon(Icons.error_outline,
                      size: 40, color: Colors.red.shade400),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.red.shade400,
                    ),
                  ),
                ] else ...[
                  Text(
                    // NDID Common Message 6.2.1 [3] — the standard wording for
                    // this screen. Do not reword; see [NdidCommonMessage].
                    NdidCommonMessage.waitingForIdp,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      height: 1.5,
                      color: LoanRegisterStyles.label,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_creating)
                    Text('กำลังสร้างรายการยืนยันตัวตน...',
                        style: LoanRegisterStyles.labelStyle())
                  else
                    Text(
                      'Transaction Ref: ${_transactionRef()}',
                      style: LoanRegisterStyles.labelStyle(),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    _formattedTime,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: LoanRegisterStyles.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('เวลาคงเหลือ', style: LoanRegisterStyles.labelStyle()),
                  if (_pollWarning != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _pollWarning!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansThai(
                        fontSize: 12,
                        height: 1.5,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                LoanRegisterStyles.padding, 12),
            child: Column(
              children: [
                if (_useRealApi) ...[
                  // The result normally arrives on its own from the 3 s poll.
                  // This is for when it doesn't: the poll only runs while this
                  // page is visible, and verifying means leaving it — so anyone
                  // returning from the bank app (or from flipping the status on
                  // the NDID UAT console) can force a check instead of waiting.
                  if (_error == null && !_creating && _referenceId != null) ...[
                    _Button(
                      label: _checkingNow
                          ? 'กำลังตรวจสอบสถานะ...'
                          : 'ตรวจสอบสถานะ',
                      filled: false,
                      onTap: _checkingNow ? null : _checkNow,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_error != null) ...[
                    _Button(
                      label: 'ลองใหม่',
                      filled: true,
                      onTap: _startVerification,
                    ),
                    const SizedBox(height: 10),
                  ],
                ] else ...[
                  // Simulates the IDP callback (the real result arrives from
                  // the bank app). Plain-browser / UI-only flow.
                  _Button(
                    label: 'จำลองยืนยันตัวตนสำเร็จ',
                    filled: true,
                    onTap: () => setState(() {
                      _verified = true;
                      _timer?.cancel();
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                _Button(
                  label: 'ยกเลิก',
                  filled: false,
                  onTap: _cancel,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Short reference shown to the customer — the gateway's `transaction_ref`
  /// when the real request exists, a placeholder in the simulated hop.
  /// What the customer sees, and what the IdP app shows them.
  ///
  /// Until 2026-08-28 this was the first 12 characters of NDID's own
  /// `ndid_request_id`, upper-cased — e.g. `8CB4B22F15A4`. NDID rejected the app
  /// review over it (issue 2): the reference must be digits only and at most 9
  /// of them, and it must match the one in the Request Message.
  ///
  /// A dash means the gateway sent no `transaction_ref`. That is deliberately
  /// not filled with a locally generated number: the IdP app is quoting the
  /// gateway's clause, so any reference of our own would be one the customer's
  /// bank never showed them — the same mismatch, pointed the other way.
  String _transactionRef() =>
      _transactionRefValue ?? (_useRealApi ? '-' : '000000001');

  /// Takes the gateway's `transaction_ref` if there is one, leaving a breadcrumb
  /// when it is missing or breaks the standard's format rule.
  ///
  /// It is displayed even when invalid — it is what the IdP app is quoting, so
  /// hiding it would leave the customer unable to match the two screens — but
  /// the trail is what turns "the reference looks wrong" into a report the
  /// backend team can act on, since this is the exact rule the review failed on.
  String? _acceptTransactionRef(String? ref) {
    if (ref == null || ref.isEmpty) {
      Diagnostics.log('ndid transaction_ref absent from gateway response');
      return _transactionRefValue;
    }
    if (!NdidTransactionRef.isValid(ref)) {
      Diagnostics.log('ndid transaction_ref "$ref" is not 5-9 digits');
    }
    return ref;
  }

  // ── Success ────────────────────────────────────────────────────────
  Widget _successBody() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: LoanRegisterStyles.primary, width: 3),
                  ),
                  child: Icon(Icons.check,
                      size: 56, color: LoanRegisterStyles.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  'ยืนยันตัวตนสำเร็จ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                LoanRegisterStyles.padding, 12),
            child: _Button(
              label: 'ตกลง',
              filled: true,
              onTap: () => context.pop(true),
            ),
          ),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;

  /// Null disables the button (used while a manual status check is running).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? LoanRegisterStyles.primary
              : LoanRegisterStyles.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: LoanRegisterStyles.primary),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansThai(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : LoanRegisterStyles.primary,
          ),
        ),
      ),
    );
  }
}
