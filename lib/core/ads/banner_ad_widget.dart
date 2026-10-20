import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_config.dart';

/// Anchored adaptive banner. Sizes itself to the screen width, renders nothing
/// until an ad is loaded, and disposes cleanly.
///
/// Mount it in a `Scaffold`'s `bottomNavigationBar` rather than inside a
/// scrolling body: it then survives body swaps instead of reloading, and it is
/// never close enough to a primary action to invite an accidental click.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _hasAttemptedLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasAttemptedLoad) {
      _hasAttemptedLoad = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    if (!AdConfig.enabled || !mounted) return;

    AdSize? size;
    try {
      size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        MediaQuery.of(context).size.width.truncate(),
      );
    } catch (_) {
      // Fall through to the fixed banner size below.
    }
    size ??= const AdSize(width: 320, height: 50);

    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed to load: ${error.message}');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}
