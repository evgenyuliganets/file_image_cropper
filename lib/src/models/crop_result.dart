import 'dart:io';

/// A completed crop output and its ownership information.
final class CropResult {
  const CropResult({required this.file, required this.isManaged});

  final File file;
  final bool isManaged;

  /// Deletes a package-managed result. Explicit caller-owned outputs are never
  /// deleted by this method.
  Future<bool> delete() async {
    if (!isManaged) {
      return false;
    }
    final String managedRoot = Directory.systemTemp
        .directory('file_image_cropper')
        .absolute
        .path;
    final String candidate = file.absolute.path;
    if (!_isDirectChild(candidate, managedRoot) ||
        !_basename(candidate).startsWith('fic_output_')) {
      return false;
    }
    final FileSystemEntityType type = await FileSystemEntity.type(
      candidate,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file) {
      return false;
    }
    await file.delete();
    return true;
  }

  static bool _isDirectChild(String candidate, String parent) {
    final String separator = Platform.pathSeparator;
    final String prefix = parent.endsWith(separator)
        ? parent
        : '$parent$separator';
    final String remainder = candidate.startsWith(prefix)
        ? candidate.substring(prefix.length)
        : '';
    return remainder.isNotEmpty && !remainder.contains(separator);
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}

extension on Directory {
  Directory directory(String child) =>
      Directory('$path${Platform.pathSeparator}$child');
}
