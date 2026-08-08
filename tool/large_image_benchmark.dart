import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/large_image_benchmark.dart <directory>',
    );
    exitCode = 64;
    return;
  }

  final Directory root = Directory(arguments.single);
  final Directory outputs = Directory(
    '${root.path}${Platform.pathSeparator}outputs',
  );
  await outputs.create(recursive: true);

  final List<File> inputs = <File>[
    File('${root.path}${Platform.pathSeparator}photo_12mp.jpg'),
    File('${root.path}${Platform.pathSeparator}photo_24mp.jpg'),
    File('${root.path}${Platform.pathSeparator}photo_46mp.jpg'),
  ];

  stdout.writeln('Full-image resize to 1920 px, JPEG quality 90:');
  for (final File input in inputs) {
    final ImageInfo info = await inspectImage(input);
    final (int width, int height) = _fitLongEdge(info, 1920);
    await _benchmark(
      label: '${_megapixels(info)} MP ${info.width}x${info.height}',
      input: input,
      inputInfo: info,
      output: File(
        '${outputs.path}${Platform.pathSeparator}'
        '${_stem(input)}_1920.jpg',
      ),
      outputSize: PixelSize(width: width, height: height),
      outputFormat: OutputFormat.jpeg,
    );
  }

  final File codecInput = inputs[1];
  final ImageInfo codecInfo = await inspectImage(codecInput);
  final (int codecWidth, int codecHeight) = _fitLongEdge(codecInfo, 1920);
  stdout.writeln('\n24 MP codec comparison at ${codecWidth}x$codecHeight:');
  await _benchmark(
    label: 'WebP quality 80',
    input: codecInput,
    inputInfo: codecInfo,
    output: File('${outputs.path}${Platform.pathSeparator}codec.webp'),
    outputSize: PixelSize(width: codecWidth, height: codecHeight),
    outputFormat: OutputFormat.webp,
  );
  await _benchmark(
    label: 'PNG lossless',
    input: codecInput,
    inputInfo: codecInfo,
    output: File('${outputs.path}${Platform.pathSeparator}codec.png'),
    outputSize: PixelSize(width: codecWidth, height: codecHeight),
    outputFormat: OutputFormat.png,
  );

  stdout.writeln('\nLarge 12 MP center crop without resize:');
  await _benchmark(
    label: '4000x3000 -> JPEG quality 90',
    input: codecInput,
    inputInfo: codecInfo,
    output: File('${outputs.path}${Platform.pathSeparator}crop_12mp.jpg'),
    region: const CropRegion.pixels(x: 1000, y: 500, width: 4000, height: 3000),
    outputFormat: OutputFormat.jpeg,
  );
}

Future<void> _benchmark({
  required String label,
  required File input,
  required ImageInfo inputInfo,
  required File output,
  required OutputFormat outputFormat,
  CropRegion? region,
  PixelSize? outputSize,
}) async {
  final CropRegion effectiveRegion =
      region ??
      const CropRegion.normalized(left: 0, top: 0, width: 1, height: 1);
  final Stopwatch timer = Stopwatch()..start();
  final CropResult result = await crop(
    CropRequest(
      input: input,
      output: output,
      overwrite: true,
      region: effectiveRegion,
      outputSize: outputSize,
      aspectMismatchPolicy: AspectMismatchPolicy.adjustCrop,
      outputFormat: outputFormat,
      jpegOptions: const JpegOptions(quality: 90),
      webpOptions: const WebpOptions(quality: 80),
    ),
  );
  timer.stop();

  final ImageInfo outputInfo = await inspectImage(result.file);
  final int expectedWidth =
      outputSize?.width ?? (effectiveRegion as PixelCropRegion).width;
  final int expectedHeight =
      outputSize?.height ?? (effectiveRegion as PixelCropRegion).height;
  if (outputInfo.width != expectedWidth ||
      outputInfo.height != expectedHeight) {
    throw StateError(
      '$label produced ${outputInfo.width}x${outputInfo.height}, '
      'expected ${expectedWidth}x$expectedHeight',
    );
  }
  stdout.writeln(
    '$label: ${_milliseconds(timer)} ms, '
    '${(await output.length() / (1024 * 1024)).toStringAsFixed(2)} MiB',
  );
}

(int, int) _fitLongEdge(ImageInfo info, int longEdge) {
  if (info.width >= info.height) {
    return (longEdge, (info.height * longEdge / info.width).round());
  }
  return ((info.width * longEdge / info.height).round(), longEdge);
}

String _stem(File file) {
  final String name = file.uri.pathSegments.last;
  final int dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

String _megapixels(ImageInfo info) =>
    (info.width * info.height / 1000000).toStringAsFixed(1);

String _milliseconds(Stopwatch stopwatch) =>
    (stopwatch.elapsedMicroseconds / 1000).toStringAsFixed(2);
