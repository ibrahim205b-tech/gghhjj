#!/usr/bin/env python3
"""Builds content/seed_questions.json — the offline starter pack.

    python3 tools/build_pack.py

= content/handwritten.json (hand-written questions)
+ questions derived from the fact tables in tools/pack_data.py
+ the who-am-I riddles and auction sets below.

Every question is marked verification.status = "curated": written from
well-established historical records with a reference link, NOT machine
verified. Run `dart run tool/check_pack.dart` (in core/) afterwards: it
drops anything the de-duplication engine considers a repeat.
"""
import hashlib
import json
import os

from pack_data import (AFCON, ASIAN_CUP, BALLON_DOR, BUNDESLIGA, CLUB_WORLD_CUP, CONFERENCE, COPA,
                       EUROPA, EUROS, LA_LIGA, LIGUE_1, N, NATIONAL_TEAM_PAGE, NATIONAL_TOP, P,
                       PL_TOP_SCORERS, PREMIER_LEAGUE, SERIE_A, TRANSFERS, UCL, UCL_AET, UCL_PENS,
                       WC_PENS, WORLD_CUPS, ar)

ROOT = os.path.join(os.path.dirname(__file__), "..")
W = "https://en.wikipedia.org/wiki/"
CREATED = "2026-11-15T00:00:00Z"
VER = {"status": "curated", "method": "manual-curation",
       "notes": "حزمة البداية: معلومات تاريخية ثابتة من سجلات معروفة مع رابط مرجعي للحكم. ليست ناتجة عن تحقق آلي."}

out = []


def src(page, title=None):
    return {"title": title or page.replace("_", " "), "url": W + page}


def acc(*names):
    """Accepted answers: Latin spelling + common variants."""
    res = []
    for n in names:
        if n and n not in res:
            res.append(n)
    return res


# Facts already asked by a hand-written question (content/handwritten.json).
COVERED = {"european-cup-1986|runner-up", "european-cup-1961|runner-up", "ballon-dor-2004|winner",
           "ballon-dor-2006|winner", "european-cup-2005|final-city", "premier-league-1992-1993|champion",
           "european-cup-2004|winner", "european-cup-2002|runner-up"}


def add(cat, diff, q, a, accepted, sources, key, topic, asof=None, items=None, exhaustive=False, clues=None):
    if key in COVERED:
        return
    qid = "pack-" + hashlib.sha1(key.encode()).hexdigest()[:12]
    d = {"id": qid, "category": cat, "difficulty": diff, "question": q, "answer": a,
         "accepted_answers": [x for x in accepted if x != a], "topic": topic, "semantic_key": key,
         "sources": sources, "created_at": CREATED, "verification": VER, "origin": "seed"}
    if asof:
        d["fact_as_of"] = asof
    if items is not None:
        d["items"] = [{"name": i[0], "aliases": list(i[1:])} for i in items]
        d["items_exhaustive"] = exhaustive
    if clues:
        d["clues"] = clues
    out.append(d)


def pick(seed, options):
    return options[int(hashlib.md5(str(seed).encode()).hexdigest(), 16) % len(options)]


def era(year):
    return "historic" if year < 1980 else ("very_expert" if year < 2000 else "expert")


def season(y):
    return f"{y}-{y + 1}"


def score_ar(s):
    a, b = s.split("-")
    return f"{a}-{b}"


def score_acc(s):
    a, b = s.split("-")
    return acc(f"{a}-{b}", f"{a} - {b}", f"{a}–{b}", f"{b}-{a}")


def names_acc(x):
    return acc(x, ar(x))

# ================================================================ WORLD CUP
for (y, hosts, win, ru, score, coach, capt, top, gball, city) in WORLD_CUPS:
    page = src(f"{y}_FIFA_World_Cup")
    host_ar = " و".join(ar(h) for h in hosts)
    add("buzzer", era(y), pick(y, [f"أي منتخب توّج بكأس العالم {y}؟", f"من بطل كأس العالم {y}؟"]),
        ar(win), names_acc(win), [page], f"world-cup-{y}|champion", "كأس العالم")
    add("wdyk", era(y), f"من المنتخب الذي حلّ وصيفاً لكأس العالم {y}؟", ar(ru), names_acc(ru), [page],
        f"world-cup-{y}|runner-up", "كأس العالم")
    add("buzzer", "historic" if y < 1970 else "hard",
        f"أين أقيمت نهائيات كأس العالم {y}؟" if len(hosts) == 1 else f"في أي بلدين أقيمت نهائيات كأس العالم {y}؟",
        host_ar, acc(*hosts, *[ar(h) for h in hosts]), [page], f"world-cup-{y}|host", "كأس العالم")
    add("wdyk", "very_expert" if y >= 1970 else "impossible", f"من المدرب الذي قاد {ar(win)} للفوز بكأس العالم {y}؟",
        ar(coach), names_acc(coach), [page], f"world-cup-{y}|winning-coach", "المدربون")
    add("wdyk", "very_expert" if y >= 1970 else "impossible", f"من كان قائد منتخب {ar(win)} المتوّج بكأس العالم {y}؟",
        ar(capt), names_acc(capt), [page], f"world-cup-{y}|winning-captain", "كأس العالم")
    if score and y not in WC_PENS:
        add("wdyk", "very_expert", f"ما النتيجة النهائية لمباراة نهائي كأس العالم {y} بين {ar(win)} و{ar(ru)}؟",
            score_ar(score), score_acc(score), [page], f"world-cup-{y}|final-score", "النهائيات")
    if y in WC_PENS:
        add("wdyk", "very_expert", f"انتهى نهائي كأس العالم {y} بالتعادل؛ بأي نتيجة حسمت ركلات الترجيح اللقب لـ{ar(win)}؟",
            WC_PENS[y], score_acc(WC_PENS[y]), [page], f"world-cup-{y}|final-penalties", "النهائيات")
    if top:
        add("buzzer" if y >= 1990 else "wdyk", "expert" if y >= 1990 else "historic",
            f"من هدّاف نهائيات كأس العالم {y}؟", ar(top), names_acc(top), [page],
            f"world-cup-{y}|top-scorer", "الهدافون")
    if gball:
        add("wdyk", "very_expert", f"من نال جائزة الكرة الذهبية لأفضل لاعب في كأس العالم {y}؟",
            ar(gball), names_acc(gball), [page], f"world-cup-{y}|golden-ball", "الجوائز")
    if city:
        add("buzzer", "very_expert", f"في أي مدينة أقيمت المباراة النهائية لكأس العالم {y}؟", ar(city),
            names_acc(city), [page], f"world-cup-{y}|final-city", "النهائيات")

