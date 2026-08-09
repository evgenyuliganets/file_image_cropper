import 'dart:io';

import 'crop_rect.dart';
import 'crop_region.dart';
import 'jpeg_options.dart';
import 'output_format.dart';
import 'pixel_size.dart';
import 'resize_options.dart';
import 'webp_options.dart';

/// Complete input, crop, resize, encoding, and output configuration.
final class CropRequest {
  /// Creates a crop request with exactly one current or legacy crop region.
  const CropRequest({
    required this.input,
    this.region,
    @Deprecated('Use region: CropRegion.pixels(...) instead.') this.crop,
    this.output,
    this.overwrite = false,
    this.outputSize,
    this.resizeFilter = ResizeFilter.bilinear,
    this.aspectMismatchPolicy = AspectMismatchPolicy.reject,
    @Deprecated('Use outputSize and resizeFilter instead.') this.resize,
    this.outputFormat = OutputFormat.png,
    this.jpegOptions = const JpegOptions(),
    this.webpOptions = const WebpOptions(),
  }) : assert(region != null || crop != null, 'region or crop is required'),
       assert(region == null || crop == null, 'region and crop are exclusive'),
       assert(
         outputSize == null || resize == null,
         'outputSize and resize are exclusive',
       );

  /// Read-only source image file.
  final File input;

  /// Region selected against the orientation-normalized source image.
  final CropRegion? region;

  /// Legacy exact-pixel crop rectangle.
  @Deprecated('Use region instead.')
  final CropRect? crop;

  /// Optional caller-owned destination; omitted for a managed result.
  final File? output;

  /// Whether an existing explicit [output] may be replaced.
  final bool overwrite;

  /// Exact encoded dimensions, or `null` to retain crop dimensions.
  final PixelSize? outputSize;

  /// Pixel resampling algorithm used when [outputSize] is supplied.
  final ResizeFilter resizeFilter;

  /// Policy for reconciling crop and output aspect ratios.
  final AspectMismatchPolicy aspectMismatchPolicy;

  /// Legacy exact resize configuration.
  @Deprecated('Use outputSize and resizeFilter instead.')
  final ResizeOptions? resize;

  /// Encoded result format.
  final OutputFormat outputFormat;

  /// JPEG-specific encoding configuration.
  final JpegOptions jpegOptions;

  /// WebP-specific encoding configuration.
  final WebpOptions webpOptions;

  /// Whether the request contains exactly one current or legacy crop region.
  bool get hasExactlyOneRegion => (region == null) != (crop == null);

  /// Whether current and legacy resize fields were both supplied.
  bool get hasConflictingOutputSize => outputSize != null && resize != null;

  /// Region after resolving the legacy [crop] alias.
  CropRegion get effectiveRegion {
    final CropRegion? requested = region;
    if (requested != null) return requested;
    final CropRect legacy = crop!;
    return PixelCropRegion(
      x: legacy.x,
      y: legacy.y,
      width: legacy.width,
      height: legacy.height,
    );
  }

  /// Output dimensions after resolving the legacy [resize] alias.
  PixelSize? get effectiveOutputSize {
    final PixelSize? requested = outputSize;
    if (requested != null) return requested;
    final ResizeOptions? legacy = resize;
    return legacy == null
        ? null
        : PixelSize(width: legacy.width, height: legacy.height);
  }

  /// Resize filter after resolving legacy configuration.
  ResizeFilter get effectiveResizeFilter => resize?.filter ?? resizeFilter;

  /// Aspect policy after applying legacy resize compatibility behavior.
  AspectMismatchPolicy get effectiveAspectMismatchPolicy =>
      resize != null && outputSize == null
      ? AspectMismatchPolicy.stretch
      : aspectMismatchPolicy;
}
