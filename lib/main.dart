import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/ads/ad_service.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Boots the ads SDK (UMP consent gate, then MobileAds init and the first
  // interstitial preload). Deliberately not awaited: startup must never wait on
  // the network, and every ad path is best-effort.
  unawaited(AdService.init());

  await pdfrxFlutterInitialize();

  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const Doc2PdfApp(),
    ),
  );
}
