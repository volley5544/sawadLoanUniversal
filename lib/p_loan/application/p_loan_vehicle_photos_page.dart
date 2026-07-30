import 'package:flutter/material.dart';
// Also the source of Uint8List here, so dart:typed_data is not imported.
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_field_row.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../loan_register/components/register_text_field.dart';
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
///
/// **The collateral block above the photos is read-only for an Extra and
/// editable for a new P-Loan**, because they have different sources. An Extra
/// tops up a contract, so `/topup/detail` describes the very vehicle being
/// photographed. A new P-Loan only *references* that contract — showing its
/// `ยี่ห้อสินค้า HONDA` here stated another loan's vehicle as this
/// application's, and the customer had no way to correct it. So the type is
/// picked and the details are typed, and the picked type is what decides which
/// photos are required below (see [PLoanFlow.requiredPhotos]).
class PLoanVehiclePhotosPage extends StatefulWidget {
  const PLoanVehiclePhotosPage({super.key, required this.flow});

  final PLoanFlow flow;

  @override
  State<PLoanVehiclePhotosPage> createState() => _PLoanVehiclePhotosPageState();
}

class _PLoanVehiclePhotosPageState extends State<PLoanVehiclePhotosPage> {
  final ImagePicker _picker = ImagePicker();
  bool _capturing = false;

  // New-P-Loan collateral inputs. Seeded from the flow so the values survive
  // a back-navigation, and written straight back to it on every keystroke.
  late final TextEditingController _brand;
  late final TextEditingController _series;
  late final TextEditingController _registration;
  late final TextEditingController _province;
  late final TextEditingController _manufactureYear;

  PLoanFlow get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    final details = _flow.newLoan;
    _brand = TextEditingController(text: details.brand);
    _series = TextEditingController(text: details.series);
    _registration = TextEditingController(text: details.registration);
    _province = TextEditingController(text: details.province);
    _manufactureYear = TextEditingController(text: details.manufactureYear);
    for (final controller in _collateralControllers) {
      controller.addListener(_onCollateralChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _collateralControllers) {
      controller
        ..removeListener(_onCollateralChanged)
        ..dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _collateralControllers =>
      [_brand, _series, _registration, _province, _manufactureYear];

  /// Mirrors the fields onto the flow, and rebuilds only when that flips the
  /// Next button — a rebuild per keystroke would re-decode the photo
  /// thumbnails below for nothing.
  void _onCollateralChanged() {
    final before = _flow.newLoan.hasCollateral;
    _flow.newLoan
      ..brand = _brand.text.trim()
      ..series = _series.text.trim()
      ..registration = _registration.text.trim()
      ..province = _province.text.trim()
      ..manufactureYear = _manufactureYear.text.trim();
    if (_flow.newLoan.hasCollateral != before) setState(() {});
  }

  /// Collateral kind for a new P-Loan. Changing it changes which photos are
  /// required, so anything already captured that the new type doesn't ask for
  /// is dropped rather than left to be submitted silently.
  Future<void> _pickCollateralType() async {
    final picked = await pickPLoanOption<PLoanCollateralType>(
      context: context,
      title: 'ประเภทหลักประกัน',
      options: PLoanCollateralType.values,
      labelOf: (type) => type.label,
      selected: _flow.newLoan.collateralType,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _flow.newLoan.collateralType = picked;
      final keep = {..._flow.requiredPhotos, ..._flow.optionalPhotos};
      _flow.photos.removeWhere((slot, _) => !keep.contains(slot));
    });
  }

  Future<void> _pickRegistrationExpiry() async {
    final current = DateTime.tryParse(_flow.newLoan.registrationExpiry);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    setState(() => _flow.newLoan.registrationExpiry =
        '${picked.year}-$month-$day');
  }

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
    final isNew = _flow.isNewPLoan;
    final required = _flow.requiredPhotos;
    final missing = _flow.missingVehiclePhoto;
    // A new P-Loan has to describe its own collateral before the photo list
    // below means anything — the type is what decides which shots are asked
    // for.
    final collateralStated = !isNew || _flow.newLoan.hasCollateral;

    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'รูปภาพหลักประกัน'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          PLoanKindBanner(kind: _flow.kind),
          RegisterStepIndicator(
              currentStep: _flow.stepNumber(4), totalSteps: _flow.totalSteps),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                  LoanRegisterStyles.padding, 24),
              children: [
                // No ContractSummaryCard here. An Extra used to open this screen
                // with one, but it restated the contract and collateral that the
                // ข้อมูลหลักประกัน rows immediately below already show, and a new
                // P-Loan never had it. Step 2 and step 6 still summarise the
                // contract; this screen is about the photos.
                const PLoanSectionHeader('ข้อมูลหลักประกัน'),
                if (isNew) _collateralInputs() else _detailRows(),
                // Until the type is known there is no meaningful photo list to
                // show, so the section is withheld rather than defaulting to
                // one type's shots.
                if (collateralStated) ...[
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
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: PLoanBottomButton(
        label: 'ยืนยัน',
        busy: _capturing,
        onPressed: (!collateralStated || missing != null)
            ? null
            : () => context.push(AppRoutes.pLoanCustomerData, extra: _flow),
      ),
    );
  }

  /// Editable collateral block for a **new** P-Loan.
  ///
  /// Brand, model, plate and expiry are shown because they identify the
  /// vehicle in the photos below, but only the year currently reaches a
  /// payload (`registerYear`); the rest have no field in either submit API
  /// yet. Plate number, province and expiry are optional — blank renders
  /// blank, which is the honest result when the customer leaves them out.
  Widget _collateralInputs() {
    final details = _flow.newLoan;
    final type = details.collateralType;
    return Column(
      children: [
        RegisterFieldRow(
          label: 'ประเภทหลักประกัน',
          value: type?.label ?? '',
          placeholder: 'กรุณาเลือกประเภทหลักประกัน',
          showDivider: type != null && type.isVehicle,
          onTap: _pickCollateralType,
        ),
        if (type == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '* กรุณาเลือกประเภทหลักประกัน เพื่อระบุรูปภาพที่ต้องถ่าย',
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                color: LoanRegisterStyles.required,
              ),
            ),
          ),
        if (type != null && type.isVehicle) ...[
          RegisterTextField(
            label: 'ยี่ห้อสินค้า',
            controller: _brand,
            hint: 'กรุณากรอกยี่ห้อสินค้า',
          ),
          RegisterTextField(
            label: 'รุ่นสินค้า',
            controller: _series,
            hint: 'กรุณากรอกรุ่นสินค้า',
          ),
          RegisterTextField(
            label: 'ปีที่ผลิต',
            controller: _manufactureYear,
            hint: 'เช่น 2562',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
          ),
          RegisterTextField(
            label: 'เลขทะเบียน (ถ้ามี)',
            controller: _registration,
            hint: 'กรุณากรอกเลขทะเบียน',
          ),
          RegisterTextField(
            label: 'ทะเบียนจังหวัด (ถ้ามี)',
            controller: _province,
            hint: 'กรุณากรอกจังหวัด',
          ),
          RegisterFieldRow(
            label: 'วันหมดอายุทะเบียน (ถ้ามี)',
            value: formatThaiDate(details.registrationExpiry),
            placeholder: 'เลือกวันที่',
            showDivider: false,
            trailing: Icon(Icons.calendar_today_outlined,
                size: 18, color: LoanRegisterStyles.label),
            onTap: _pickRegistrationExpiry,
          ),
        ],
      ],
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
