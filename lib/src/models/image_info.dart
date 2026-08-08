import 'image_format.dart';

/// Metadata read from an image without a full pixel decode.
final class ImageInfo {
  const ImageInfo({
    required this.width,
    required this.height,
    required this.format,
    required this.orientation,
  });

  final int width;
  final int height;
  final ImageFormat format;
  final int orientation;

  /// Width after normalizing the EXIF orientation.
  int get orientedWidth =>
      orientation >= 5 && orientation <= 8 ? height : width;

  /// Height after normalizing the EXIF orientation.
  int get orientedHeight =>
      orientation >= 5 && orientation <= 8 ? width : height;
}
