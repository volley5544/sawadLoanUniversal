import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../loan_register/components/env_version_tag.dart';
import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_field_row.dart';
import '../../loan_register/components/register_text_field.dart';
import '../../loan_register/components/save_next_bar.dart';
import '../../services/native_bridge.dart';
import '../../services/p_loan_api_service.dart';

/// A scalar text field on the P-Loan form: its API key, Thai label and
/// keyboard type.
class _Field {
  const _Field(this.key, this.label, {this.keyboard = TextInputType.text});
  final String key;
  final String label;
  final TextInputType keyboard;
}

/// A group of image uploads sent to the API as repeated `key[]` file parts.
class _ImageGroup {
  const _ImageGroup(this.key, this.label);
  final String key;
  final String label;
}

const _num = TextInputType.numberWithOptions(decimal: true);

/// Form sections, keyed to the fields of the `regmast_ploan.php` API.
const List<(String, List<_Field>)> _sections = [
  ('ข้อมูลรายการ', [
    _Field('transNo', 'เลขที่รายการ'),
    _Field('transDate', 'วันที่ทำรายการ'),
    _Field('statusCode', 'สถานะ'),
    _Field('empId', 'รหัสพนักงาน', keyboard: TextInputType.number),
    _Field('branchID', 'รหัสสาขา'),
    _Field('refContractNo', 'เลขที่สัญญาอ้างอิง'),
    _Field('mktChannel', 'ช่องทางการตลาด'),
    _Field('customerSource', 'แหล่งที่มาลูกค้า'),
  ]),
  ('ข้อมูลลูกค้า', [
    _Field('citizenId', 'เลขบัตรประชาชน', keyboard: TextInputType.number),
    _Field('test', 'ชื่อลูกค้า (test)'),
    _Field('mobileNo', 'เบอร์โทรศัพท์', keyboard: TextInputType.phone),
    _Field('registerYear', 'ปีที่จดทะเบียน (พ.ศ.)', keyboard: TextInputType.number),
  ]),
  ('ข้อมูลสินเชื่อ', [
    _Field('requestCredit', 'วงเงินที่ขอ', keyboard: _num),
    _Field('creditAmt', 'วงเงินอนุมัติ', keyboard: _num),
    _Field('loanAmt', 'ยอดจัดสินเชื่อ', keyboard: _num),
    _Field('termPeriod', 'จำนวนงวด', keyboard: TextInputType.number),
    _Field('totalAmt', 'ยอดรวมทั้งสิ้น', keyboard: _num),
    _Field('intAmt', 'ดอกเบี้ยรวม', keyboard: _num),
    _Field('intRate', 'อัตราดอกเบี้ย (%)', keyboard: _num),
    _Field('regularPeriod', 'ค่างวดปกติ', keyboard: _num),
    _Field('lastPeriod', 'ค่างวดสุดท้าย', keyboard: _num),
    _Field('lastPeriodPromo', 'ค่างวดสุดท้าย (โปรโมชัน)', keyboard: _num),
    _Field('payDay', 'วันชำระ'),
    _Field('initialDate', 'วันเริ่มสัญญา'),
  ]),
  ('ข้อมูลการโอนเงิน', [
    _Field('bankCode', 'ธนาคาร'),
    _Field('bankAccNo', 'เลขที่บัญชี', keyboard: TextInputType.number),
    _Field('transferAmt', 'ยอดโอน', keyboard: _num),
  ]),
  ('ตำแหน่ง GPS', [
    _Field('gpsProvinceId', 'จังหวัด (id)', keyboard: TextInputType.number),
    _Field('gpsAumphurId', 'อำเภอ (id)', keyboard: TextInputType.number),
    _Field('longitude', 'ลองจิจูด', keyboard: _num),
    _Field('latitude', 'ละติจูด', keyboard: _num),
  ]),
  ('ความยินยอมและอื่น ๆ', [
    _Field('marketingConsent', 'ยินยอมการตลาด (Y/N)'),
    _Field('sensitiveConsent', 'ยินยอมข้อมูลอ่อนไหว (Y/N)'),
    _Field('remark', 'หมายเหตุ'),
  ]),
];

