import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../router/app_router.dart';
import '../../services/native_bridge.dart';
import 'components/p_loan_components.dart';
import 'models/p_loan_flow.dart';

/// **Step 4 — รูปภาพหลักประกัน.** Captures the collateral photos the loan type
/// requires: whole vehicle + tax disc for motorcycles, four sides + odometer +
/// tax disc for cars.
///
/// Photos are held in the flow as raw bytes and base64-encoded once at submit
/// time, rather than the source's approach of uploading each one to Firebase
/// Storage and threading three parallel URL/file/base64 fields per slot through
/// the page model.
class PLoanVehiclePhotosPage extends StatefulWidget {
  const PLoanVehiclePhotosPage({super.key, required this.flow});

  final PLoanFlow flow;

  @override
  State<PLoanVehiclePhotosPage> createState() => _PLoanVehiclePhotosPageState();
}

class _PLoanVehiclePhotosPageState extends State<PLoanVehiclePhotosPage> {
  final ImagePicker _picker = ImagePicker();
  bool _capturing = false;

  PLoanFlow get _flow => widget.flow;

  /// Captures one slot. Inside the host the native camera provides the framing
  /// mask for [PLoanPhoto.cameraAction]; elsewhere `image_picker` stands in.
  Future<void> _capture(PLoanPhoto slot) async {
    if (_capturing) return;
    setState(() => _capturing = true);
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
        _capturing = false;
        if (bytes != null && bytes.isNotEmpty) _flow.photos[slot] = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ไม่สามารถถ่ายรูปได้: $e')));
    }
  }

  void _remove(PLoanPhoto slot) {
    setState(() => _flow.photos.remove(slot));
  }

  @override
  Widget build(BuildContext context) {
    final contract = _flow.contract;
    final required = _flow.requiredPhotos;
    final missing = _flow.missingVehiclePhoto;

    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'รูปภาพหลักประกัน'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          PLoanKindBanner(kind: _flow.kind),
          const RegisterStepIndicator(currentStep: 4, totalSteps: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                  LoanRegisterStyles.padding, 24),
              children: [
                if (contract != null)
                  ContractSummaryCard(
                    loanTypeCode: contract.contractDetails.loanTypeCode,
                    loanTypeName: contract.contractDetails.loanTypeName,
                    contractNo: contract.contractNo,
                    collateralInformation:
                        contract.contractDetails.collateralInformation,
                  ),
                const PLoanSectionHeader('ข้อมูลหลักประกัน'),
                _detailRows(),
                const PLoanSectionHeader('ถ่ายรูปหลักประกัน'),
                for (final slot in required)
                  _PhotoSlot(
                    slot: slot,
                    bytes: _flow.photos[slot],
                    busy: _capturing,
                    onCapture: () => _capture(slot),
                    onRemove: () => _remove(slot),
                  ),
                // Slots the P-Loan submission has room for. Optional, so the
                // Next button ignores them.
                const PLoanSectionHeader('เอกสารเพิ่มเติม (ไม่บังคับ)'),
                for (final slot in _flow.optionalPhotos)
                  _PhotoSlot(
                    slot: slot,
                    bytes: _flow.photos[slot],
                    busy: _capturing,
                    onCapture: () => _capture(slot),
                    onRemove: () => _remove(slot),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: PLoanBottomButton(
        label: 'ยืนยัน',
        busy: _capturing,
        onPressed: missing != null
            ? null
            : () => context.push(AppRoutes.pLoanCustomerData, extra: _flow),
      ),
    );
  }

  Widget _detailRows() {
    final detail = _flow.amountDetail;
    if (detail == null) return const SizedBox.shrink();
    final car = detail.carDetails;
    return Column(
      children: [
        PLoanAmountRow(
            label: 'ทะเบียนจังหวัด', value: car.province),
        PLoanAmountRow(
          label: 'วันหมดอายุทะเบียน',
          value: formatThaiDate(detail.contractDetails.licensePlateExpireDate),
        ),
        PLoanAmountRow(
            label: 'ยี่ห้อสินค้า', value: detail.contractDetails.vehicleBrand),
        PLoanAmountRow(
            label: 'รุ่นสินค้า', value: car.series, showDivider: false),
      ],
    );
  }
}

/// One required-photo block: red prompt, then either a capture button or the
/// captured thumbnail with a remove affordance.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.slot,
    required this.bytes,
    required this.busy,
    required this.onCapture,
    required this.onRemove,
  });

  final PLoanPhoto slot;
  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final captured = bytes != null && bytes!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.label,
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.required,
            ),
          ),
          const SizedBox(height: 10),
          if (!captured)
            SizedBox(
              height: 56,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onCapture,
                icon: const Icon(Icons.camera_alt_outlined, size: 20),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8F3FB),
                  foregroundColor: const Color(0xFF1D71B8),
                  side: const BorderSide(color: Color(0xFF1D71B8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                label: Text(
                  'ถ่ายรูปภาพ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    bytes!,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Image.asset(
                      'assets/p_loan/error_image.png',
                      height: 220,
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: InkWell(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0x98000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 20, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
