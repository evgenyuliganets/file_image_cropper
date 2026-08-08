import '../models/crop_region.dart';
import '../models/pixel_size.dart';

enum ImageFit { contain, cover }

final class ViewportSize {
  const ViewportSize({required this.width, required this.height});

  final double width;
  final double height;
}

final class ViewportRect {
  const ViewportRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Converts a crop overlay into image-relative coordinates without depending
/// on Flutter painting types.
abstract final class CropGeometry {
  static NormalizedCropRegion fromViewport({
    required PixelSize imageSize,
    required ViewportSize viewportSize,
    required ViewportRect cropWindow,
    ImageFit fit = ImageFit.contain,
    double scale = 1,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    _requirePositive(imageSize.width.toDouble(), 'imageSize.width');
    _requirePositive(imageSize.height.toDouble(), 'imageSize.height');
    _requirePositive(viewportSize.width, 'viewportSize.width');
    _requirePositive(viewportSize.height, 'viewportSize.height');
    _requirePositive(cropWindow.width, 'cropWindow.width');
    _requirePositive(cropWindow.height, 'cropWindow.height');
    _requirePositive(scale, 'scale');
    if (!offsetX.isFinite || !offsetY.isFinite) {
      throw ArgumentError('viewport offsets must be finite');
    }

    final double widthScale = viewportSize.width / imageSize.width;
    final double heightScale = viewportSize.height / imageSize.height;
    final double fittedScale = switch (fit) {
      ImageFit.contain => widthScale < heightScale ? widthScale : heightScale,
      ImageFit.cover => widthScale > heightScale ? widthScale : heightScale,
    };
    final double displayedWidth = imageSize.width * fittedScale * scale;
    final double displayedHeight = imageSize.height * fittedScale * scale;
    final double imageLeft =
        (viewportSize.width - displayedWidth) / 2 + offsetX;
    final double imageTop =
        (viewportSize.height - displayedHeight) / 2 + offsetY;

    final double left = (cropWindow.left - imageLeft) / displayedWidth;
    final double top = (cropWindow.top - imageTop) / displayedHeight;
    final double width = cropWindow.width / displayedWidth;
    final double height = cropWindow.height / displayedHeight;
    const double epsilon = 1e-9;
    if (left < -epsilon ||
        top < -epsilon ||
        left + width > 1 + epsilon ||
        top + height > 1 + epsilon) {
      throw RangeError('cropWindow extends outside the displayed image');
    }
    final double normalizedLeft = left.clamp(0, 1).toDouble();
    final double normalizedTop = top.clamp(0, 1).toDouble();
    final double normalizedRight = (left + width).clamp(0, 1).toDouble();
    final double normalizedBottom = (top + height).clamp(0, 1).toDouble();
    return NormalizedCropRegion(
      left: normalizedLeft,
      top: normalizedTop,
      width: normalizedRight - normalizedLeft,
      height: normalizedBottom - normalizedTop,
    );
  }

  static void _requirePositive(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'must be finite and positive');
    }
  }
}
