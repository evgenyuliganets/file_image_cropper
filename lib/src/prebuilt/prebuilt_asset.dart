import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';

const nativeImageEngineAssetName = 'src/ffi/native_image_engine.dart';
const prebuiltReleaseTag = 'native-v0.3.0';

const _releaseBase =
    'https://github.com/evgenyuliganets/file_image_cropper/releases/download';
const _maximumAssetBytes = 32 * 1024 * 1024;

final class PrebuiltAsset {
  const PrebuiltAsset({required this.fileName, required this.sha256});

  final String fileName;
  final String sha256;

  Uri get downloadUri =>
      Uri.parse('$_releaseBase/$prebuiltReleaseTag/$fileName');
}

PrebuiltAsset prebuiltAssetFor(
  OS os,
  Architecture architecture, {
  IOSSdk? iOSSdk,
}) {
  if (os == OS.iOS && iOSSdk == null) {
    throw ArgumentError.notNull('iOSSdk');
  }
  if (os != OS.iOS && iOSSdk != null) {
    throw ArgumentError.value(iOSSdk, 'iOSSdk', 'Only valid for iOS.');
  }

  final key = _targetKey(os, architecture, iOSSdk);
  final asset = _prebuiltAssets[key];
  if (asset == null) {
    throw UnsupportedError(
      'file_image_cropper has no prebuilt native library for $key. '
      'Build from source by setting '
      'hooks.user_defines.file_image_cropper.build_from_source to true.',
    );
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.sha256)) {
    throw StateError(
      'The prebuilt checksum for ${asset.fileName} has not been published.',
    );
  }
  return asset;
}

Future<File> downloadPrebuiltAsset(
  PrebuiltAsset asset,
  Directory outputDirectory,
) async {
  await outputDirectory.create(recursive: true);
  final destination = File.fromUri(outputDirectory.uri.resolve(asset.fileName));
  if (await destination.exists() &&
      await _sha256(destination) == asset.sha256) {
    return destination;
  }

  final temporary = File(
    '${destination.path}.download-$pid-'
    '${DateTime.now().microsecondsSinceEpoch}',
  );
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..userAgent = 'file_image_cropper/$prebuiltReleaseTag';

  try {
    final request = await client.getUrl(asset.downloadUri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Downloading ${asset.downloadUri} returned HTTP '
        '${response.statusCode}. To build without downloading a prebuilt '
        'library, set '
        'hooks.user_defines.file_image_cropper.build_from_source to true.',
        uri: asset.downloadUri,
      );
    }
    if (response.contentLength > _maximumAssetBytes) {
      throw StateError(
        'Prebuilt asset ${asset.fileName} is unexpectedly large '
        '(${response.contentLength} bytes).',
      );
    }

    final sink = temporary.openWrite(mode: FileMode.writeOnly);
    var received = 0;
    try {
      await for (final chunk in response) {
        received += chunk.length;
        if (received > _maximumAssetBytes) {
          throw StateError(
            'Prebuilt asset ${asset.fileName} exceeded '
            '$_maximumAssetBytes bytes.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final actualHash = await _sha256(temporary);
    if (actualHash != asset.sha256) {
      throw StateError(
        'Checksum mismatch for ${asset.fileName}: expected ${asset.sha256}, '
        'received $actualHash.',
      );
    }

    if (await destination.exists()) {
      await destination.delete();
    }
    return temporary.rename(destination.path);
  } finally {
    client.close(force: true);
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

String _targetKey(OS os, Architecture architecture, IOSSdk? iOSSdk) =>
    [os.name, architecture.name, if (iOSSdk != null) iOSSdk.type].join('-');

Future<String> _sha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

const _prebuiltAssets = <String, PrebuiltAsset>{
  'android-arm': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_android_arm.so',
    sha256: '80f6c3e1a731cbf5b7ca9fb2111a5a7fe5c7ab88ec14367e4c49cfccc351e4b5',
  ),
  'android-arm64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_android_arm64.so',
    sha256: '981beb6b8c74993ce04ebb8cf971fb62c30ccdcc537b8cc6214b0e16bf3e463c',
  ),
  'android-x64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_android_x64.so',
    sha256: '05851c7a06eaf5cfceadc450f5ff08d17d37c975161f068e6c5a27304601adf3',
  ),
  'ios-arm64-iphoneos': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_ios_arm64_iphoneos.dylib',
    sha256: '59040e9099fc63d7fea3e86c0c02146a21c972596df055c2286196f267085057',
  ),
  'ios-arm64-iphonesimulator': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_ios_arm64_iphonesimulator.dylib',
    sha256: '43f14d10b1ec670046448ec809abc0f560a4e4e7e52426d289ade4f61c1fabc6',
  ),
  'ios-x64-iphonesimulator': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_ios_x64_iphonesimulator.dylib',
    sha256: '9130d20e4a7adb701f8f7545a60058688b774ef59d8d6d17c67f496cad0c7419',
  ),
  'linux-arm64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_linux_arm64.so',
    sha256: '08906c37428f1c61613714b590dfb0d4af7f86fc493b9d579bed35687ff90e9c',
  ),
  'linux-x64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_linux_x64.so',
    sha256: 'a87051503a0fc7bc384246e5b7e71413368f4de1f9f82e1851320cb354ddd795',
  ),
  'macos-arm64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_macos_arm64.dylib',
    sha256: 'e5183c72f763595f952fdc8e685fd9742b79e6e9f3e05de3e5a71b35480730d2',
  ),
  'macos-x64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_macos_x64.dylib',
    sha256: 'b3e923d9e1e661ee325531f795189fcee40f13b67ada70d54ab3806fa2dab304',
  ),
  'windows-arm64': PrebuiltAsset(
    fileName: 'file_image_cropper_native_windows_arm64.dll',
    sha256: 'f7de0e09baa5d609d0f695ef87f80bef4d825e16e29f8325723314bfb813a3ce',
  ),
  'windows-x64': PrebuiltAsset(
    fileName: 'file_image_cropper_native_windows_x64.dll',
    sha256: '39c5ff0642c88722abaa1fbc6d2c420ddf7bf4bd243309c380fc6f6c5fb875e4',
  ),
};
