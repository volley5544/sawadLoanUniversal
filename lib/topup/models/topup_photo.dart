/// The photos a top-up request collects, and the wire field each one fills in
/// the `POST /topup` body.
///
/// Deliberately **its own enum** rather than a reuse of `PLoanPhoto`. The two
/// products happen to photograph the same things today, but each enum is that
/// product's own wire contract: `PLoanPhoto` additionally carries a
/// `regmast_ploan.php` image group, which `POST /topup` has no notion of. Two
/// small enums that can diverge beat one shared enum that has to serve two
/// payloads.
library;

/// A photo slot on the top-up flow.
enum TopupPhoto {
  /// Whole-vehicle shot — motorcycles only (`M`).
  fullVehicle(
    payloadKey: 'property_image',
    cameraAction: 'fullVehicleCamera',
    label: 'บังคับถ่ายรูปภาพหลักประกันเต็มคันมองเห็นป้ายทะเบียนชัดเจน*',
    missingMessage: 'บังคับถ่ายรูปภาพหลักประกันเต็มคันมองเห็นป้ายทะเบียนชัดเจน',
  ),

  /// Tax disc (ป้ายวงกลม) — required for every loan type.
  taxDisc(
    payloadKey: 'act_image',
    cameraAction: 'circleCamera',
    label: 'บังคับถ่ายรูปภาพป้ายวงกลม*',
    missingMessage: 'บังคับถ่ายรูปภาพป้ายวงกลม',
  ),
  carRight(
    payloadKey: 'car_image_right',
    cameraAction: 'rightCamera',
    label: 'บังคับถ่ายรูปด้านข้างขวาเต็มคัน*',
    missingMessage: 'บังคับถ่ายรูปด้านข้างขวาเต็มคัน',
  ),
  carLeft(
    payloadKey: 'car_image_left',
    cameraAction: 'leftCamera',
    label: 'บังคับถ่ายรูปด้านข้างซ้ายเต็มคัน*',
    missingMessage: 'บังคับถ่ายรูปด้านข้างซ้ายเต็มคัน',
  ),
  carFront(
    payloadKey: 'car_image_front',
    cameraAction: 'frontCamera',
    label: 'บังคับถ่ายรูปด้านหน้าตรงเต็มคันมองเห็นป้ายทะเบียนชัดเจน*',
    missingMessage: 'บังคับถ่ายรูปด้านหน้าตรงเต็มคัน',
  ),
  carBack(
    payloadKey: 'car_image_back',
    cameraAction: 'backCamera',
    label: 'บังคับถ่ายรูปด้านหลังตรงเต็มคันมองเห็นป้ายทะเบียนชัดเจน*',
    missingMessage: 'บังคับถ่ายรูปด้านหลังตรงเต็มคัน',
  ),
  carMile(
    payloadKey: 'car_image_mile',
    cameraAction: 'mileCamera',
    label: 'บังคับถ่ายรูปภาพเลขไมล์*',
    missingMessage: 'บังคับถ่ายรูปภาพเลขไมล์',
  ),

  /// The ID card, read by `/vision/thai-id-validate` before it is accepted.
  ///
  /// ⚠ [cameraAction] must stay `idCardCamera`: the host matches the action
  /// string exactly and falls through to the rear-camera ID-card mask for
  /// anything it doesn't recognise, so a near-miss fails silently with a
  /// wrong-looking camera rather than an error.
  idCard(
    payloadKey: 'customer_image_2',
    cameraAction: 'idCardCamera',
    label: 'รูปบัตรประชาชน*',
    missingMessage: 'กรุณาถ่ายรูปบัตรประชาชน',
  ),

  /// Selfie holding the ID card.
  ///
  /// ⚠ `selfie` is the **only** other action the host branches on (it compares
  /// `action.toLowerCase() == 'selfie'`), which is why this is not
  /// `selfieCamera`. That exact bug cost the P-Loan flow its front camera.
  selfieWithIdCard(
    payloadKey: 'customer_image_3',
    cameraAction: 'selfie',
    label: 'รูปถ่ายคู่บัตรประชาชน*',
    missingMessage: 'กรุณาถ่ายรูปคู่บัตรประชาชน',
  );

  const TopupPhoto({
    required this.payloadKey,
    required this.cameraAction,
    required this.label,
    required this.missingMessage,
  });

  /// Field name in the `POST /topup` JSON body.
  final String payloadKey;

  /// Action string handed to the host's `openCamera` JS handler, which picks
  /// the framing mask from it.
  final String cameraAction;

  /// Caption on the capture tile.
  final String label;

  /// Shown when the flow is blocked because this slot is empty.
  final String missingMessage;

  /// The two identity photos, which live on the conclusion screen rather than
  /// the collateral one.
  static const List<TopupPhoto> identity = [idCard, selfieWithIdCard];
}
