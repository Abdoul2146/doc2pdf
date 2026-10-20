import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/providers.dart';
import '../../data/models/conversion_models.dart';
import '../../data/services/word_inspector.dart';

enum ConversionStatus { idle, ready, converting, success, failure }

@immutable
class ConverterState {
  const ConverterState({
    this.status = ConversionStatus.idle,
    this.file,
    this.progress,
    this.result,
    this.errorMessage,
    this.pageSize = PageSizePreset.matchDocument,
    this.orientation = PageOrientation.portrait,
    this.colorMode = PdfColorMode.color,
    this.keepScreenOn = true,
  });

  final ConversionStatus status;
  final SelectedFile? file;
  final ConversionProgress? progress;
  final ConversionResult? result;
  final String? errorMessage;
  final PageSizePreset pageSize;
  final PageOrientation orientation;
  final PdfColorMode colorMode;
  final bool keepScreenOn;

  bool get isConverting => status == ConversionStatus.converting;
  bool get hasFile => file != null;
  bool get canConvert => hasFile && !isConverting && (file?.format.isSupported ?? false);

  ConverterState copyWith({
    ConversionStatus? status,
    SelectedFile? file,
    bool clearFile = false,
    ConversionProgress? progress,
    ConversionResult? result,
    bool clearResult = false,
    String? errorMessage,
    bool clearError = false,
    PageSizePreset? pageSize,
    PageOrientation? orientation,
    PdfColorMode? colorMode,
    bool? keepScreenOn,
  }) {
    return ConverterState(
      status: status ?? this.status,
      file: clearFile ? null : (file ?? this.file),
      progress: progress ?? this.progress,
      result: clearResult ? null : (result ?? this.result),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pageSize: pageSize ?? this.pageSize,
      orientation: orientation ?? this.orientation,
      colorMode: colorMode ?? this.colorMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}

final converterControllerProvider =
    NotifierProvider<ConverterController, ConverterState>(ConverterController.new);

class ConverterController extends Notifier<ConverterState> {
  bool _disposed = false;

  @override
  ConverterState build() {
    ref.onDispose(() => _disposed = true);
    final settings = ref.read(settingsRepositoryProvider);
    return ConverterState(
      pageSize: _presetFromId(settings.pageSize()),
      orientation: _orientationFromId(settings.orientation()),
      colorMode: _colorModeFromId(settings.colorMode()),
      keepScreenOn: settings.keepScreenOn(),
    );
  }

  void _update(ConverterState next) {
    if (!_disposed) state = next;
  }

  Future<void> pickFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Select a Word document',
      type: FileType.custom,
      allowedExtensions: const <String>['docx', 'doc'],
    );

    final path = picked?.path;
    if (path == null) return;

    _update(
      state.copyWith(
        status: ConversionStatus.ready,
        progress: null,
        result: null,
        clearResult: true,
        clearError: true,
      ),
    );

    final inspector = ref.read(wordInspectorProvider);
    try {
      final selected = await inspector.inspect(File(path));
      _update(state.copyWith(file: selected, status: ConversionStatus.ready));

      if (!selected.format.isSupported) {
        _update(
          state.copyWith(
            status: ConversionStatus.failure,
            errorMessage: const ConversionException(
              ConversionErrorCode.unsupportedFormat,
              'unsupported',
            ).userMessage,
          ),
        );
      }
    } catch (error) {
      _update(
        state.copyWith(
          status: ConversionStatus.failure,
          errorMessage: 'Could not read the selected file: $error',
        ),
      );
    }
  }

  void clearFile() {
    _update(
      state.copyWith(
        status: ConversionStatus.idle,
        clearFile: true,
        clearResult: true,
        clearError: true,
      ),
    );
  }

  void setPageSize(PageSizePreset value) {
    _update(state.copyWith(pageSize: value));
    ref.read(settingsRepositoryProvider).setPageSize(value.id);
  }

  void setOrientation(PageOrientation value) {
    _update(state.copyWith(orientation: value));
    ref.read(settingsRepositoryProvider).setOrientation(value.id);
  }

