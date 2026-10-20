import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ads/ad_service.dart';
import '../../core/ads/banner_ad_widget.dart';
import '../../core/theme/app_theme.dart';
import '../converter/converter_controller.dart';
import '../converter/widgets/converting_view.dart';
import '../result/widgets/result_view.dart';
import '../settings/settings_screen.dart';
import 'widgets/home_content.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(converterControllerProvider);

    // One interstitial per successful conversion. The result screen is already
    // on screen by then, and AdService caps shows to one per few minutes, so a
    // batch of quick conversions cannot turn into an ad storm.
    ref.listen<ConverterState>(converterControllerProvider, (previous, next) {
      final justSucceeded =
          next.status == ConversionStatus.success &&
          next.result != null &&
          previous?.status != ConversionStatus.success;
      if (justSucceeded) {
        AdService.showInterstitialAd(onAdDismissed: () {});
      }
    });

    final Widget body;
    final String bodyKey;
    if (state.isConverting) {
      body = const ConvertingView();
      bodyKey = 'converting';
    } else if (state.status == ConversionStatus.success && state.result != null) {
      body = ResultView(result: state.result!);
      bodyKey = 'result';
    } else {
      body = const HomeContent();
      bodyKey = 'home';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('doc2pdf'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(bodyKey), child: body),
        ),
      ),
      // Lives on the scaffold, not inside the body: it survives picker/result/
      // progress swaps instead of reloading, and it never sits next to the
      // Convert, Preview or Share buttons.
      bottomNavigationBar: const BannerAdWidget(),
    );
  }
}
