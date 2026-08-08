import 'dart:io';

import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final logger = Logger.root
      ..level = .WARNING
      ..onRecord.listen((record) => stderr.writeln(record.message));
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: ['src/$packageName.c'],
    );
    await cbuilder.run(input: input, output: output, logger: logger);
    await RustBuilder(
      assetName: 'src/ffi/native_image_engine.dart',
    ).run(input: input, output: output);
  });
}
