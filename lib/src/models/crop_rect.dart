/// Legacy exact-pixel crop rectangle.
///
/// Prefer `CropRegion.pixels(...)` in new code.
final class CropRect {
  /// Creates an exact-pixel crop rectangle.
  const CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Horizontal offset from the oriented image's left edge.
  final int x;

  /// Vertical offset from the oriented image's top edge.
  final int y;

  /// Width of the selected source area in pixels.
  final int width;

  /// Height of the selected source area in pixels.
  final int height;
}
