import 'dart:io';

import 'src/filesystem/managed_file_system.dart';
import 'src/ffi/native_image_engine.dart';
import 'src/models/crop_request.dart';
import 'src/models/crop_result.dart';
import 'src/models/image_info.dart';

export 'src/api/file_image_cropper_api.dart';
export 'src/geometry/crop_geometry.dart';
export 'src/ffi/native_image_engine.dart'
    show
        CropException,
        CropFailureReason,
        CropStatus,
        ImageInspectionException,
        ImageInspectionReason,
        ImageInspectionStatus,
        NativeImageEngine;
export 'src/models/crop_rect.dart';
export 'src/models/crop_region.dart';
export 'src/models/crop_request.dart';
export 'src/models/crop_result.dart';
export 'src/models/image_format.dart';
export 'src/models/image_info.dart';
export 'src/models/jpeg_options.dart';
export 'src/models/output_format.dart';
export 'src/models/pixel_size.dart';
export 'src/models/resize_options.dart';
export 'src/models/webp_options.dart';
export 'src/widgets/crop_editor.dart';
export 'src/widgets/crop_editor_controller.dart';
export 'src/widgets/crop_overlay_style.dart';
export 'src/widgets/file_image_cropper_page.dart';

/// Reads image metadata in a worker isolate without decoding pixel data.
Future<ImageInfo> inspectImage(File input) =>
    const NativeImageEngine().inspectImage(input);

/// Crops a supported file input and atomically commits the encoded result.
Future<CropResult> crop(CropRequest request) =>
    const NativeImageEngine().crop(request);

/// Removes package-owned temporary files and leaves unrelated entries intact.
Future<void> clearTemporaryFiles({Duration? olderThan}) async {
  await ManagedFileSystem.clear(olderThan: olderThan);
}
