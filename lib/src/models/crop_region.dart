/// Selects a crop relative to the orientation-normalized image.
sealed class CropRegion {
  const CropRegion();

  /// Uses exact physical pixel coordinates.
  const factory CropRegion.pixels({
    required int x,
    required int y,
    required int width,
    required int height,
  }) = PixelCropRegion;

  /// Uses fractions in the inclusive image coordinate space `0..1`.
  const factory CropRegion.normalized({
    required double left,
    required double top,
    required double width,
    required double height,
  }) = NormalizedCropRegion;

  /// Selects the largest centered region with [aspectRatio].
  const factory CropRegion.centered({required double aspectRatio}) =
      CenteredCropRegion;
}

/// An exact crop in orientation-normalized source pixels.
final class PixelCropRegion extends CropRegion {
  /// Creates an exact source-pixel crop.
  const PixelCropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Horizontal offset from the oriented image's left edge.
  final int x;

  /// Vertical offset from the oriented image's top edge.
  final int y;

  /// Selected width in source pixels.
  final int width;

  /// Selected height in source pixels.
  final int height;
}

/// A crop expressed as fractions of the orientation-normalized image.
final class NormalizedCropRegion extends CropRegion {
  /// Creates a normalized crop contained inside the `0..1` image space.
  const NormalizedCropRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Fractional offset from the oriented image's left edge.
  final double left;

  /// Fractional offset from the oriented image's top edge.
  final double top;

  /// Fractional width relative to the oriented image.
  final double width;

  /// Fractional height relative to the oriented image.
  final double height;
}

/// The largest centered crop with a requested aspect ratio.
final class CenteredCropRegion extends CropRegion {
  /// Creates a centered crop with [aspectRatio].
  const CenteredCropRegion({required this.aspectRatio});

  /// Requested width divided by height.
  final double aspectRatio;
}

/// Controls how a crop is reconciled with an exact output aspect ratio.
enum AspectMismatchPolicy {
  /// Rejects materially different aspect ratios instead of distorting pixels.
  reject,

  /// Shrinks the crop around its center to match the output aspect ratio.
  adjustCrop,

  /// Keeps the crop unchanged and stretches it to the exact output size.
  stretch,
}
