import 'dart:io';

import 'package:flutter/services.dart';

import '../filesystem/managed_file_system.dart';
import '../ffi/native_image_engine.dart' show ensureNativeImageEngineLoaded;
import '../models/crop_region.dart';
import '../models/crop_request.dart';
import '../models/crop_result.dart';
import '../models/image_format.dart';
import '../models/image_info.dart';

const String _windowsHeifExtensions =
    'https://apps.microsoft.com/detail/9pmmsr1cgpwg';
const String _linuxLibheif = 'https://github.com/strukturag/libheif';

final class HeicCodecUnavailableException implements Exception {
  const HeicCodecUnavailableException({
    required this.platform,
    required this.message,
    required this.helpUri,
  });

  final String platform;
  final String message;
  final Uri helpUri;

  @override
  String toString() =>
      'HeicCodecUnavailableException($platform): $message ($helpUri)';
}

final class HeicPlatformException implements Exception {
  const HeicPlatformException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'HeicPlatformException($code): $message';
}

final class HeicPlatformBackend {
  const HeicPlatformBackend();

  static const MethodChannel _channel = MethodChannel(
    'file_image_cropper/heic',
  );

  Future<ImageInfo> inspect(File input) async {
    _ensureSupportedPlatform();
    final Map<Object?, Object?> response = await _invoke(
      'inspectHeic',
      <String, Object?>{'inputPath': input.path},
    );
    return ImageInfo(
      width: response['width']! as int,
      height: response['height']! as int,
      format: ImageFormat.heic,
      orientation: 1,
    );
  }

  Future<CropResult> crop(CropRequest request) async {
    _ensureSupportedPlatform();
    final CropRegion region = request.effectiveRegion;
    final outputSize = request.effectiveOutputSize;
    final background = request.jpegOptions.background;
    final Map<String, Object?> arguments = <String, Object?>{
      'inputPath': request.input.path,
      'outputPath': request.output?.path,
      'managedRoot': ManagedFileSystem.root.path,
      'overwrite': request.overwrite,
      'regionType': switch (region) {
        PixelCropRegion() => 0,
        NormalizedCropRegion() => 1,
        CenteredCropRegion() => 2,
      },
      'regionA': switch (region) {
        PixelCropRegion(:final x) => x.toDouble(),
        NormalizedCropRegion(:final left) => left,
        CenteredCropRegion(:final aspectRatio) => aspectRatio,
      },
      'regionB': switch (region) {
        PixelCropRegion(:final y) => y.toDouble(),
        NormalizedCropRegion(:final top) => top,
        CenteredCropRegion() => 0.0,
      },
      'regionC': switch (region) {
        PixelCropRegion(:final width) => width.toDouble(),
        NormalizedCropRegion(:final width) => width,
        CenteredCropRegion() => 0.0,
      },
      'regionD': switch (region) {
        PixelCropRegion(:final height) => height.toDouble(),
        NormalizedCropRegion(:final height) => height,
        CenteredCropRegion() => 0.0,
      },
      'outputWidth': outputSize?.width ?? 0,
      'outputHeight': outputSize?.height ?? 0,
      'resizeFilter': request.effectiveResizeFilter.index,
      'aspectPolicy': request.effectiveAspectMismatchPolicy.index,
      'outputFormat': request.outputFormat.index,
      'jpegQuality': request.jpegOptions.quality,
      'jpegBackgroundRed': background.red,
      'jpegBackgroundGreen': background.green,
      'jpegBackgroundBlue': background.blue,
      'webpLossless': request.webpOptions.lossless,
      'webpQuality': request.webpOptions.quality,
    };
    final Map<Object?, Object?> response = await _invoke('cropHeic', arguments);
    return CropResult(
      file: File(response['path']! as String),
      isManaged: response['isManaged']! as bool,
    );
  }

  Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      ensureNativeImageEngineLoaded();
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>(method, arguments);
      if (result == null) {
        throw const HeicPlatformException(
          code: 'empty_response',
          message: 'The platform HEIC decoder returned no result.',
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw HeicPlatformException(
        code: error.code,
        message: error.message ?? 'Platform HEIC operation failed.',
        details: error.details,
      );
    } on MissingPluginException {
      throw const HeicPlatformException(
        code: 'plugin_unavailable',
        message: 'The HEIC platform bridge is unavailable in this build.',
      );
    }
  }

  void _ensureSupportedPlatform() {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return;
    if (Platform.isWindows) {
      throw HeicCodecUnavailableException(
        platform: 'windows',
        message:
            'HEIC input is not decoded by file_image_cropper on Windows yet. '
            'Install Microsoft HEIF Image Extensions to view or convert it, '
            'then pass JPEG, PNG, or WebP to the package.',
        helpUri: Uri.parse(_windowsHeifExtensions),
      );
    }
    if (Platform.isLinux) {
      throw HeicCodecUnavailableException(
        platform: 'linux',
        message:
            'HEIC input is not decoded by file_image_cropper on Linux yet. '
            'Install a distribution package based on libheif to convert it, '
            'then pass JPEG, PNG, or WebP to the package.',
        helpUri: Uri.parse(_linuxLibheif),
      );
    }
    throw HeicCodecUnavailableException(
      platform: Platform.operatingSystem,
      message: 'HEIC input is unavailable on this platform.',
      helpUri: Uri.parse(_linuxLibheif),
    );
  }
}
