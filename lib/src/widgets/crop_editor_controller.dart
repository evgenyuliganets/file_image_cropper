import 'package:flutter/foundation.dart';

import '../models/crop_region.dart';

/// Controls and observes the currently selected normalized crop region.
final class CropEditorController extends ChangeNotifier {
  CropEditorController({
    NormalizedCropRegion initialRegion = const NormalizedCropRegion(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
    ),
  }) : _resetRegion = initialRegion,
       _region = initialRegion {
    _validate(initialRegion);
  }

  NormalizedCropRegion _resetRegion;
  NormalizedCropRegion _region;

  NormalizedCropRegion get region => _region;

  /// Updates the selection. Values are relative to the oriented image.
  void setRegion(NormalizedCropRegion region) {
    _validate(region);
    if (_sameRegion(_region, region)) return;
    _region = region;
    notifyListeners();
  }

  /// Changes the region restored by [reset], optionally applying it now.
  void setResetRegion(NormalizedCropRegion region, {bool apply = true}) {
    _validate(region);
    _resetRegion = region;
    if (apply) setRegion(region);
  }

  /// Restores the configured reset region.
  void reset() => setRegion(_resetRegion);

  static void _validate(NormalizedCropRegion region) {
    final List<double> values = <double>[
      region.left,
      region.top,
      region.width,
      region.height,
    ];
    if (values.any((double value) => !value.isFinite) ||
        region.left < 0 ||
        region.top < 0 ||
        region.width <= 0 ||
        region.height <= 0 ||
        region.left + region.width > 1 ||
        region.top + region.height > 1) {
      throw ArgumentError.value(
        region,
        'region',
        'must be finite, positive, and contained inside 0..1',
      );
    }
  }

  static bool _sameRegion(
    NormalizedCropRegion left,
    NormalizedCropRegion right,
  ) =>
      left.left == right.left &&
      left.top == right.top &&
      left.width == right.width &&
      left.height == right.height;
}
