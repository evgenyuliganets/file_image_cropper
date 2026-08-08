import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:file_image_cropper/src/prebuilt/prebuilt_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('prebuilt native assets', () {
    test('reuses a verified cached asset without a download', () async {
      final directory = await Directory.systemTemp.createTemp(
        'file_image_cropper_prebuilt_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      const bytes = <int>[11, 22, 33, 44, 55];
      final hash = sha256.convert(bytes).toString();
      final asset = PrebuiltAsset(fileName: 'cached.dll', sha256: hash);
      final cached = File.fromUri(directory.uri.resolve(asset.fileName));
      await cached.writeAsBytes(bytes, flush: true);

      final resolved = await downloadPrebuiltAsset(asset, directory);

      expect(resolved.path, cached.path);
      expect(await resolved.readAsBytes(), bytes);
    });

    test('requires the iOS SDK for an iOS target', () {
      expect(
        () => prebuiltAssetFor(OS.iOS, Architecture.arm64),
        throwsArgumentError,
      );
    });

    test('rejects an iOS SDK for a non-iOS target', () {
      expect(
        () => prebuiltAssetFor(
          OS.windows,
          Architecture.x64,
          iOSSdk: IOSSdk.iPhoneSimulator,
        ),
        throwsArgumentError,
      );
    });
  });
}
