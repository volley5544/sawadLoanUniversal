import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../loan_register/components/register_field_row.dart';
import '../models/ndid_models.dart';
import '../services/ndid_service.dart';

/// NDID identity-verification flow (ยืนยันตัวตนผ่าน NDID).
///
/// Drives the RP side of the DAP/NDID verify flow against the local NDID Node
/// proxy (see [NdidService]):
///   1. list the IdPs the customer can verify with (`POST /idp/list`)
///   2. let the customer pick one (or more) and send the request (`/rp/verify`)
///   3. poll status (`/rp/verify/{ref}`) until ACCEPTED / REJECTED / TIMEOUT …
///   4. allow cancelling a pending request (`/rp/verify/{ref}/close`)
///
/// Pops with the final UPPERCASE status string (e.g. `ACCEPTED`) so the caller
/// (step 1) can reflect it on the wizard form, or `null` if dismissed.
class NdidVerifyPage extends StatefulWidget {
  const NdidVerifyPage({
    Key? key,
    required this.thaiId,
    this.fullName = '',
    this.requestMessage = 'ขอยืนยันตัวตนเพื่อสมัครสินเชื่อ',
  }) : super(key: key);

  /// Customer's Thai national ID. May contain dashes/spaces — digits are
  /// extracted for the NDID `identifier`.
  final String thaiId;
  final String fullName;
  final String requestMessage;

  @override
  State<NdidVerifyPage> createState() => _NdidVerifyPageState();
}

enum _Stage { intro, selectIdp, waiting, done }

class _NdidVerifyPageState extends State<NdidVerifyPage> {
  late final NdidService _service;
  late final String _identifier; // digits only

  _Stage _stage = _Stage.intro;
  bool _busy = false;
  String? _error;

  List<NdidIdp> _idps = const [];
  final Set<String> _selectedIdpIds = {};