# ================================================================ EURO
for (y, hosts, win, ru, score) in EUROS:
    page = src(f"UEFA_Euro_{y}")
    add("buzzer", era(y), pick(y, [f"من بطل أمم أوروبا {y}؟", f"أي منتخب توّج بلقب كأس أمم أوروبا {y}؟"]),
        ar(win), names_acc(win), [page], f"euro-{y}|champion", "أمم أوروبا")
    add("wdyk", era(y), f"من وصيف بطولة أمم أوروبا {y}؟", ar(ru), names_acc(ru), [page], f"euro-{y}|runner-up", "أمم أوروبا")
    add("buzzer", "very_expert" if y < 2000 else "hard",
        f"أين أقيمت بطولة أمم أوروبا {y}؟" if len(hosts) == 1 else f"ما البلدان المستضيفان لأمم أوروبا {y}؟",
        " و".join(ar(h) for h in hosts), acc(*hosts, *[ar(h) for h in hosts]), [page], f"euro-{y}|host", "أمم أوروبا")
    if score and score != "2-2":
        add("wdyk", "very_expert", f"ما نتيجة نهائي أمم أوروبا {y} بين {ar(win)} و{ar(ru)}؟", score, score_acc(score),
            [page], f"euro-{y}|final-score", "النهائيات")

# ================================================================ CHAMPIONS LEAGUE
for (y, win, ru, score, coach, city) in UCL:
    page = src(f"{y}_European_Cup_final" if y <= 1992 else f"{y}_UEFA_Champions_League_final")
    comp = "كأس أوروبا للأندية البطلة" if y <= 1992 else "دوري أبطال أوروبا"
    d = "impossible" if y < 1970 else era(y)
    add("buzzer", d, pick(y, [f"من بطل {comp} عام {y}؟", f"أي نادٍ رفع لقب {comp} في {y}؟"]),
        ar(win), names_acc(win), [page], f"european-cup-{y}|winner", "دوري أبطال أوروبا")
    add("wdyk", d, f"من الفريق الذي خسر نهائي {comp} {y} أمام {ar(win)}؟", ar(ru), names_acc(ru), [page],
        f"european-cup-{y}|runner-up", "دوري أبطال أوروبا")
    add("wdyk", "impossible" if y < 1990 else "very_expert", f"من مدرب {ar(win)} المتوّج بلقب {comp} {y}؟",
        ar(coach), names_acc(coach), [page], f"european-cup-{y}|winning-coach", "المدربون")
    if score and y not in UCL_PENS:
        extra = " بعد التمديد" if y in UCL_AET else ""
        add("wdyk", "very_expert", f"بأي نتيجة فاز {ar(win)} على {ar(ru)} في نهائي {comp} {y}{extra}؟", score,
            score_acc(score), [page], f"european-cup-{y}|final-score", "النهائيات")
    if y in UCL_PENS:
        add("wdyk", "very_expert", f"حُسم نهائي {comp} {y} بركلات الترجيح؛ ما نتيجتها لصالح {ar(win)}؟",
            UCL_PENS[y], score_acc(UCL_PENS[y]), [page], f"european-cup-{y}|penalties", "النهائيات")
    if city:
        add("buzzer", "very_expert", f"في أي مدينة أقيم نهائي {comp} {y}؟", ar(city), names_acc(city.replace(" city", "")),
            [page], f"european-cup-{y}|final-city", "النهائيات")

# ================================================================ BALLON D'OR
for y, who in BALLON_DOR.items():
    d = "impossible" if y < 1970 else ("historic" if y < 1990 else ("very_expert" if y < 2008 else "hard"))
    add("buzzer" if y >= 1990 else "wdyk", d,
        pick(y, [f"من فاز بالكرة الذهبية عام {y}؟", f"من اللاعب المتوّج بجائزة الكرة الذهبية في {y}؟"]),
        ar(who), names_acc(who), [src("Ballon_d%27Or", "Ballon d'Or")], f"ballon-dor-{y}|winner", "الكرة الذهبية",
        asof=f"{y}-12-31")

# ================================================================ LEAGUES
LEAGUES = [
    (PREMIER_LEAGUE, "الدوري الإنجليزي الممتاز", "List_of_English_football_champions", "premier-league"),
    (LA_LIGA, "الدوري الإسباني", "List_of_Spanish_football_champions", "la-liga"),
    (SERIE_A, "الدوري الإيطالي", "List_of_Italian_football_champions", "serie-a"),
    (BUNDESLIGA, "الدوري الألماني", "List_of_German_football_champions", "bundesliga"),
    (LIGUE_1, "الدوري الفرنسي", "List_of_French_football_champions", "ligue-1"),
]
for table, name, page, key in LEAGUES:
    for y, champ in table.items():
        d = "historic" if y < 1995 else ("very_expert" if y < 2008 else "expert")
        add("buzzer" if y % 2 else "wdyk", d,
            pick(f"{key}{y}", [f"من بطل {name} موسم {season(y)}؟", f"أي نادٍ توّج بلقب {name} في موسم {season(y)}؟"]),
            ar(champ), names_acc(champ), [src(page)], f"{key}-{season(y)}|champion", "الدوريات الأوروبية")

for y, (who, goals) in PL_TOP_SCORERS.items():
    page = [src("Premier_League_Golden_Boot")]
    add("wdyk", "very_expert" if y < 2005 else "expert", f"من هدّاف الدوري الإنجليزي الممتاز موسم {season(y)}؟",
        ar(who), names_acc(who), page, f"premier-league-{season(y)}|top-scorer", "الهدافون")
    add("wdyk", "impossible" if y < 2010 else "very_expert",
        f"كم هدفاً سجّل {ar(who)} ليتوّج هدافاً للدوري الإنجليزي الممتاز موسم {season(y)}؟",
        str(goals), acc(str(goals), f"{goals} هدفاً"), page, f"premier-league-{season(y)}|top-scorer-goals", "الأرقام القياسية")

