import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:exercise_tracker_prototype/features/about/about_page.dart';

void main() {
  testWidgets('About displays installed metadata rather than hardcoded version',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutPage(
        loadPackageInfo: () async => PackageInfo(
          appName: 'ReTrace',
          packageName: 'com.example.exercise_tracker_prototype',
          version: '9.8.7',
          buildNumber: '42',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('גרסה'), findsOneWidget);
    expect(find.text('9.8.7'), findsOneWidget);
    expect(find.text('מספר בנייה'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('About handles metadata failure and allows retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: AboutPage(loadPackageInfo: () async {
        attempts++;
        if (attempts == 1) throw StateError('Platform unavailable');
        return PackageInfo(
          appName: 'ReTrace', packageName: 'retrace',
          version: '1.2.3', buildNumber: '99',
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('לא ניתן לטעון את פרטי הגרסה.'), findsOneWidget);
    await tester.tap(find.text('נסה שוב'));
    await tester.pumpAndSettle();
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
  });
}
