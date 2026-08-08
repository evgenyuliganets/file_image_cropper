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

    test('maps every supported target to a verified release asset', () {
      final targets =
          <({OS os, Architecture architecture, IOSSdk? sdk, String fileName})>[
            (
              os: OS.android,
              architecture: Architecture.arm,
              sdk: null,
              fileName: 'libfile_image_cropper_native_android_arm.so',
            ),
            (
              os: OS.android,
              architecture: Architecture.arm64,
              sdk: null,
              fileName: 'libfile_image_cropper_native_android_arm64.so',
            ),
            (
              os: OS.android,
              architecture: Architecture.x64,
              sdk: null,
              fileName: 'libfile_image_cropper_native_android_x64.so',
            ),
            (
              os: OS.iOS,
              architecture: Architecture.arm64,
              sdk: IOSSdk.iPhoneOS,
              fileName: 'libfile_image_cropper_native_ios_arm64_iphoneos.dylib',
            ),
            (
              os: OS.iOS,
              architecture: Architecture.arm64,
              sdk: IOSSdk.iPhoneSimulator,
              fileName:
                  'libfile_image_cropper_native_ios_arm64_iphonesimulator.dylib',
            ),
            (
              os: OS.iOS,
              architecture: Architecture.x64,
              sdk: IOSSdk.iPhoneSimulator,
              fileName:
                  'libfile_image_cropper_native_ios_x64_iphonesimulator.dylib',
            ),
            (
              os: OS.linux,
              architecture: Architecture.arm64,
              sdk: null,
              fileName: 'libfile_image_cropper_native_linux_arm64.so',
            ),
            (
              os: OS.linux,
              architecture: Architecture.x64,
              sdk: null,
              fileName: 'libfile_image_cropper_native_linux_x64.so',
            ),
            (
              os: OS.macOS,
              architecture: Architecture.arm64,
              sdk: null,
              fileName: 'libfile_image_cropper_native_macos_arm64.dylib',
            ),
            (
              os: OS.macOS,
              architecture: Architecture.x64,
              sdk: null,
              fileName: 'libfile_image_cropper_native_macos_x64.dylib',
            ),
            (
              os: OS.windows,
              architecture: Architecture.arm64,
              sdk: null,
              fileName: 'file_image_cropper_native_windows_arm64.dll',
            ),
            (
              os: OS.windows,
              architecture: Architecture.x64,
              sdk: null,
              fileName: 'file_image_cropper_native_windows_x64.dll',
            ),
          ];

      for (final target in targets) {
        final asset = prebuiltAssetFor(
          target.os,
          target.architecture,
          iOSSdk: target.sdk,
        );
        expect(asset.fileName, target.fileName);
        expect(asset.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });
  });
}
