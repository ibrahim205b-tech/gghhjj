/// Text normalisation used by the de-duplication fingerprints.
///
/// The same rules are implemented in the backend (`backend/src/dedup.ts`); the
/// shared test vectors in `core/test/fixtures/normalize_vectors.json` keep the
/// two implementations in lock-step.
library;

const _arabicDiacritics =
    r'[ؐ-ًؚ-ٰٟۖ-ۭـ]';

const Map<String, String> _charMap = {
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', //
  'ى': 'ي', 'ئ': 'ي', 'ؤ': 'و', 'ة': 'ه',
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'ç': 'c', 'č': 'c', 'ć': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n', 'ń': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'š': 's', 'ş': 's', 'ș': 's', 'ž': 'z', 'ğ': 'g',
  'ł': 'l', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'đ': 'd', 'ı': 'i', 'ř': 'r', 'ț': 't', 'ţ': 't',
};

/// Function words that carry no meaning for duplicate detection.
const Set<String> stopwords = {
  // Arabic (already normalised form)
  'من', 'في', 'على', 'الي', 'عن', 'ما', 'ماذا', 'هو', 'هي', 'كم', 'اي',
  'الذي', 'التي', 'الذين', 'مع', 'او', 'و', 'هل', 'كان', 'كانت', 'تم', 'قد',
  'لقد', 'ثم', 'بعد', 'قبل', 'حتي', 'منذ', 'هذا', 'هذه', 'ذلك', 'تلك', 'لم',
  'لا', 'ان', 'انه', 'به', 'بها', 'له', 'لها', 'عام', 'سنه', 'موسم',
  'اذكر', 'سم', 'سمي', 'تستطيع', 'تسميه', 'تسميتهم', 'لاعبا', 'لاعب', 'لاعبين',
  'اول', 'اخر', 'مره', 'نسخه', 'بطوله',
  // English
  'the', 'a', 'an', 'of', 'in', 'on', 'at', 'to', 'for', 'by', 'with', 'and',
  'or', 'is', 'was', 'were', 'which', 'who', 'what', 'how', 'many', 'did',
  'does', 'from', 'that', 'this', 'name', 'player', 'players', 'season',
  'first', 'last', 'year',
};

/// Lower-cases, strips Arabic diacritics/tatweel, unifies alef/ya/ta-marbuta,
/// folds Latin accents, removes punctuation and collapses whitespace.
String normalizeText(String input) {
  var s = input.toLowerCase().replaceAll(RegExp(_arabicDiacritics), '');
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    b.write(_charMap[ch] ?? ch);
  }
  s = b.toString();
  // Anything that is not a letter or digit becomes a space.
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return s.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Strips common Arabic clitics so "والبرازيل" / "البرازيل" / "برازيل" match.
String stemToken(String t) {
  var s = t;
  if (s.length > 4 && (s.startsWith('وال') || s.startsWith('بال') ||
      s.startsWith('فال') || s.startsWith('كال'))) {
    s = s.substring(3);
  } else if (s.length > 3 && s.startsWith('لل')) {
    // "للاعبين" = لِ + اللاعبين → لاعبين ; "للدوري" = لِ + الدوري → دوري
    s = s[2] == 'ا' ? s.substring(1) : s.substring(2);
  } else if (s.length > 3 && s.startsWith('ال')) {
    s = s.substring(2);
  } else if (s.length > 4 && s.startsWith('و') && !s.startsWith('وو')) {
    s = s.substring(1);
  }
  return s;
}

/// Meaningful tokens of a text: normalised, stemmed, stop-words removed.
List<String> contentTokens(String input) {
  final out = <String>[];
  for (final raw in normalizeText(input).split(' ')) {
    if (raw.isEmpty) continue;
    if (stopwords.contains(raw)) continue;
    final t = stemToken(raw);
    if (t.isEmpty || stopwords.contains(t)) continue;
    out.add(t);
  }
  return out;
}

/// Canonical form of an answer / entity name ("ال" removed, no spaces).
String normalizeAnswer(String input) =>
    contentTokens(input).isEmpty
        ? normalizeText(input).replaceAll(' ', '')
        : contentTokens(input).join();

/// Character trigram set over the content tokens.
Set<String> trigrams(String input) {
  final joined = ' ${contentTokens(input).join(' ')} ';
  final out = <String>{};
  for (var i = 0; i + 3 <= joined.length; i++) {
    out.add(joined.substring(i, i + 3));
  }
  return out;
}

/// The numbers mentioned in a text (years, scores, counts). Two questions
/// that differ only in a year ask about different facts.
Set<String> numberTokens(String input) => RegExp(r'\d+')
    .allMatches(normalizeText(input))
    .map((m) => m.group(0)!)
    .toSet();

double jaccard<T>(Set<T> a, Set<T> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  return inter / (a.length + b.length - inter);
}

/// Similarity of two question texts in [0, 1].
double textSimilarity(String a, String b) => jaccard(trigrams(a), trigrams(b));
