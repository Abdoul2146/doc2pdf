import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves the scratch file the native renderer writes the PDF into.
///
/// This is only a *working* copy: Preview and Share read it, and the native
/// layer additionally publishes the finished PDF into shared
/// `Documents/doc2pdf`, which is what the user actually keeps. Because only one
/// conversion result is ever live at a time, the folder is wiped before every
/// conversion, and living under the cache directory means Android can reclaim
/// it even if the app never cleans up.
class OutputService {
  const OutputService();

  static const String folderName = 'doc2pdf';

  /// Shared destination the native publisher writes to, as shown to users.
  /// Must stay in sync with `DocumentPublisher.RELATIVE_LOCATION`.
  static const String sharedLocation = 'Documents/$folderName';

  /// The working-copy folder. Safe to call from the UI: it creates the folder
  /// if missing but never deletes anything.
  Future<Directory> scratchDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Builds the working-copy path for [sourceName], clearing any previous
  /// conversion first.
  Future<String> resolveOutputPath(String sourceName) async {
    final dir = await scratchDirectory();
    await _clear(dir);
    final separator = Platform.pathSeparator;
    final stem = _stripExtension(sourceName);
    return '${dir.path}$separator$stem.pdf';
  }

  Future<void> _clear(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        await entity.delete(recursive: true);
      }
    } on FileSystemException {
      // A stale file is harmless: the native printer truncates its target anyway.
    }
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return stem.isEmpty ? 'document' : stem;
  }
}
