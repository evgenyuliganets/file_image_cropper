import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../api/file_image_cropper_api.dart';
import '../filesystem/managed_file_system.dart';
import '../heic/heic_detector.dart';
import '../heic/heic_platform_backend.dart';
import '../models/crop_region.dart';
import '../models/crop_request.dart';
import '../models/crop_result.dart';
import '../models/image_format.dart';
import '../models/image_info.dart';
import '../models/output_format.dart';

final class NativeImageInfoResult extends Struct {
  @Int32()
  external int status;

  @Uint32()
  external int reason;

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int format;

  @Uint8()
  external int orientation;

  @Array(3)
  external Array<Uint8> reserved;
}

@Native<
  NativeImageInfoResult Function(Pointer<Uint8> pathBytes, Size pathLength)
>(symbol: 'file_image_cropper_inspect_image')
external NativeImageInfoResult _inspectImageNative(
  Pointer<Uint8> pathBytes,
  int pathLength,
);

final class NativeCropResult extends Struct {
  @Int32()
  external int status;

  @Uint32()
  external int reason;

  @Size()
  external int pathLength;

  @Uint8()
  external int isManaged;

  @Array(7)
  external Array<Uint8> reserved;
}

final class NativeCropOptions extends Struct {
  @Uint32()
  external int regionType;

  @Uint32()
  external int aspectPolicy;

  @Double()
  external double regionA;

  @Double()
  external double regionB;

  @Double()
  external double regionC;

  @Double()
  external double regionD;

  @Uint32()
  external int outputWidth;

  @Uint32()
  external int outputHeight;

  @Uint32()
  external int resizeFilter;

  @Uint32()
  external int outputFormat;

  @Uint32()
  external int jpegQuality;

  @Uint32()
  external int jpegBackgroundRed;

  @Uint32()
  external int jpegBackgroundGreen;

  @Uint32()
  external int jpegBackgroundBlue;

  @Uint32()
  external int webpLossless;

  @Uint32()
  external int webpQuality;

  @Uint32()
  external int overwrite;
}

@Native<
  NativeCropResult Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<NativeCropOptions>,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'file_image_cropper_crop_image')
external NativeCropResult _cropImageNative(
  Pointer<Uint8> input,
  int inputLength,
  Pointer<Uint8> output,
  int outputLength,
  Pointer<Uint8> managedRoot,
  int managedRootLength,
  Pointer<NativeCropOptions> options,
  Pointer<Uint8> resultPath,
  int resultPathCapacity,
);

@Native<Uint32 Function()>(symbol: 'file_image_cropper_abi_version')
external int _nativeAbiVersion();

/// Ensures the bundled Rust code asset is loaded before a platform bridge
/// resolves the raw-RGBA symbol from the same native library.
void ensureNativeImageEngineLoaded() {
  final int version = _nativeAbiVersion();
  if (version < 3) {
    throw StateError('HEIC requires file_image_cropper native ABI 3 or newer.');
  }
}

final class NativeImageEngine implements FileImageCropperApi {
  const NativeImageEngine();

  @override
  Future<ImageInfo> inspectImage(File input) async {
    if (await isHeicFile(input)) {
      return const HeicPlatformBackend().inspect(input);
    }
    return _nativeWorker.execute<ImageInfo>(
      _WorkerOperation.inspect,
      input.path,
    );
  }

  @override
  Future<CropResult> crop(CropRequest request) async {
    _validateCropRequest(request);
    if (await isHeicFile(request.input)) {
      return const HeicPlatformBackend().crop(request);
    }
    return _nativeWorker.execute<CropResult>(_WorkerOperation.crop, request);
  }
}

final _NativeWorker _nativeWorker = _NativeWorker();

enum _WorkerOperation { inspect, crop }

final class _WorkerRequest {
  const _WorkerRequest(this.operation, this.payload, this.replyTo);

  final _WorkerOperation operation;
  final Object payload;
  final SendPort replyTo;
}

final class _WorkerResponse {
  const _WorkerResponse.success(this.result) : error = null, stackTrace = null;

  const _WorkerResponse.failure(this.error, this.stackTrace) : result = null;

  final Object? result;
  final Object? error;
  final StackTrace? stackTrace;
}

final class _NativeWorker {
  Future<SendPort>? _sendPort;

  Future<T> execute<T>(_WorkerOperation operation, Object payload) async {
    final SendPort sendPort = await (_sendPort ??= _start());
    final ReceivePort responsePort = ReceivePort();
    sendPort.send(_WorkerRequest(operation, payload, responsePort.sendPort));
    try {
      final _WorkerResponse response =
          await responsePort.first as _WorkerResponse;
      if (response.error case final Object error) {
        Error.throwWithStackTrace(
          error,
          response.stackTrace ?? StackTrace.empty,
        );
      }
      return response.result as T;
    } finally {
      responsePort.close();
    }
  }

  Future<SendPort> _start() async {
    final ReceivePort readyPort = ReceivePort();
    try {
      await Isolate.spawn(
        _nativeWorkerMain,
        readyPort.sendPort,
        debugName: 'file_image_cropper.worker',
        errorsAreFatal: true,
      );
      return await readyPort.first as SendPort;
    } catch (_) {
      _sendPort = null;
      rethrow;
    } finally {
      readyPort.close();
    }
  }
}

