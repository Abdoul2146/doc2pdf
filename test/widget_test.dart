import 'package:doc2pdf/app.dart';
import 'package:doc2pdf/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home screen shows the file picker prompt', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const Doc2PdfApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Word to PDF'), findsOneWidget);
    expect(find.text('Choose a Word file'), findsOneWidget);
    expect(find.text('Supports .docx and .doc'), findsOneWidget);
  });
}
