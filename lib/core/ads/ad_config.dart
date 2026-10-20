import 'package:flutter/foundation.dart';

/// AdMob inventory for doc2pdf.
///
/// Everything here is currently Google's public *sample* inventory: it serves
/// test ads everywhere and can never generate invalid traffic or revenue.
/// Before shipping, create the app + ad units for `com.magnatrus.doc2pdf` in the
/// AdMob console (publisher `ca-app-pub-2321249943983804`) and replace the three
/// values below — the app ID lives in `AndroidManifest.xml`, not here.
class AdConfig {
  const AdConfig._();

  /// Master switch. Flip to `false` to ship a build with no ads at all without
  /// touching any call site.
  static const bool enabled = true;

  /// TODO(release): replace with the real doc2pdf banner unit ID.
  static const String _bannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  /// TODO(release): replace with the real doc2pdf interstitial unit ID.
  static const String _interstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  /// Debug builds always use the sample inventory so a dev tap can never
  /// register as a real click on a live account.
  static String get bannerAdUnitId =>
      kDebugMode ? _testBannerAdUnitId : _bannerAdUnitId;

  static String get interstitialAdUnitId =>
      kDebugMode ? _testInterstitialAdUnitId : _interstitialAdUnitId;

  static const String _testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
}
