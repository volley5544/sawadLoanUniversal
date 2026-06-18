import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import '../services/native_bridge.dart';
import 'components/loan_register_styles.dart';
import 'components/register_autocomplete_field.dart';
import 'components/register_field_row.dart';
import 'components/register_step_indicator.dart';
import 'components/register_text_field.dart';
import 'components/save_next_bar.dart';
import 'models/loan_register_form.dart';

/// Step 2 of the loan-register wizard — ข้อมูลหลักประกัน (Collateral
/// Information). Screen #2 on slide 7. The ถ่ายรูปภาพ/OCR action asks the native
/// WebView host to capture the document (see [NativeCameraBridge]).
class CollateralInfoPage extends StatefulWidget {
  const CollateralInfoPage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  @override
  State<CollateralInfoPage> createState() => _CollateralInfoPageState();
}

class _CollateralInfoPageState extends State<CollateralInfoPage> {
  late final LoanRegisterForm _form = widget.form ?? LoanRegisterForm.mock();

  /// Mask type passed to the native host's `openCamera` handler.
  static const String _kCaptureAction = 'idCard';

  /// Decoded bytes of the captured document, cached for display.
  Uint8List? _docBytes;

  @override
  void initState() {
    super.initState();
    if (_form.documentImageBase64.isNotEmpty) {
      _docBytes = _tryDecode(_form.documentImageBase64);
    }
  }

  late final TextEditingController _chassis =
      TextEditingController(text: _form.chassisNumber);
  late final TextEditingController _engine =
      TextEditingController(text: _form.engineNumber);
  late final TextEditingController _registration =
      TextEditingController(text: _form.registrationNumber);

  // ── Mock option lists (UI-only) ──────────────────────────────────
  static const List<String> _productGroups = [
    '[MC] - รถมอเตอร์ไซค์',
    '[CAR] - รถยนต์',
    '[TRUCK] - รถบรรทุก',
    '[LAND] - ที่ดิน',
  ];
  static const List<String> _brands = [
    'YAMAHA',
    'HONDA',
    'SUZUKI',
    'KAWASAKI',
    'VESPA',
    'GPX',
  ];
  static const List<String> _models = [
    'FINN-YAMAHA-MC',
    'GRAND FILANO',
    'AEROX 155',
    'WAVE 110i',
    'CLICK 125i',
    'PCX 160',
  ];
  static const List<String> _colors = [
    'ขาว',
    'ดำ',
    'แดง',
    'น้ำเงิน',
    'ฟ้า',
    'เทา',
    'เงิน',
    'เขียว',
    'อื่นๆ',
  ];
  static const List<String> _details = [
    'FINN-YAMAHA-MC 115cc',
    'GRAND FILANO 125cc',
    'AEROX 155cc',
    'WAVE 110i 110cc',
  ];
  static const List<String> _provinces = [
    'กรุงเทพมหานคร',
    'นนทบุรี',
    'ปทุมธานี',
    'สมุทรปราการ',
    'ชลบุรี',
    'ระยอง',
    'เชียงใหม่',
    'เชียงราย',
    'ขอนแก่น',
    'นครราชสีมา',
    'อุบลราชธานี',
    'อุดรธานี',
    'สงขลา',
    'ภูเก็ต',
    'สุราษฎร์ธานี',
    'นครศรีธรรมราช',
  ];

  List<String> get _years =>
      [for (int y = DateTime.now().year; y >= 2000; y--) '$y'];

  @override
  void dispose() {
    _chassis.dispose();
    _engine.dispose();
    _registration.dispose();
    super.dispose();
  }

  void _save() {
    _form
      ..chassisNumber = _chassis.text
      ..engineNumber = _engine.text
      ..registrationNumber = _registration.text;
  }

