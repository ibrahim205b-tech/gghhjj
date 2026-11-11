// Renders screenshots of key screens with the real Arabic fonts.
// Run: flutter test tool/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/app_test.dart' as t;

Future<void> loadFonts() async {
  for (final (family, files) in [
    ('NotoKufiArabic', ['NotoKufiArabic-Regular.ttf', 'NotoKufiArabic-Bold.ttf']),
    ('NotoSans', ['NotoSans-Regular.ttf', 'NotoSans-Bold.ttf']),
    ('MaterialIcons', ['__icons__']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      final path = f == '__icons__'
          ? '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
          : 'assets/fonts/$f';
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final (name, size) in [('phone_dashboard', const Size(412, 915)), ('tablet_dashboard', const Size(1280, 800))]) {
    testWidgets(name, (tester) async {
      await t.launch(tester, size);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/screenshots/$name.png'));
    });
  }
  testWidgets('phone_collect', (tester) async {
    await t.launch(tester, const Size(412, 915), collector: true);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/screenshots/phone_collector.png'));
  });
}
