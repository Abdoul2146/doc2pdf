import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/conversion_models.dart';
import '../converter_controller.dart';

class ConvertingView extends ConsumerWidget {
  const ConvertingView({super.key});

  static const _steps = <ConversionPhase>[
    ConversionPhase.detecting,
    ConversionPhase.parsing,
    ConversionPhase.rendering,
    ConversionPhase.paginating,
    ConversionPhase.printing,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(converterControllerProvider);
    final theme = Theme.of(context);

    final progress = state.progress;
    final phase = progress?.phase ?? ConversionPhase.detecting;
    final percent = progress?.percent ?? 0;
    final currentIndex = _steps.indexOf(phase);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(
                      value: percent <= 0 ? null : percent / 100,
                      strokeWidth: 6,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Converting…',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            phase.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    _StepRow(
                      label: _steps[i].label,
                      state: i < currentIndex
                          ? _StepState.done
                          : (i == currentIndex
                                ? _StepState.active
                                : _StepState.pending),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Keep the app open. Large documents can take a little longer.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, active, pending }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>()!;

    final Widget leading = switch (state) {
      _StepState.done => Icon(Icons.check_circle, size: 20, color: status.success),
      _StepState.active => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: theme.colorScheme.primary,
        ),
      ),
      _StepState.pending => Icon(
        Icons.circle_outlined,
        size: 20,
        color: theme.colorScheme.outline,
      ),
    };

    final color = switch (state) {
      _StepState.done => theme.colorScheme.onSurface,
      _StepState.active => theme.colorScheme.onSurface,
      _StepState.pending => theme.colorScheme.onSurfaceVariant,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: state == _StepState.active
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
