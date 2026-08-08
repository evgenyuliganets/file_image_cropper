import 'dart:io';

/// Resolves the package-owned temporary root. Native code owns file naming,
/// staging, commit, and cleanup within this directory.
final class ManagedFileSystem {
  const ManagedFileSystem._();

  static Directory get root => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}file_image_cropper',
  );

  static Future<ManagedCleanupReport> clear({Duration? olderThan}) async {
    final Directory directory = root;
    if (!await directory.exists()) {
      return const ManagedCleanupReport();
    }
    int removed = 0;
    int skipped = 0;
    int failed = 0;
    final DateTime cutoff = DateTime.now().subtract(olderThan ?? Duration.zero);
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      final String name = entity.uri.pathSegments
          .where((String segment) => segment.isNotEmpty)
          .last;
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file || !name.startsWith('fic_')) {
        skipped++;
        continue;
      }
      try {
        if (olderThan != null &&
            (await entity.stat()).modified.isAfter(cutoff)) {
          skipped++;
          continue;
        }
        await entity.delete();
        removed++;
      } on FileSystemException {
        failed++;
      }
    }
    return ManagedCleanupReport(
      removed: removed,
      skipped: skipped,
      failed: failed,
    );
  }
}

final class ManagedCleanupReport {
  const ManagedCleanupReport({
    this.removed = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  final int removed;
  final int skipped;
  final int failed;
}