# ================================================================ CONTINENTAL / CLUB CUPS
for table, name, page, key, diff in [
    (AFCON, "كأس الأمم الأفريقية", "Africa_Cup_of_Nations", "afcon", "expert"),
    (ASIAN_CUP, "كأس آسيا", "AFC_Asian_Cup", "asian-cup", "very_expert"),
    (COPA, "كوبا أمريكا", "Copa_Am%C3%A9rica", "copa-america", "expert"),
    (CLUB_WORLD_CUP, "كأس العالم للأندية", "FIFA_Club_World_Cup", "club-world-cup", "expert"),
    (EUROPA, "الدوري الأوروبي / كأس الاتحاد الأوروبي", "UEFA_Europa_League", "uefa-cup", "expert"),
    (CONFERENCE, "دوري المؤتمر الأوروبي", "UEFA_Conference_League", "conference-league", "hard"),
]:
    for y, champ in table.items():
        add("buzzer" if y % 2 == 0 else "wdyk", "historic" if y < 1990 else diff,
            pick(f"{key}{y}", [f"من بطل {name} {y}؟", f"من توّج بلقب {name} في نسخة {y}؟"]),
            ar(champ), names_acc(champ), [src(page, page.replace("_", " ").replace("%C3%A9", "é"))],
            f"{key}-{y}|champion", "البطولات")

# ================================================================ RECORDS / TRANSFERS
for team, who in NATIONAL_TOP.items():
    add("wdyk", "expert", f"من الهدّاف التاريخي لمنتخب {ar(team)} (حتى منتصف 2025)؟", ar(who), names_acc(who),
        [src(NATIONAL_TEAM_PAGE[team])], f"national-team-{team.lower().replace(' ', '-')}|all-time-top-scorer",
        "الأرقام القياسية", asof="2025-06-30")

for (who, frm, to, y) in TRANSFERS:
    page = [src(who.replace(" ", "_").replace("'", "%27"), who)]
    if who == "Ronaldo":
        page = [src("Ronaldo_(Brazilian_footballer)", "Ronaldo (Brazilian footballer)")]
    add("wdyk", "expert", f"من أي نادٍ انتقل {ar(who)} إلى {ar(to)} عام {y}؟", ar(frm), names_acc(frm), page,
        f"transfer-{who.lower().replace(' ', '-')}-{y}|from-club", "الانتقالات")
    add("buzzer", "expert", f"إلى أي نادٍ انتقل {ar(who)} قادماً من {ar(frm)} عام {y}؟", ar(to), names_acc(to), page,
        f"transfer-{who.lower().replace(' ', '-')}-{y}|to-club", "الانتقالات")

