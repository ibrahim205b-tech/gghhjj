// Regenerates test/fixtures/normalize_vectors.json — the shared contract
// between the Dart (app) and TypeScript (backend) de-duplication code.
// Run: dart run tool/gen_vectors.dart
import 'dart:convert';
import 'dart:io';

import 'package:hhkkll_core/hhkkll_core.dart';

const inputs = [
  'من سجّل الهدف الذهبي في نهائي أمم أوروبا 2000؟',
  'مَن سجَّل الهدفَ الذهبيَّ في نهائيّ أمم أوروبا ٢٠٠٠؟',
  'والبرازيل فازت بكأس العالم',
  'Who scored the golden goal in the Euro 2000 final?',
  'José Mourinho — Inter, Porto & Chelsea!',
  'إبراهيم ـ آدم ـ أحمد ـ مدرسة ـ مستشفى',
  'Atatürk Olympic Stadium',
  'Ole Gunnar Solskjær',
  'للاعبين في الدوري الإسباني',
  'كم لاعباً تستطيع تسمية من منتخب البرازيل شاركوا في كأس العالم؟',
];

void main() {
  final vectors = [
    for (final s in inputs)
      {
        'input': s,
        'normalized': normalizeText(s),
        'tokens': contentTokens(s),
        'answer': normalizeAnswer(s),
        'numbers': (numberTokens(s).toList()..sort()),
        'trigram_count': trigrams(s).length,
      },
  ];
  final pairs = [
    for (var i = 0; i < inputs.length; i++)
      for (var j = i + 1; j < inputs.length; j++)
        {'a': i, 'b': j, 'similarity': textSimilarity(inputs[i], inputs[j])},
  ];
  File('test/fixtures/normalize_vectors.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({'vectors': vectors, 'pairs': pairs}),
  );
  stdout.writeln('wrote ${vectors.length} vectors, ${pairs.length} pairs');
}
