import 'package:flutter/material.dart';
// Also the source of Uint8List here, so dart:typed_data is not imported.
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../services/native_bridge.dart';
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

  /// Captures one slot. Inside the host the native camera supplies the framing
  /// mask for [TopupPhoto.cameraAction] and hands the image back through the
  /// `openCamera` JS handler; in a plain browser `image_picker` stands in.
  ///
  /// This is the JS-bridge replacement for the source's console-log protocol,
  /// which printed `"${action}CameraAction5544${type}"` and then waited for the
  /// host to dispatch a `fromFlutterMobile` CustomEvent carrying the base64.
  /// `callHandler` returns a promise, so the image is simply the awaited
  /// result — no global listener, no correlation by action name, and a cancel
  /// is just `null` instead of silence.
  Future<void> _capture(TopupPhoto slot) async {
    if (_capturing != null) return;
    setState(() => _capturing = slot);
    try {
      final Uint8List? bytes;
      if (NativeCameraBridge.isSupported) {
        bytes = await NativeCameraBridge.captureDocument(slot.cameraAction);
      } else {
        final file = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          imageQuality: 50,
        );
        bytes = file == null ? null : await file.readAsBytes();
      }
      if (!mounted) return;
      setState(() {
        _capturing = null;
        if (bytes != null && bytes.isNotEmpty) _flow.photos[slot] = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ไม่สามารถถ่ายรูปได้: $e')));
    }
  }

  void _remove(TopupPhoto slot) => setState(() => _flow.photos.remove(slot));

  @override
  Widget build(BuildContext context) {
    final contract = _flow.contract;
    final missing = _flow.missingCollateralPhoto;

    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'รูปภาพหลักประกัน'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(5),
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
