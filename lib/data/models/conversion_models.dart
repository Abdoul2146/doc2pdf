import 'dart:io';

import 'package:flutter/foundation.dart';

/// Detected Word container format.
enum WordFormat {
  docx('docx', 'Word document (.docx)'),
  doc('doc', 'Legacy Word (.doc)'),
  unknown('unknown', 'Unsupported file');

  const WordFormat(this.id, this.label);

  final String id;
  final String label;

  static WordFormat fromId(String? id) => switch (id) {
    'docx' => WordFormat.docx,
    'doc' => WordFormat.doc,
    _ => WordFormat.unknown,
  };

  bool get isSupported => this != WordFormat.unknown;

  /// `.doc` goes through Apache POI (HWPF) and is best-effort only.
  bool get isLegacy => this == WordFormat.doc;
}

/// Output colour handling.
enum PdfColorMode {
  color('color', 'Colour'),
  mono('mono', 'Black & white');

  const PdfColorMode(this.id, this.label);

  final String id;
  final String label;
}

/// Page size presets (portrait dimensions, in thousandths of an inch).
enum PageSizePreset {
  matchDocument('match', 'Match document', null, null),
  a4('a4', 'A4', 8268, 11693),
  letter('letter', 'Letter', 8500, 11000),
  legal('legal', 'Legal', 8500, 14000),
  a5('a5', 'A5', 5827, 8268);

  const PageSizePreset(this.id, this.label, this.portraitWidthMils, this.portraitHeightMils);

  final String id;
  final String label;
  final int? portraitWidthMils;
  final int? portraitHeightMils;

  bool get isFixed => portraitWidthMils != null;
}

enum PageOrientation {
  portrait('portrait', 'Portrait'),
  landscape('landscape', 'Landscape');

  const PageOrientation(this.id, this.label);

  final String id;
  final String label;
}

/// Ordered conversion phases reported by the native renderer.
enum ConversionPhase {
  detecting('detecting', 'Checking file'),
  parsing('parsing', 'Reading document'),
  rendering('rendering', 'Laying out pages'),
  paginating('paginating', 'Finishing pages'),
  printing('printing', 'Writing PDF'),
  done('done', 'Done');

  const ConversionPhase(this.id, this.label);

  final String id;
  final String label;

  static ConversionPhase fromId(String? id) => ConversionPhase.values.firstWhere(
    (phase) => phase.id == id,
    orElse: () => ConversionPhase.rendering,
  );
}

/// Resolved page geometry handed to the native printer.
@immutable
class PageGeometry {
  const PageGeometry(this.widthMils, this.heightMils);

  final int widthMils;
  final int heightMils;

  static const PageGeometry a4 = PageGeometry(8268, 11693);

  @override
  bool operator ==(Object other) =>
      other is PageGeometry &&
      other.widthMils == widthMils &&
      other.heightMils == heightMils;

  @override
  int get hashCode => Object.hash(widthMils, heightMils);
}

/// Everything the native layer needs to convert one file.
@immutable
class ConversionRequest {
  const ConversionRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.geometry,
    required this.colorMode,
    required this.jobName,
  });

  final String sourcePath;
  final String outputPath;
  final PageGeometry geometry;
  final PdfColorMode colorMode;
  final String jobName;

  Map<String, Object?> toMap() => <String, Object?>{
    'sourcePath': sourcePath,
    'outputPath': outputPath,
    'pageWidthMils': geometry.widthMils,
    'pageHeightMils': geometry.heightMils,
    'colorMode': colorMode.id,
    'jobName': jobName,
  };
}

/// Result of a successful conversion.
@immutable
class ConversionResult {
  const ConversionResult({
    required this.outputPath,
    required this.pageCount,
    required this.format,
    required this.sizeBytes,
    required this.duration,
    this.savedLocation,
    this.savedName,
    this.savedPath,
    this.saveWarning,
  });

  final String outputPath;
  final int pageCount;
  final WordFormat format;
  final int sizeBytes;
  final Duration duration;

  /// Shared folder the PDF was published into, e.g. `Documents/doc2pdf`.
  /// Null when publishing failed; see [saveWarning].
  final String? savedLocation;

  /// Final file name in [savedLocation]. May differ from the source name when a
  /// file of that name already existed there.
  final String? savedName;

  /// Absolute path of the published file, only known on Android 8/9.
  final String? savedPath;

  /// Set when the PDF could not be published into shared storage (for example
  /// the user declined the storage permission on Android 8/9). The conversion
  /// itself still succeeded and the working copy remains shareable.
  final String? saveWarning;

  bool get savedToSharedStorage => savedLocation != null;

  /// User-facing location such as `Documents/doc2pdf/report.pdf`.
  String? get savedDisplayPath {
    final location = savedLocation;
    final name = savedName;
    if (location == null || name == null) return null;
    return '$location/$name';
  }

  File get file => File(outputPath);

  String get fileName => outputPath.split(Platform.pathSeparator).last;

  factory ConversionResult.fromMap(Map<String, Object?> map) {
    return ConversionResult(
      outputPath: map['outputPath']! as String,
      pageCount: (map['pageCount']! as num).toInt(),
      format: WordFormat.fromId(map['format'] as String?),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
      savedLocation: map['savedLocation'] as String?,
      savedName: map['savedName'] as String?,
      savedPath: map['savedPath'] as String?,
      saveWarning: map['saveWarning'] as String?,
    );
  }
}

/// Progress event from the native renderer.
@immutable
class ConversionProgress {
  const ConversionProgress({required this.phase, required this.percent});

  final ConversionPhase phase;
  final int percent;

  factory ConversionProgress.fromMap(Map<Object?, Object?> map) {
    return ConversionProgress(
      phase: ConversionPhase.fromId(map['phase'] as String?),
      percent: ((map['percent'] as num?)?.toInt() ?? 0).clamp(0, 100),
    );
  }
}

/// A picked Word file plus cheap-to-compute metadata.
@immutable
class SelectedFile {
  const SelectedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.format,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final WordFormat format;

  File get file => File(path);
}

/// Typed errors surfaced to the UI.
enum ConversionErrorCode {
  fileNotFound('file_not_found'),
  unsupportedFormat('unsupported_format'),
  docParseFailed('doc_parse_failed'),
  renderFailed('render_failed'),
  printFailed('print_failed'),
  passwordProtected('password_protected'),
  busy('busy'),
  unknown('unknown');

  const ConversionErrorCode(this.id);

  final String id;

  static ConversionErrorCode fromId(String? id) => ConversionErrorCode.values
      .firstWhere((code) => code.id == id, orElse: () => ConversionErrorCode.unknown);
}

class ConversionException implements Exception {
  const ConversionException(this.code, this.message);

  final ConversionErrorCode code;
  final String message;

  String get userMessage => switch (code) {
    ConversionErrorCode.fileNotFound => 'That file could not be found. It may have been moved or deleted.',
    ConversionErrorCode.unsupportedFormat => 'Only Word .docx and .doc files can be converted.',
    ConversionErrorCode.docParseFailed =>
      'This legacy .doc file could not be read. It may be damaged or password-protected.',
    ConversionErrorCode.renderFailed => 'The document could not be rendered. It may be damaged.',
    ConversionErrorCode.printFailed => 'The PDF could not be written. Check you have free storage and try again.',
    ConversionErrorCode.passwordProtected => 'Password-protected documents are not supported yet.',
    ConversionErrorCode.busy => 'A conversion is already running. Please wait for it to finish.',
    ConversionErrorCode.unknown => 'Something went wrong during conversion. Please try again.',
  };

  @override
  String toString() => 'ConversionException($code, $message)';
}
