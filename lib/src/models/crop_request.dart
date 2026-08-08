import 'dart:io';

import 'crop_rect.dart';
import 'crop_region.dart';
import 'jpeg_options.dart';
import 'output_format.dart';
import 'pixel_size.dart';
import 'resize_options.dart';
import 'webp_options.dart';

final class CropRequest {
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

  final File input;
  final CropRegion? region;

  @Deprecated('Use region instead.')
  final CropRect? crop;
  final File? output;
  final bool overwrite;
  final PixelSize? outputSize;
  final ResizeFilter resizeFilter;
  final AspectMismatchPolicy aspectMismatchPolicy;

  @Deprecated('Use outputSize and resizeFilter instead.')
  final ResizeOptions? resize;
  final OutputFormat outputFormat;
  final JpegOptions jpegOptions;
  final WebpOptions webpOptions;

  bool get hasExactlyOneRegion => (region == null) != (crop == null);

  bool get hasConflictingOutputSize => outputSize != null && resize != null;

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

  PixelSize? get effectiveOutputSize {
    final PixelSize? requested = outputSize;
    if (requested != null) return requested;
    final ResizeOptions? legacy = resize;
    return legacy == null
        ? null
        : PixelSize(width: legacy.width, height: legacy.height);
  }

  ResizeFilter get effectiveResizeFilter => resize?.filter ?? resizeFilter;

  AspectMismatchPolicy get effectiveAspectMismatchPolicy =>
      resize != null && outputSize == null
      ? AspectMismatchPolicy.stretch
      : aspectMismatchPolicy;
}
