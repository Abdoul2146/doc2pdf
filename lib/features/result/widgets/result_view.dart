import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/conversion_models.dart';
import '../../converter/converter_controller.dart';
import '../../preview/pdf_preview_screen.dart';

class ResultView extends ConsumerWidget {
  const ResultView({super.key, required this.result});

  final ConversionResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>()!;
    final controller = ref.read(converterControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: status.successContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 44, color: status.success),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'PDF ready',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          result.savedName ?? result.fileName,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (result.savedDisplayPath != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Saved to ${result.savedDisplayPath}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (result.saveWarning != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: status.warningContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: status.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    result.saveWarning!,
                    style: theme.textTheme.bodySmall?.copyWith(color: status.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Pages',
                    value: '${result.pageCount}',
                  ),
                ),
                _divider(theme),
                Expanded(
                  child: _Stat(
                    label: 'Size',
                    value: formatBytes(result.sizeBytes),
                  ),
                ),
                _divider(theme),
                Expanded(
                  child: _Stat(
                    label: 'Time',
                    value: formatDuration(result.duration),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (result.format.isLegacy) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Converted from a legacy .doc file — check the result for layout differences.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfPreviewScreen(
                path: result.outputPath,
                title: result.savedName ?? result.fileName,
              ),
            ),
          ),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => _share(context, result),
          icon: const Icon(Icons.ios_share),
          label: const Text('Share PDF'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton.icon(
          onPressed: controller.dismissResult,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Convert another file'),
        ),
      ],
    );
  }

  Widget _divider(ThemeData theme) => Container(
    width: 1,
    height: 36,
    color: theme.colorScheme.outlineVariant,
  );

  Future<void> _share(BuildContext context, ConversionResult result) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.outputPath, mimeType: 'application/pdf')],
          subject: result.savedName ?? result.fileName,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share the file: $error')),
        );
      }
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
