import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';

const nativeImageEngineAssetName = 'src/ffi/native_image_engine.dart';
const prebuiltReleaseTag = 'native-v0.2.0';

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
    sha256: '4912a843bfaf269eab3bbcccce52cc7d868b549f0f3b356f2ee623779785a318',
  ),
  'android-arm64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_android_arm64.so',
    sha256: 'aa4f7d409ade819cb319d2fad4a2961fb62d1a02189c1da9030938199db72c69',
  ),
  'android-x64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_android_x64.so',
    sha256: '0697b253bd9cc9eed8031ccc75e3da897afe2302b1b7b95ea45c5fe075d9d23c',
  ),
  'ios-arm64-iphoneos': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_ios_arm64_iphoneos.dylib',
    sha256: 'f7d3a9e10f4ece6b300145c6f03da6bc4fbb046c93f6fa0f9864fd451098f195',
  ),
  'ios-arm64-iphonesimulator': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_ios_arm64_iphonesimulator.dylib',
    sha256: '2e39e54e95b894725676ee1641feec5a54b06175fe6c454817332cedddad854a',
  ),
  'ios-x64-iphonesimulator': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_ios_x64_iphonesimulator.dylib',
    sha256: 'd23aabd38c90a70463f8806493924494d7c2dd3213172f70676e54c8f3936179',
  ),
  'linux-arm64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_linux_arm64.so',
    sha256: '87a1af6553e6bbb2462f77d36abb6827ce73df1f30fb4ac26e426bf1f401521a',
  ),
  'linux-x64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_linux_x64.so',
    sha256: 'f3ab4ba356797d314a25fd48d3da71e11d5f513a083762ee75185ec714c50477',
  ),
  'macos-arm64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_macos_arm64.dylib',
    sha256: '49edf325b96a68af2bf172f2f5692326009871e4443255e1dfd30e97a0887cb7',
  ),
  'macos-x64': PrebuiltAsset(
    fileName: 'libfile_image_cropper_native_macos_x64.dylib',
    sha256: '0e1b73c435308d0c182090f3cb523771cbde29c0ceaa9b2284fad624ea460a2d',
  ),
  'windows-arm64': PrebuiltAsset(
    fileName: 'file_image_cropper_native_windows_arm64.dll',
    sha256: 'a9be816cdedd05f40cb6de38ed82d63d75c1aac818a321084c6a18bdc17ca1d2',
  ),
  'windows-x64': PrebuiltAsset(
    fileName: 'file_image_cropper_native_windows_x64.dll',
    sha256: '216732b98de5f1148a7774960639e15ee8d374c2a7df4e36d32a390995bd17da',
  ),
};
