# file_image_cropper

A fast, multithreaded, file-first image cropper for Flutter, powered by a
native Rust engine. Includes a ready-to-use crop screen, a fully customizable
editor, and a code-driven API.

- Android, iOS, Windows, macOS, and Linux
- JPEG, PNG, static WebP, and platform-supported static HEIC input
- JPEG, PNG, and WebP output
- Free-form or fixed-aspect crop selection
- Exact output dimensions when requested
- Responsive UI while native processing runs in the background
- Safe managed temporary files and atomic explicit outputs

Web is not supported.

## Install

```console
flutter pub add file_image_cropper
```

## Quick start: interactive crop screen

The default editor lets the user choose any crop shape. Omitting `outputSize`
keeps the selected crop's source-pixel dimensions.

```dart
import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';

final CropResult? result = await showFileImageCropper(
  context,
  FileImageCropperPage(
    input: File(imagePath),
    config: const CropperPageConfig(
      outputFormat: OutputFormat.jpeg,
      jpegOptions: JpegOptions(quality: 85),
    ),
  ),
);

if (result != null) {
  print(result.file.path);
}
```

### Fixed aspect ratio and exact output size

Supplying `outputSize` locks the default editor to the same aspect ratio and
resizes the encoded result to those exact physical pixels.

```dart
FileImageCropperPage(
  input: File(imagePath),
  config: const CropperPageConfig(
    outputSize: PixelSize(width: 1080, height: 1080),
    outputFormat: OutputFormat.jpeg,
    jpegOptions: JpegOptions(quality: 85),
  ),
);
```

To lock only the selection shape without forcing an output resolution, set
`aspectRatio` on the page and omit `outputSize`:

```dart
FileImageCropperPage(
  input: File(imagePath),
  aspectRatio: 4 / 3,
  config: const CropperPageConfig(
    outputFormat: OutputFormat.jpeg,
  ),
);
```

### Output configuration

| Parameter | Meaning |
| --- | --- |
| `output` | Optional caller-owned destination file. Omit it for a managed temporary result. |
| `overwrite` | Allows replacing an existing explicit output. Defaults to `false`. |
| `outputSize` | Exact encoded width and height in physical pixels. Also locks the default UI aspect ratio. |
| `resizeFilter` | Resize algorithm. Bilinear is the default; nearest is useful for pixel art. |
| `aspectMismatchPolicy` | Controls how a crop is adjusted when its ratio differs from `outputSize`. |
| `outputFormat` | `jpeg`, `png`, or `webp`. Defaults to PNG. |
| `jpegOptions` | JPEG quality and background used when flattening transparency. Ignored for other formats. |
| `webpOptions` | WebP quality and lossless mode. Ignored for other formats. |

For photographs, JPEG quality `80-90` is usually the fastest and most practical
choice. WebP generally produces smaller files but takes longer to encode. PNG
is best when lossless pixels or transparency are required.

## Crop through code

The UI is optional. Use `crop()` directly when the crop region is already
known:

```dart
final CropResult result = await crop(
  CropRequest(
    input: File('input.jpg'),
    region: const CropRegion.centered(aspectRatio: 4 / 3),
    outputSize: const PixelSize(width: 1200, height: 900),
    outputFormat: OutputFormat.webp,
    webpOptions: const WebpOptions(quality: 84),
  ),
);

print(result.file.path);
```

Available crop regions:

| Region | Use case |
| --- | --- |
| `CropRegion.normalized(...)` | Fractions from `0` to `1`; recommended for custom Flutter crop overlays. |
| `CropRegion.centered(...)` | Largest centered crop with a requested aspect ratio. |
| `CropRegion.pixels(...)` | Exact coordinates in orientation-normalized source pixels. |

An inspection call is not required before normalized or centered crops. All
regions are resolved against the orientation-normalized image, so callers do
not need to reproduce JPEG EXIF rotations.

### Using picker packages

The input is always a `dart:io` `File`. No copy is needed for common picker
results:

```dart
// image_picker or another API returning XFile:
final File input = File(xFile.path);

// photo_manager:
final File? input = await asset.originFile;
```

`file_image_cropper` does not depend on a picker package.

## Customize the crop UI

`FileImageCropperPage` exposes builders for the app bar, body, editor,
controls, confirm/cancel buttons, processing state, errors, image, loading
state, and crop overlay.

