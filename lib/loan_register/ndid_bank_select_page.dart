import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import '../services/diagnostics.dart';
import '../services/native_bridge.dart';
import '../services/ndid_api.dart';
import '../services/ndid_common_message.dart';
import 'components/env_version_tag.dart';
import 'components/loan_register_styles.dart';
import '../models/ndid_subject.dart';

/// เลือกธนาคารที่เกี่ยวข้อง NDID — pick the Identity Provider (IDP) bank used
/// for NDID verification (screens #3–#4 on slide 8).
///
/// Shows banks the customer has already registered with NDID, and those they
/// have not. **Both grids are selectable** — picking any bank and tapping ถัดไป
/// continues to [NdidVerifyPage] with that IdP's node id. The two groups are
/// only a hint about what happens next: a registered bank verifies straight
/// away, an unregistered one first walks the customer through NDID sign-up in
/// the bank's own app, then verifies — the same request either way, so this
/// build does not branch on it. (The bank's own app — K+ PIN pad, NDID consent,
/// sign-up — is a third-party screen handled outside this build.)
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
  const _NdidBank(this.code, this.name, this.color,
      {this.idpId, this.logoUrl = ''});

  /// Short mark shown when there is no [logoUrl] (or it fails to load). Kept
  /// deliberately short — it sits in a 44×44 box.
  final String code;
  final String name;
  final Color color;

  /// Real NDID node id (e.g. `idp1`) — null for the mock browser-only banks.
  final String? idpId;

  /// Logo served by the NDID gateway; empty for the mock browser-only banks.
  final String logoUrl;
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
    Diagnostics.log('ndid idp/list start');
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
      final registeredTiles = registered.map(_toBank).toList(growable: false);
      final otherTiles = others.map(_toBank).toList(growable: false);
      // The tile count is the number that matters: see [_kMaxLogoTiles]. `logos`
      // is how many platform views this render will actually create, so a future
      // trail shows at a glance whether the ration held.
      Diagnostics.log('ndid idp/list ok registered=${registeredTiles.length} '
          'others=${otherTiles.length} '
          'logos=${registeredTiles.take(_kMaxLogoTiles).where(
                (b) => b.logoUrl.isNotEmpty,
              ).length}');
      setState(() {
        _registered = registeredTiles;
        _notRegistered = otherTiles;
        _loading = false;
      });
    } on NdidApiException catch (e) {
      Diagnostics.log('ndid idp/list fail ${e.message}');
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
        return _NdidBank(s.code, name, s.color,
            idpId: idp.id, logoUrl: idp.logoUrl);
      }
    }
    return _NdidBank(
      _initials(idp),
      name,
      LoanRegisterStyles.primary,
      idpId: idp.id,
      logoUrl: idp.logoUrl,
    );
  }

  /// Short mark for an IdP outside [_knownBankStyles], used when its logo is
  /// missing or fails to load.
  ///
  /// This used to be `idp.id.toUpperCase()`, which was fine on the DAP node
  /// (`idp1`, `idp2`) and broke on the uat gateway, whose ids are **UUIDs**: a
  /// 36-character string in a 44×44 box overflowed its tile. Initials come from
  /// the name instead, which is what a reader can actually match to the label
  /// underneath.
  static String _initials(NdidIdp idp) {
    final en = idp.displayNameEn.trim();
    if (RegExp(r'[A-Za-z]').hasMatch(en)) {
      final letters = en
          .split(RegExp(r'[\s.()\-]+'))
          .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-z0-9]').hasMatch(w))
          .take(3)
          .map((w) => w[0].toUpperCase())
          .join();
      if (letters.isNotEmpty) return letters;
    }
    // Thai names have no word breaks to take initials from, so a short prefix
    // of the name is the best available mark.
    final th = idp.displayNameTh.replaceFirst('ธนาคาร', '').trim();
    if (th.isNotEmpty) return th.characters.take(3).toString();
    return '—';
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
          // NDID Common Message 6.2.1 [2] — the standard tells the customer
          // what makes a provider usable before they pick one. Do not reword.
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              NdidCommonMessage.chooseIdp,
              style: LoanRegisterStyles.labelStyle(),
            ),
          ),
          _groupTitle('ผู้ให้บริการที่เคยลงทะเบียน NDID'),
          if (_registered.isEmpty)
            Text('ไม่พบผู้ให้บริการที่ท่านเคยลงทะเบียน NDID',
                style: LoanRegisterStyles.labelStyle())
          else
            _bankGrid(_registered, enabled: true, showLogos: true),
          const SizedBox(height: 20),
          _groupTitle('ผู้ให้บริการที่ยังไม่ลงทะเบียน NDID'),
          _bankGrid(_notRegistered, enabled: true, showLogos: false),
          const SizedBox(height: 8),
          Text(
            'หากเลือกผู้ให้บริการที่ยังไม่ได้ลงทะเบียน '
            'ท่านจะต้องลงทะเบียน NDID กับธนาคารนั้นในแอปของธนาคารก่อนจึงจะยืนยันตัวตนได้',
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

  /// Most tiles allowed to render a real logo — i.e. the ceiling on how many HTML
  /// `<img>` **platform views** this page may create at once.
  ///
  /// **This limit is why the page no longer kills the WebView.** Every logo tile
  /// is an `Image.network` with [WebHtmlElementStrategy.prefer] (see [_bankMark]
  /// for why it has to be), and in Flutter web's CanvasKit renderer each platform
  /// view splits the scene into its own GPU-backed overlay canvas. The uat gateway
  /// returns **16** IdPs for a real customer — 1 registered, 15 not — and both
  /// grids are built eagerly in a [Wrap] with no viewport culling, so all 16
  /// appeared at once. At phone DPR that is on the order of 12 MB per overlay,
  /// far past what one WKWebView content process gets, and the process was
  /// killed: a foreground crash on this screen, confirmed from a tester's
  /// breadcrumb trail (2026-08-17) which ended at `push /ndidBankSelectPage` with
  /// no exception and no lifecycle change before it. It only reproduced when the
  /// customer lingered here; tapping a bank within ~3 s beat the image loads.
  static const int _kMaxLogoTiles = 4;

  /// Builds one grid. `showLogos` is granted to the *registered* grid only, and
  /// even there capped at [_kMaxLogoTiles].
  ///
  /// Registered is the right grid to spend the budget on: it is the bank the
  /// customer actually uses, and it is normally one or two tiles. The
  /// not-registered grid is the long one, and a coloured [_codeMark] with the
  /// bank's initials identifies it well enough to pick.
  Widget _bankGrid(
    List<_NdidBank> banks, {
    required bool enabled,
    required bool showLogos,
  }) {
    final children = <Widget>[];
    for (int i = 0; i < banks.length; i++) {
      children.add(_bankTile(
        banks[i],
        enabled: enabled,
        showLogo: showLogos && i < _kMaxLogoTiles,
      ));
    }
    return Wrap(spacing: 12, runSpacing: 12, children: children);
  }

  /// The 44×44 square at the top of a tile: the IdP's own logo when the gateway
  /// gives one, else a coloured box with [_NdidBank.code].
  ///
  /// **Why `webHtmlElementStrategy: prefer`.** The gateway serves these logos
  /// with **no** `access-control-allow-*` headers, and the placeholder one is an
  /// **SVG** — so Flutter web's default byte-fetch path fails twice over (CORS
  /// blocks it, and there is no SVG decoder in `dart:ui`). `prefer` displays the
  /// image in an HTML `<img>` element instead, which needs no CORS and renders
  /// SVG natively. The bridge is no help here: `httpRequest` returns its body as
  /// a UTF-8 string, which cannot carry a JPEG.
  ///
  /// ⚠ **Each of these is a platform view, and they are rationed.** `showLogo` is
  /// false for most tiles — see [_kMaxLogoTiles] for the crash that made that
  /// necessary. Do not render one unconditionally again.
  ///
  /// Off web, and if the element approach fails too, [_codeMark] takes over —
  /// so a tile is never blank.
  Widget _bankMark(_NdidBank bank, {required bool showLogo}) {
    if (!showLogo || bank.logoUrl.isEmpty) return _codeMark(bank);
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Image.network(
        bank.logoUrl,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => _codeMark(bank),
      ),
    );
  }

  Widget _codeMark(_NdidBank bank) {
    return Container(
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.notoSansThai(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _bankTile(
    _NdidBank bank, {
    required bool enabled,
    required bool showLogo,
  }) {
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
              _bankMark(bank, showLogo: showLogo),
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
    // The IdP Marketing Name, which NDID's standard messages must show instead
    // of the word "IdP" or a node id (guideline 6.2.1 bullet 4).
    widget.form?.ndidIdpName = bank.name;
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
