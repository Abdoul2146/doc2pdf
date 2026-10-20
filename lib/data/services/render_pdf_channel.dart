import 'package:flutter/services.dart';

import '../models/conversion_models.dart';

/// Thin wrapper over the native `doc2pdf/render` method channel and
/// `doc2pdf/progress` event channel.
class RenderPdfChannel {
  const RenderPdfChannel();

  static const MethodChannel _method = MethodChannel('doc2pdf/render');
  static const EventChannel _progressChannel = EventChannel(
    'doc2pdf/progress',
  );

  /// Broadcast stream of native progress events. Safe to listen to repeatedly;
  /// the underlying stream is broadcast by the platform.
  Stream<ConversionProgress> watchProgress() {
    return _progressChannel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      return ConversionProgress.fromMap(map);
    });
  }

  Future<ConversionResult> convert(ConversionRequest request) async {
    try {
      final raw = await _method.invokeMethod<Map<Object?, Object?>>(
        'convert',
        request.toMap(),
      );
      if (raw == null) {
        throw const ConversionException(
          ConversionErrorCode.unknown,
          'Native layer returned an empty response',
        );
      }
      return ConversionResult.fromMap(raw.cast<String, Object?>());
    } on PlatformException catch (error) {
      throw ConversionException(
        ConversionErrorCode.fromId(error.code),
        error.message ?? error.code,
      );
    } on MissingPluginException {
      throw const ConversionException(
        ConversionErrorCode.unknown,
        'Conversion engine is unavailable on this device',
      );
    }
  }

  Future<void> dispose() async {
    await _method.invokeMethod<void>('dispose');
  }
}
