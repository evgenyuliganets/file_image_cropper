import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('oriented dimensions swap width and height for quarter turns', () {
    const ImageInfo normal = ImageInfo(
      width: 640,
      height: 480,
      format: ImageFormat.jpeg,
      orientation: 1,
    );
    const ImageInfo rotated = ImageInfo(
      width: 640,
      height: 480,
      format: ImageFormat.jpeg,
      orientation: 6,
    );

    expect((normal.orientedWidth, normal.orientedHeight), (640, 480));
    expect((rotated.orientedWidth, rotated.orientedHeight), (480, 640));
  });

  test('viewport geometry accounts for contain letterboxing', () {
    final NormalizedCropRegion region = CropGeometry.fromViewport(
      imageSize: const PixelSize(width: 400, height: 200),
      viewportSize: const ViewportSize(width: 200, height: 200),
      cropWindow: const ViewportRect(
        left: 50,
        top: 50,
        width: 100,
        height: 100,
      ),
    );

    expect(region.left, closeTo(0.25, 1e-12));
    expect(region.top, closeTo(0, 1e-12));
    expect(region.width, closeTo(0.5, 1e-12));
    expect(region.height, closeTo(1, 1e-12));
  });

  test('viewport geometry rejects a crop in contain padding', () {
    expect(
      () => CropGeometry.fromViewport(
        imageSize: const PixelSize(width: 400, height: 200),
        viewportSize: const ViewportSize(width: 200, height: 200),
        cropWindow: const ViewportRect(
          left: 0,
          top: 0,
          width: 100,
          height: 100,
        ),
      ),
      throwsRangeError,
    );
  });

  test(
    'inspect image detects PNG content without trusting extension',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'file_image_cropper_metadata_test_',
      );
      try {
        final File input = File(
          '${directory.path}${Platform.pathSeparator}wrong-extension.bin',
        );
        await input.writeAsBytes(<int>[
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
          0,
          0,
          0,
          13,
          0x49,
          0x48,
          0x44,
          0x52,
          0,
          0,
          2,
          128,
          0,
          0,
          1,
          224,
          8,
          6,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);

        final ImageInfo info = await inspectImage(input);

        expect(info.width, 640);
        expect(info.height, 480);
        expect(info.format, ImageFormat.png);
        expect(info.orientation, 1);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('inspect image maps missing input error', () async {
    final File missing = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'file_image_cropper_missing_${DateTime.now().microsecondsSinceEpoch}.png',
    );

    await expectLater(
      inspectImage(missing),
      throwsA(
        isA<ImageInspectionException>()
            .having(
              (ImageInspectionException error) => error.status,
              'status',
              ImageInspectionStatus.inputNotFound,
            )
            .having(
              (ImageInspectionException error) => error.reason,
              'reason',
              ImageInspectionReason.none,
            ),
      ),
    );
  });

  test('inspect image exposes structured invalid-image reason', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'file_image_cropper_invalid_test_',
    );
    try {
      final File input = File(
        '${directory.path}${Platform.pathSeparator}broken.png',
      );
      await input.writeAsBytes(<int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);

      await expectLater(
        inspectImage(input),
        throwsA(
          isA<ImageInspectionException>()
              .having(
                (ImageInspectionException error) => error.status,
                'status',
                ImageInspectionStatus.invalidImage,
              )
              .having(
                (ImageInspectionException error) => error.reason,
                'reason',
                ImageInspectionReason.invalidStructure,
              ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('end-to-end PNG crop resize creates managed result', () async {
    final File input = File('native/tests/fixtures/png/pngtest.png');
    final List<int> original = await input.readAsBytes();

    final CropResult result = await crop(
      CropRequest(
        input: input,
        region: const CropRegion.pixels(x: 1, y: 2, width: 40, height: 30),
        outputSize: const PixelSize(width: 20, height: 15),
      ),
    );
    try {
      expect(result.isManaged, isTrue);
      expect(await result.file.exists(), isTrue);
      final ImageInfo info = await inspectImage(result.file);
      expect((info.width, info.height, info.format), (20, 15, ImageFormat.png));
      expect(await input.readAsBytes(), original);
    } finally {
      expect(await result.delete(), isTrue);
    }
  });

  test('normalized crop resolves natively without pre-inspection', () async {
    final CropResult result = await crop(
      CropRequest(
        input: File('native/tests/fixtures/png/pngtest.png'),
        region: const CropRegion.normalized(
          left: 0,
          top: 0,
          width: 0.5,
          height: 0.5,
        ),
      ),
    );
    try {
      final ImageInfo info = await inspectImage(result.file);
      // The fixture carries a quarter-turn orientation, so the normalized
      // region is resolved against its 69x91 display dimensions.
      expect((info.width, info.height), (35, 46));
    } finally {
      expect(await result.delete(), isTrue);
    }
  });

  test('centered region produces an exact requested square', () async {
    final CropResult result = await crop(
      CropRequest(
        input: File('native/tests/fixtures/png/pngtest.png'),
        region: const CropRegion.centered(aspectRatio: 1),
        outputSize: const PixelSize(width: 32, height: 32),
      ),
    );
    try {
      final ImageInfo info = await inspectImage(result.file);
      expect((info.width, info.height), (32, 32));
    } finally {
      expect(await result.delete(), isTrue);
    }
  });

  test('aspect mismatch is rejected without implicit stretching', () async {
    await expectLater(
      crop(
        CropRequest(
          input: File('native/tests/fixtures/png/pngtest.png'),
          region: const CropRegion.pixels(x: 0, y: 0, width: 40, height: 30),
          outputSize: const PixelSize(width: 20, height: 20),
        ),
      ),
      throwsA(
        isA<CropException>()
            .having(
              (CropException error) => error.status,
              'status',
              CropStatus.invalidRequest,
            )
            .having(
              (CropException error) => error.reason,
              'reason',
              CropFailureReason.aspectMismatch,
            ),
      ),
    );
  });

  test('deprecated request fields preserve legacy stretching', () async {
    final CropResult result = await crop(
      CropRequest(
        input: File('native/tests/fixtures/png/pngtest.png'),
        // ignore: deprecated_member_use
        crop: const CropRect(x: 0, y: 0, width: 20, height: 20),
        // ignore: deprecated_member_use
        resize: const ResizeOptions(width: 20, height: 10),
      ),
    );
    try {
      final ImageInfo info = await inspectImage(result.file);
      expect((info.width, info.height), (20, 10));
    } finally {
      expect(await result.delete(), isTrue);
    }
  });

  test('end-to-end PNG respects explicit no-overwrite', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'file_image_cropper_output_test_',
    );
    try {
      final File output = File(
        '${directory.path}${Platform.pathSeparator}result.png',
      );
      await output.writeAsString('existing');
      await expectLater(
        crop(
          CropRequest(
            input: File('native/tests/fixtures/png/pngtest.png'),
            output: output,
            region: const CropRegion.pixels(x: 0, y: 0, width: 10, height: 10),
          ),
        ),
        throwsA(
          isA<CropException>().having(
            (CropException error) => error.status,
            'status',
            CropStatus.output,
          ),
        ),
      );
      expect(await output.readAsString(), 'existing');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'end-to-end JPEG normalizes orientation and creates managed result',
    () async {
      final File input = File('native/tests/fixtures/jpeg/Portrait_6.jpg');
      final List<int> original = await input.readAsBytes();

      final CropResult result = await crop(
        CropRequest(
          input: input,
          region: const CropRegion.pixels(x: 10, y: 20, width: 120, height: 80),
          outputSize: const PixelSize(width: 60, height: 40),
          outputFormat: OutputFormat.jpeg,
          jpegOptions: const JpegOptions(
            quality: 92,
            background: RgbColor(248, 248, 248),
          ),
        ),
      );
      try {
        expect(result.isManaged, isTrue);
        final ImageInfo info = await inspectImage(result.file);
        expect(
          (info.width, info.height, info.format),
          (60, 40, ImageFormat.jpeg),
        );
        expect(info.orientation, 1);
        expect(await input.readAsBytes(), original);
      } finally {
        expect(await result.delete(), isTrue);
      }
    },
  );

  test('JPEG quality is validated before native processing', () {
    expect(
      () => crop(
        CropRequest(
          input: File('native/tests/fixtures/jpeg/Portrait_1.jpg'),
          region: const CropRegion.pixels(x: 0, y: 0, width: 10, height: 10),
          outputFormat: OutputFormat.jpeg,
          jpegOptions: const JpegOptions(quality: 0),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('end-to-end static WebP decode and lossless encode', () async {
    final File input = File('native/tests/fixtures/webp/test.webp');
    final List<int> original = await input.readAsBytes();

    final CropResult result = await crop(
      CropRequest(
        input: input,
        region: const CropRegion.pixels(x: 1, y: 2, width: 40, height: 30),
        outputSize: const PixelSize(width: 20, height: 15),
        outputFormat: OutputFormat.webp,
        webpOptions: const WebpOptions(lossless: true, quality: 80),
      ),
    );
    try {
      expect(result.isManaged, isTrue);
      final ImageInfo info = await inspectImage(result.file);
      expect(
        (info.width, info.height, info.format),
        (20, 15, ImageFormat.webp),
      );
      expect(await input.readAsBytes(), original);
    } finally {
      expect(await result.delete(), isTrue);
    }
  });

  test('WebP quality is validated before native processing', () {
    expect(
      () => crop(
        CropRequest(
          input: File('native/tests/fixtures/png/pngtest.png'),
          region: const CropRegion.pixels(x: 0, y: 0, width: 10, height: 10),
          outputFormat: OutputFormat.webp,
          webpOptions: const WebpOptions(quality: 101),
        ),
      ),
      throwsArgumentError,
    );
  });
}