@pragma('vm:entry-point')
void _nativeWorkerMain(SendPort readyPort) {
  final ReceivePort requestPort = ReceivePort();
  readyPort.send(requestPort.sendPort);
  requestPort.listen((Object? message) {
    final _WorkerRequest request = message! as _WorkerRequest;
    try {
      final Object result = switch (request.operation) {
        _WorkerOperation.inspect => _inspectImagePath(
          request.payload as String,
        ),
        _WorkerOperation.crop => _cropImage(request.payload as CropRequest),
      };
      request.replyTo.send(_WorkerResponse.success(result));
    } catch (error, stackTrace) {
      request.replyTo.send(_WorkerResponse.failure(error, stackTrace));
    }
  });
}

const int _resultPathCapacity = 65536;

CropResult _cropImage(CropRequest request) {
  final Pointer<Utf8> input = request.input.path.toNativeUtf8();
  final Pointer<Utf8>? output = request.output?.path.toNativeUtf8();
  final Pointer<Utf8> managedRoot = ManagedFileSystem.root.path.toNativeUtf8();
  final Pointer<NativeCropOptions> options = calloc<NativeCropOptions>();
  final Pointer<Uint8> resultPath = malloc<Uint8>(_resultPathCapacity);
  try {
    final region = request.effectiveRegion;
    final outputSize = request.effectiveOutputSize;
    final background = request.jpegOptions.background;
    final NativeCropOptions nativeOptions = options.ref
      ..aspectPolicy = request.effectiveAspectMismatchPolicy.index
      ..outputWidth = outputSize?.width ?? 0
      ..outputHeight = outputSize?.height ?? 0
      ..resizeFilter = request.effectiveResizeFilter.index
      ..outputFormat = request.outputFormat.index
      ..jpegQuality = request.jpegOptions.quality
      ..jpegBackgroundRed = background.red
      ..jpegBackgroundGreen = background.green
      ..jpegBackgroundBlue = background.blue
      ..webpLossless = request.webpOptions.lossless ? 1 : 0
      ..webpQuality = request.webpOptions.quality
      ..overwrite = request.overwrite ? 1 : 0;
    switch (region) {
      case PixelCropRegion(:final x, :final y, :final width, :final height):
        nativeOptions
          ..regionType = 0
          ..regionA = x.toDouble()
          ..regionB = y.toDouble()
          ..regionC = width.toDouble()
          ..regionD = height.toDouble();
      case NormalizedCropRegion(
        :final left,
        :final top,
        :final width,
        :final height,
      ):
        nativeOptions
          ..regionType = 1
          ..regionA = left
          ..regionB = top
          ..regionC = width
          ..regionD = height;
      case CenteredCropRegion(:final aspectRatio):
        nativeOptions
          ..regionType = 2
          ..regionA = aspectRatio;
    }
    final NativeCropResult result = _cropImageNative(
      input.cast(),
      input.length,
      output?.cast() ?? nullptr,
      output?.length ?? 0,
      managedRoot.cast(),
      managedRoot.length,
      options,
      resultPath,
      _resultPathCapacity,
    );
    if (result.status != 0) {
      throw CropException(
        status: CropStatus.fromCode(result.status),
        reason: CropFailureReason.fromCode(result.reason),
        inputPath: request.input.path,
      );
    }
    final String path = utf8.decode(resultPath.asTypedList(result.pathLength));
    return CropResult(file: File(path), isManaged: result.isManaged != 0);
  } finally {
    malloc.free(input);
    if (output != null) malloc.free(output);
    malloc.free(managedRoot);
    calloc.free(options);
    malloc.free(resultPath);
  }
}

