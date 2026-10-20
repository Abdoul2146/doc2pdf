import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/conversion_models.dart';
import '../../converter/converter_controller.dart';

class HomeContent extends ConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(converterControllerProvider);
    final controller = ref.read(converterControllerProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        _Hero(),
        const SizedBox(height: AppSpacing.xl),
        if (state.file == null)
          _PickCard(onTap: controller.pickFile)
        else
          _FileSummaryCard(
            file: state.file!,
            onReplace: controller.pickFile,
            onClear: controller.clearFile,
          ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ErrorCard(message: state.errorMessage!),
        ],
        if (state.file?.format.isLegacy ?? false) ...[
          const SizedBox(height: AppSpacing.lg),
          const _LegacyNotice(),
        ],
        if (state.file != null) ...[
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('Output settings'),
          const SizedBox(height: AppSpacing.md),
          _OptionsCard(state: state, controller: controller),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: state.canConvert ? controller.convert : null,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Convert to PDF'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              'Conversion runs entirely on your device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Word to PDF',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Turn .docx and .doc files into clean PDFs — right on your device.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xxl,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.upload_file_outlined,
                  size: 30,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Choose a Word file',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Supports .docx and .doc',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileSummaryCard extends StatelessWidget {
  const _FileSummaryCard({
    required this.file,
    required this.onReplace,
    required this.onClear,
  });

  final SelectedFile file;
  final VoidCallback onReplace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>()!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.description_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _Badge(
                        label: file.format.label,
                        color: file.format.isLegacy
                            ? status.warning
                            : status.success,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        formatBytes(file.sizeBytes),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onReplace,
              icon: const Icon(Icons.swap_horiz_outlined),
              tooltip: 'Replace file',
            ),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_outlined),
              tooltip: 'Remove file',
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.state, required this.controller});

  final ConverterState state;
  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final isDocx = state.file?.format == WordFormat.docx;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Page size',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownMenu<PageSizePreset>(
              initialSelection: state.pageSize,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: true,
              dropdownMenuEntries: PageSizePreset.values
                  .where((preset) => preset.isFixed || isDocx)
                  .map(
                    (preset) => DropdownMenuEntry(
                      value: preset,
                      label: preset.label,
                    ),
                  )
                  .toList(),
              onSelected: (value) {
                if (value != null) controller.setPageSize(value);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Orientation',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PageOrientation>(
                segments: PageOrientation.values
                    .map(
                      (value) => ButtonSegment(
                        value: value,
                        label: Text(value.label),
                        icon: Icon(
                          value == PageOrientation.portrait
                              ? Icons.crop_portrait
                              : Icons.crop_landscape,
                        ),
                      ),
                    )
                    .toList(),
                selected: {state.orientation},
                onSelectionChanged: (selection) =>
                    controller.setOrientation(selection.first),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Colour',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PdfColorMode>(
                segments: PdfColorMode.values
                    .map(
                      (value) => ButtonSegment(
                        value: value,
                        label: Text(value.label),
                        icon: Icon(
                          value == PdfColorMode.color
                              ? Icons.palette_outlined
                              : Icons.contrast,
                        ),
                      ),
                    )
                    .toList(),
                selected: {state.colorMode},
                onSelectionChanged: (selection) =>
                    controller.setColorMode(selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyNotice extends StatelessWidget {
  const _LegacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: status.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Legacy .doc files are rebuilt from their content, so layout and '
              'styling may differ slightly from the original. For best results, '
              're-save the file as .docx first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