# ================================================================ WHO AM I
WHO = [
    ("Zinedine Zidane", "زين الدين زيدان", "very_expert", [
        "بدأت مسيرتي الاحترافية في نادي كان الفرنسي.", "لعبت لبوردو ثم انتقلت إلى يوفنتوس عام 1996.",
        "سجلت هدفين برأسي في نهائي كأس العالم 1998.", "طُردت في نهائي كأس العالم 2006 في آخر مباراة لي.",
        "قدت ريال مدريد مدرباً للقب دوري الأبطال ثلاث مرات متتالية."]),
    ("Andrés Iniesta", "أندريس إنييستا", "expert", [
        "تخرجت من أكاديمية لاماسيا.", "لعبت في اليابان مع فيسيل كوبي بعد رحيلي عن إسبانيا.",
        "توّجت بأمم أوروبا 2008 و2012.", "سجلت هدف الفوز في نهائي كأس العالم 2010."]),
    ("Xavi", "تشافي هيرنانديز", "expert", [
        "لعبت مع السد القطري ثم دربته.", "قضيت مسيرتي الأوروبية كلها لاعباً في برشلونة.",
        "كنت أفضل لاعب في أمم أوروبا 2008.", "عدت إلى برشلونة مدرباً وفزت بالدوري الإسباني 2022-2023."]),
    ("Cristiano Ronaldo", "كريستيانو رونالدو", "hard", [
        "بدأت مسيرتي في سبورتينغ لشبونة.", "انتقلت إلى السعودية عام 2023.",
        "لعبت ليوفنتوس بين 2018 و2021.", "توّجت بأمم أوروبا 2016 مع بلادي.",
        "أنا الهداف التاريخي لريال مدريد ودوري أبطال أوروبا."]),
    ("Lionel Messi", "ليونيل ميسي", "hard", [
        "نشأت في روساريو وتدرجت في نيولز أولد بويز.", "لعبت لباريس سان جيرمان بين 2021 و2023.",
        "انتقلت إلى إنتر ميامي الأمريكي عام 2023.", "فزت بالكرة الذهبية ثماني مرات.",
        "توّجت بكأس العالم 2022 قائداً لمنتخب بلادي."]),
    ("Wayne Rooney", "واين روني", "expert", [
        "بدأت مسيرتي مع إيفرتون.", "لعبت لدي سي يونايتد الأمريكي.",
        "انتقلت إلى مانشستر يونايتد عام 2004.", "أنا الهداف التاريخي لمانشستر يونايتد."]),
    ("Steven Gerrard", "ستيفن جيرارد", "expert", [
        "لعبت مع لوس أنجلوس غالاكسي في نهاية مسيرتي.", "قدت رينجرز مدرباً إلى لقب الدوري الإسكتلندي 2021.",
        "قضيت مسيرتي الإنجليزية كلها في نادٍ واحد.", "كنت قائد ليفربول في ليلة إسطنبول 2005."]),
    ("Frank Lampard", "فرانك لامبارد", "expert", [
        "تخرجت من أكاديمية وست هام.", "لعبت لمانشستر سيتي ونيويورك سيتي في آخر مسيرتي.",
        "انتقلت إلى تشيلسي عام 2001.", "أنا الهداف التاريخي لتشيلسي رغم أنني لاعب وسط."]),
    ("Paolo Maldini", "باولو مالديني", "expert", [
        "والدي كان قائداً ومدرباً لمنتخب إيطاليا.", "عدت إلى ناديي لاحقاً مديراً فنياً.",
        "فزت بكأس أوروبا / دوري الأبطال خمس مرات.", "قضيت مسيرتي كلها مدافعاً في ميلان."]),
    ("Francesco Totti", "فرانشيسكو توتي", "expert", [
        "توّجت بكأس العالم 2006.", "فزت بالدوري الإيطالي مرة واحدة عام 2001.",
        "لُقبت بـ«الأمير» و«ملك روما».", "قضيت مسيرتي كلها في نادي روما."]),
    ("Alessandro Del Piero", "أليساندرو ديل بييرو", "very_expert", [
        "بدأت مسيرتي في بادوفا.", "لعبت في أستراليا مع سيدني إف سي ثم في الهند.",
        "بقيت مع ناديي عند هبوطه للدرجة الثانية عام 2006.", "أنا اللاعب الأكثر مشاركة في تاريخ يوفنتوس."]),
    ("Raúl", "راؤول غونزاليس", "very_expert", [
        "تدرجت في فئات أتلتيكو مدريد الصغرى.", "لعبت لشالكه الألماني ثم السد القطري.",
        "فزت بدوري الأبطال ثلاث مرات: 1998 و2000 و2002.", "كنت قائد ريال مدريد ورمزه لسنوات طويلة."]),
    ("Iker Casillas", "إيكر كاسياس", "expert", [
        "انتقلت إلى بورتو عام 2015.", "تدرجت في أكاديمية ريال مدريد.",
        "توّجت بأمم أوروبا 2008 و2012.", "رفعت كأس العالم 2010 قائداً لإسبانيا وحارساً لمرماها."]),
    ("Sergio Ramos", "سيرخيو راموس", "expert", [
        "بدأت مسيرتي في إشبيلية.", "لعبت لباريس سان جيرمان بين 2021 و2023.",
        "انتقلت إلى ريال مدريد عام 2005.", "سجلت هدف التعادل في الدقيقة 93 بنهائي دوري الأبطال 2014."]),
    ("Luka Modrić", "لوكا مودريتش", "expert", [
        "بدأت مسيرتي في دينامو زغرب.", "لعبت لتوتنهام بين 2008 و2012.",
        "قدت منتخب بلادي إلى نهائي كأس العالم 2018.", "كسرت احتكار ميسي ورونالدو للكرة الذهبية عام 2018."]),
    ("Karim Benzema", "كريم بنزيما", "expert", [
        "بدأت مسيرتي في ليون.", "انتقلت إلى الاتحاد السعودي عام 2023.",
        "انتقلت إلى ريال مدريد عام 2009.", "فزت بالكرة الذهبية عام 2022."]),
    ("Robert Lewandowski", "روبرت ليفاندوفسكي", "expert", [
        "لعبت لليش بوزنان قبل الانتقال إلى ألمانيا.", "سجلت خمسة أهداف في تسع دقائق أمام فولفسبورغ عام 2015.",
        "انتقلت من دورتموند إلى بايرن ميونخ عام 2014.", "انتقلت إلى برشلونة عام 2022."]),
    ("Zlatan Ibrahimović", "زلاتان إبراهيموفيتش", "expert", [
        "بدأت مسيرتي في مالمو.", "لعبت لأياكس ويوفنتوس وإنتر وبرشلونة وميلان وباريس سان جيرمان.",
        "لعبت لمانشستر يونايتد ولوس أنجلوس غالاكسي.", "أنا الهداف التاريخي لمنتخب السويد."]),
    ("Gerd Müller", "غيرد مولر", "historic", [
        "أنهيت مسيرتي في الولايات المتحدة مع فورت لودرديل.", "فزت بالكرة الذهبية عام 1970.",
        "سجلت هدف الفوز في نهائي كأس العالم 1974.", "لُقبت بـ«المدفعجي» وكنت هداف بايرن ميونخ التاريخي لعقود."]),
    ("Franz Beckenbauer", "فرانز بيكنباور", "historic", [
        "لعبت لنيويورك كوزموس في الولايات المتحدة.", "فزت بالكرة الذهبية مرتين.",
        "رفعت كأس العالم 1974 قائداً.", "فزت بكأس العالم 1990 مدرباً، ولُقبت بـ«القيصر»."]),
    ("Johan Cruyff", "يوهان كرويف", "historic", [
        "أنهيت مسيرتي لاعباً في فينورد.", "انتقلت إلى برشلونة عام 1973.",
        "فزت بالكرة الذهبية ثلاث مرات.", "قدت برشلونة مدرباً لأول لقب كأس أوروبا عام 1992."]),
    ("Marco van Basten", "ماركو فان باستن", "very_expert", [
        "بدأت مسيرتي في أياكس.", "اعتزلت مبكراً بسبب إصابة الكاحل.",
        "سجلت هدفاً طائراً شهيراً في نهائي أمم أوروبا 1988.", "فزت بالكرة الذهبية ثلاث مرات مع ميلان."]),
    ("Diego Maradona", "دييغو مارادونا", "hard", [
        "بدأت مسيرتي في أرجنتينوس جونيورز.", "لعبت لبرشلونة بين 1982 و1984.",
        "قدت نابولي إلى لقبي الدوري الإيطالي.", "سجلت هدف «يد الله» وتوّجت بكأس العالم 1986."]),
    ("Pelé", "بيليه", "hard", [
        "لعبت لنيويورك كوزموس في نهاية مسيرتي.", "قضيت معظم مسيرتي في سانتوس.",
        "شاركت في أربع نسخ من كأس العالم.", "أنا اللاعب الوحيد المتوّج بكأس العالم ثلاث مرات."]),
    ("Ronaldo", "رونالدو (الظاهرة)", "expert", [
        "بدأت مسيرتي في كروزيرو.", "لعبت لآيندهوفن ثم برشلونة ثم إنتر.",
        "انتقلت إلى ريال مدريد عام 2002.", "سجلت ثمانية أهداف وتوّجت بكأس العالم 2002."]),
    ("Roberto Carlos", "روبرتو كارلوس", "very_expert", [
        "لعبت لبالميراس ثم إنتر ميلان.", "لعبت لفنربخشه التركي بعد رحيلي عن إسبانيا.",
        "سجلت ركلة حرة «مستحيلة» أمام فرنسا عام 1997.", "ظهير أيسر توّج بثلاثة ألقاب لدوري الأبطال مع ريال مدريد."]),
    ("Cafu", "كافو", "very_expert", [
        "بدأت مسيرتي في ساو باولو.", "فزت بالدوري الإيطالي مع روما عام 2001.",
        "فزت بدوري الأبطال مع ميلان عام 2007.", "رفعت كأس العالم 2002 قائداً للبرازيل."]),
    ("Didier Deschamps", "ديدييه ديشان", "very_expert", [
        "بدأت مسيرتي في نانت.", "كنت قائد مارسيليا المتوّج بدوري الأبطال 1993.",
        "رفعت كأس العالم 1998 قائداً.", "فزت بكأس العالم 2018 مدرباً."]),
    ("Carlo Ancelotti", "كارلو أنشيلوتي", "expert", [
        "لعبت لبارما وروما وميلان.", "دربت يوفنتوس وباريس سان جيرمان وبايرن ونابولي وإيفرتون.",
        "حققت الثنائية مع تشيلسي عام 2010.", "أنا المدرب الأكثر تتويجاً بدوري أبطال أوروبا."]),
    ("Pep Guardiola", "بيب غوارديولا", "hard", [
        "لعبت لبريشيا وروما والأهلي القطري.", "دربت بايرن ميونخ بين 2013 و2016.",
        "حققت الثلاثية مع برشلونة عام 2009.", "حققت الثلاثية مع مانشستر سيتي عام 2023."]),
    ("Alex Ferguson", "أليكس فيرغسون", "expert", [
        "قدت أبردين للفوز بكأس الكؤوس الأوروبية 1983.", "توليت تدريب ناديي الأشهر عام 1986.",
        "حققت الثلاثية عام 1999.", "فزت بالدوري الإنجليزي الممتاز 13 مرة مع مانشستر يونايتد."]),
    ("Arsène Wenger", "أرسين فينغر", "expert", [
        "دربت ناغويا غرامبوس الياباني.", "دربت موناكو قبل ذلك.",
        "قضيت 22 عاماً مدرباً لنادٍ إنجليزي واحد.", "قدت فريق «الذين لا يُقهرون» في موسم 2003-2004."]),
    ("Antonio Conte", "أنطونيو كونتي", "very_expert", [
        "كنت قائد يوفنتوس لاعباً.", "قدت منتخب إيطاليا في أمم أوروبا 2016.",
        "فزت بالدوري الإنجليزي مع تشيلسي 2017.", "فزت بالدوري الإيطالي مع يوفنتوس وإنتر ونابولي."]),
    ("Diego Simeone", "دييغو سيميوني", "expert", [
        "لعبت لإنتر ولاتسيو.", "حققت الثنائية لاعباً مع أتلتيكو مدريد عام 1996.",
        "توليت تدريب أتلتيكو مدريد في ديسمبر 2011.", "فزت بالدوري الإسباني مدرباً عامي 2014 و2021."]),
    ("Mohamed Salah", "محمد صلاح", "hard", [
        "بدأت مسيرتي في المقاولون العرب.", "لعبت لبازل السويسري ثم تشيلسي.",
        "لعبت لفيورنتينا وروما.", "سجلت 32 هدفاً في أول موسم لي مع ليفربول."]),
    ("Riyad Mahrez", "رياض محرز", "expert", [
        "بدأت مسيرتي الاحترافية في لوهافر.", "انتقلت إلى الأهلي السعودي عام 2023.",
        "توّجت بالدوري الإنجليزي مع ليستر سيتي 2016.", "قدت الجزائر قائداً للقب كأس الأمم الأفريقية 2019."]),
    ("Sadio Mané", "ساديو ماني", "expert", [
        "لعبت لميتز الفرنسي ثم ريد بول سالزبورغ.", "سجلت أسرع هاتريك في الدوري الإنجليزي مع ساوثهامبتون.",
        "انتقلت إلى بايرن ميونخ عام 2022.", "قدت السنغال إلى لقب كأس الأمم الأفريقية 2021."]),
    ("Erling Haaland", "إرلينغ هالاند", "hard", [
        "بدأت مسيرتي في براين ثم مولده النرويجيين.", "لعبت لريد بول سالزبورغ.",
        "انتقلت من دورتموند إلى مانشستر سيتي عام 2022.", "سجلت 36 هدفاً في أول موسم لي بالدوري الإنجليزي."]),
    ("Kylian Mbappé", "كيليان مبابي", "hard", [
        "بدأت مسيرتي الاحترافية في موناكو.", "توّجت بكأس العالم 2018.",
        "سجلت هاتريك في نهائي كأس العالم 2022.", "انتقلت إلى ريال مدريد عام 2024."]),
    ("Neymar", "نيمار", "hard", [
        "عدت إلى سانتوس عام 2025.", "فزت بالميدالية الذهبية الأولمبية 2016.",
        "انتقلت إلى باريس سان جيرمان بأغلى صفقة في التاريخ عام 2017.", "انتقلت إلى الهلال السعودي عام 2023."]),
    ("Luis Suárez", "لويس سواريز", "expert", [
        "بدأت مسيرتي في ناسيونال.", "لعبت لغرونينغن ثم أياكس.",
        "فزت بالدوري الإسباني مع أتلتيكو مدريد 2021.", "شكلت ثلاثياً هجومياً شهيراً مع ميسي ونيمار."]),
    ("Gareth Bale", "غاريث بيل", "expert", [
        "بدأت مسيرتي في ساوثهامبتون.", "أنهيت مسيرتي مع لوس أنجلوس إف سي.",
        "انتقلت إلى ريال مدريد عام 2013.", "سجلت هدفاً مقصياً في نهائي دوري الأبطال 2018."]),
    ("Kevin De Bruyne", "كيفن دي بروين", "expert", [
        "بدأت مسيرتي في غينك.", "لعبت لفولفسبورغ قبل الانتقال إلى إنجلترا للمرة الثانية.",
        "انتقلت إلى نابولي عام 2025.", "صانع ألعاب مانشستر سيتي لعقد كامل."]),
    ("Virgil van Dijk", "فيرجيل فان دايك", "expert", [
        "بدأت مسيرتي في غرونينغن.", "لعبت لسيلتك ثم ساوثهامبتون.",
        "انتقلت إلى ليفربول في يناير 2018.", "مدافع هولندي فاز بدوري الأبطال 2019."]),
    ("Manuel Neuer", "مانويل نوير", "expert", [
        "بدأت مسيرتي في شالكه.", "انتقلت إلى بايرن ميونخ عام 2011.",
        "توّجت بكأس العالم 2014.", "حارس مرمى اشتهر بدور «الحارس الليبرو»."]),
    ("Lev Yashin", "ليف ياشين", "impossible", [
        "قضيت مسيرتي كلها في دينامو موسكو.", "توّجت بأمم أوروبا 1960.",
        "لُقبت بـ«العنكبوت الأسود».", "أنا الحارس الوحيد الفائز بالكرة الذهبية (1963)."]),
    ("Eusébio", "أوزيبيو", "historic", [
        "وُلدت في موزمبيق.", "فزت بالكرة الذهبية عام 1965.",
        "كنت هداف كأس العالم 1966.", "أسطورة بنفيكا ولُقبت بـ«الفهد الأسود»."]),
    ("Alfredo Di Stéfano", "ألفريدو دي ستيفانو", "impossible", [
        "لعبت لريفر بليت ثم مييوناريوس الكولومبي.", "مثّلت منتخبات أكثر من بلد.",
        "سجلت في خمسة نهائيات متتالية لكأس أوروبا.", "قائد ريال مدريد الذي هيمن على أوروبا في الخمسينيات."]),
    ("Ferenc Puskás", "فرينك بوشكاش", "impossible", [
        "لعبت لهونفيد المجري.", "سجلت أربعة أهداف في نهائي كأس أوروبا 1960.",
        "انضممت إلى ريال مدريد بعد الثلاثين من عمري.", "تحمل جائزة أجمل هدف في العالم اسمي."]),
    ("Michel Platini", "ميشيل بلاتيني", "historic", [
        "لعبت لنانسي ثم سانت إتيان.", "سجلت تسعة أهداف في أمم أوروبا 1984.",
        "فزت بالكرة الذهبية ثلاث مرات متتالية مع يوفنتوس.", "أصبحت لاحقاً رئيساً للاتحاد الأوروبي."]),
    ("George Weah", "جورج ويا", "very_expert", [
        "لعبت لموناكو ثم باريس سان جيرمان.", "انتقلت إلى ميلان عام 1995.",
        "أنا الأفريقي الوحيد الفائز بالكرة الذهبية.", "أصبحت رئيساً لبلادي ليبيريا."]),
    ("Hristo Stoichkov", "هريستو ستويتشكوف", "very_expert", [
        "بدأت في سسكا صوفيا.", "كنت أحد هدافي كأس العالم 1994.",
        "فزت بالكرة الذهبية عام 1994.", "نجم برشلونة في عهد كرويف و«فريق الأحلام»."]),
    ("Gabriel Batistuta", "غابرييل باتيستوتا", "very_expert", [
        "لعبت لنيولز وريفر بليت وبوكا جونيورز.", "لعبت للعربي القطري في نهاية مسيرتي.",
        "فزت بالدوري الإيطالي مع روما عام 2001.", "أسطورة فيورنتينا ولُقبت بـ«باتيغول»."]),
    ("Andriy Shevchenko", "أندريه شيفتشينكو", "expert", [
        "بدأت مسيرتي في دينامو كييف.", "انتقلت إلى تشيلسي عام 2006.",
        "فزت بالكرة الذهبية عام 2004.", "دربت منتخب بلادي في أمم أوروبا 2020."]),
    ("Louis van Gaal", "لويس فان خال", "very_expert", [
        "فزت بالدوري الهولندي مع ألكمار 2009.", "فزت بكأس الاتحاد الإنجليزي مع مانشستر يونايتد 2016.",
        "قدت هولندا للمركز الثالث في كأس العالم 2014.", "قدت أياكس للقب دوري الأبطال 1995."]),
    ("Romário", "روماريو", "very_expert", [
        "بدأت في فاسكو دا غاما.", "لعبت لآيندهوفن ثم برشلونة.",
        "أصبحت عضواً في مجلس الشيوخ البرازيلي.", "كنت أفضل لاعب في كأس العالم 1994."]),
    ("Rivaldo", "ريفالدو", "very_expert", [
        "لعبت لبالميراس ثم ديبورتيفو لاكورونيا.", "فزت بدوري الأبطال مع ميلان 2003.",
        "انتقلت إلى برشلونة عام 1997.", "فزت بالكرة الذهبية 1999 وكأس العالم 2002."]),
    ("Fabio Capello", "فابيو كابيلو", "very_expert", [
        "لعبت لروما ويوفنتوس وميلان.", "دربت منتخبي إنجلترا وروسيا.",
        "فزت بالدوري الإسباني مع ريال مدريد مرتين.", "قدت ميلان لسحق برشلونة 4-0 في نهائي 1994."]),
    ("Jamie Vardy", "جيمي فاردي", "expert", [
        "لعبت في الدرجات الدنيا وكنت أعمل في مصنع.", "انضممت إلى ليستر سيتي من فليتوود تاون عام 2012.",
        "سجلت في 11 مباراة متتالية بالدوري الإنجليزي.", "كنت هداف ليستر في موسم اللقب التاريخي 2016."]),
]
for (latin, arabic, diff, clues) in WHO:
    page = latin.replace(" ", "_").replace("'", "%27")
    if latin == "Ronaldo":
        page = "Ronaldo_(Brazilian_footballer)"
    if latin == "Raúl":
        page = "Ra%C3%BAl_(footballer)"
    if latin == "Xavi":
        page = "Xavi"
    if latin == "Rodri":
        page = "Rodri_(footballer,_born_1996)"
    if latin == "Luis Suárez":
        page = "Luis_Su%C3%A1rez"
    add("whoami", diff, "من أنا؟", arabic, acc(latin, ar(latin)), [src(page, latin)],
        "person:" + latin.lower().replace(" ", "-"), "من أنا؟", clues=clues)