void _validateCropRequest(CropRequest request) {
  if (!request.hasExactlyOneRegion) {
    throw ArgumentError('exactly one of region or crop must be provided');
  }
  if (request.hasConflictingOutputSize) {
    throw ArgumentError('outputSize and resize are mutually exclusive');
  }
  const int maxNativeDimension = 0xffffffff;
  switch (request.effectiveRegion) {
    case PixelCropRegion(:final x, :final y, :final width, :final height):
      if (x < 0 ||
          y < 0 ||
          width <= 0 ||
          height <= 0 ||
          x > maxNativeDimension ||
          y > maxNativeDimension ||
          width > maxNativeDimension ||
          height > maxNativeDimension) {
        throw ArgumentError.value(
          request.effectiveRegion,
          'region',
          'pixel coordinates must fit unsigned 32-bit values',
        );
      }
    case NormalizedCropRegion(
      :final left,
      :final top,
      :final width,
      :final height,
    ):
      if (!left.isFinite ||
          !top.isFinite ||
          !width.isFinite ||
          !height.isFinite ||
          left < 0 ||
          top < 0 ||
          width <= 0 ||
          height <= 0 ||
          left + width > 1 ||
          top + height > 1) {
        throw ArgumentError.value(
          request.effectiveRegion,
          'region',
          'normalized coordinates must be finite and inside 0..1',
        );
      }
    case CenteredCropRegion(:final aspectRatio):
      if (!aspectRatio.isFinite || aspectRatio <= 0) {
        throw ArgumentError.value(
          aspectRatio,
          'region.aspectRatio',
          'must be finite and positive',
        );
      }
  }
  final outputSize = request.effectiveOutputSize;
  if (outputSize != null &&
      (outputSize.width <= 0 ||
          outputSize.height <= 0 ||
          outputSize.width > maxNativeDimension ||
          outputSize.height > maxNativeDimension)) {
    throw ArgumentError.value(
      outputSize,
      'outputSize',
      'dimensions must be positive unsigned 32-bit values',
    );
  }
  if (request.outputFormat == OutputFormat.jpeg) {
    final jpeg = request.jpegOptions;
    if (jpeg.quality < 1 || jpeg.quality > 100) {
      throw ArgumentError.value(
        jpeg.quality,
        'jpegOptions.quality',
        'must be 1..100',
      );
    }
    final background = jpeg.background;
    for (final (name, value) in <(String, int)>[
      ('red', background.red),
      ('green', background.green),
      ('blue', background.blue),
    ]) {
      if (value < 0 || value > 255) {
        throw ArgumentError.value(
          value,
          'jpegOptions.background.$name',
          'must be 0..255',
        );
      }
    }
  }
  if (request.outputFormat == OutputFormat.webp) {
    final quality = request.webpOptions.quality;
    if (quality < 0 || quality > 100) {
      throw ArgumentError.value(
        quality,
        'webpOptions.quality',
        'must be 0..100',
      );
    }
  }
}

enum CropStatus {
  invalidPath(1),
  input(2),
  unsupportedFormat(3),
  decode(4),
  invalidRequest(5),
  output(6),
  encode(7),
  resultPathTooLong(8),
  nativePanic(255),
  unknown(-1);

  const CropStatus(this.code);
  final int code;
  static CropStatus fromCode(int code) =>
      values.firstWhere((value) => value.code == code, orElse: () => unknown);
}

enum CropFailureReason {
  none(0),
  zeroDimensions(1),
  dimensionOverflow(2),
  bufferSizeMismatch(3),
  pixelLimitExceeded(4),
  allocationFailed(5),
  invalidCrop(6),
  invalidOrientation(7),
  invalidRowLayout(8),
  aspectMismatch(9),
  unknown(-1);

  const CropFailureReason(this.code);
  final int code;
  static CropFailureReason fromCode(int code) =>
      values.firstWhere((value) => value.code == code, orElse: () => unknown);
}

final class CropException implements Exception {
  const CropException({
    required this.status,
    required this.reason,
    required this.inputPath,
  });
  final CropStatus status;
  final CropFailureReason reason;
  final String inputPath;

  @override
  String toString() =>
      'CropException(${status.name}, ${reason.name}, $inputPath)';
}

ImageInfo _inspectImagePath(String path) {
  final Pointer<Utf8> nativePath = path.toNativeUtf8();
  try {
    final NativeImageInfoResult result = _inspectImageNative(
      nativePath.cast<Uint8>(),
      nativePath.length,
    );
    if (result.status != 0) {
      throw ImageInspectionException(
        status: ImageInspectionStatus.fromCode(result.status),
        reason: ImageInspectionReason.fromCode(result.reason),
        path: path,
      );
    }
    return ImageInfo(
      width: result.width,
      height: result.height,
      format: switch (result.format) {
        1 => ImageFormat.jpeg,
        2 => ImageFormat.png,
        3 => ImageFormat.webp,
        _ => throw StateError('Unknown native image format: ${result.format}'),
      },
      orientation: result.orientation,
    );
  } finally {
    malloc.free(nativePath);
  }
}

enum ImageInspectionStatus {
  invalidPathEncoding(1),
  inputNotFound(2),
  inputNotFile(3),
  unsupportedFormat(4),
  invalidImage(5),
  io(6),
  nativePanic(255),
  unknown(-1);

  const ImageInspectionStatus(this.code);
  final int code;

  static ImageInspectionStatus fromCode(int code) => values.firstWhere(
    (ImageInspectionStatus value) => value.code == code,
    orElse: () => unknown,
  );
}

enum ImageInspectionReason {
  none(0),
  truncated(1),
  invalidStructure(2),
  dimensionsMissing(3),
  zeroDimensions(4),
  animatedUnsupported(5),
  inspectionLimitExceeded(6),
  unknown(-1);

  const ImageInspectionReason(this.code);
  final int code;

  static ImageInspectionReason fromCode(int code) => values.firstWhere(
    (ImageInspectionReason value) => value.code == code,
    orElse: () => unknown,
  );
}

final class ImageInspectionException implements Exception {
  const ImageInspectionException({
    required this.status,
    required this.reason,
    required this.path,
  });

  final ImageInspectionStatus status;
  final ImageInspectionReason reason;
  final String path;

  @override
  String toString() =>
      'ImageInspectionException(${status.name}, ${reason.name}, $path)';
}
