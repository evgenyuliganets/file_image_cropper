import 'dart:io';

import '../models/crop_request.dart';
import '../models/crop_result.dart';
import '../models/image_info.dart';

/// Public file-first image processing API.
abstract interface class FileImageCropperApi {
  /// Reads dimensions, detected format, and orientation without decoding the
  /// complete pixel buffer.
  Future<ImageInfo> inspectImage(File input);

  /// Crops, optionally resizes, and encodes a file through the native engine.
  Future<CropResult> crop(CropRequest request);
}