/// The 12 image groups the API accepts (repeated `key[]` file parts).
const List<_ImageGroup> _imageGroups = [
  _ImageGroup('documentImage', 'เอกสารประกอบ'),
  _ImageGroup('eSignatureImage', 'ลายเซ็นอิเล็กทรอนิกส์'),
  _ImageGroup('bookBankImage', 'หน้าสมุดบัญชี'),
  _ImageGroup('cardIdImage', 'บัตรประชาชน'),
  _ImageGroup('carBookImage', 'เล่มทะเบียนรถ'),
  _ImageGroup('carImage', 'รูปรถ'),
  _ImageGroup('requestDocImage', 'เอกสารคำขอ'),
  _ImageGroup('customerImage', 'รูปลูกค้า'),
  _ImageGroup('coBorrowCenSusImage', 'ทะเบียนบ้านผู้กู้ร่วม'),
  _ImageGroup('coBorrowCardIdImage', 'บัตรประชาชนผู้กู้ร่วม'),
  _ImageGroup('coCustomerImage', 'รูปผู้กู้ร่วม'),
  _ImageGroup('coBorrowRequestDocImage', 'เอกสารคำขอผู้กู้ร่วม'),
];

/// Sample values (from the original `p-loan-api-call.php`) so the form renders
/// fully populated, matching the mock-data convention used elsewhere.
const Map<String, String> _sampleValues = {
  'transNo': 'C2026060415543600789',
  'transDate': '2026-06-04 16:03:58',
  'mobileNo': '0863652156',
  'creditAmt': '6500.00',
  'loanAmt': '6000.00',
  'gpsAumphurId': '1041',
  'gpsProvinceId': '10',
  'termPeriod': '12',
  'totalAmt': '6795.70',
  'intAmt': '795.70',
  'intRate': '1.09',
  'regularPeriod': '566.00',
  'lastPeriod': '569.70',
  'lastPeriodPromo': '',
  'payDay': '',
  'initialDate': '',
  'bankCode': 'BBL',
  'bankAccNo': '1234567890',
  'transferAmt': '',
  'statusCode': 'A',
  'empId': '9472',
  'branchID': '1C',
  'remark': '',
  'requestCredit': '136500.00',
  'longitude': '100.5755956',
  'latitude': '13.8890019',
  'mktChannel': '065',
  'registerYear': '2559',
  'customerSource': '9',
  'marketingConsent': 'Y',
  'sensitiveConsent': 'Y',
  'refContractNo': '6ฑM690501001NF48X',
  'citizenId': '1670200003359',
  'test': 'Nimit',
};

/// A data-entry form for the legacy P-Loan registration API
/// (`regmast_ploan.php`). Every field maps 1:1 to an API parameter; the image
/// sections collect photos via the native camera bridge and are submitted as
/// repeated `key[]` file parts. Reached from the home menu.
class PLoanFormPage extends StatefulWidget {
  const PLoanFormPage({Key? key}) : super(key: key);

  @override
  State<PLoanFormPage> createState() => _PLoanFormPageState();
}

class _PLoanFormPageState extends State<PLoanFormPage> {
  /// One controller per scalar field, keyed by API name.
  final Map<String, TextEditingController> _controllers = {};

  /// Attached image bytes per image-group key.
  final Map<String, List<Uint8List>> _images = {};