  NdidVerifyResult? _request;
  NdidVerificationStatus? _status;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _service = NdidService(baseUrl: AppState().ndidBaseUrl);
    _identifier = widget.thaiId.replaceAll(RegExp(r'\D'), '');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _service.dispose();
    super.dispose();
  }

  String get _callbackUrl => AppState().ndidCallbackUrl;

  bool get _hasValidId => _identifier.length == 13;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _loadIdps() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idps = await _service.listIdps(identifier: _identifier);
      if (!mounted) return;
      setState(() {
        _idps = idps;
        // Preselect the only IdP for a one-tap flow.
        _selectedIdpIds
          ..clear()
          ..addAll(idps.length == 1 ? [idps.first.id] : const <String>[]);
        _stage = _Stage.selectIdp;
      });
    } on NdidApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedIdpIds.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.verify(
        identifier: _identifier,
        idpIdList: _selectedIdpIds.toList(),
        requestMessage: widget.requestMessage,
        callbackUrl: _callbackUrl,
      );
      if (!mounted) return;
      setState(() {
        _request = result;
        _status = const NdidVerificationStatus(status: NdidStatus.pending);
        _stage = _Stage.waiting;
      });
      _startPolling();
    } on NdidApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refreshStatus());
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final ref = _request?.referenceId;
    if (ref == null || ref.isEmpty) return;
    try {
      final status = await _service.checkStatus(ref);
      if (!mounted) return;
      setState(() => _status = status);
      if (status.status.isTerminal) {
        _poll?.cancel();
        setState(() => _stage = _Stage.done);
      }
    } on NdidApiException catch (e) {
      // Keep polling on transient errors but surface the latest message.
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _cancelRequest() async {
    final ref = _request?.referenceId;
    if (ref == null || ref.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    _poll?.cancel();
    try {
      await _service.close(ref, callbackUrl: _callbackUrl);
    } on NdidApiException {
      // Best-effort — close failures shouldn't trap the user on this screen.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop('CANCELLED');
      }
    }
  }

  void _finish() {
    final label = _status?.status.name
        .toUpperCase()
        .replaceAll('REQUESTEDERROR', 'REQUESTED_ERROR');
    Navigator.of(context).pop(label);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block accidental back-swipe while a request is pending; require the
      // explicit ยกเลิก so we close the NDID request server-side.
      canPop: _stage != _Stage.waiting,
      child: Scaffold(
        backgroundColor: LoanRegisterStyles.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: _stage == _Stage.waiting
              ? const SizedBox.shrink()
              : BackButton(color: LoanRegisterStyles.primary),
          centerTitle: true,
          title: Text('ยืนยันตัวตน NDID',
              style: LoanRegisterStyles.appBarTitleStyle()),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: LoanRegisterStyles.padding),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.intro:
        return _buildIntro();
      case _Stage.selectIdp:
        return _buildSelectIdp();
      case _Stage.waiting:
        return _buildWaiting();
      case _Stage.done:
        return _buildDone();
    }
  }

  // Stage 1 — identity summary + start button.
  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const RegisterSectionTitle('ข้อมูลผู้ยืนยันตัวตน'),
        _identityCard(),
        const SizedBox(height: 16),
        Text(
          'ระบบจะส่งคำขอยืนยันตัวตนไปยังผู้ให้บริการยืนยันตัวตน (IdP) '
          'ที่ท่านลงทะเบียนไว้กับ NDID กรุณายืนยันตัวตนผ่านแอปของผู้ให้บริการนั้น',
          style: LoanRegisterStyles.labelStyle().copyWith(height: 1.5),
        ),
        if (!_hasValidId) ...[
          const SizedBox(height: 12),
          _inlineWarning('เลขบัตรประชาชนไม่ถูกต้อง (ต้องมี 13 หลัก)'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _inlineWarning(_error!),
        ],
        const Spacer(),
        _primaryButton(
          label: 'เริ่มยืนยันตัวตน',
          enabled: _hasValidId && !_busy,
          loading: _busy,
          onTap: _loadIdps,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // Stage 2 — IdP picker.
  Widget _buildSelectIdp() {
    if (_idps.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          _inlineWarning(
              'ไม่พบผู้ให้บริการยืนยันตัวตน (IdP) สำหรับเลขบัตรนี้ '
              'กรุณาลงทะเบียน NDID กับธนาคารหรือผู้ให้บริการก่อน'),
          const Spacer(),
          _primaryButton(
              label: 'ลองอีกครั้ง',
              enabled: !_busy,
              loading: _busy,
              onTap: _loadIdps),
          const SizedBox(height: 12),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const RegisterSectionTitle('เลือกผู้ให้บริการยืนยันตัวตน'),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.separated(
            itemCount: _idps.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _idpTile(_idps[i]),
          ),
        ),
        if (_error != null) ...[
          _inlineWarning(_error!),
          const SizedBox(height: 8),
        ],
        _primaryButton(
          label: 'ส่งคำขอยืนยันตัวตน',
          enabled: _selectedIdpIds.isNotEmpty && !_busy,
          loading: _busy,
          onTap: _submit,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // Stage 3 — pending / polling.
  Widget _buildWaiting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            valueColor:
                AlwaysStoppedAnimation<Color>(LoanRegisterStyles.primary),
          ),
        ),
        const SizedBox(height: 24),
        Text('รอการยืนยันตัวตน', style: LoanRegisterStyles.sectionTitleStyle()),
        const SizedBox(height: 8),
        Text(
          'กรุณายืนยันตัวตนผ่านแอปของผู้ให้บริการ (IdP) ที่ท่านเลือก\n'
          'หน้าจอนี้จะอัปเดตสถานะให้อัตโนมัติ',
          textAlign: TextAlign.center,
          style: LoanRegisterStyles.labelStyle().copyWith(height: 1.5),
        ),
        const SizedBox(height: 24),
        _referenceCard(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _inlineWarning(_error!),
        ],
        const Spacer(),
        OutlinedButton(
          onPressed: _busy ? null : _cancelRequest,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(color: LoanRegisterStyles.primary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: Text('ยกเลิกคำขอ',
              style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.primary)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // Stage 4 — terminal result.
  Widget _buildDone() {
    final status = _status?.status ?? NdidStatus.unknown;
    final success = status.isSuccess;
    final info = _statusPresentation(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Icon(info.icon, size: 72, color: info.color),
        const SizedBox(height: 16),
        Text(info.title, style: LoanRegisterStyles.sectionTitleStyle()),
        const SizedBox(height: 8),
        Text(
          info.detail,
          textAlign: TextAlign.center,
          style: LoanRegisterStyles.labelStyle().copyWith(height: 1.5),
        ),
        const SizedBox(height: 20),
        _referenceCard(),
        if ((_status?.responseList ?? const []).isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._status!.responseList.map(_responseRow),
        ],
        if ((_status?.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _inlineWarning(_status!.errorMessage),
        ],
        const Spacer(),
        if (!success && !status.isSuccess)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _stage = _Stage.intro;
                  _request = null;
                  _status = null;
                  _error = null;
                });
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(color: LoanRegisterStyles.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('ลองยืนยันใหม่',
                  style: GoogleFonts.notoSansThai(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LoanRegisterStyles.primary)),
            ),
          ),
        _primaryButton(label: 'เสร็จสิ้น', enabled: true, onTap: _finish),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  Widget _identityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        children: [
          if (widget.fullName.trim().isNotEmpty)
            RegisterFieldRow(label: 'ชื่อ-นามสกุล', value: widget.fullName),
          RegisterFieldRow(
            label: 'เลขบัตรประชาชน',
            value: _maskId(_identifier),
          ),
          RegisterFieldRow(
            label: 'Namespace',
            value: NdidService.citizenIdNamespace,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _idpTile(NdidIdp idp) {
    final selected = _selectedIdpIds.contains(idp.id);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        // Single-select keeps the demo flow simple (min_idp = 1).
        _selectedIdpIds
          ..clear()
          ..add(idp.id);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? LoanRegisterStyles.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? LoanRegisterStyles.primary
                : LoanRegisterStyles.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.label,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(idp.label, style: LoanRegisterStyles.valueStyle()),
                  if (idp.id.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(idp.id, style: LoanRegisterStyles.labelStyle()),
                  ],
                ],
              ),
            ),
            if (idp.agent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: LoanRegisterStyles.divider,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Agent', style: LoanRegisterStyles.labelStyle()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _referenceCard() {
    final ref = _request?.referenceId ?? '';
    final reqId = _request?.ndidRequestId ?? '';
    if (ref.isEmpty && reqId.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Column(
        children: [
          if (ref.isNotEmpty)
            RegisterFieldRow(
              label: 'Reference ID',
              value: ref,
              valueStyle: LoanRegisterStyles.valueStyle()
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w500),
              showDivider: reqId.isNotEmpty,
            ),
          if (reqId.isNotEmpty)
            RegisterFieldRow(
              label: 'NDID Request ID',
              value: reqId,
              valueStyle: LoanRegisterStyles.valueStyle()
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w500),
              showDivider: false,
            ),
        ],
      ),
    );
  }

  Widget _responseRow(NdidIdpResponse r) {
    final ok = r.accepted;
    final detail = StringBuffer(r.idpId);
    if (r.ial != null) detail.write('  ·  IAL ${r.ial}');
    if (r.aal != null) detail.write('  ·  AAL ${r.aal}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            r.errorCode != null
                ? Icons.error_outline
                : (ok ? Icons.check_circle : Icons.cancel),
            size: 18,
            color: r.errorCode != null
                ? LoanRegisterStyles.required
                : (ok ? Colors.green : LoanRegisterStyles.required),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.errorCode != null
                  ? '${r.idpId}: ${r.errorDescription} (${r.errorCode})'
                  : detail.toString(),
              style: LoanRegisterStyles.labelStyle(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LoanRegisterStyles.required.withOpacity(.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: LoanRegisterStyles.required),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: LoanRegisterStyles.requiredStyle()
                    .copyWith(height: 1.4, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? LoanRegisterStyles.primary
              : LoanRegisterStyles.primary.withOpacity(.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: GoogleFonts.notoSansThai(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  // ── Presentation helpers ───────────────────────────────────────────────────

  _StatusInfo _statusPresentation(NdidStatus status) {
    switch (status) {
      case NdidStatus.accepted:
        return _StatusInfo(
          icon: Icons.verified_user,
          color: Colors.green,
          title: 'ยืนยันตัวตนสำเร็จ',
          detail: 'ผู้ให้บริการยืนยันตัวตน (IdP) ยืนยันตัวตนของท่านเรียบร้อยแล้ว',
        );
      case NdidStatus.rejected:
        return _StatusInfo(
          icon: Icons.cancel,
          color: LoanRegisterStyles.required,
          title: 'การยืนยันตัวตนถูกปฏิเสธ',
          detail: 'ผู้ให้บริการปฏิเสธคำขอยืนยันตัวตน กรุณาลองใหม่อีกครั้ง',
        );
      case NdidStatus.timeout:
        return _StatusInfo(
          icon: Icons.timer_off,
          color: LoanRegisterStyles.required,
          title: 'หมดเวลายืนยันตัวตน',
          detail: 'ไม่ได้รับการยืนยันภายในเวลาที่กำหนด กรุณาลองใหม่อีกครั้ง',
        );
      case NdidStatus.cancelled:
        return _StatusInfo(
          icon: Icons.block,
          color: LoanRegisterStyles.label,
          title: 'ยกเลิกคำขอแล้ว',
          detail: 'คำขอยืนยันตัวตนถูกยกเลิก',
        );
      case NdidStatus.requestedError:
      case NdidStatus.idpOrAsError:
        return _StatusInfo(
          icon: Icons.error,
          color: LoanRegisterStyles.required,
          title: 'เกิดข้อผิดพลาด',
          detail: 'ระบบ NDID แจ้งข้อผิดพลาดระหว่างการยืนยันตัวตน',
        );
      default:
        return _StatusInfo(
          icon: Icons.help_outline,
          color: LoanRegisterStyles.label,
          title: 'สถานะไม่ทราบ',
          detail: 'ไม่สามารถระบุสถานะการยืนยันตัวตนได้',
        );
    }
  }

  String _maskId(String digits) {
    if (digits.length != 13) return widget.thaiId;
    // x-xxxx-xxxxx-xx-x with the middle hidden, last 4 visible.
    final visible = digits.substring(9);
    return '${digits[0]}-xxxx-xxxxx-${visible.substring(0, 2)}-${visible.substring(2)}';
  }
}

class _StatusInfo {
  _StatusInfo({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
}
