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