```dart
FileImageCropperPage(
  input: input,
  config: const CropperPageConfig(
    outputSize: PixelSize(width: 1200, height: 800),
    outputFormat: OutputFormat.jpeg,
  ),
  appBarBuilder: (context, actions) => AppBar(
    title: const Text('Edit photo'),
    leading: IconButton(
      onPressed: actions.cancel,
      icon: const Icon(Icons.arrow_back),
    ),
  ),
  overlayStyle: const CropOverlayStyle(
    maskColor: Color(0xaa000000),
    borderColor: Colors.amber,
    handleColor: Colors.amber,
    handleShape: CropHandleShape.circle,
    gridRows: 3,
    gridColumns: 3,
  ),
  confirmButtonBuilder: (context, onPressed, processing) => FilledButton(
    onPressed: onPressed,
    child: Text(processing ? 'Saving...' : 'Save'),
  ),
);
```

For a completely custom screen, embed only `CropEditor` and use its
controller:

```dart
final CropEditorController controller = CropEditorController();

CropEditor(
  input: input,
  controller: controller,
  aspectRatio: 4 / 3,
  overlayBuilder: (context, details) => MyCropOverlay(details: details),
);

final CropResult result = await crop(
  CropRequest(input: input, region: controller.region),
);
```

The editor supports moving and resizing the selection, edge and corner
handles, double-tap reset, and pan/zoom for precise work. `requestBuilder` and
`executor` are injectable for custom request construction, state management,
and testing.

## Explicit and managed outputs

When `output` is omitted, the package creates a managed result under
`Directory.systemTemp/file_image_cropper`:

```dart
final CropResult result = await crop(
  CropRequest(
    input: input,
    region: const CropRegion.centered(aspectRatio: 1),
    outputFormat: OutputFormat.jpeg,
  ),
);

assert(result.isManaged);
await result.delete();
```

Managed results remain valid until explicitly deleted. Bulk cleanup removes
only package-owned files:

```dart
await clearTemporaryFiles(olderThan: const Duration(days: 1));
```

To choose the destination yourself:

```dart
final CropResult result = await crop(
  CropRequest(
    input: input,
    output: File('exports/cropped.jpg'),
    overwrite: false,
    region: const CropRegion.normalized(
      left: 0.1,
      top: 0.1,
      width: 0.8,
      height: 0.8,
    ),
    outputFormat: OutputFormat.jpeg,
  ),
);

assert(!result.isManaged);
```

The explicit output's parent directory must already exist. Existing files are
rejected unless `overwrite` is `true`. Calling `CropResult.delete()` on an
explicit caller-owned output is a safe no-op.

Inputs are opened read-only and are never copied, changed, or deleted. Outputs
are written to a unique staging file and atomically committed after a
successful encode.

## Inspect image metadata

Read dimensions, format, and orientation without decoding all pixels:

```dart
final ImageInfo info = await inspectImage(File('photo.webp'));
print('${info.width} x ${info.height}, ${info.format}');
```

Inspection is useful for validation and mapping custom viewport coordinates,
but it is not required before a normal crop.

## Formats and platforms

| Capability | JPEG | PNG | static WebP | static HEIC |
| --- | --- | --- | --- | --- |
| Inspect | All platforms | All platforms | All platforms | Android 9+, iOS, macOS, Windows*, Linux** |
| Input | All platforms | All platforms | All platforms | Android 9+, iOS, macOS, Windows*, Linux** |
| Output | All platforms | All platforms | All platforms | Not supported |

Supported platforms are Android, iOS, Windows, macOS, and Linux. Animated
WebP/GIF or HEIF, AVIF, TIFF, and camera RAW formats are not supported.

### HEIC desktop requirements

HEIC uses the native platform decoder. Crop regions, resizing, and output
options behave the same as for the other input formats.

- On Windows, install
  [Microsoft HEIF Image Extensions](https://apps.microsoft.com/detail/9pmmsr1cgpwg)
  and any HEVC component required by the image.
- On Linux, install your distribution's
  [libheif](https://github.com/strukturag/libheif) runtime package with an HEVC
  decoder. The package does not bundle or download `libheif`.

If an optional codec is missing, `inspectImage()` and `crop()` throw
`HeicCodecUnavailableException` with a platform-specific `helpUri`. Restart
the application after installing the codec.

## Performance

Long-running work stays off the Flutter UI isolate. The native engine uses a
bounded thread pool for larger operations and avoids parallel scheduling
overhead for small images.

## Maintainer source builds

Normal applications do not need this configuration. Maintainers can explicitly
build the native engine from source in the root application's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    file_image_cropper:
      build_from_source: true
```

This mode requires Rust and the relevant cross-compilation tools.

## License

MIT. See [LICENSE](LICENSE).