  /// Scrollable bottom-sheet dropdown used by the selectable fields.
  void _pickOption(String title, List<String> options, String current,
      ValueChanged<String> onPick) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: LoanRegisterStyles.appBarTitleStyle()),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options
                    .map((o) => ListTile(
                          title:
                              Text(o, style: LoanRegisterStyles.valueStyle()),
                          trailing: o == current
                              ? Icon(Icons.check,
                                  color: LoanRegisterStyles.primary)
                              : null,
                          onTap: () => Navigator.of(context).pop(o),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) setState(() => onPick(result));
  }

  void _pickDate(ValueChanged<String> onPick) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) {
      final buddhistYear = picked.year + 543;
      final formatted =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/$buddhistYear';
      setState(() => onPick(formatted));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('2. ข้อมูลหลักประกัน',
            style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          const RegisterStepIndicator(currentStep: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const RegisterSectionTitle('ข้อมูลหลักประกัน'),
                  const SizedBox(height: 8),
                  _form.documentImageBase64.isEmpty || _docBytes == null
                      ? _ocrButton()
                      : _uploadedDocCard(),
                  const SizedBox(height: 6),
                  // กลุ่มสินค้า — dropdown
                  RegisterFieldRow(
                    label: 'กลุ่มสินค้า',
                    value: _form.productGroup,
                    placeholder: 'กรุณาเลือกกลุ่มสินค้า',
                    onTap: () => _pickOption('กลุ่มสินค้า', _productGroups,
                        _form.productGroup, (v) => _form.productGroup = v),
                  ),
                  // ยี่ห้อสินค้า — autocomplete text field
                  RegisterAutocompleteField(
                    label: 'ยี่ห้อสินค้า',
                    labelTrailing: const OcrBadge(),
                    initialValue: _form.brand,
                    options: _brands,
                    hint: 'กรุณากรอกยี่ห้อสินค้า',
                    onChanged: (v) => _form.brand = v,
                  ),
                  // รุ่นสินค้า — autocomplete text field
                  RegisterAutocompleteField(
                    label: 'รุ่นสินค้า',
                    initialValue: _form.model,
                    options: _models,
                    hint: 'กรุณากรอกรุ่นสินค้า',
                    onChanged: (v) => _form.model = v,
                  ),
                  // สีสินค้า — dropdown
                  RegisterFieldRow(
                    label: 'สีสินค้า',
                    value: _form.color,
                    labelTrailing: const OcrBadge(),
                    placeholder: 'กรุณาเลือกสีสินค้า',
                    onTap: () => _pickOption('สีสินค้า', _colors, _form.color,
                        (v) => _form.color = v),
                  ),
                  // รายละเอียดสินค้า — autocomplete text field
                  RegisterAutocompleteField(
                    label: 'รายละเอียดสินค้า',
                    initialValue: _form.productDetail,
                    options: _details,
                    hint: 'กรุณากรอกรายละเอียดสินค้า',
                    onChanged: (v) => _form.productDetail = v,
                  ),
                  // เลขตัวถัง — text field
                  RegisterTextField(
                    label: 'เลขตัวถัง',
                    controller: _chassis,
                    hint: 'กรุณากรอกเลขตัวถัง',
                  ),
                  // เลขเครื่องยนต์ — text field
                  RegisterTextField(
                    label: 'เลขเครื่องยนต์',
                    controller: _engine,
                    labelTrailing: const OcrBadge(),
                    hint: 'กรุณากรอกเลขเครื่องยนต์',
                  ),
                  // ปีที่ผลิต — dropdown
                  RegisterFieldRow(
                    label: 'ปีที่ผลิต',
                    value: _form.manufactureYear,
                    labelTrailing: const OcrBadge(),
                    placeholder: 'กรุณาเลือกปีที่ผลิต',
                    onTap: () => _pickOption('ปีที่ผลิต', _years,
                        _form.manufactureYear, (v) => _form.manufactureYear = v),
                  ),
                  // เลขทะเบียน — text field
                  RegisterTextField(
                    label: 'เลขทะเบียน',
                    controller: _registration,
                    labelTrailing: const OcrBadge(),
                    hint: 'กรุณากรอกเลขทะเบียน',
                  ),
                  // ทะเบียนจังหวัด — dropdown
                  RegisterFieldRow(
                    label: 'ทะเบียนจังหวัด',
                    value: _form.registrationProvince,
                    labelTrailing: const OcrBadge(),
                    placeholder: 'กรุณาเลือกทะเบียนจังหวัด',
                    onTap: () => _pickOption(
                        'ทะเบียนจังหวัด',
                        _provinces,
                        _form.registrationProvince,
                        (v) => _form.registrationProvince = v),
                  ),
                  // วันหมดอายุทะเบียน — date picker
                  RegisterFieldRow(
                    label: 'วันหมดอายุทะเบียน',
                    value: _form.registrationExpiry,
                    placeholder: 'กรุณาเลือกวันหมดอายุทะเบียน',
                    trailing: Icon(Icons.calendar_month_outlined,
                        color: LoanRegisterStyles.label, size: 22),
                    showDivider: false,
                    onTap: () =>
                        _pickDate((d) => _form.registrationExpiry = d),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SaveNextBar(
            onSaveDraft: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('บันทึกข้อมูลร่างแล้ว')),
            ),
            onNext: () {
              _save();
              context.push(AppRoutes.loanInfo, extra: _form);
            },
          ),
        ],
      ),
    );
  }

  /// Uploaded-document card shown after a successful capture: thumbnail +
  /// status + ดูเอกสาร (preview) + delete (clear).
  Widget _uploadedDocCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _docBytes!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'เอกสารหลักประกัน',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'อัปโหลดแล้ว',
                      style: GoogleFonts.notoSansThai(
                          fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _docAction(Icons.visibility_outlined, 'ดูเอกสาร',
              LoanRegisterStyles.primary, _viewDocument, showLabel: true),
          const SizedBox(width: 8),
          _docAction(Icons.delete_outline, 'ลบเอกสาร', LoanRegisterStyles.required,
              () => setState(() {
                    _form.documentImageBase64 = '';
                    _docBytes = null;
                  })),
        ],
      ),
    );
  }

  /// Full-screen, zoomable preview of the captured document.
  void _viewDocument() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: Center(child: Image.memory(_docBytes!)),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docAction(
      IconData icon, String label, Color color, VoidCallback onTap,
      {bool showLabel = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(showLabel ? 20 : 8),
      child: Container(
        padding: showLabel
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
            : const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: showLabel ? Colors.white : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(showLabel ? 20 : 8),
          border: Border.all(color: color.withOpacity(showLabel ? 1 : 0.4)),
        ),
        child: showLabel
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              )
            : Icon(icon, size: 18, color: color),
      ),
    );
  }

  /// Ask the native host to capture the document, then cache the bytes for
  /// display and keep the base64 on the form for the future OCR API call.
  Future<void> _captureDocument() async {
    if (!NativeCameraBridge.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('การถ่ายรูปใช้ได้เฉพาะในแอปพลิเคชันเท่านั้น')),
      );
      return;
    }
    try {
      final bytes = await NativeCameraBridge.captureDocument(_kCaptureAction);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('รูป Output: $bytes')),
      );
      if (!mounted || bytes == null) return; // null = cancelled / no image
      setState(() {
        _docBytes = bytes;
        _form.documentImageBase64 = base64Encode(bytes);
      });
      // TODO: POST the image to the OCR API and auto-fill the fields below.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถถ่ายรูปเอกสารได้: $e')),
      );
    }
  }

  Uint8List? _tryDecode(String base64) {
    try {
      final comma = base64.indexOf(',');
      final raw =
          base64.startsWith('data:') && comma != -1 ? base64.substring(comma + 1) : base64;
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// The ถ่ายรูปภาพ/OCR action → asks the native WebView host to open its
  /// camera (see [NativeCameraBridge]). On a successful capture it stores the
  /// returned base64 (shown as the uploaded card) ready for the future OCR API
  /// call that will auto-fill the fields below.
  Widget _ocrButton() {
    return InkWell(
      onTap: _captureDocument,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFD9EBFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1D71B8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined,
                color: const Color(0xFF1D71B8), size: 20),
            const SizedBox(width: 8),
            Text(
              'ถ่ายรูปภาพ/OCR',
              style: GoogleFonts.notoSansThai(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D71B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}