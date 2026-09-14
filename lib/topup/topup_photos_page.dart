import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../services/image_downscale.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';
import 'models/topup_photo.dart';

/// **Step 5 — รูปภาพหลักประกัน.** Captures the collateral photos the loan type
/// requires: whole vehicle + tax disc for a motorcycle, four sides + odometer +
/// tax disc for a car, tax disc alone for anything else.
///
/// Photos are held in the flow as raw bytes and base64-encoded once at submit
/// time. The source instead uploaded each one to Firebase Storage and threaded
/// three parallel URL/file/base64 fields per slot through the page model —
/// twenty-one fields for seven photos, and a Firebase Storage dependency this
/// app does not have. The bytes are what `POST /topup` wants; the Storage copy
/// was never read back.
///
/// ## This screen uses `image_picker`, **not** the native camera bridge
///
/// Unlike every other capture in this app. The host's `openCamera` handler
/// branches on `action.toLowerCase() == 'selfie'` and falls through to its
/// **ID-card framing mask** for every other action it is given — including all
/// seven collateral ones. An ID-card-shaped cutout is the wrong frame for a
/// whole vehicle, a tax disc or an odometer, and the host cannot be taught new
/// masks without an app release.
///
/// So this screen takes the plain camera instead: no mask, the customer frames
/// the shot themselves. The identity photos on step 7 keep the bridge, because
/// there the ID-card and selfie masks are exactly right.
///
/// ⚠ Two consequences, both handled here:
///
///  - **`image_picker_for_web` ignores `maxWidth`/`imageQuality`**, so the
///    browser returns the camera's full-resolution file and the native
///    downscale the bridge used to do no longer happens. Seven of those
///    base64-encoded into one JSON body would be tens of megabytes, so every
///    capture goes through [ImageDownscale.jpeg] — see
///    `services/image_downscale.dart`.
///  - It relies on the **WebView host's file-chooser support**
///    (`onShowFileChooser` on Android, its iOS equivalent). That is already
///    exercised by `p_loan/submit_form`'s attachment groups, so it is not new
///    ground — but it is the first thing to check if the button does nothing
///    on a device.
///
/// [TopupPhoto.cameraAction] is now unused by this screen. It is kept on the
/// enum because the two identity slots still need it, and because restoring
/// the bridge here is a one-line change if the host ever learns the masks.
class TopupPhotosPage extends StatefulWidget {
  const TopupPhotosPage({super.key, required this.flow});

  final TopupFlow flow;

  @override
  State<TopupPhotosPage> createState() => _TopupPhotosPageState();
}

class _TopupPhotosPageState extends State<TopupPhotosPage> {
  final ImagePicker _picker = ImagePicker();
  TopupPhoto? _capturing;

  TopupFlow get _flow => widget.flow;

  /// Captures one collateral slot with the plain camera — see the class doc
  /// for why this does not go through the host's `openCamera` bridge.
  ///
  /// `maxWidth`/`imageQuality` are still passed because off-web `image_picker`
  /// honours them; on web they are ignored, which is what
  /// [ImageDownscale.jpeg] is for. Doing both means one code path serves the
  /// WebView, a plain browser and a mobile build.
  Future<void> _capture(TopupPhoto slot) async {
    if (_capturing != null) return;
    setState(() => _capturing = slot);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 50,
      );
      // Cancelling is not a failure — leave the slot exactly as it was.
      if (file == null) {
        if (mounted) setState(() => _capturing = null);
        return;
      }
      final raw = await file.readAsBytes();
      final bytes = await ImageDownscale.jpeg(raw);
      if (!mounted) return;
      setState(() {
        _capturing = null;
        if (bytes.isNotEmpty) _flow.setPhoto(slot, bytes);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ไม่สามารถถ่ายรูปได้: $e')));
    }
  }

  void _remove(TopupPhoto slot) => setState(() => _flow.photos.remove(slot));

  /// Registration and tax details for the vehicle being photographed.
  ///
  /// Read-only: this is the record the contract is secured against, and the
  /// customer cannot change it from here — a correction goes through the
  /// branch, the same as their personal data on step 6.
  ///
  /// Prefers the priced detail call, falling back to `/loan/list`'s row
  /// **field by field**.
  ///
  /// ⚠ The fallback must be per field, not per object. `/topup/recal` — which
  /// replaced `/topup/detail` in this flow on 2026-09-14 — returns
  /// `car_details` and `contract_details` as **present but entirely blank**
  /// blocks, so `detail?.carDetails ?? contract?.carDetails` never falls
  /// through: the left side is non-null, and every row rendered empty. That is
  /// what left this section blank, and it is the same defect as the five other
  /// top-up reads fixed on 2026-09-14 — this was the sixth, found on a device.
  /// A `??` against a sub-object of either response is always wrong here.
  Widget _vehicleDetails() {
    final detail = _flow.amountDetail;
    final contract = _flow.contract;
    final detailCar = detail?.carDetails;
    final contractCar = contract?.carDetails;
    final detailContract = detail?.contractDetails;
    final contractContract = contract?.contractDetails;

    String pick(List<String?> candidates) => candidates
        .map((c) => c?.trim() ?? '')
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');

    final rows = <(String, String)>[
      ('ทะเบียนจังหวัด', pick([detailCar?.province, contractCar?.province])),
      (
        'วันหมดอายุทะเบียน',
        formatThaiDate(pick([
          detailContract?.licensePlateExpireDate,
          contractContract?.licensePlateExpireDate,
        ])),
      ),
      (
        'ยี่ห้อสินค้า',
        // `vehicle_brand` on contract_details and `car_brand` on car_details
        // are the same fact from two blocks; whichever arrives is right.
        pick([
          detailContract?.vehicleBrand,
          contractContract?.vehicleBrand,
          detailCar?.brand,
          contractCar?.brand,
        ]),
      ),
      ('รุ่นสินค้า', pick([detailCar?.series, contractCar?.series])),
    ];

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          PLoanAmountRow(
            label: rows[i].$1,
            // A blank field renders as a dash rather than an empty gap, so a
            // missing value reads as "not on file" instead of a layout bug.
            value: rows[i].$2.isEmpty ? '-' : rows[i].$2,
            showDivider: i != rows.length - 1,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final contract = _flow.contract;
    final missing = _flow.missingCollateralPhoto;

    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      // The source titles this screen ข้อมูลการต่อภาษี — it carries the
      // registration/tax block as well as the photos.
      appBar: topupAppBar(context, 'ข้อมูลการต่อภาษี'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 24),
              children: [
                if (contract != null)
                  ContractSummaryCard(
                    loanTypeCode: contract.contractDetails.loanTypeCode,
                    loanTypeName: contract.contractDetails.loanTypeName,
                    contractNo: contract.contractNo,
                    collateralInformation:
                        contract.contractDetails.collateralInformation,
                  ),
                _vehicleDetails(),
                const PLoanSectionHeader('ถ่ายรูปหลักประกัน'),
                Text(
                  'กรุณาถ่ายรูปให้เห็นรายละเอียดชัดเจนในที่ที่มีแสงเพียงพอ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: LoanRegisterStyles.label,
                  ),
                ),
                const SizedBox(height: 14),
                for (final slot in _flow.requiredPhotos)
                  TopupPhotoTile(
                    slot: slot,
                    bytes: _flow.photos[slot],
                    busy: _capturing == slot,
                    onCapture: () => _capture(slot),
                    onClear: () => _remove(slot),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: PLoanBottomButton(
        label: 'ถัดไป',
        onPressed: missing != null
            ? null
            : () => context.push(AppRoutes.topupCustomerData, extra: _flow),
      ),
    );
  }
}
