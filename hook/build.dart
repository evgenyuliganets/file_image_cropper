import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:file_image_cropper/src/prebuilt/prebuilt_asset.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final buildFromSourceValue = input.userDefines['build_from_source'];
    if (buildFromSourceValue is! bool?) {
      throw const FormatException(
        'hooks.user_defines.file_image_cropper.build_from_source must be a '
        'boolean or omitted.',
      );
    }

    final customLibrary = input.userDefines.path('native_library');
    if (customLibrary != null && buildFromSourceValue == true) {
      throw const FormatException(
        'native_library and build_from_source cannot be enabled together.',
      );
    }

    if (customLibrary != null) {
      final file = File.fromUri(customLibrary);
      if (!await file.exists()) {
        throw ArgumentError.value(
          customLibrary,
          'native_library',
          'The configured native library does not exist.',
        );
      }
      output.dependencies.add(customLibrary);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: nativeImageEngineAssetName,
          linkMode: DynamicLoadingBundled(),
          file: customLibrary,
        ),
      );
      return;
    }

    if (buildFromSourceValue != true) {
      final code = input.config.code;
      final asset = prebuiltAssetFor(
        code.targetOS,
        code.targetArchitecture,
        iOSSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
      );
      final file = await downloadPrebuiltAsset(
        asset,
        Directory.fromUri(input.outputDirectoryShared),
      );
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: nativeImageEngineAssetName,
          linkMode: DynamicLoadingBundled(),
          file: file.uri,
        ),
      );
      return;
    }

    final logger = Logger.root
      ..level = .WARNING
      ..onRecord.listen((record) => stderr.writeln(record.message));
    await RustBuilder(
      assetName: nativeImageEngineAssetName,
    ).run(input: input, output: output, logger: logger);
  });
}