  final ImagePicker _picker = ImagePicker();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (final section in _sections) {
      for (final f in section.$2) {
        _controllers[f.key] =
            TextEditingController(text: _sampleValues[f.key] ?? '');
      }
    }
    for (final g in _imageGroups) {
      _images[g.key] = <Uint8List>[];
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Collect the current scalar values into the API field map.
  Map<String, String> _collectFields() =>
      {for (final e in _controllers.entries) e.key: e.value.text.trim()};

  /// Let the user pick a camera shot or a gallery image for [group], then
  /// append it.
  ///
  /// Camera prefers the native host's own camera (framing mask + native
  /// downscaling) when the bridge is available; everything else goes through
  /// `image_picker`, which on web is a hidden `<input type="file">`.
  Future<void> _addImage(_ImageGroup group) async {
    final source = await _pickImageSource(group.label);
    if (source == null || !mounted) return; // sheet dismissed
    final useHostCamera =
        source == ImageSource.camera && NativeCameraBridge.isSupported;
    try {
      final bytes = useHostCamera
          ? await NativeCameraBridge.captureDocument(group.key)
          : await _pickWithImagePicker(source);
      if (!mounted || bytes == null) return; // null = cancelled
      setState(() => _images[group.key]!.add(bytes));
    } catch (e) {
      if (!mounted) return;
      _snack('ไม่สามารถแนบรูปได้: $e');
    }
  }

  /// Bottom sheet asking กล้อง vs. คลังภาพ. Returns null if dismissed.
  Future<ImageSource?> _pickImageSource(String title) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
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
            ListTile(
              leading: Icon(Icons.photo_camera_outlined,
                  color: LoanRegisterStyles.primary),
              title: Text('ถ่ายรูป', style: LoanRegisterStyles.valueStyle()),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: LoanRegisterStyles.primary),
              title: Text('เลือกรูปจากคลังภาพ',
                  style: LoanRegisterStyles.valueStyle()),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Pick one image through `image_picker`. The size caps are honoured on
  /// mobile/desktop only — `image_picker_for_web` ignores them, so a web build
  /// gets the original file bytes.
  Future<Uint8List?> _pickWithImagePicker(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    return file == null ? null : await file.readAsBytes();
  }

  void _removeImage(String key, int index) {
    setState(() => _images[key]!.removeAt(index));
  }

  /// Show the scalar payload that would be sent (handy for testing without a
  /// reachable backend).
  void _previewPayload() {
    final fields = _collectFields();
    final files = {
      for (final g in _imageGroups)
        if (_images[g.key]!.isNotEmpty) '${g.key}[]': _images[g.key]!.length
    };
    final pretty = const JsonEncoder.withIndent('  ')
        .convert({'fields': fields, 'files (count)': files});
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Payload', style: LoanRegisterStyles.appBarTitleStyle()),
        content: SingleChildScrollView(
          child: SelectableText(pretty,
              style: GoogleFonts.robotoMono(fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final service = PLoanApiService();
    try {
      final result = await service.submit(
        fields: _collectFields(),
        imageGroups: {
          for (final g in _imageGroups)
            if (_images[g.key]!.isNotEmpty) g.key: _images[g.key]!,
        },
      );
      if (!mounted) return;
      _snack('ส่งข้อมูลสำเร็จ: ${result is String ? result : jsonEncode(result)}');
    } on PLoanApiException catch (e) {
      if (!mounted) return;
      _snack('ส่งข้อมูลไม่สำเร็จ: ${e.message}');
    } finally {
      service.dispose();
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text(
          'สมัครสินเชื่อ P-Loan',
          style: LoanRegisterStyles.appBarTitleStyle()
              .copyWith(color: LoanRegisterStyles.primary),
        ),
        actions: const [EnvVersionTag()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 24),
        children: [
          for (final section in _sections) ...[
            RegisterSectionTitle(section.$1),
            for (final f in section.$2)
              RegisterTextField(
                label: f.label,
                controller: _controllers[f.key]!,
                keyboardType: f.keyboard,
              ),
          ],
          RegisterSectionTitle('รูปภาพและเอกสารแนบ'),
          for (final g in _imageGroups)
            _ImageGroupTile(
              group: g,
              images: _images[g.key]!,
              onAdd: () => _addImage(g),
              onRemove: (i) => _removeImage(g.key, i),
            ),
        ],
      ),
      bottomNavigationBar: SaveNextBar(
        saveLabel: 'ดู Payload',
        nextLabel: _submitting ? 'กำลังส่ง…' : 'ส่งข้อมูล',
        onSaveDraft: _previewPayload,
        onNext: _submitting ? () {} : _submit,
      ),
    );
  }
}

/// One image group: a label, an "แนบรูป" button, and thumbnails of what's
/// attached (tap the × to remove).
class _ImageGroupTile extends StatelessWidget {
  const _ImageGroupTile({
    required this.group,
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  final _ImageGroup group;
  final List<Uint8List> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${group.label}  (${images.length})',
                    style: LoanRegisterStyles.labelStyle()
                        .copyWith(fontSize: 14)),
              ),
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: LoanRegisterStyles.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LoanRegisterStyles.primary),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          size: 16, color: LoanRegisterStyles.primary),
                      const SizedBox(width: 6),
                      Text('แนบรูป',
                          style: GoogleFonts.notoSansThai(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: LoanRegisterStyles.primary,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < images.length; i++)
                  _Thumbnail(bytes: images[i], onRemove: () => onRemove(i)),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Divider(color: LoanRegisterStyles.divider, height: 1),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes,
              width: 64, height: 64, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            iconSize: 18,
            icon: const Icon(Icons.cancel, color: Colors.black54),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
