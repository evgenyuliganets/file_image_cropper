enum ResizeFilter { nearest, bilinear }

final class ResizeOptions {
  const ResizeOptions({
    required this.width,
    required this.height,
    this.filter = ResizeFilter.bilinear,
  });

  final int width;
  final int height;
  final ResizeFilter filter;
}
