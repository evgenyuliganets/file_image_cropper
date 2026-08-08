# file_image_cropper

A fast, file-first image cropper for Flutter with a customizable editor widget.
JPEG, PNG, and static WebP files are decoded, transformed, and encoded by a
Rust native engine while the Flutter UI isolate remains responsive.

## Supported platforms

- Android
- iOS
- Windows
- macOS
- Linux

Web is not supported.

## Native build model

Application builds download one precompiled Rust library matching the target
platform and architecture. The build hook verifies its embedded SHA-256 digest
before Flutter bundles it and reuses the verified file from Flutter's shared
build cache on later builds. Package consumers therefore do not need Rust,
`rustup`, Cargo, or a Rust cross-compilation toolchain.

Flutter still needs its normal platform toolchain: the Android SDK/NDK for an
Android app, Xcode for an Apple app, Visual Studio Build Tools for Windows, or
the standard Linux desktop build dependencies. These are Flutter requirements,
not additional requirements introduced by this package.

Maintainers and source-build environments can opt out of the download in the
root application's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    file_image_cropper:
      build_from_source: true
```

That mode uses the pinned Rust toolchain and requires Rust plus the relevant
cross-compilation tools. A previously built library can instead be supplied
with an absolute or app-relative path:

```yaml
hooks:
  user_defines:
    file_image_cropper:
      native_library: tool/native/file_image_cropper_native.dll
```

`native_library` and `build_from_source` are mutually exclusive. Prebuilt
libraries are published as a separate GitHub Release for each package version;
the package itself stays small and each build downloads only its target asset.

## Supported formats

| Capability | JPEG | PNG | static WebP |
| --- | --- | --- | --- |
| Inspect | yes | yes | yes |
| Input | yes | yes | yes |
| Output | yes | yes | yes |

Animated WebP/GIF, HEIC/HEIF, AVIF, TIFF, and camera RAW formats are not
supported. Formats are detected from their contents instead of filename
extensions.

## Usage

```dart
import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';

final result = await crop(
  CropRequest(
    input: File('input.jpg'),
    region: const CropRegion.centered(aspectRatio: 4 / 3),
    outputSize: const PixelSize(width: 1200, height: 900),
    outputFormat: OutputFormat.webp,
    webpOptions: const WebpOptions(quality: 84),
  ),
);

print(result.file.path);

// Managed outputs remain valid until explicitly removed.
await result.delete();
```

### Interactive crop UI

The UI layer is optional; the `crop()` and `inspectImage()` functions remain
available for code-driven processing. To open the ready-made crop screen:

```dart
final result = await showFileImageCropper(
  context,
  FileImageCropperPage(
    input: File('input.jpg'),
    config: const CropperPageConfig(
      outputSize: PixelSize(width: 1080, height: 1080),
      outputFormat: OutputFormat.webp,
      webpOptions: WebpOptions(quality: 84),
    ),
  ),
);
```

The editor reads metadata internally, displays the orientation-normalized
image, and sends a normalized selection to the same native crop pipeline. The
selection can be moved, resized from corners or edges, recreated by dragging
outside it, and reset with a double tap or the reset action. The app-bar mode
switch enables pan/zoom up to 8x for precise work on large source images.
Supplying an `outputSize` locks the default editor to the matching aspect ratio.

The ready-made page exposes builders for the app bar, complete body, editor,
controls, confirm/cancel buttons, processing state, page error, image,
loading/error state, and crop overlay. The built-in mask is configurable too:

```dart
FileImageCropperPage(
  input: input,
  config: const CropperPageConfig(
    outputSize: PixelSize(width: 1200, height: 800),
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
  confirmButtonBuilder: (context, onPressed, processing) => FilledButton.icon(
    onPressed: onPressed,
    icon: processing
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.check),
    label: const Text('Save'),
  ),
);
```

For an entirely custom screen, embed only `CropEditor` and read its controller:

```dart
final editorController = CropEditorController();

CropEditor(
  input: input,
  controller: editorController,
  aspectRatio: 4 / 3,
  overlayBuilder: (context, details) => MyCropOverlay(details: details),
);

final result = await crop(
  CropRequest(input: input, region: editorController.region),
);
```

`requestBuilder` and `executor` are injectable on `FileImageCropperPage` for
advanced request construction, state-management integration, and testing.

`CropRequest.input` is always a `dart:io` `File`. An `image_picker` `XFile`
can be passed as `File(xFile.path)` without copying it. A `photo_manager`
`originFile` is already compatible. This package does not depend on either
picker package.

### Explicit output

```dart
final result = await crop(
  CropRequest(
    input: File('input.png'),
    output: File('exports/cropped.jpg'),
    overwrite: false,
    region: const CropRegion.normalized(
      left: 0.1,
      top: 0.1,
      width: 0.8,
      height: 0.8,
    ),
    outputFormat: OutputFormat.jpeg,
    jpegOptions: const JpegOptions(
      quality: 92,
      background: RgbColor.white,
    ),
  ),
);

