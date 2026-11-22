"""Arabic text preparation for speech synthesis.

Design rules (see docs/ARABIC_TEXT.md):
  * Never change the meaning of the text and never drop existing diacritics.
  * Never invent diacritics here (an engine may diacritize on its own; that is
    an engine option, not something this module does).
  * Turn things a TTS model would otherwise read strangely into plain words:
    phone numbers, long digit runs, dates, percentages, a few common symbols.
  * Keep punctuation that carries prosody (، . ؟ ! ؛ :) and remove symbols
    that a model might try to pronounce (* # _ ~ | < > [ ] { } emojis ...).
  * Split long text on sentence boundaries, then clause boundaries, then
    word boundaries - never inside a word - preserving order.
"""

from __future__ import annotations

import re
import unicodedata

# ---------------------------------------------------------------------------
# Character tables
# ---------------------------------------------------------------------------

ARABIC_INDIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
TASHKEEL_RE = re.compile(r"[ً-ْٰ]")
TATWEEL = "ـ"
ARABIC_LETTER_RE = re.compile(r"[ء-ي]")

_ONES = ["صفر", "واحد", "اثنان", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة"]
_TEENS = {
    10: "عشرة", 11: "أحد عشر", 12: "اثنا عشر", 13: "ثلاثة عشر", 14: "أربعة عشر",
    15: "خمسة عشر", 16: "ستة عشر", 17: "سبعة عشر", 18: "ثمانية عشر", 19: "تسعة عشر",
}
_TENS = {2: "عشرون", 3: "ثلاثون", 4: "أربعون", 5: "خمسون", 6: "ستون", 7: "سبعون", 8: "ثمانون", 9: "تسعون"}
_HUNDREDS = {1: "مئة", 2: "مئتان", 3: "ثلاثمئة", 4: "أربعمئة", 5: "خمسمئة",
             6: "ستمئة", 7: "سبعمئة", 8: "ثمانمئة", 9: "تسعمئة"}
# (singular, dual, plural 3-10, accusative singular for 11+)
_SCALES = [
    (10**9, ("مليار", "ملياران", "مليارات", "مليارًا")),
    (10**6, ("مليون", "مليونان", "ملايين", "مليونًا")),
    (10**3, ("ألف", "ألفان", "آلاف", "ألفًا")),
]
# Spoken forms for digits read one by one (phone numbers): "اثنين" reads more
# naturally than "اثنان" when digits are listed.
_DIGIT_WORDS = ["صفر", "واحد", "اثنين", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة"]

MONTHS = [
    # Gregorian (Levantine/Iraqi names and Egyptian/Gulf names)
    "كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران", "تموز", "آب", "أيلول",
    "تشرين الأول", "تشرين الثاني", "كانون الأول",
    "يناير", "فبراير", "مارس", "أبريل", "إبريل", "مايو", "يونيو", "يوليو", "أغسطس",
    "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
]
_MONTHS_BY_NUMBER = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو",
                     "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
_MONTH_ALT = "|".join(sorted((re.escape(m) for m in MONTHS), key=len, reverse=True))


# ---------------------------------------------------------------------------
# Numbers
# ---------------------------------------------------------------------------

def _below_100(n: int) -> str:
    if n < 10:
        return _ONES[n]
    if n < 20:
        return _TEENS[n]
    tens, ones = divmod(n, 10)
    if ones == 0:
        return _TENS[tens]
    return f"{_ONES[ones]} و{_TENS[tens]}"


def _below_1000(n: int) -> str:
    hundreds, rest = divmod(n, 100)
    parts = []
    if hundreds:
        parts.append(_HUNDREDS[hundreds])
    if rest:
        parts.append(_below_100(rest))
    return " و".join(parts)


def number_to_words(n: int) -> str:
    """Modern Standard Arabic cardinal (nominative), 0 .. 999,999,999,999."""
    if n < 0:
        return "سالب " + number_to_words(-n)
    if n == 0:
        return "صفر"
    if n >= 10**12:
        return digits_to_words(str(n))
    parts = []
    for value, (one, two, plural, acc) in _SCALES:
        count, n = divmod(n, value)
        if not count:
            continue
        if count == 1:
            parts.append(one)
        elif count == 2:
            parts.append(two)
        elif 3 <= count <= 10:
            parts.append(f"{_below_100(count)} {plural}")
        else:
            parts.append(f"{_below_1000(count)} {acc}")
    if n:
        parts.append(_below_1000(n))
    return " و".join(parts)


def year_to_words(y: int) -> str:
    """Years are read as commonly spoken: 2026 -> ألفين وستة وعشرين."""
    if 2000 <= y <= 2099:
        rest = y - 2000
        if rest == 0:
            return "ألفين"
        return "ألفين و" + _oblique(_below_100(rest) if rest < 100 else _below_1000(rest))
    if 1900 <= y <= 1999:
        return "ألف وتسعمئة و" + _oblique(_below_100(y - 1900)) if y != 1900 else "ألف وتسعمئة"
    return number_to_words(y)


def _oblique(words: str) -> str:
    """Nominative -> genitive/accusative endings used in dates and years."""
    words = re.sub(r"ون\b", "ين", words)
    words = words.replace("اثنان", "اثنين").replace("اثنا عشر", "اثني عشر")
    return words


def day_to_words(d: int) -> str:
    return _oblique(_below_100(d))


def digits_to_words(digits: str) -> str:
    return " ".join(_DIGIT_WORDS[int(c)] for c in digits if c.isdigit())


# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

_PHONE_RE = re.compile(r"(?<!\d)(\+?\d[\d\- ]{5,}\d)(?!\d)")
_DATE_NUMERIC_RE = re.compile(r"(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})(?!\d)")
_DATE_TEXT_RE = re.compile(rf"(?<!\d)(\d{{1,2}})\s+({_MONTH_ALT})\s+(\d{{4}})(?!\d)")
_MONTH_YEAR_RE = re.compile(rf"({_MONTH_ALT})\s+(\d{{4}})(?!\d)")
_TIME_RE = re.compile(r"(?<!\d)(\d{1,2}):(\d{2})(?!\d)")
_PERCENT_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s*[%٪]")
_DECIMAL_RE = re.compile(r"(?<!\d)(\d+)[.,٫](\d+)(?!\d)")
_THOUSANDS_RE = re.compile(r"(?<!\d)(\d{1,3}(?:,\d{3})+)(?!\d)")
_INT_RE = re.compile(r"\d+")
_SYMBOLS_DROP_RE = re.compile(r"[*#_~|<>\[\]{}^`\\=]+")
_SPACES_RE = re.compile(r"[ \t ​-‏‪-‮⁦-⁩]+")
_ABBREVIATIONS = {
    r"\bد\.\s*": "دكتور ",
    r"\bم\.\s*": "مهندس ",
    r"\bأ\.\s*": "أستاذ ",
    r"\bص\.\s*ب\.?": "صندوق بريد",
    r"\bإلخ\b\.?": "إلى آخره",
    r"\bالخ\b\.?": "إلى آخره",
}
_SYMBOL_WORDS = {
    "&": " و ",
    "+": " زائد ",
    "@": " آت ",
    "$": " دولار ",
    "€": " يورو ",
}


def _group_digits(digits: str) -> list[str]:
    """Group digits the way people dictate them (11-digit mobile: 4-3-4)."""
    if len(digits) == 11:
        return [digits[:4], digits[4:7], digits[7:]]
    if len(digits) <= 4:
        return [digits]
    groups = [digits[i:i + 3] for i in range(0, len(digits), 3)]
    if len(groups[-1]) == 1:  # avoid a lonely trailing digit
        last = groups.pop()
        groups[-1] = groups[-1] + last
    return groups


def _phone(m: re.Match) -> str:
    raw = m.group(1)
    digits = re.sub(r"\D", "", raw)
    # A phone number / ID: starts with 0 or +, or is long. Short plain numbers
    # are left to the cardinal reader.
    if raw.startswith("+") or digits.startswith("0") or len(digits) >= 8:
        prefix = "زائد " if raw.startswith("+") else ""
        return " " + prefix + "، ".join(digits_to_words(g) for g in _group_digits(digits)) + " "
    return raw


def _date_numeric(m: re.Match) -> str:
    day, month, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if 1 <= month <= 12 and 1 <= day <= 31:
        return f"{day_to_words(day)} {_MONTHS_BY_NUMBER[month - 1]} {year_to_words(year)}"
    return m.group(0)


def _date_text(m: re.Match) -> str:
    return f"{day_to_words(int(m.group(1)))} {m.group(2)} {year_to_words(int(m.group(3)))}"


def _time(m: re.Match) -> str:
    h, mnt = int(m.group(1)), int(m.group(2))
    if h > 23 or mnt > 59:
        return m.group(0)
    hour = "الساعة " + _below_100(h)
    if mnt == 0:
        return hour
    if mnt == 30:
        return hour + " والنصف"
    if mnt == 15:
        return hour + " والربع"
    return f"{hour} و{_below_100(mnt)} دقيقة"


def _decimal(m: re.Match) -> str:
    whole, frac = m.group(1), m.group(2)
    return f"{number_to_words(int(whole))} فاصلة {number_to_words(int(frac)) if not frac.startswith('0') else digits_to_words(frac)}"


def _percent(m: re.Match) -> str:
    val = m.group(1).replace(",", ".")
    if "." in val:
        a, b = val.split(".", 1)
        spoken = f"{number_to_words(int(a))} فاصلة {digits_to_words(b)}"
    else:
        spoken = number_to_words(int(val))
    return f"{spoken} بالمئة"


def _integer(m: re.Match) -> str:
    s = m.group(0)
    if len(s) > 1 and s.startswith("0"):
        return digits_to_words(s)
    if len(s) > 12:
        return digits_to_words(s)
    return number_to_words(int(s))


def normalize_arabic(text: str, *, keep_tashkeel: bool = True, expand_numbers: bool = True) -> str:
    """Prepare text for a TTS engine without changing its meaning."""
    if not text:
        return ""
    t = unicodedata.normalize("NFC", text)
    t = t.translate(ARABIC_INDIC_DIGITS)
    t = t.replace(TATWEEL, "")
    if not keep_tashkeel:
        t = TASHKEEL_RE.sub("", t)
    # Unify punctuation (keep prosody marks, Arabic forms preferred).
    t = (t.replace("?", "؟").replace(";", "؛")
          .replace("“", "\"").replace("”", "\"").replace("«", "\"").replace("»", "\"")
          .replace("…", "...").replace("–", "، ").replace("—", "، "))
    t = re.sub(r"(?<=[؀-ۿ\s]),(?=[؀-ۿ\s])", "،", t)
    t = re.sub(r"\.{3,}", "...", t)
    t = re.sub(r"([!؟])\1+", r"\1", t)
    # Remove URLs/emails: reading them aloud is almost never wanted.
    t = re.sub(r"https?://\S+|www\.\S+", " ", t)
    t = re.sub(r"\S+@\S+\.\S+", " ", t)
    for pattern, repl in _ABBREVIATIONS.items():
        t = re.sub(pattern, repl, t)
    if expand_numbers:
        t = _DATE_NUMERIC_RE.sub(_date_numeric, t)
        t = _DATE_TEXT_RE.sub(_date_text, t)
        t = _MONTH_YEAR_RE.sub(lambda m: f"{m.group(1)} {year_to_words(int(m.group(2)))}", t)
        t = _TIME_RE.sub(_time, t)
        t = _PERCENT_RE.sub(_percent, t)
        t = _PHONE_RE.sub(_phone, t)
        t = _THOUSANDS_RE.sub(lambda m: number_to_words(int(m.group(1).replace(",", ""))), t)
        t = _DECIMAL_RE.sub(_decimal, t)
        t = _INT_RE.sub(_integer, t)
    for sym, word in _SYMBOL_WORDS.items():
        t = t.replace(sym, word)
    t = _SYMBOLS_DROP_RE.sub(" ", t)
    # Drop emoji / pictographs and other symbol categories the model can't say.
    t = "".join(ch for ch in t if unicodedata.category(ch) not in ("So", "Sk", "Co", "Cs"))
    t = t.replace("\"", "").replace("(", "، ").replace(")", "، ")
    t = _SPACES_RE.sub(" ", t)
    t = re.sub(r"\s*\n\s*", "\n", t)
    t = re.sub(r"\s+([،.؟!؛:])", r"\1", t)
    t = re.sub(r"([،؛])(?:\s*[،؛])+", r"\1", t)
    t = re.sub(r"^[\s،؛]+", "", t, flags=re.M)
    return t.strip()


def has_arabic(text: str) -> bool:
    return bool(ARABIC_LETTER_RE.search(text))


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------

_SENTENCE_END_RE = re.compile(r"(?<=[.!؟?\n])\s+|\n+")
_CLAUSE_RE = re.compile(r"(?<=[،,؛;:])\s+")


def split_into_chunks(text: str, max_chars: int = 220) -> list[str]:
    """Split text into ordered chunks <= max_chars, never cutting a word.

    Order of preference: sentence end, clause mark, word boundary. A single
    word longer than max_chars is kept whole (it is never cut).
    """
    text = text.strip()
    if not text:
        return []
    if len(text) <= max_chars:
        return [text]

    sentences = [s.strip() for s in _SENTENCE_END_RE.split(text) if s and s.strip()]
    pieces: list[str] = []
    for s in sentences:
        if len(s) <= max_chars:
            pieces.append(s)
            continue
        for clause in (c.strip() for c in _CLAUSE_RE.split(s) if c.strip()):
            if len(clause) <= max_chars:
                pieces.append(clause)
                continue
            words, cur = clause.split(), ""
            for w in words:
                if cur and len(cur) + 1 + len(w) > max_chars:
                    pieces.append(cur)
                    cur = w
                else:
                    cur = f"{cur} {w}" if cur else w
            if cur:
                pieces.append(cur)

    # Greedily merge small neighbouring pieces back together.
    chunks: list[str] = []
    for p in pieces:
        if chunks and len(chunks[-1]) + 1 + len(p) <= max_chars:
            chunks[-1] = f"{chunks[-1]} {p}"
        else:
            chunks.append(p)
    return chunks