  void setColorMode(PdfColorMode value) {
    _update(state.copyWith(colorMode: value));
    ref.read(settingsRepositoryProvider).setColorMode(value.id);
  }

  void setKeepScreenOn(bool value) {
    _update(state.copyWith(keepScreenOn: value));
    ref.read(settingsRepositoryProvider).setKeepScreenOn(value);
  }

  void dismissResult() {
    _update(
      state.copyWith(
        status: state.file == null ? ConversionStatus.idle : ConversionStatus.ready,
        clearResult: true,
        clearError: true,
      ),
    );
  }

  Future<void> convert() async {
    final selected = state.file;
    if (selected == null || state.isConverting) return;

    _update(
      state.copyWith(
        status: ConversionStatus.converting,
        progress: const ConversionProgress(phase: ConversionPhase.detecting, percent: 0),
        clearResult: true,
        clearError: true,
      ),
    );

    final channel = ref.read(renderPdfChannelProvider);
    final inspector = ref.read(wordInspectorProvider);
    final outputs = ref.read(outputServiceProvider);

    final subscription = channel.watchProgress().listen((progress) {
      if (!_disposed && state.isConverting) {
        _update(state.copyWith(progress: progress));
      }
    });

    var wakeLock = false;
    try {
      if (state.keepScreenOn) {
        await WakelockPlus.enable();
        wakeLock = true;
      }

      final geometry = await _resolveGeometry(selected, inspector);
      final outputPath = await outputs.resolveOutputPath(selected.name);

      final result = await channel.convert(
        ConversionRequest(
          sourcePath: selected.path,
          outputPath: outputPath,
          geometry: geometry,
          colorMode: state.colorMode,
          jobName: selected.name,
        ),
      );

      _update(
        state.copyWith(
          status: ConversionStatus.success,
          result: result,
          progress: const ConversionProgress(phase: ConversionPhase.done, percent: 100),
        ),
      );
    } on ConversionException catch (error) {
      _update(
        state.copyWith(status: ConversionStatus.failure, errorMessage: error.userMessage),
      );
    } catch (error) {
      _update(
        state.copyWith(
          status: ConversionStatus.failure,
          errorMessage: 'Something went wrong during conversion: $error',
        ),
      );
    } finally {
      await subscription.cancel();
      if (wakeLock) {
        await WakelockPlus.disable();
      }
    }
  }

  Future<PageGeometry> _resolveGeometry(
    SelectedFile selected,
    WordInspector inspector,
  ) async {
    if (state.pageSize == PageSizePreset.matchDocument && selected.format == WordFormat.docx) {
      final geometry = await inspector.readPageGeometry(
        selected.file,
        force: state.orientation,
      );
      if (geometry != null) return geometry;
    }
    if (state.pageSize.isFixed) {
      return _orient(
        PageGeometry(
          state.pageSize.portraitWidthMils!,
          state.pageSize.portraitHeightMils!,
        ),
        state.orientation,
      );
    }
    return _orient(PageGeometry.a4, state.orientation);
  }

  PageGeometry _orient(PageGeometry geometry, PageOrientation orientation) {
    final portrait = geometry.widthMils <= geometry.heightMils;
    switch (orientation) {
      case PageOrientation.portrait:
        return portrait ? geometry : PageGeometry(geometry.heightMils, geometry.widthMils);
      case PageOrientation.landscape:
        return portrait ? PageGeometry(geometry.heightMils, geometry.widthMils) : geometry;
    }
  }

  PageSizePreset _presetFromId(String? id) => PageSizePreset.values.firstWhere(
    (preset) => preset.id == id,
    orElse: () => PageSizePreset.matchDocument,
  );

  PageOrientation _orientationFromId(String? id) => PageOrientation.values.firstWhere(
    (value) => value.id == id,
    orElse: () => PageOrientation.portrait,
  );

  PdfColorMode _colorModeFromId(String? id) => PdfColorMode.values.firstWhere(
    (value) => value.id == id,
    orElse: () => PdfColorMode.color,
  );
}
