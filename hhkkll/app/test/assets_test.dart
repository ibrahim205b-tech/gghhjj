import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled starter pack is identical to hhkkll/content', () {
    expect(File('assets/data/seed_questions.json').readAsStringSync(),
        File('../content/seed_questions.json').readAsStringSync(),
        reason: 'run: cp ../content/seed_questions.json assets/data/');
  });

  test('every sound effect referenced by the app exists', () {
    final src = File('lib/services/sound.dart').readAsStringSync();
    final names = RegExp(r"\('([a-z_]+)'\)").allMatches(src).map((m) => m.group(1)!);
    expect(names.length, greaterThan(15));
    for (final n in names) {
      expect(File('assets/sounds/$n.wav').existsSync(), isTrue, reason: n);
    }
  });
}
