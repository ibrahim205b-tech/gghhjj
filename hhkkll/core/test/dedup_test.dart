import 'dart:convert';
import 'dart:io';

import 'package:hhkkll_core/hhkkll_core.dart';
import 'package:test/test.dart';

Question q(
  String id,
  String text,
  String answer, {
  Category cat = Category.whatDoYouKnow,
  List<String> acc = const [],
  String key = '',
  List<String> items = const [],
  List<String> clues = const [],
}) =>
    Question(
      id: id,
      category: cat,
      difficulty: Difficulty.expert,
      text: text,
      answer: answer,
      acceptedAnswers: acc,
      semanticKey: key,
      items: [for (final i in items) AuctionItem(name: i)],
      clues: clues,
      sources: const [Source(title: 't', url: 'https://example.org/x')],
      createdAt: DateTime.utc(2026),
      verification: const Verification(status: 'curated', method: 'test'),
    );

void main() {
  group('normalisation', () {
    test('diacritics, alef forms and Arabic digits are unified', () {
      expect(normalizeText('مَن سجَّل في نهائيّ ٢٠٠٠؟'),
          normalizeText('من سجل في نهائي 2000'));
      expect(normalizeText('أإآا'), 'اااا');
      expect(normalizeText('José Mourinho!'), 'jose mourinho');
    });

    test('definite article and conjunction prefixes are stemmed', () {
      expect(normalizeAnswer('البرازيل'), normalizeAnswer('برازيل'));
      expect(normalizeAnswer('والبرازيل'), normalizeAnswer('البرازيل'));
    });

    test('shared vectors match (contract with the TypeScript backend)', () {
      final data = jsonDecode(
        File('test/fixtures/normalize_vectors.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final v in (data['vectors'] as List).cast<Map<String, dynamic>>()) {
        final s = v['input'] as String;
        expect(normalizeText(s), v['normalized'], reason: s);
        expect(contentTokens(s), v['tokens'], reason: s);
        expect(normalizeAnswer(s), v['answer'], reason: s);
        expect(trigrams(s).length, v['trigram_count'], reason: s);
      }
    });
  });

  group('DedupIndex', () {
    test('rejects the exact same question and the same id', () {
      final idx = DedupIndex();
      expect(idx.tryAdd(q('1', 'من سجّل هدف الفوز في نهائي 2010؟', 'إنييستا')), isNull);
      expect(idx.check(q('1', 'نص آخر تماماً عن موضوع آخر', 'x'))!.code, 'same-id');
      expect(idx.check(q('2', 'من سجّل هدف الفوز في نهائي 2010؟', 'إنييستا'))!.code,
          'same-wording');
    });

    test('rejects a diacritics / punctuation variant of the same wording', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'من سجّل هدف الفوز في نهائي كأس العالم 2010؟', 'إنييستا'));
      final r = idx.check(q('2', 'مَن سَجَّلَ هدفَ الفوزِ في نهائيّ كأسِ العالمِ ٢٠١٠', 'إنييستا'));
      expect(r, isNotNull);
    });

    test('rejects a re-worded question with the same answer', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'من سجّل هدف إسبانيا الوحيد في نهائي كأس العالم 2010 أمام هولندا؟',
            'أندريس إنييستا', acc: ['Andrés Iniesta']));
      final r = idx.check(q('2', 'نهائي كأس العالم 2010 بين إسبانيا وهولندا حُسم بهدف وحيد، من صاحبه؟',
          'Andres Iniesta'));
      expect(r, isNotNull);
      expect(r!.code, 'same-answer-similar-question');
    });

    test('rejects the same fact moved to another section (semantic key)', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'من سجّل الهدف الذهبي في نهائي يورو 2000؟', 'تريزيغيه',
            key: 'euro-2000-final|golden-goal-scorer'));
      final r = idx.check(q('2', 'لاعب فرنسي حسم لقب القارة العجوز بهدف قاتل في روتردام',
          'David Trezeguet',
          cat: Category.buzzer, key: 'Euro 2000 Final | Golden Goal Scorer'));
      expect(r!.code, 'same-fact');
    });

    test('rejects a who-am-i riddle about the same person', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'من أنا؟', 'لويس فيغو', cat: Category.whoAmI,
            acc: ['Luís Figo'], clues: ['a', 'b', 'c']));
      final r = idx.check(q('2', 'خمّن اللاعب', 'Luis Figo', cat: Category.whoAmI,
          clues: ['x', 'y', 'z']));
      expect(r!.code, 'same-riddle-subject');
    });

    test('rejects an auction with the same answer set', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'كم منتخباً فاز بكأس العالم؟', '8', cat: Category.auction,
            items: ['البرازيل', 'ألمانيا', 'إيطاليا', 'الأرجنتين', 'فرنسا', 'الأوروغواي', 'إنجلترا', 'إسبانيا']));
      final r = idx.check(q('2', 'سمِّ أبطال المونديال عبر التاريخ', '8 منتخبات',
          cat: Category.auction,
          items: ['برازيل', 'المانيا', 'ايطاليا', 'الارجنتين', 'فرنسا', 'الاوروغواي', 'انجلترا']));
      expect(r!.code, 'same-answer-set');
    });

    test('accepts different facts that look alike (different year)', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'من فاز بالكرة الذهبية عام 2004؟', 'شيفتشينكو'));
      expect(idx.check(q('2', 'من فاز بالكرة الذهبية عام 2006؟', 'كانافارو')), isNull);
    });

    test('accepts the same answer for a different year', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'من بطل الدوري الإنجليزي الممتاز موسم 2007-2008؟', 'مانشستر يونايتد'));
      expect(idx.check(q('2', 'من بطل الدوري الإنجليزي الممتاز موسم 2008-2009؟', 'مانشستر يونايتد')), isNull);
    });

    test('accepts different questions that share an answer', () {
      final idx = DedupIndex()
        ..addQuestion(q('1', 'أمام أي نادٍ فاز ستيوا بوخارست بنهائي 1986 بركلات الترجيح؟', 'برشلونة'));
      expect(
          idx.check(q('2', 'من الفريق الذي هزمه بنفيكا 3-2 في نهائي كأس أوروبا 1961؟', 'برشلونة')),
          isNull);
    });

    test('serialises and restores', () {
      final idx = DedupIndex()..addQuestion(q('1', 'من سجّل هدف الفوز في نهائي 2010؟', 'إنييستا'));
      final copy = DedupIndex()..loadJson(jsonDecode(jsonEncode(idx.toJson())) as List);
      expect(copy.check(q('9', 'من سجّل هدف الفوز في نهائي 2010؟', 'x')), isNotNull);
    });
  });

  group('seed pack', () {
    final raw = jsonDecode(File('../content/seed_questions.json').readAsStringSync())
        as Map<String, dynamic>;
    final questions = (raw['questions'] as List)
        .map((e) => Question.fromJson((e as Map).cast()))
        .toList();

    test('every question is structurally valid and has a source', () {
      for (final x in questions) {
        expect(x.validate(), isEmpty, reason: x.id);
        expect(x.verification.status, 'curated',
            reason: 'hand-written questions must not claim machine verification');
      }
    });

    test('covers all four sections', () {
      for (final c in Category.values) {
        expect(questions.where((x) => x.category == c).length, greaterThanOrEqualTo(9),
            reason: c.code);
      }
    });

    test('contains no duplicates according to the engine itself', () {
      final idx = DedupIndex();
      for (final x in questions) {
        expect(idx.tryAdd(x), isNull, reason: x.id);
      }
    });

    test('round-trips through JSON', () {
      for (final x in questions) {
        final y = Question.fromJson(jsonDecode(jsonEncode(x.toJson())) as Map<String, dynamic>);
        expect(y.textFingerprint, x.textFingerprint);
        expect(y.semanticFingerprint, x.semanticFingerprint);
      }
    });
  });
}
