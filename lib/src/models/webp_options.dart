/// Static WebP encoding configuration.
final class WebpOptions {
  /// Creates WebP options for lossy or lossless encoding.
  const WebpOptions({this.lossless = false, this.quality = 80});

  /// Whether to preserve pixels losslessly.
  final bool lossless;

  /// Quality in the range 0..100. In lossless mode this changes compression
  /// effort, not pixel fidelity.
  final int quality;
}
