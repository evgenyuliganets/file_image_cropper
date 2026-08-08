import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';
import 'package:file_image_cropper/src/heic/heic_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fic_heic_test_');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('detects HEIC by compatible brand rather than extension', () async {
    final File input = File('${temporary.path}/photo.bin');
    await input.writeAsBytes(<int>[
      0,
      0,
      0,
      24,
      ...'ftyp'.codeUnits,
      ...'mif1'.codeUnits,
      0,
      0,
      0,
      0,
      ...'heic'.codeUnits,
      ...'mif1'.codeUnits,
    ]);
    expect(await isHeicFile(input), isTrue);
  });

  test('does not confuse AVIF with HEIC', () async {
    final File input = File('${temporary.path}/photo.heic');
    await input.writeAsBytes(<int>[
      0,
      0,
      0,
      20,
      ...'ftyp'.codeUnits,
      ...'avif'.codeUnits,
      0,
      0,
      0,
      0,
      ...'mif1'.codeUnits,
    ]);
    expect(await isHeicFile(input), isFalse);
  });

  test('Windows and Linux return actionable HEIC codec guidance', () async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    final File input = File('${temporary.path}/photo.heic');
    await input.writeAsBytes(<int>[
      0,
      0,
      0,
      20,
      ...'ftyp'.codeUnits,
      ...'heic'.codeUnits,
      0,
      0,
      0,
      0,
      ...'mif1'.codeUnits,
    ]);

    await expectLater(
      inspectImage(input),
      throwsA(
        isA<HeicCodecUnavailableException>()
            .having(
              (HeicCodecUnavailableException error) => error.platform,
              'platform',
              Platform.isWindows ? 'windows' : 'linux',
            )
            .having(
              (HeicCodecUnavailableException error) => error.helpUri.hasScheme,
              'helpUri',
              isTrue,
            ),
      ),
    );
  });
}
