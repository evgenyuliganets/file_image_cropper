import 'dart:io';
import 'dart:typed_data';

const Set<String> _hevcHeifBrands = <String>{
  'heic',
  'heix',
  'hevc',
  'hevx',
  'heim',
  'heis',
};
const Set<String> _genericHeifBrands = <String>{'mif1', 'msf1'};
const Set<String> _avifBrands = <String>{'avif', 'avis'};

/// Identifies HEVC-backed HEIF by its ISO BMFF `ftyp` box, not its extension.
Future<bool> isHeicFile(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open(mode: FileMode.read);
    final int length = await handle.length();
    if (length < 12) return false;
    final Uint8List bytes = await handle.read(length.clamp(12, 4096));
    return _containsHeicFileType(bytes);
  } on FileSystemException {
    // Preserve the native pipeline's structured missing/input errors.
    return false;
  } finally {
    await handle?.close();
  }
}

bool _containsHeicFileType(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  int offset = 0;
  while (offset + 8 <= bytes.length) {
    final int size32 = data.getUint32(offset, Endian.big);
    final String type = _ascii(bytes, offset + 4);
    int headerSize = 8;
    int boxSize = size32;
    if (size32 == 1) {
      if (offset + 16 > bytes.length) return false;
      final int high = data.getUint32(offset + 8, Endian.big);
      final int low = data.getUint32(offset + 12, Endian.big);
      boxSize = high * 0x100000000 + low;
      headerSize = 16;
    } else if (size32 == 0) {
      boxSize = bytes.length - offset;
    }
    if (boxSize < headerSize || offset + boxSize > bytes.length) return false;
    if (type == 'ftyp' && boxSize >= headerSize + 8) {
      final int brandsStart = offset + headerSize;
      final Set<String> brands = <String>{_ascii(bytes, brandsStart)};
      for (
        int brandOffset = brandsStart + 8;
        brandOffset + 4 <= offset + boxSize;
        brandOffset += 4
      ) {
        brands.add(_ascii(bytes, brandOffset));
      }
      if (brands.any(_hevcHeifBrands.contains)) return true;
      return brands.any(_genericHeifBrands.contains) &&
          !brands.any(_avifBrands.contains);
    }
    offset += boxSize;
  }
  return false;
}

String _ascii(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));
