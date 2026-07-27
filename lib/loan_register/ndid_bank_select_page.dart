import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import '../services/native_bridge.dart';
import '../services/ndid_api.dart';
import 'components/env_version_tag.dart';
import 'components/loan_register_styles.dart';
import '../models/ndid_subject.dart';

/// เลือกธนาคารที่เกี่ยวข้อง NDID — pick the Identity Provider (IDP) bank used
/// for NDID verification (screens #3–#4 on slide 8).
///
/// Shows banks the customer has already registered with NDID, and those they
/// have not. Picking a registered bank and tapping ถัดไป continues to
/// [NdidVerifyPage]. (The bank's own app — K+ PIN pad, NDID consent — is a
/// third-party screen handled outside this build.)
///
/// **Data source:** inside the native host ([NativeCameraBridge.isSupported])
/// the two grids come from the real NDID local-node API (`POST /idp/list`,
/// with/without the customer's Thai ID — see `lib/services/ndid_api.dart`);
/// in a plain browser the hardcoded mock banks below are shown and the flow
/// stays simulated.
class NdidBankSelectPage extends StatefulWidget {
  const NdidBankSelectPage({Key? key, this.form}) : super(key: key);

  /// The flow that launched this screen — the loan-register wizard's form or
  /// the P-Loan application's flow. Only [NdidSubject] is needed, which is why
  /// both can share these screens.
  final NdidSubject? form;

  @override
  State<NdidBankSelectPage> createState() => _NdidBankSelectPageState();
}

class _NdidBank {
  const _NdidBank(this.code, this.name, this.color, {this.idpId});
  final String code;
  final String name;
  final Color color;

  /// Real NDID node id (e.g. `idp1`) — null for the mock browser-only banks.
  final String? idpId;
}

class _NdidBankSelectPageState extends State<NdidBankSelectPage> {
  _NdidBank? _selected;

  bool get _useRealApi => NativeCameraBridge.isSupported;

  bool _loading = false;
  String? _error;
  List<_NdidBank> _registered = const [];
  List<_NdidBank> _notRegistered = const [];

  // Banks the customer has registered with NDID (plain-browser mock only).
  static const List<_NdidBank> _mockRegistered = [
    _NdidBank('BBL', 'ธนาคารกรุงเทพ', Color(0xFF1B3A8B)),
    _NdidBank('KRUNGSRI', 'ธนาคารกรุงศรี', Color(0xFFFCC200)),
    _NdidBank('K+', 'ธนาคารกสิกรไทย', Color(0xFF138F2D)),
  ];

  // Banks not yet registered with NDID (plain-browser mock only).
  static const List<_NdidBank> _mockNotRegistered = [
    _NdidBank('SCB', 'ธนาคารไทยพาณิชย์', Color(0xFF4E2A84)),
    _NdidBank('KTB', 'ธนาคารกรุงไทย', Color(0xFF00A4E4)),
    _NdidBank('TTB', 'ทีทีบี', Color(0xFF0050A0)),
  ];

  @override
  void initState() {
    super.initState();
    if (_useRealApi) {
      _loadIdps();
    } else {
      _registered = _mockRegistered;
      _notRegistered = _mockNotRegistered;
    }
  }

  /// Digits-only Thai ID from the launching flow.
  String get _citizenId => widget.form?.ndidThaiId ?? '';

