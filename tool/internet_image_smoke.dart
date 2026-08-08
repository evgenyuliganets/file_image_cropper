import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/internet_image_smoke.dart <directory>',
    );
    exitCode = 64;
    return;
  }

  final Directory directory = Directory(arguments.single);
  final Directory outputDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}outputs',
  );
  await outputDirectory.create(recursive: true);

  final List<_SmokeCase> cases = <_SmokeCase>[
    _SmokeCase('flower.jpg', 'flower.webp', OutputFormat.webp),
    _SmokeCase('example.png', 'example.jpg', OutputFormat.jpeg),
    _SmokeCase('gallery.webp', 'gallery.png', OutputFormat.png),
  ];

  for (final _SmokeCase smokeCase in cases) {
    final File input = File(
      '${directory.path}${Platform.pathSeparator}${smokeCase.inputName}',
    );
    final List<int> original = await input.readAsBytes();
    final Stopwatch inspectTimer = Stopwatch()..start();
    final ImageInfo inputInfo = await inspectImage(input);
    inspectTimer.stop();
    final int cropWidth = inputInfo.width.clamp(1, 240);
    final int cropHeight = inputInfo.height.clamp(1, 180);
    final int outputWidth = (cropWidth ~/ 2).clamp(1, cropWidth);
    final int outputHeight = (cropHeight ~/ 2).clamp(1, cropHeight);
    final File output = File(
      '${outputDirectory.path}${Platform.pathSeparator}'
      '${smokeCase.outputName}',
    );

    final Stopwatch cropTimer = Stopwatch()..start();
    final CropResult result = await crop(
      CropRequest(
        input: input,
        output: output,
        overwrite: true,
        region: CropRegion.pixels(
          x: (inputInfo.width - cropWidth) ~/ 2,
          y: (inputInfo.height - cropHeight) ~/ 2,
          width: cropWidth,
          height: cropHeight,
        ),
        outputSize: PixelSize(width: outputWidth, height: outputHeight),
        aspectMismatchPolicy: AspectMismatchPolicy.adjustCrop,
        outputFormat: smokeCase.outputFormat,
      ),
    );
    cropTimer.stop();

    final Stopwatch outputInspectTimer = Stopwatch()..start();
    final ImageInfo outputInfo = await inspectImage(result.file);
    outputInspectTimer.stop();
    if (result.isManaged ||
        outputInfo.width != outputWidth ||
        outputInfo.height != outputHeight ||
        await input.readAsBytes().then(
          (bytes) => !_sameBytes(bytes, original),
        )) {
      throw StateError('Smoke check failed for ${smokeCase.inputName}');
    }

    stdout.writeln(
      '${smokeCase.inputName}: '
      '${inputInfo.width}x${inputInfo.height} ${inputInfo.format.name} -> '
      '${outputInfo.width}x${outputInfo.height} ${outputInfo.format.name} '
      '(${await result.file.length()} bytes); '
      'inspect ${_milliseconds(inspectTimer)} ms, '
      'crop ${_milliseconds(cropTimer)} ms, '
      'verify ${_milliseconds(outputInspectTimer)} ms',
    );
  }
}

String _milliseconds(Stopwatch stopwatch) =>
    (stopwatch.elapsedMicroseconds / 1000).toStringAsFixed(2);

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

final class _SmokeCase {
  const _SmokeCase(this.inputName, this.outputName, this.outputFormat);

  final String inputName;
  final String outputName;
  final OutputFormat outputFormat;
}