# ================================================================ AUCTION
def items_from(names):
    return [(ar(n), n) for n in names]


AUCTIONS = [
    ("كم دولة تستطيع أن تسمّي من الدول التي استضافت نهائيات كأس العالم (حتى 2022)؟",
     ["Uruguay", "Italy", "France", "Brazil", "Switzerland", "Sweden", "Chile", "England", "Mexico", "Germany",
      "Argentina", "Spain", "United States", "South Korea", "Japan", "South Africa", "Russia", "Qatar"],
     True, "world-cup|host-countries|to-2022", "FIFA_World_Cup_hosts", "historic"),
    ("كم منتخباً تستطيع أن تسمّي ممن خسروا نهائي كأس العالم دون أن يفوزوا باللقب أبداً (حتى 2022)؟",
     ["Netherlands", "Hungary", "Czechoslovakia", "Sweden", "Croatia"], True,
     "world-cup|finalists-never-won|to-2022", "List_of_FIFA_World_Cup_finals", "very_expert"),
    ("كم مدرباً تستطيع أن تسمّي ممن قادوا منتخباتهم للفوز بكأس العالم (حتى 2022)؟",
     ["Alberto Suppici", "Vittorio Pozzo", "Juan López Fontana", "Sepp Herberger", "Vicente Feola", "Aymoré Moreira",
      "Alf Ramsey", "Mário Zagallo", "Helmut Schön", "César Luis Menotti", "Enzo Bearzot", "Carlos Bilardo",
      "Franz Beckenbauer", "Carlos Alberto Parreira", "Aimé Jacquet", "Luiz Felipe Scolari", "Marcello Lippi",
      "Vicente del Bosque", "Joachim Löw", "Didier Deschamps", "Lionel Scaloni"], True,
     "world-cup|winning-coaches|to-2022", "List_of_FIFA_World_Cup_finals", "impossible"),
    ("كم لاعباً تستطيع أن تسمّي ممن نالوا الكرة الذهبية لأفضل لاعب في كأس العالم بين 1982 و2022؟",
     ["Paolo Rossi", "Diego Maradona", "Salvatore Schillaci", "Romário", "Ronaldo", "Oliver Kahn",
      "Zinedine Zidane", "Diego Forlán", "Lionel Messi", "Luka Modrić"], True,
     "world-cup|golden-ball-winners|1982-2022", "FIFA_World_Cup_awards", "very_expert"),
    ("كم قائداً تستطيع أن تسمّي ممن رفعوا كأس العالم بين 1966 و2022؟",
     ["Bobby Moore", "Carlos Alberto", "Franz Beckenbauer", "Daniel Passarella", "Dino Zoff", "Diego Maradona",
      "Lothar Matthäus", "Dunga", "Didier Deschamps", "Cafu", "Fabio Cannavaro", "Iker Casillas", "Philipp Lahm",
      "Hugo Lloris"], True, "world-cup|winning-captains|1966-2022", "List_of_FIFA_World_Cup_finals", "impossible"),
    ("كم نادياً تستطيع أن تسمّي من الأندية المتوّجة بدوري أبطال أوروبا بين 2000 و2025؟",
     ["Real Madrid", "Bayern Munich", "AC Milan", "Porto", "Liverpool", "Barcelona", "Manchester United",
      "Inter Milan", "Chelsea", "Manchester City", "Paris Saint-Germain"], True,
     "ucl|winning-clubs|2000-2025", "List_of_European_Cup_and_UEFA_Champions_League_finals", "expert"),
    ("كم مدرباً تستطيع أن تسمّي ممن فازوا بدوري أبطال أوروبا بين 2000 و2025؟",
     ["Vicente del Bosque", "Ottmar Hitzfeld", "Carlo Ancelotti", "José Mourinho", "Rafael Benítez",
      "Frank Rijkaard", "Alex Ferguson", "Pep Guardiola", "Roberto Di Matteo", "Jupp Heynckes", "Luis Enrique",
      "Zinedine Zidane", "Jürgen Klopp", "Hansi Flick", "Thomas Tuchel"], True,
     "ucl|winning-coaches|2000-2025", "List_of_European_Cup_and_UEFA_Champions_League_winning_managers", "very_expert"),
    ("كم نادياً تستطيع أن تسمّي من أبطال الدوري الإسباني منذ موسم 1990-1991 حتى 2024-2025؟",
     ["Barcelona", "Real Madrid", "Atlético Madrid", "Deportivo La Coruña", "Valencia"], True,
     "la-liga|champions|1990-2025", "List_of_Spanish_football_champions", "expert"),
    ("كم نادياً تستطيع أن تسمّي من أبطال الدوري الإيطالي منذ موسم 1990-1991 حتى 2024-2025؟",
     ["Sampdoria", "AC Milan", "Juventus", "Lazio", "Roma", "Inter Milan", "Napoli"], True,
     "serie-a|champions|1990-2025", "List_of_Italian_football_champions", "very_expert"),
    ("كم نادياً تستطيع أن تسمّي من أبطال الدوري الألماني منذ موسم 1994-1995 حتى 2024-2025؟",
     ["Borussia Dortmund", "Bayern Munich", "1. FC Kaiserslautern", "Werder Bremen", "VfB Stuttgart",
      "VfL Wolfsburg", "Bayer Leverkusen"], True, "bundesliga|champions|1994-2025",
     "List_of_German_football_champions", "very_expert"),
    ("كم نادياً تستطيع أن تسمّي من أبطال الدوري الفرنسي منذ موسم 2001-2002 حتى 2024-2025؟",
     ["Lyon", "Bordeaux", "Marseille", "Lille", "Montpellier", "Paris Saint-Germain", "Monaco"], True,
     "ligue-1|champions|2001-2025", "List_of_French_football_champions", "very_expert"),
    ("كم نادياً تستطيع أن تسمّي من أبطال كأس الاتحاد الأوروبي / الدوري الأوروبي بين 2000 و2025؟",
     ["Galatasaray", "Liverpool", "Feyenoord", "Porto", "Valencia", "CSKA Moscow", "Sevilla",
      "Zenit Saint Petersburg", "Shakhtar Donetsk", "Atlético Madrid", "Chelsea", "Manchester United", "Villarreal",
      "Eintracht Frankfurt", "Atalanta", "Tottenham Hotspur"], True, "uefa-cup|winners|2000-2025",
     "UEFA_Europa_League", "very_expert"),
    ("كم منتخباً تستطيع أن تسمّي من أبطال كأس الأمم الأفريقية بين 1986 و2023؟",
     ["Egypt", "Cameroon", "Algeria", "Ivory Coast", "Nigeria", "South Africa", "Tunisia", "Zambia", "Senegal"], True,
     "afcon|champions|1986-2023", "Africa_Cup_of_Nations", "expert"),
    ("كم منتخباً تستطيع أن تسمّي من أبطال كأس آسيا بين 1968 و2023؟",
     ["Iran", "Kuwait", "Saudi Arabia", "Japan", "Iraq", "Australia", "Qatar"], True,
     "asian-cup|champions|1968-2023", "AFC_Asian_Cup", "expert"),
    ("كم منتخباً تستطيع أن تسمّي من أبطال كوبا أمريكا بين 1991 و2024؟",
     ["Argentina", "Uruguay", "Brazil", "Colombia", "Chile"], True, "copa-america|champions|1991-2024",
     "Copa_Am%C3%A9rica", "expert"),
    ("كم لاعباً تستطيع أن تسمّي ممن فازوا بالكرة الذهبية وهم لاعبون في ريال مدريد (حتى 2025)؟",
     ["Alfredo Di Stéfano", "Raymond Kopa", "Luís Figo", "Ronaldo", "Fabio Cannavaro", "Cristiano Ronaldo",
      "Luka Modrić", "Karim Benzema"], True, "ballon-dor|winners-at-real-madrid|to-2025",
     "Ballon_d%27Or", "very_expert"),
    ("كم لاعباً ألمانياً تستطيع أن تسمّي ممن فازوا بالكرة الذهبية (حتى 2025)؟",
     ["Gerd Müller", "Franz Beckenbauer", "Karl-Heinz Rummenigge", "Lothar Matthäus", "Matthias Sammer"], True,
     "ballon-dor|german-winners|to-2025", "Ballon_d%27Or", "very_expert"),
    ("كم لاعباً فرنسياً تستطيع أن تسمّي ممن فازوا بالكرة الذهبية (حتى 2025)؟",
     ["Raymond Kopa", "Michel Platini", "Jean-Pierre Papin", "Zinedine Zidane", "Karim Benzema", "Ousmane Dembélé"],
     True, "ballon-dor|french-winners|to-2025", "Ballon_d%27Or", "expert"),
    ("كم لاعباً إنجليزياً تستطيع أن تسمّي ممن فازوا بالكرة الذهبية (حتى 2025)؟",
     ["Stanley Matthews", "Bobby Charlton", "Kevin Keegan", "Michael Owen"], True,
     "ballon-dor|english-winners|to-2025", "Ballon_d%27Or", "very_expert"),
    ("كم لاعباً برازيلياً تستطيع أن تسمّي ممن فازوا بالكرة الذهبية (حتى 2025)؟",
     ["Ronaldo", "Rivaldo", "Ronaldinho", "Kaká"], True, "ballon-dor|brazilian-winners|to-2025",
     "Ballon_d%27Or", "expert"),
    ("كم مدرباً تستطيع أن تسمّي ممن فازوا بلقب الدوري الإنجليزي الممتاز (حتى موسم 2024-2025)؟",
     ["Alex Ferguson", "Kenny Dalglish", "Arsène Wenger", "José Mourinho", "Carlo Ancelotti", "Roberto Mancini",
      "Manuel Pellegrini", "Claudio Ranieri", "Antonio Conte", "Pep Guardiola", "Jürgen Klopp", "Arne Slot"], True,
     "premier-league|title-winning-managers|to-2025", "List_of_Premier_League_managers", "very_expert"),
    ("كم منتخباً تستطيع أن تسمّي ممن فازوا بكأس العالم وكأس أمم أوروبا معاً (حتى 2024)؟",
     ["Germany", "Spain", "France", "Italy"], True, "world-cup-and-euro|double-winners|to-2024",
     "UEFA_European_Championship", "expert"),
    ("كم نادياً تستطيع أن تسمّي من الأندية التي لعب لها كريستيانو رونالدو (حتى 2025)؟",
     ["Sporting CP", "Manchester United", "Real Madrid", "Juventus", "Al Nassr"], True,
     "cristiano-ronaldo|clubs|to-2025", "Cristiano_Ronaldo", "hard"),
    ("كم نادياً تستطيع أن تسمّي من الأندية التي لعب لها زلاتان إبراهيموفيتش؟",
     ["Malmö FF", "Ajax", "Juventus", "Inter Milan", "Barcelona", "AC Milan", "Paris Saint-Germain",
      "Manchester United", "LA Galaxy"], True, "zlatan-ibrahimovic|clubs", "Zlatan_Ibrahimovi%C4%87", "expert"),
    ("كم منتخباً أفريقياً تستطيع أن تسمّي ممن شاركوا في كأس العالم 2022؟",
     ["Senegal", "Cameroon", "Ghana", "Morocco", "Tunisia"], True, "world-cup-2022|african-teams",
     "2022_FIFA_World_Cup", "hard"),
    ("كم منتخباً عربياً تستطيع أن تسمّي ممن شاركوا في كأس العالم 2022؟",
     ["Qatar", "Saudi Arabia", "Tunisia", "Morocco"], True, "world-cup-2022|arab-teams", "2022_FIFA_World_Cup", "hard"),
    ("كم نادياً إنجليزياً تستطيع أن تسمّي ممن فازوا بكأس أوروبا / دوري الأبطال (حتى 2025)؟",
     ["Manchester United", "Liverpool", "Nottingham Forest", "Aston Villa", "Chelsea", "Manchester City"], True,
     "european-cup|english-winners|to-2025", "List_of_European_Cup_and_UEFA_Champions_League_finals", "very_expert"),
    ("كم نادياً إيطالياً تستطيع أن تسمّي ممن فازوا بكأس أوروبا / دوري الأبطال (حتى 2025)؟",
     ["AC Milan", "Inter Milan", "Juventus"], True, "european-cup|italian-winners|to-2025",
     "List_of_European_Cup_and_UEFA_Champions_League_finals", "expert"),
    ("كم نادياً ألمانياً تستطيع أن تسمّي ممن فازوا بكأس أوروبا / دوري الأبطال (حتى 2025)؟",
     ["Bayern Munich", "Hamburger SV", "Borussia Dortmund"], True, "european-cup|german-winners|to-2025",
     "List_of_European_Cup_and_UEFA_Champions_League_finals", "very_expert"),
    ("كم نادياً هولندياً تستطيع أن تسمّي ممن فازوا بكأس أوروبا / دوري الأبطال (حتى 2025)؟",
     ["Feyenoord", "Ajax", "PSV Eindhoven"], True, "european-cup|dutch-winners|to-2025",
     "List_of_European_Cup_and_UEFA_Champions_League_finals", "very_expert"),
    ("كم نادياً تستطيع أن تسمّي من أبطال كأس العالم للأندية بنظامها القديم (2000–2023)؟",
     ["Corinthians", "São Paulo", "Internacional", "AC Milan", "Manchester United", "Barcelona", "Inter Milan",
      "Bayern Munich", "Real Madrid", "Liverpool", "Chelsea", "Manchester City"], True,
     "club-world-cup|winners|2000-2023", "FIFA_Club_World_Cup", "very_expert"),
    ("كم لاعباً تستطيع أن تسمّي ممن فازوا بالكرة الذهبية ثلاث مرات متتالية (حتى 2025)؟",
     ["Michel Platini", "Lionel Messi"], True, "ballon-dor|three-in-a-row", "Ballon_d%27Or", "very_expert"),
]
P.update({"Kenny Dalglish": "كيني دالغليش", "Arsène Wenger": "أرسين فينغر", "Roberto Mancini": "روبرتو مانشيني",
          "Manuel Pellegrini": "مانويل بيليغريني", "Claudio Ranieri": "كلاوديو رانييري",
          "Antonio Conte": "أنطونيو كونتي", "Arne Slot": "آرني سلوت"})
N.update({"LA Galaxy": "لوس أنجلوس غالاكسي"})
for (q, names, exhaustive, key, page, diff) in AUCTIONS:
    if len(names) < 3:
        continue
    add("auction", diff, q, f"{len(names)}", acc(str(len(names))), [src(page)], key, "المزاد",
        items=items_from(names), exhaustive=exhaustive)

# ================================================================ WRITE
hand = json.load(open(os.path.join(ROOT, "content", "handwritten.json")))["questions"]
allq = hand + out
ids = [q["id"] for q in allq]
assert len(ids) == len(set(ids)), "duplicate ids"
json.dump({"version": 2, "generated": CREATED, "questions": allq},
          open(os.path.join(ROOT, "content", "seed_questions.json"), "w"), ensure_ascii=False, indent=0)
by = {}
for q in allq:
    by[q["category"]] = by.get(q["category"], 0) + 1
print(len(allq), by)
