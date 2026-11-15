// Validates the starter pack with the real engine and removes anything the
// de-duplication index treats as a repeat.
//   dart run tool/check_pack.dart          (report only)
//   dart run tool/check_pack.dart --fix    (rewrite the pack without them)
import 'dart:convert';
import 'dart:io';

import 'package:hhkkll_core/hhkkll_core.dart';

void main(List<String> args) {
  final file = File('../content/seed_questions.json');
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final list = (raw['questions'] as List).cast<Map<String, dynamic>>();
  final idx = DedupIndex();
  final keep = <Map<String, dynamic>>[];
  var invalid = 0, dups = 0;
  for (final m in list) {
    final q = Question.fromJson(m);
    final problems = q.validate();
    if (problems.isNotEmpty) {
      invalid++;
      stdout.writeln('INVALID ${q.id}: $problems');
      continue;
    }
    final r = idx.tryAdd(q);
    if (r != null) {
      dups++;
      final other = list.firstWhere((e) => e['id'] == r.otherId);
      stdout.writeln('DUP ${r.code}${r.score == null ? '' : ' ${r.score!.toStringAsFixed(2)}'}\n'
          '   new: ${q.category.code} ${q.text} → ${q.answer}\n'
          '   old: ${other['category']} ${other['question']} → ${other['answer']}');
      continue;
    }
    keep.add(m);
  }
  final counts = <String, int>{};
  for (final m in keep) {
    counts.update(m['category'] as String, (v) => v + 1, ifAbsent: () => 1);
  }
  stdout.writeln('kept ${keep.length} / ${list.length} (invalid $invalid, duplicates $dups) $counts');
  if (args.contains('--fix')) {
    raw['questions'] = keep;
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(raw));
    stdout.writeln('rewrote ${file.path}');
  }
}
