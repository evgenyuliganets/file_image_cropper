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

final class PixelCropRegion extends CropRegion {
  const PixelCropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

final class NormalizedCropRegion extends CropRegion {
  const NormalizedCropRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

final class CenteredCropRegion extends CropRegion {
  const CenteredCropRegion({required this.aspectRatio});

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
