/// An exact physical pixel size.
final class PixelSize {
  const PixelSize({required this.width, required this.height});

  final int width;
  final int height;

  double get aspectRatio => width / height;
}
