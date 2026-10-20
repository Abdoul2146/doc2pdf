import 'package:doc2pdf/core/ads/ad_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdService.canShow', () {
    final now = DateTime(2026, 1, 1, 12, 0);

    test('allows the first show when none has happened yet', () {
      expect(AdService.canShow(lastShownAt: null, now: now), isTrue);
    });

    test('blocks a show before the interval has elapsed', () {
      expect(
        AdService.canShow(
          lastShownAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('allows a show exactly at the interval boundary', () {
      expect(
        AdService.canShow(
          lastShownAt: now.subtract(AdService.minInterval),
          now: now,
        ),
        isTrue,
      );
    });

    test('allows a show after the interval has elapsed', () {
      expect(
        AdService.canShow(
          lastShownAt: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isTrue,
      );
    });

    test('honours a custom interval', () {
      expect(
        AdService.canShow(
          lastShownAt: now.subtract(const Duration(seconds: 30)),
          now: now,
          interval: const Duration(seconds: 20),
        ),
        isTrue,
      );
    });
  });
}
