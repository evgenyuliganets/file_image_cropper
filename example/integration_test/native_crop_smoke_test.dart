import 'dart:convert';
import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native engine crops and encodes every output format', (_) async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'file_image_cropper_mobile_smoke_',
    );
    try {
      final File input = File(
        '${directory.path}${Platform.pathSeparator}input.png',
      );
      await input.writeAsBytes(_testPng());

      final ImageInfo source = await inspectImage(input);
      expect(
        (source.width, source.height, source.format),
        (4, 3, ImageFormat.png),
      );

      for (final OutputFormat format in OutputFormat.values) {
        final CropResult result = await crop(
          CropRequest(
            input: input,
            region: const CropRegion.pixels(x: 1, y: 1, width: 2, height: 2),
            outputSize: const PixelSize(width: 8, height: 8),
            outputFormat: format,
            webpOptions: const WebpOptions(lossless: true),
          ),
        );
        try {
          expect(result.isManaged, isTrue);
          final ImageInfo output = await inspectImage(result.file);
          expect((output.width, output.height), (8, 8));
          expect(output.format.name, format.name);
        } finally {
          expect(await result.delete(), isTrue);
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

List<int> _testPng() {
  const int width = 4;
  const int height = 3;
  final List<int> scanlines = <int>[];
  for (int y = 0; y < height; y++) {
    scanlines.add(0);
    for (int x = 0; x < width; x++) {
      scanlines.addAll(<int>[x * 60, y * 90, 255 - x * 40, x == y ? 128 : 255]);
    }
  }
  return <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ..._pngChunk('IHDR', <int>[..._u32(width), ..._u32(height), 8, 6, 0, 0, 0]),
    ..._pngChunk('IDAT', ZLibEncoder().convert(scanlines)),
    ..._pngChunk('IEND', const <int>[]),
  ];
}

List<int> _pngChunk(String type, List<int> data) {
  final List<int> typeBytes = ascii.encode(type);
  return <int>[
    ..._u32(data.length),
    ...typeBytes,
    ...data,
    ..._u32(_crc32(<int>[...typeBytes, ...data])),
  ];
}

List<int> _u32(int value) => <int>[
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

int _crc32(List<int> bytes) {
  int crc = 0xffffffff;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