assert(!result.isManaged);
```

The explicit output's parent directory must already exist. An existing output
is rejected unless `overwrite` is `true`.

### Crop coordinates and exact output size

An inspection call is not required before cropping. Choose the coordinate form
that matches the UI:

- `CropRegion.normalized` uses image-relative fractions from `0` to `1` and is
  normally the best representation for an interactive crop overlay.
- `CropRegion.centered` selects the largest centered area with the requested
  aspect ratio.
- `CropRegion.pixels` remains available when exact source pixels are already
  known.

All regions are resolved by Rust against the orientation-normalized image, so
EXIF rotations do not have to be reproduced in Dart. `outputSize` is the exact
physical pixel size of the encoded result. By default, a materially different
crop/output aspect ratio is rejected instead of silently distorting pixels.
Use `AspectMismatchPolicy.adjustCrop` to shrink the crop around its center, or
`AspectMismatchPolicy.stretch` only when distortion is intentional.

For a Flutter crop overlay, convert its viewport rectangle once and pass the
result directly:

```dart
final region = CropGeometry.fromViewport(
  imageSize: PixelSize(
    width: imageInfo.orientedWidth,
    height: imageInfo.orientedHeight,
  ),
  viewportSize: const ViewportSize(width: 360, height: 640),
  cropWindow: const ViewportRect(
    left: 30,
    top: 170,
    width: 300,
    height: 300,
  ),
  fit: ImageFit.contain,
  scale: currentZoom,
  offsetX: currentPan.dx,
  offsetY: currentPan.dy,
);

final result = await crop(
  CropRequest(
    input: inputFile,
    region: region,
    outputSize: const PixelSize(width: 1080, height: 1080),
    aspectMismatchPolicy: AspectMismatchPolicy.adjustCrop,
  ),
);
```

`CropRect`/`resize` request fields are retained as deprecated compatibility
aliases. Legacy resize requests keep their former stretching behavior.

### Inspect metadata without decoding pixels

```dart
final info = await inspectImage(File('photo.webp'));
print('${info.width} x ${info.height}, ${info.format}');
```

Inspection is useful for previews, validation, and mapping a concrete Flutter
viewport. It is not a prerequisite for normalized or centered crops.

### Temporary-file cleanup

When `output` is omitted, the package creates a managed result under
`Directory.systemTemp/file_image_cropper`. Delete a single managed result with
`CropResult.delete()`, or remove package-owned temporary files in bulk:

```dart
await clearTemporaryFiles(olderThan: const Duration(days: 1));
```

Cleanup only considers regular files with the package-owned prefix. It does
not follow links or remove unrelated files/directories. Calling `delete()` on
an explicit caller-owned output is a no-op and returns `false`.

## File lifecycle

Inputs are opened read-only and are never copied, changed, or deleted. Every
output is written to a unique staging file beside its final destination. The
engine flushes and syncs that file before committing it. Failed or abandoned
staging files are removed on a best-effort basis.

Managed final outputs and internal staging files are separate concepts:

- `fic_output_*` is a completed package-managed result owned by the caller
  until it is deleted.
- `fic_staging_*` is internal and must never be used as a result.

## Processing and performance

Long-running FFI work runs on one lazily started, persistent Dart worker
isolate. The native engine owns a bounded Rayon thread pool. Small images stay
single-threaded to avoid scheduling overhead; larger orientation, crop/resize,
and encoding workloads use disjoint row bands and codec-native threads.
Nested parallel sections fall back to sequential processing so thread counts
do not multiply unexpectedly.

The current engine:

- normalizes JPEG EXIF orientations 1 through 8 before applying crop
  coordinates;
- uses alpha-correct bilinear resize or nearest-neighbor resize;
- uses SIMD TurboJPEG encoding where supported;
- uses the zlib-rs PNG backend;
- enables libwebp's threaded static encoder;
- validates dimensions and allocation limits before allocating RGBA buffers.

## Filesystem structure

```text
lib/
|-- file_image_cropper.dart              # Public API
`-- src/
    |-- api/                              # API interface
    |-- ffi/                              # Native ABI adapter and worker isolate
    |-- filesystem/                       # Managed temporary-file policy
    |-- geometry/                         # Viewport-to-image coordinate mapping
    |-- widgets/                          # Optional editor and ready-made page
    |-- models/                           # Requests, results, and options
    `-- prebuilt/                         # Target map, download, SHA-256 check

hook/
`-- build.dart                            # Prebuilt-first native asset hook

.github/workflows/
`-- prebuilt-native.yml                   # Cross-platform binary release

native/src/
|-- ffi/                                  # Stable C ABI
|-- codecs/                               # JPEG, PNG, and WebP codecs
|-- pipeline/                             # File and pixel orchestration
|-- threading/                            # Bounded native parallelism
|-- filesystem/                           # Input, output, staging, cleanup
|-- crop.rs / resize.rs / rotate.rs
`-- error.rs                              # Structured native errors
```

The Rust core is intentionally structured around `Read + Seek` metadata input
so future file-descriptor adapters do not require coupling image parsing to a
filesystem path.

## Verification

The test suite covers real JPEG orientation fixtures, PNG and WebP fixtures,
format detection, malformed input, codec conversion, managed and explicit
outputs, no-clobber commits, cleanup ownership, sequential/parallel output
equivalence, crop-editor gestures, and UI customization builders.

The platform workflow runs Rust formatting/tests, Flutter analysis, widget and
FFI smoke tests, desktop Flutter builds on Windows/Linux/macOS, an Android emulator
runtime smoke, and iOS device/simulator builds with a simulator runtime smoke.
Applications should still validate performance and OS-version compatibility on
their own supported real devices before shipping to users.

Flutter is pinned in CI and Rust targets are pinned in
`native/rust-toolchain.toml`.

## License

MIT. See [LICENSE](LICENSE).
