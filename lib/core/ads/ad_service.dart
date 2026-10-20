import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Centralizes all AdMob behavior: the UMP consent gate, SDK initialization,
/// interstitial preloading, and a frequency cap on interstitial shows.
///
/// Mirrors the pattern used across the sibling apps, with one deliberate
/// addition: ads are strictly best-effort. Every entry point swallows failures,
/// because a device with no network must still convert documents normally.
class AdService {
  AdService._();

  /// Minimum gap between two interstitial shows.
  static const Duration minInterval = Duration(minutes: 3);

  static bool _initialized = false;

  static InterstitialAd? _interstitialAd;
  static int _loadAttempts = 0;
  static DateTime? _lastShownAt;

  /// Boots the SDK and preloads the first interstitial. Safe to call once per
  /// launch; later calls are no-ops. Never throws, never blocks startup.
  static Future<void> init() async {
    if (!AdConfig.enabled || _initialized) return;
    _initialized = true;
    try {
      await _requestConsent();
      await MobileAds.instance.initialize();
      loadInterstitialAd();
    } catch (_) {
      // Ads are best-effort: the app must work fully without them.
    }
  }

  /// UMP consent flow. Silent outside regulated regions; failures fall through
  /// so ad loading still proceeds (the SDK then serves limited ads).
  static Future<void> _requestConsent() async {
    try {
      final completer = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => completer.complete(),
        (_) => completer.complete(),
      );
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        // Fire-and-forget: the form is modal, init must not wait on it.
        ConsentForm.loadAndShowConsentFormIfRequired((_) {});
      }
    } catch (_) {
      // Best-effort: proceed without blocking init.
    }
  }

  /// Pure frequency-cap decision, kept static so it can be unit tested.
  static bool canShow({
    required DateTime? lastShownAt,
    required DateTime now,
    Duration interval = minInterval,
  }) {
    if (lastShownAt == null) return true;
    return now.difference(lastShownAt) >= interval;
  }

  /// Preloads one interstitial, retrying up to 3 times per cycle.
  static void loadInterstitialAd() {
    if (!AdConfig.enabled || !_initialized) return;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _loadAttempts = 0;
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('Interstitial failed to load: ${error.message}');
          _interstitialAd = null;
          _loadAttempts++;
          if (_loadAttempts < 3) loadInterstitialAd();
        },
      ),
    );
  }

  /// Shows the preloaded interstitial when the frequency cap allows, then
  /// invokes [onAdDismissed] on every path (shown, failed, capped, absent) so
  /// no caller can ever hang. Always preloads the next one after a show.
  static void showInterstitialAd({required VoidCallback onAdDismissed}) {
    final ad = _interstitialAd;
    if (!AdConfig.enabled ||
        ad == null ||
        !canShow(lastShownAt: _lastShownAt, now: DateTime.now())) {
      if (ad == null) loadInterstitialAd();
      onAdDismissed();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        _interstitialAd = null;
        _lastShownAt = DateTime.now();
        onAdDismissed();
        loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        ad.dispose();
        _interstitialAd = null;
        onAdDismissed();
        loadInterstitialAd();
      },
    );
    ad.show();
  }
}