  Future<void> _loadIdps() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      // IdPs the customer onboarded with (by Thai ID) + the full IdP list;
      // the difference fills the "not registered" grid.
      final results = await Future.wait([
        NdidApi.listIdps(identifier: _citizenId),
        NdidApi.listIdps(),
      ]);
      final registered = results[0];
      final registeredIds = registered.map((e) => e.id).toSet();
      final others =
          results[1].where((e) => !registeredIds.contains(e.id)).toList();
      if (!mounted) return;
      setState(() {
        _registered = registered.map(_toBank).toList(growable: false);
        _notRegistered = others.map(_toBank).toList(growable: false);
        _loading = false;
      });
    } on NdidApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Map a real IdP to the tile model, borrowing the well-known Thai bank
  /// colors/short codes when the name matches; otherwise a neutral style.
  _NdidBank _toBank(NdidIdp idp) {
    final name = idp.displayNameTh.isNotEmpty ? idp.displayNameTh : idp.id;
    final haystack = '${idp.displayNameTh} ${idp.displayNameEn}'.toLowerCase();
    for (final s in _knownBankStyles) {
      if (s.keywords.any(haystack.contains)) {
        return _NdidBank(s.code, name, s.color, idpId: idp.id);
      }
    }
    return _NdidBank(
      idp.id.toUpperCase(),
      name,
      LoanRegisterStyles.primary,
      idpId: idp.id,
    );
  }

  static const List<_BankStyle> _knownBankStyles = [
    _BankStyle('BBL', ['กรุงเทพ', 'bangkok bank', 'bbl'], Color(0xFF1B3A8B)),
    _BankStyle('K+', ['กสิกร', 'kasikorn', 'kbank'], Color(0xFF138F2D)),
    _BankStyle(
        'KRUNGSRI', ['กรุงศรี', 'ayudhya', 'krungsri'], Color(0xFFFCC200)),
    _BankStyle(
        'SCB', ['ไทยพาณิชย์', 'siam commercial', 'scb'], Color(0xFF4E2A84)),
    _BankStyle('KTB', ['กรุงไทย', 'krungthai', 'ktb'], Color(0xFF00A4E4)),
    _BankStyle('TTB', ['ทีทีบี', 'ทหารไทย', 'ttb'], Color(0xFF0050A0)),
    _BankStyle('GSB', ['ออมสิน', 'gsb'], Color(0xFFEC008C)),
  ];

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
        title: Text('เลือกผู้ให้บริการยืนยันตัวตน NDID',
            style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 15)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(child: _body()),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: LoanRegisterStyles.primary),
            const SizedBox(height: 16),
            Text('กำลังโหลดรายชื่อผู้ให้บริการ...',
                style: LoanRegisterStyles.labelStyle()),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: LoanRegisterStyles.padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: LoanRegisterStyles.label),
              const SizedBox(height: 12),
              Text(
                'ไม่สามารถโหลดรายชื่อผู้ให้บริการ NDID ได้',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: LoanRegisterStyles.value,
                ),
              ),
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: LoanRegisterStyles.labelStyle()),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadIdps,
                style: OutlinedButton.styleFrom(
                  foregroundColor: LoanRegisterStyles.primary,
                  side: BorderSide(color: LoanRegisterStyles.primary),
                ),
                child: Text('ลองใหม่', style: GoogleFonts.notoSansThai()),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(horizontal: LoanRegisterStyles.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupTitle('ผู้ให้บริการที่เคยลงทะเบียน NDID'),
          if (_registered.isEmpty)
            Text('ไม่พบผู้ให้บริการที่ท่านเคยลงทะเบียน NDID',
                style: LoanRegisterStyles.labelStyle())
          else
            _bankGrid(_registered, enabled: true),
          const SizedBox(height: 20),
          _groupTitle('ผู้ให้บริการที่ยังไม่ลงทะเบียน NDID'),
          _bankGrid(_notRegistered, enabled: false),
          const SizedBox(height: 8),
          Text(
            'หากยังไม่ได้ลงทะเบียน NDID กรุณาลงทะเบียนกับธนาคารก่อน',
            style: LoanRegisterStyles.labelStyle(),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.notoSansThai(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: LoanRegisterStyles.value,
        ),
      ),
    );
  }

  Widget _bankGrid(List<_NdidBank> banks, {required bool enabled}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: banks
          .map((b) => _bankTile(b, enabled: enabled))
          .toList(growable: false),
    );
  }

  Widget _bankTile(_NdidBank bank, {required bool enabled}) {
    final bool isSelected = enabled && identical(_selected, bank);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => setState(() => _selected = bank) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.cardBorder,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bank.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  bank.code,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bank.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.notoSansThai(
                  fontSize: 11,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
            LoanRegisterStyles.padding, 12),
        child: Row(
          children: [
            Expanded(
              child: _BarButton(
                label: 'ย้อนกลับ',
                filled: false,
                onTap: () => context.pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BarButton(
                label: 'ถัดไป',
                filled: true,
                enabled: _selected != null,
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _next() async {
    final bank = _selected;
    if (bank == null) return;
    widget.form?.ndidIdpId = bank.idpId; // null in the mock browser flow
    final ok = await context.push<bool>(AppRoutes.ndidVerify,
        extra: widget.form);
    if (ok == true && mounted) context.pop(true);
  }
}

class _BankStyle {
  const _BankStyle(this.code, this.keywords, this.color);
  final String code;
  final List<String> keywords;
  final Color color;
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color primary = LoanRegisterStyles.primary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? (enabled ? primary : primary.withOpacity(0.4))
              : LoanRegisterStyles.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: primary),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansThai(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : primary,
          ),
        ),
      ),
    );
  }
}
