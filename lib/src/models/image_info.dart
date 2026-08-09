import 'image_format.dart';

/// Metadata read from an image without a full pixel decode.
final class ImageInfo {
  /// Creates inspected source metadata.
  const ImageInfo({
    required this.width,
    required this.height,
    required this.format,
    required this.orientation,
  });

  /// Stored image width before EXIF orientation normalization.
  final int width;

  /// Stored image height before EXIF orientation normalization.
  final int height;

  /// Detected source format.
  final ImageFormat format;

  /// EXIF orientation value, or `1` when no transformation is needed.
  final int orientation;

  /// Width after normalizing the EXIF orientation.
  int get orientedWidth =>
      orientation >= 5 && orientation <= 8 ? height : width;

  /// Height after normalizing the EXIF orientation.
  int get orientedHeight =>
      orientation >= 5 && orientation <= 8 ? width : height;
}
