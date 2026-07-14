import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/native_bridge.dart';
import '../services/ndid_api.dart';
import 'components/env_version_tag.dart';
import 'components/loan_register_styles.dart';
import 'models/loan_register_form.dart';

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

  final LoanRegisterForm? form;

  @override
  State<NdidVerifyPage> createState() => _NdidVerifyPageState();
}

class _NdidVerifyPageState extends State<NdidVerifyPage> {
  /// Countdown for the customer to complete verification in their bank app.
  /// Matches the `request_timeout` sent on the real verify request.
  static const Duration _requestTimeout = Duration(hours: 1);
  static const Duration _pollInterval = Duration(seconds: 3);

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
  String? _ndidRequestId;

  String get _citizenId =>
      (widget.form?.thaiId ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  @override
  void initState() {
    super.initState();
    _startCountdown();
    if (_useRealApi) _startVerification();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _remaining = _requestTimeout;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        t.cancel();
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
      final req = await NdidApi.createVerifyRequest(
        identifier: _citizenId,
        idpId: widget.form!.ndidIdpId!,
        requestTimeoutSeconds: _requestTimeout.inSeconds,
      );
      if (!mounted) return;
      setState(() {
        _creating = false;
        _referenceId = req.referenceId;
        _ndidRequestId = req.ndidRequestId;
      });
      _startCountdown();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _pollStatus());
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
    if (ref == null || _verified) return;
    final NdidVerifyStatus status;
    try {
      status = await NdidApi.getVerifyStatus(ref);
    } on NdidApiException {
      return; // transient poll failure — keep polling
    }
    if (!mounted || status.isPending) return;
    _pollTimer?.cancel();
    if (status.isAccepted) {
      setState(() {
        _verified = true;
        _timer?.cancel();
      });
    } else {
      setState(() {
        _error = switch (status.status) {
          'REJECTED' => 'การยืนยันตัวตนถูกปฏิเสธจากธนาคาร',
          'TIMEOUT' => 'หมดเวลาการยืนยันตัวตน กรุณาทำรายการใหม่',
          'CANCELLED' => 'รายการยืนยันตัวตนถูกยกเลิก',
          _ => 'การยืนยันตัวตนไม่สำเร็จ (${status.status})',
        };
        _referenceId = null;
      });
    }
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
                    'ทำรายการยืนยันตัวตนผ่านแอปพลิเคชันของธนาคารที่เลือก '
                    'ภายในระยะเวลาที่กำหนด (จำกัด 1 ครั้ง/รายการ) '
                    'กรุณาเปิดแอปธนาคารเพื่อยืนยันตัวตนของท่าน',
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
                  // Result arrives from the bank app via the NDID poll; the
                  // only action while waiting is retrying after a failure.
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

  /// Short reference shown to the customer — the NDID request id (or local
  /// reference id) when the real request exists, a placeholder otherwise.
  String _transactionRef() {
    final id = _ndidRequestId ?? _referenceId;
    if (id == null) return _useRealApi ? '-' : '1234ETE';
    return id.length > 12 ? id.substring(0, 12).toUpperCase() : id.toUpperCase();
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
  final VoidCallback onTap;

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
