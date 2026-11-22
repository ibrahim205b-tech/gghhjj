from app.text.arabic import normalize_arabic, number_to_words, split_into_chunks, year_to_words


def test_required_sentences_unchanged():
    for s in ["مرحباً بك، هذا اختبار لتوليد الكلام باللغة العربية.",
              "أهلاً وسهلاً، شلونكم؟ اليوم راح نجرب نظام استنساخ الصوت.",
              "أريد إنشاء تسجيل صوتي واضح وطبيعي باللغة العربية."]:
        assert normalize_arabic(s) == s


def test_phone_and_date():
    out = normalize_arabic("الرقم 07700240001، والتاريخ 22 نوفمبر 2026.")
    assert out == ("الرقم صفر سبعة سبعة صفر، صفر اثنين أربعة، صفر صفر صفر واحد، "
                   "والتاريخ اثنين وعشرين نوفمبر ألفين وستة وعشرين.")
    assert not any(c.isdigit() for c in out)


def test_international_phone():
    out = normalize_arabic("+9647701234567")
    assert out.startswith("زائد تسعة ستة أربعة")
    assert "واحد اثنين ثلاثة" in out


def test_numbers():
    assert number_to_words(0) == "صفر"
    assert number_to_words(11) == "أحد عشر"
    assert number_to_words(25) == "خمسة وعشرون"
    assert number_to_words(100) == "مئة"
    assert number_to_words(1250) == "ألف ومئتان وخمسون"
    assert number_to_words(2000) == "ألفان"
    assert number_to_words(5000) == "خمسة آلاف"
    assert number_to_words(1_000_000) == "مليون"
    assert year_to_words(2026) == "ألفين وستة وعشرين"
    assert year_to_words(1990) == "ألف وتسعمئة وتسعين"


def test_arabic_indic_digits_and_percent_time():
    assert normalize_arabic("٢٥٪") == "خمسة وعشرون بالمئة"
    assert normalize_arabic("الساعة 10:30") == "الساعة الساعة عشرة والنصف" or "عشرة والنصف" in normalize_arabic("10:30")
    assert normalize_arabic("05/03/2025") == "خمسة مارس ألفين وخمسة وعشرين"


def test_diacritics_preserved_and_not_added():
    s = "ذَهَبَ الوَلَدُ إلى المَدرَسةِ."
    assert normalize_arabic(s) == s
    plain = "ذهب الولد إلى المدرسة."
    assert normalize_arabic(plain) == plain


def test_symbols_and_punctuation():
    out = normalize_arabic("هل هذا صحيح؟؟ *مهم* 😀 #وسم https://example.com")
    assert "*" not in out and "#" not in out and "http" not in out and "😀" not in out
    assert "؟؟" not in out and "؟" in out
    assert normalize_arabic("مرحبا?") == "مرحبا؟"
    assert normalize_arabic("أحمد, محمد") == "أحمد، محمد"
    assert normalize_arabic("د. أحمد") == "دكتور أحمد"


def test_tatweel_removed():
    assert normalize_arabic("جمـــيل") == "جميل"


def test_chunking_keeps_order_and_words():
    text = " ".join(f"الجملة رقم {i} تحتوي على بعض الكلمات المفيدة." for i in range(40))
    chunks = split_into_chunks(text, 120)
    assert all(len(c) <= 120 for c in chunks)
    assert " ".join(chunks).split() == text.split()


def test_chunking_long_sentence_without_punctuation():
    text = " ".join(["كلمة"] * 200)
    chunks = split_into_chunks(text, 50)
    assert all(len(c) <= 50 for c in chunks)
    assert " ".join(chunks).split() == text.split()


def test_chunking_single_long_word_not_cut():
    w = "ا" * 300
    assert split_into_chunks(w, 100) == [w]


def test_chunking_empty_and_short():
    assert split_into_chunks("   ", 100) == []
    assert split_into_chunks("مرحبا", 100) == ["مرحبا"]
