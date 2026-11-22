import '../data/models.dart';

/// Normalises Arabic text for comparing short answers: removes diacritics,
/// tatweel, punctuation; unifies alef/ya/ta-marbuta forms; trims spaces.
String normalizeAnswer(String s) {
  var t = s.trim().toLowerCase();
  t = t.replaceAll(RegExp(r'[ً-ْٰـ]'), '');
  t = t.replaceAll(RegExp('[إأآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}\s.\-/]', unicode: true), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

class AnswerInput {
  AnswerInput({this.optionId, this.text});
  final String? optionId;
  final String? text;
  bool get isEmpty => optionId == null && (text == null || text!.trim().isEmpty);
}

bool isCorrect(Question q, AnswerInput a) {
  if (a.isEmpty) return false;
  switch (q.type) {
    case QuestionType.multipleChoice:
    case QuestionType.trueFalse:
      return q.options.any((o) => o.id == a.optionId && o.isCorrect);
    case QuestionType.shortAnswer:
      final accepted = (q.answerText ?? '').split('|').map(normalizeAnswer).where((e) => e.isNotEmpty);
      return accepted.contains(normalizeAnswer(a.text ?? ''));
  }
}

class QuizResult {
  QuizResult(this.total, this.correct);
  final int total;
  final int correct;
  double get percent => total == 0 ? 0 : correct * 100 / total;
}

QuizResult grade(List<Question> questions, Map<String, AnswerInput> answers) =>
    QuizResult(questions.length, questions.where((q) => isCorrect(q, answers[q.id] ?? AnswerInput())).length);
