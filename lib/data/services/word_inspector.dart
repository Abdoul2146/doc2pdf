import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/conversion_models.dart';

/// Reads just enough of a Word file to classify it and (for `.docx`) recover the
/// first section's page geometry, mirroring the native sniffing logic.
class WordInspector {
  const WordInspector();

  static const List<int> _zipMagic = <int>[0x50, 0x4B];
  static const List<int> _ole2Magic = <int>[
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
  ];

  Future<SelectedFile> inspect(File file) async {
    final bytes = await file.readAsBytes();
    final format = _classify(bytes);
    return SelectedFile(
      path: file.path,
      name: file.uri.pathSegments.last,
      sizeBytes: bytes.length,
      format: format,
    );
  }

  WordFormat _classify(Uint8List bytes) {
    if (_startsWith(bytes, _zipMagic) && _zipContainsDocumentXml(bytes)) {
      return WordFormat.docx;
    }
    if (_startsWith(bytes, _ole2Magic)) {
      return WordFormat.doc;
    }
    return WordFormat.unknown;
  }

  /// Returns the first section's page size for a `.docx`, or `null` when it
  /// cannot be determined (the caller then falls back to a preset).
  Future<PageGeometry?> readPageGeometry(File file, {PageOrientation? force}) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final entry = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => archive.files.firstWhere(
          (f) => f.name == 'word/document2.xml',
          orElse: () => throw const FormatException('no document.xml'),
        ),
      );
      final document = XmlDocument.parse(_decode(entry.content));

      final sectPr = document.descendants
          .whereType<XmlElement>()
          .firstWhere(
            (element) => element.name.local == 'sectPr',
            orElse: () => throw const FormatException('no sectPr'),
          );

      final pageSize = sectPr.childElements.firstWhere(
        (element) => element.name.local == 'pgSz',
        orElse: () => throw const FormatException('no pgSz'),
      );

      var width = _intAttr(pageSize, 'w');
      var height = _intAttr(pageSize, 'h');
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null;
      }

      final orient = _stringAttr(pageSize, 'orient')?.toLowerCase();
      final isLandscape = orient == 'landscape';
      if (isLandscape == (width < height)) {
        final temp = width;
        width = height;
        height = temp;
      }

      var geometry = PageGeometry(_twipsToMils(width), _twipsToMils(height));

      if (force != null) {
        geometry = _applyOrientation(geometry, force);
      }
      return geometry;
    } catch (_) {
      return null;
    }
  }

  PageGeometry _applyOrientation(PageGeometry geometry, PageOrientation orientation) {
    final portrait =
        geometry.widthMils <= geometry.heightMils;
    switch (orientation) {
      case PageOrientation.portrait:
        return portrait
            ? geometry
            : PageGeometry(geometry.heightMils, geometry.widthMils);
      case PageOrientation.landscape:
        return portrait
            ? PageGeometry(geometry.heightMils, geometry.widthMils)
            : geometry;
    }
  }

  bool _zipContainsDocumentXml(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      return archive.files.any(
        (f) => f.name == 'word/document.xml' || f.name == 'word/document2.xml',
      );
    } catch (_) {
      return false;
    }
  }

  bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  int? _intAttr(XmlElement element, String localName) {
    final value = _stringAttr(element, localName);
    return value == null ? null : int.tryParse(value);
  }

  String? _stringAttr(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  int _twipsToMils(int twips) => (twips * 1000 / 1440).round();

  String _decode(Uint8List bytes) {
    // Strip a UTF-8 BOM if present.
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      bytes = Uint8List.sublistView(bytes, 3);
    }
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }
}
