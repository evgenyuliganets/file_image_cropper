final class RgbColor {
  const RgbColor(this.red, this.green, this.blue);

  static const RgbColor white = RgbColor(255, 255, 255);

  final int red;
  final int green;
  final int blue;
}

final class JpegOptions {
  const JpegOptions({this.quality = 90, this.background = RgbColor.white});

  final int quality;
  final RgbColor background;
}
