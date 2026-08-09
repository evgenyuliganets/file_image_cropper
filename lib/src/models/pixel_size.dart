/// An exact physical pixel size.
final class PixelSize {
  /// Creates an exact positive output size.
  const PixelSize({required this.width, required this.height});

  /// Width in physical pixels.
  final int width;

  /// Height in physical pixels.
  final int height;

  /// Width divided by height.
  double get aspectRatio => width / height;
}
