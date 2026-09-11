/// Shrinks a captured photo before it goes into a submit payload.
///
/// ## Why this exists
///
/// `image_picker_for_web` — what `image_picker` becomes in this build —
/// **ignores `maxWidth` and `imageQuality`**. It is a hidden
/// `<input type="file" accept="image/*" capture>`, and the browser hands back
/// whatever the camera produced, at full resolution.
///
/// That is survivable when a photo is only displayed. It is not survivable when
/// seven of them are base64-encoded into one JSON body: a modern phone camera
/// produces ~4 MB per shot, base64 adds a third, and `POST /topup` would be
/// asked to swallow tens of megabytes. The top-up flow's collateral screen
/// captures exactly that many.
///
/// The native camera bridge does this downscale itself (≈1280 px / JPEG ~80),
/// which is why the P-Loan flow never needed it — that flow only reaches
/// `image_picker` in a plain browser, where nothing is submitted in anger. The
/// top-up collateral screen uses `image_picker` **inside the host too** (the
/// host applies an ID-card framing mask to every action it does not recognise,
/// which is wrong for photographing a vehicle), so the downscale has to happen
/// here instead.
///
/// ## Why a canvas and not `package:image`
///
/// `dart:ui` can decode and resize but cannot **encode** JPEG — `toByteData`
/// offers PNG and raw RGBA only, and a PNG of a photograph is larger than the
/// JPEG it replaced. `package:image` has a JPEG encoder but is pure Dart, and
/// encoding a 12-megapixel image that way inside a WebView takes seconds per
/// photo. A canvas plus `toDataURL('image/jpeg', q)` is the browser's own
/// native encoder, and this build is a web build.
///
/// ## Failure is not an error
///
/// [ImageDownscale.jpeg] returns the **original bytes** rather than throwing if
/// anything goes wrong — an unreadable blob, a canvas the WebView refuses, a
/// platform with no canvas at all. A photo that is too big still beats no photo
/// at all, and the submit failure that might follow is both visible and
/// reported. Never let this step lose a capture the customer just took.
library;

export 'image_downscale_stub.dart'
    if (dart.library.js_interop) 'image_downscale_web.dart';
