final class WebpOptions {
  const WebpOptions({this.lossless = false, this.quality = 80});

  final bool lossless;

  /// Quality in the range 0..100. In lossless mode this changes compression
  /// effort, not pixel fidelity.
  final int quality;
}
