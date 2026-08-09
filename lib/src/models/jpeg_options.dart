/// An 8-bit RGB color used to flatten transparency for JPEG output.
final class RgbColor {
  /// Creates an RGB color from channels in the range `0..255`.
  const RgbColor(this.red, this.green, this.blue);

  /// Opaque white.
  static const RgbColor white = RgbColor(255, 255, 255);

  /// Red channel in the range `0..255`.
  final int red;

  /// Green channel in the range `0..255`.
  final int green;

  /// Blue channel in the range `0..255`.
  final int blue;
}

/// JPEG encoding configuration.
final class JpegOptions {
  /// Creates JPEG options with quality `1..100` and a transparency background.
  const JpegOptions({this.quality = 90, this.background = RgbColor.white});

  /// Lossy JPEG quality in the range `1..100`.
  final int quality;

  /// Color composited behind transparent input pixels.
  final RgbColor background;
}
