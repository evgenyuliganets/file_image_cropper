## 0.3.5

- Kept crop handles fully visible over editor padding while preserving the
  same padded image bounds and crop interaction geometry.

## 0.3.4

- Added safe default crop-editor padding, including Android system gesture
  insets, and increased drag-handle touch targets to 48 logical pixels.

## 0.3.3

- Added explicit 16 KB ELF page alignment for the Android HEIC bridge so the
  plugin is compatible with 16 KB page-size devices even when built with older
  Android NDK toolchains.

## 0.3.2

- Added Swift Package Manager support for the shared iOS and macOS plugin while
  retaining CocoaPods compatibility.
- Expanded dartdoc coverage across crop requests, regions, output options, and
  editor styling APIs.
- Updated the native-assets build dependencies to their newest versions
  compatible with the minimum supported Flutter release.

## 0.3.1

- Reorganized and simplified the README around installation, interactive and
  code-driven cropping, output configuration, customization, and file
  lifecycle.
- Added clearer guidance for free-form selection, fixed aspect ratios, exact
  output dimensions, and format-specific encoding options.

## 0.3.0

- Added static HEIC input and inspection on Android 9+, iOS, macOS, Windows,
  and Linux. Windows uses an installed WIC HEIF/HEVC decoder; Linux dynamically
  uses an installed `libheif` runtime with an HEVC decoder.
- Added a direct borrowed-RGBA native ABI, keeping decoded pixels out of Dart
  and avoiding intermediate PNG files before Rust crop/resize/encode.
- Added structured `HeicCodecUnavailableException` guidance with Microsoft
  HEIF Image Extensions and libheif links when an optional desktop codec is
  unavailable.
- HEIC output, animated HEIF, AVIF, TIFF, and RAW remain unsupported.

## 0.2.0

- Added verified prebuilt Rust libraries for Android, iOS, Linux, macOS, and
  Windows so application builds no longer require Rust by default.
- Added SHA-256 validation, shared build-cache reuse, bounded downloads, and
  atomic replacement for downloaded native assets.
- Added an explicit source-build fallback and a custom native-library override
  for development and controlled build environments.
- Removed the unused C package template and its generated bindings from the
  build pipeline.

## 0.1.0

- Added file-first JPEG, PNG, and static WebP inspection and processing.
- Added crop, EXIF orientation normalization, nearest/bilinear resize, and
  JPEG/PNG/WebP conversion.
- Added pixel, normalized, and centered crop regions, exact output pixel sizes,
  aspect-ratio policies, and viewport geometry helpers. The original pixel
  crop/resize request fields remain available as deprecated compatibility APIs.
- Added an optional interactive `CropEditor`, customizable overlay/controller,
  and a ready-made `FileImageCropperPage` with replaceable app bar, body,
  controls, actions, loading, error, and processing UI.
- Added configurable JPEG quality/background and lossy/lossless WebP options.
- Added a persistent Dart worker isolate and bounded multithreaded Rust pixel
  processing.
- Added atomic staged output commits, managed temporary results, safe cleanup,
  and explicit no-overwrite behavior, including native no-replace renames on
  Android, Linux, iOS, and macOS.
- Added structured Dart and Rust errors and cross-platform native build checks.
- Declared Android, iOS, Windows, macOS, and Linux support. Web, animated
  formats, HEIC/HEIF, AVIF, TIFF, and RAW are not supported in this release.
