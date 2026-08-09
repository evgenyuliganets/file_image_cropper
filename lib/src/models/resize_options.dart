/// Pixel resampling algorithms available during resize.
enum ResizeFilter {
  /// Nearest-neighbor sampling, useful for hard-edged pixel art.
  nearest,

  /// Alpha-correct bilinear sampling for photographic content.
  bilinear,
}

/// Legacy resize configuration retained for API compatibility.
final class ResizeOptions {
  /// Creates a legacy resize request.
  const ResizeOptions({
    required this.width,
    required this.height,
    this.filter = ResizeFilter.bilinear,
  });

  /// Exact output width in pixels.
  final int width;

  /// Exact output height in pixels.
  final int height;

  /// Resampling algorithm.
  final ResizeFilter filter;
}
