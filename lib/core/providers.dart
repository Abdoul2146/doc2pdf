import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/output_service.dart';
import '../data/services/render_pdf_channel.dart';
import '../data/services/settings_repository.dart';
import '../data/services/word_inspector.dart';

/// Overridden in `main()` once [SharedPreferences] has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

final renderPdfChannelProvider = Provider<RenderPdfChannel>(
  (ref) => const RenderPdfChannel(),
);

final wordInspectorProvider = Provider<WordInspector>(
  (ref) => const WordInspector(),
);

final outputServiceProvider = Provider<OutputService>(
  (ref) => const OutputService(),
);
