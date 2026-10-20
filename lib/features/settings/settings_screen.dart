import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/output_service.dart';
import '../converter/converter_controller.dart';
import 'theme_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final converter = ref.watch(converterControllerProvider);
    final converterController = ref.read(converterControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).setMode(selection.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader('Conversion'),
          SwitchListTile(
            value: converter.keepScreenOn,
            onChanged: converterController.setKeepScreenOn,
            title: const Text('Keep screen on while converting'),
            subtitle: const Text(
              'Prevents the screen from sleeping during long conversions.',
            ),
            secondary: const Icon(Icons.screen_lock_rotation_outlined),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader('Storage'),
          const _OutputFolderTile(),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your documents stay private'),
            subtitle: Text(
              'Conversion happens entirely on this device — your files are never '
              'uploaded. Network access is used only to load ads.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.campaign_outlined),
            title: Text('Ad-supported'),
            subtitle: Text(
              'doc2pdf is free and shows ads. Ads never see the files you convert.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.verified_outlined),
            title: Text('Document fidelity'),
            subtitle: Text(
              '.docx files are rendered with bundled metric-compatible fonts '
              '(Carlito, Caladea, Arimo, Tinos, Cousine â€” SIL OFL). Legacy .doc '
              'files are rebuilt best-effort.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              'doc2pdf',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputFolderTile extends StatelessWidget {
  const _OutputFolderTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: const Text('Saved to'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            OutputService.sharedLocation,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Phone storage › Documents › ${OutputService.folderName} — visible in '
            'any file manager.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

