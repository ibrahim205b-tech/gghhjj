// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class L10nAr extends L10n {
  L10nAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'إنجاز';

  @override
  String get slogan => 'خطوتك اليوم تصنع مستقبلك';

  @override
  String get welcome => 'هلا بيك بإنجاز';

  @override
  String get goodMorning => 'صباح الخير';

  @override
  String get goodEvening => 'مساء الخير';

  @override
  String helloName(Object name) {
    return 'هلا $name';
  }

  @override
  String get todayProgress => 'شكد أنجزت اليوم؟';

  @override
  String get todayTasks => 'شنو عندك اليوم؟';

  @override
  String get studySchedule => 'جدولي الدراسي';

  @override
  String get startStudying => 'يلا نبدي دراسة';

  @override
  String get addTask => 'ضيف مهمة';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get close => 'سد';

  @override
  String get done => 'تم';

  @override
  String get next => 'التالي';

  @override
  String get back => 'رجوع';

  @override
  String get skip => 'تخطي';

  @override
  String get confirm => 'أكد';

  @override
  String get areYouSure => 'متأكد تريد تكمل؟';

  @override
  String get deleteConfirm => 'متأكد تريد تحذفها؟ ما تگدر ترجعها بعدين.';

  @override
  String get noInternet => 'ماكو اتصال بالإنترنت';

  @override
  String get offlineHint => 'تگدر تكمل شغلك، وراح نزامن من يرجع النت.';

  @override
  String get syncing => 'دا نزامن بياناتك...';

  @override
  String get syncDone => 'تمت المزامنة بنجاح';

  @override
  String get syncFailed => 'ما گدرنا نزامن هسه، راح نحاول بعدين';

  @override
  String lastSync(Object when) {
    return 'آخر مزامنة: $when';
  }

  @override
  String get neverSynced => 'بعد ما صارت مزامنة';

  @override
  String get noTasks => 'حالياً ما عندك مهام';

  @override
  String get congrats => 'عاشت إيدك!';

  @override
  String get upcomingExams => 'امتحاناتك الجاية';

  @override
  String get dailyMotivation => 'تحفيز اليوم';

  @override
  String get myNotes => 'ملاحظاتي';

  @override
  String get myLibrary => 'مكتبتي';

  @override
  String get myAchievements => 'إنجازاتي';

  @override
  String get tryAgain => 'حاول مرة ثانية';

  @override
  String get loading => 'لحظة، دا نحمل البيانات...';

  @override
  String get newUpdate => 'أكو تحديث جديد للتطبيق';

  @override
  String get openTelegram => 'افتح قناة التليجرام';

  @override
  String get downloadUpdate => 'نزّل التحديث الجديد';

  @override
  String get updateNow => 'حدّث التطبيق';

  @override
  String get later => 'لاحقاً';

  @override
  String get updateBody =>
      'هلا بيك! أكو تحديث جديد لتطبيق إنجاز. حدّث التطبيق حتى تستفاد من الميزات الجديدة.';

  @override
  String get updateMandatory => 'هذا التحديث ضروري حتى تكمل تستخدم التطبيق.';

  @override
  String get completed => 'مكتمل';

  @override
  String get inProgress => 'دا تشتغل عليه';

  @override
  String get notStarted => 'بعدك ما بديت';

  @override
  String get needsReview => 'يحتاج مراجعة';

  @override
  String get errorGeneric => 'صار خلل، حاول مرة ثانية';

  @override
  String get requiredField => 'هذا الحقل مطلوب';

  @override
  String get seeAll => 'شوف الكل';

  @override
  String get quickActions => 'اختصارات';

  @override
  String get homeTab => 'الرئيسية';

  @override
  String get scheduleTab => 'جدولي';

  @override
  String get subjectsTab => 'موادي';

  @override
  String get examsTab => 'الاختبارات';

  @override
  String get moreTab => 'المزيد';

  @override
  String get onbTitle1 => 'نظّم دراستك';

  @override
  String get onbBody1 => 'جدول، مهام، ومنظم ذكي يرتبلك وقتك حسب امتحاناتك.';

  @override
  String get onbTitle2 => 'تابع تقدمك';

  @override
  String get onbBody2 => 'شوف شكد خلصت من كل مادة، وشكد درست كل يوم.';

  @override
  String get onbTitle3 => 'اختبر نفسك';

  @override
  String get onbBody3 => 'بنك أسئلة ومكتبة ملازم مرتبة حسب صفك وفرعك.';

  @override
  String get getStarted => 'يلا نبدي';

  @override
  String get signInGoogle => 'سجّل دخول بحساب Google';

  @override
  String get continueOffline => 'كمل بدون حساب';

  @override
  String get offlineModeNote =>
      'بدون حساب، بياناتك تبقى على هذا الجهاز بس وما تنزامن.';

  @override
  String get backendMissing =>
      'خدمة الحسابات بعدها ما مفعّلة بهذي النسخة. تگدر تستخدم التطبيق بدون حساب.';

  @override
  String get signInFailed => 'ما گدرنا نسجل دخولك. حاول مرة ثانية.';

  @override
  String get signingIn => 'دا نسجل دخولك...';

  @override
  String get profileSetup => 'عرّفنا بنفسك';

  @override
  String get displayName => 'اسمك';

  @override
  String get displayNameHint => 'شنو تحب نناديك؟';

  @override
  String get governorate => 'المحافظة (اختياري)';

  @override
  String get chooseStage => 'بأي مرحلة أنت؟';

  @override
  String get chooseGrade => 'بأي صف؟';

  @override
  String get chooseBranch => 'شنو فرعك؟';

  @override
  String get chooseYear => 'السنة الدراسية';

  @override
  String get setupDone => 'كلشي جاهز!';

  @override
  String get setupDoneBody => 'هسه نطلعلك المواد والمحتوى الخاص بصفك.';

  @override
  String get enterApp => 'خش للتطبيق';

  @override
  String get subjectsCount => 'المواد';

  @override
  String get weeklyGoal => 'هدف الأسبوع';

  @override
  String get streakDays => 'أيام متواصلة';

  @override
  String tasksOf(Object done, Object total) {
    return '$done من $total مهام';
  }

  @override
  String studiedToday(Object time) {
    return 'درست $time';
  }

  @override
  String hoursMinutes(Object h, Object m) {
    return '$hس $mد';
  }

  @override
  String fromYesterday(Object diff) {
    return '$diff عن البارحة';
  }

  @override
  String get aiStudyPlan => 'رتبلي دراستي';

  @override
  String get studyNow => 'ادرس هسه';

  @override
  String get weeklyPerformance => 'أداءك هذا الأسبوع';

  @override
  String get latestAnnouncements => 'آخر الإعلانات';

  @override
  String get upcomingTasks => 'مهامك الجاية';

  @override
  String get priorityHigh => 'مهم';

  @override
  String get priorityNormal => 'عادي';

  @override
  String get priorityLow => 'مو مستعجل';

  @override
  String get taskTitle => 'عنوان المهمة';

  @override
  String get dueDate => 'تاريخ التسليم';

  @override
  String get startTime => 'يبدي';

  @override
  String get endTime => 'يخلص';

  @override
  String get priority => 'الأهمية';

  @override
  String get subject => 'المادة';

  @override
  String get noSubject => 'بدون مادة';

  @override
  String get estimatedMinutes => 'الوقت المتوقع (دقايق)';

  @override
  String get addSession => 'ضيف حصة دراسة';

  @override
  String get editSession => 'عدّل الحصة';

  @override
  String get sessionTitle => 'شنو راح تدرس؟';

  @override
  String get repeatWeekly => 'تتكرر كل أسبوع';

  @override
  String get breakMinutes => 'الاستراحة (دقايق)';

  @override
  String get note => 'ملاحظة';

  @override
  String get markDone => 'خلصتها';

  @override
  String plannedVsActual(Object planned, Object actual) {
    return 'المخطط: $planned • الفعلي: $actual';
  }

  @override
  String get listView => 'قائمة';

  @override
  String get calendarView => 'تقويم';

  @override
  String get noSessions => 'ماكو حصص بهذا اليوم';

  @override
  String get weekdays => 'الاثنين,الثلاثاء,الأربعاء,الخميس,الجمعة,السبت,الأحد';

  @override
  String get chapters => 'الفصول';

  @override
  String get topics => 'المواضيع';

  @override
  String get difficultTopic => 'موضوع صعب';

  @override
  String get markDifficult => 'علّمه صعب';

  @override
  String get revision => 'مراجعة';

  @override
  String get noSubjects =>
      'بعد ما انضافت مواد لصفك. راح تطلع هنا أول ما تنضاف.';

  @override
  String subjectProgress(Object percent) {
    return 'خلصت $percent٪';
  }

  @override
  String get difficulty => 'الصعوبة';

  @override
  String get easy => 'سهل';

  @override
  String get medium => 'متوسط';

  @override
  String get hard => 'صعب';

  @override
  String get planner => 'المنظم الذكي';

  @override
  String get plannerIntro =>
      'گلّي شكد ساعة تگدر تدرس باليوم، وأني أوزعلك المواضيع الباقية حسب الصعوبة وموعد الامتحانات.';

  @override
  String get dailyHours => 'ساعات الدراسة باليوم';

  @override
  String get planDays => 'لكم يوم أرتب؟';

  @override
  String get generatePlan => 'رتبلي الخطة';

  @override
  String planReady(Object count) {
    return 'رتبتلك $count مهمة. بالتوفيق!';
  }

  @override
  String behindSchedule(Object count) {
    return 'عندك $count مهام فاتت وما خلصتها';
  }

  @override
  String get redistribute => 'وزعها من جديد';

  @override
  String get redistributed => 'رتبنا المهام اللي فاتتك على الأيام الجاية';

  @override
  String get nothingToPlan => 'ماكو مواضيع باقية حتى نرتبها. يا سلام!';

  @override
  String get exams => 'امتحاناتي';

  @override
  String get addExam => 'ضيف امتحان';

  @override
  String get examTitle => 'اسم الامتحان';

  @override
  String get examDate => 'موعد الامتحان';

  @override
  String get officialExam => 'موعد رسمي';

  @override
  String get personalExam => 'تذكير شخصي';

  @override
  String daysLeft(Object days) {
    return 'باقي $days يوم';
  }

  @override
  String get examToday => 'الامتحان اليوم!';

  @override
  String get examTomorrow => 'عندك امتحان باچر';

  @override
  String get examPassed => 'خلص';

  @override
  String get score => 'الدرجة';

  @override
  String get maxScore => 'من كم';

  @override
  String get targetScore => 'الدرجة اللي تريدها';

  @override
  String get recordScore => 'سجّل درجتك';

  @override
  String requiredScore(Object target, Object needed) {
    return 'حتى توصل لمعدل $target تحتاج $needed بالامتحانات الباقية';
  }

  @override
  String get source => 'المصدر';

  @override
  String get noExams => 'ماكو امتحانات جاية';

  @override
  String get questionBank => 'بنك الأسئلة';

  @override
  String get startTest => 'ابدي الاختبار';

  @override
  String get timedTest => 'بوقت';

  @override
  String get untimedTest => 'بدون وقت';

  @override
  String get chooseSubject => 'اختار المادة';

  @override
  String get chooseChapter => 'اختار الفصل (اختياري)';

  @override
  String get allChapters => 'كل الفصول';

  @override
  String get questionsCount => 'عدد الأسئلة';

  @override
  String get noQuestions => 'بعد ماكو أسئلة منشورة لهذا الاختيار.';

  @override
  String questionNofM(Object n, Object m) {
    return 'سؤال $n من $m';
  }

  @override
  String get trueLabel => 'صح';

  @override
  String get falseLabel => 'غلط';

  @override
  String get yourAnswer => 'جوابك';

  @override
  String get typeAnswer => 'اكتب جوابك هنا';

  @override
  String get submit => 'سلّم';

  @override
  String get submitConfirm => 'متأكد تريد تسلم؟ باقي أسئلة ما جاوبتها.';

  @override
  String get result => 'النتيجة';

  @override
  String correctOf(Object correct, Object total) {
    return '$correct صح من $total';
  }

  @override
  String get reviewAnswers => 'راجع الأجوبة';

  @override
  String get explanation => 'الشرح';

  @override
  String get correctAnswer => 'الجواب الصح';

  @override
  String get saveQuestion => 'احفظ السؤال';

  @override
  String get savedQuestions => 'الأسئلة المحفوظة';

  @override
  String get retryMistakes => 'عيد الأسئلة اللي غلطت بيها';

  @override
  String get testHistory => 'سجل الاختبارات';

  @override
  String get timeUp => 'خلص الوقت!';

  @override
  String get officialSourceBadge => 'سؤال وزاري';

  @override
  String get practiceBadge => 'سؤال تدريبي';

  @override
  String get library => 'المكتبة';

  @override
  String get search => 'دوّر...';

  @override
  String get allTypes => 'الكل';

  @override
  String get download => 'نزّل';

  @override
  String get downloading => 'دا ننزل...';

  @override
  String get downloaded => 'منزّل على جهازك';

  @override
  String get open => 'افتح';

  @override
  String get favorites => 'المفضلة';

  @override
  String get readingHistory => 'قريتها مؤخراً';

  @override
  String get noFiles => 'ماكو ملفات بعد';

  @override
  String fileSize(Object size) {
    return 'الحجم: $size';
  }

  @override
  String get needOnlineToDownload => 'تحتاج إنترنت حتى تنزل الملف أول مرة';

  @override
  String get motivation => 'التحفيز';

  @override
  String get share => 'شارك';

  @override
  String get previousMotivation => 'تحفيزات سابقة';

  @override
  String get noMotivation => 'بعد ماكو تحفيز منشور';

  @override
  String get tools => 'الأدوات';

  @override
  String get pomodoro => 'بومودورو';

  @override
  String get focusTime => 'وقت التركيز';

  @override
  String get breakTime => 'وقت الاستراحة';

  @override
  String get start => 'ابدي';

  @override
  String get pause => 'وكف';

  @override
  String get resume => 'كمّل';

  @override
  String get reset => 'صفّر';

  @override
  String get stopwatch => 'ساعة إيقاف';

  @override
  String get saveStudyTime => 'سجّل وقت الدراسة';

  @override
  String studyTimeSaved(Object minutes) {
    return 'سجلنا $minutes دقيقة دراسة. عاشت إيدك!';
  }

  @override
  String get gradeCalculator => 'حاسبة المعدل';

  @override
  String get percentageCalculator => 'حاسبة النسبة';

  @override
  String get addRow => 'ضيف مادة';

  @override
  String get average => 'المعدل';

  @override
  String get value => 'القيمة';

  @override
  String get total => 'المجموع';

  @override
  String get percentage => 'النسبة';

  @override
  String get tasks => 'مهامي';

  @override
  String get expenses => 'مصاريفي';

  @override
  String get addExpense => 'ضيف مصروف';

  @override
  String get amount => 'المبلغ (دينار)';

  @override
  String get monthTotal => 'مجموع هذا الشهر';

  @override
  String get goals => 'أهدافي';

  @override
  String get weeklyGoals => 'أهداف الأسبوع';

  @override
  String get monthlyGoals => 'أهداف الشهر';

  @override
  String get addGoal => 'ضيف هدف';

  @override
  String get goalTitle => 'شنو هدفك؟';

  @override
  String get targetValue => 'الهدف';

  @override
  String get progressValue => 'وصلت';

  @override
  String get statistics => 'إحصائياتي';

  @override
  String get totalStudyHours => 'مجموع ساعات الدراسة';

  @override
  String get tasksCompleted => 'مهام خلصتها';

  @override
  String get testsTaken => 'اختبارات سويتها';

  @override
  String get avgScore => 'معدل درجاتك';

  @override
  String get achievementLocked => 'بعدك ما وصلتله';

  @override
  String get reminders => 'التذكيرات';

  @override
  String get addNote => 'ضيف ملاحظة';

  @override
  String get noteTitle => 'العنوان';

  @override
  String get noteBody => 'اكتب ملاحظتك...';

  @override
  String get noNotes => 'ماكو ملاحظات بعد';

  @override
  String get guidance => 'دليل الجامعات';

  @override
  String get guidanceIntro => 'معلومات عن الجامعات والكليات ومعدلات القبول.';

  @override
  String get admissionAverage => 'معدل القبول';

  @override
  String get deadline => 'آخر موعد للتقديم';

  @override
  String lastUpdated(Object date) {
    return 'آخر تحديث: $date';
  }

  @override
  String get officialInfo => 'معلومة رسمية موثقة';

  @override
  String get unofficialInfo => 'معلومة غير رسمية — تأكد منها';

  @override
  String get noGuidance => 'بعد ماكو معلومات منشورة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get profile => 'ملفي الشخصي';

  @override
  String get editProfile => 'عدّل ملفي';

  @override
  String get academicInfo => 'معلوماتي الدراسية';

  @override
  String get changeYear => 'غيّر السنة أو الصف';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get motivationNotifications => 'إشعارات التحفيز';

  @override
  String get studyReminders => 'تذكيرات الدراسة';

  @override
  String get examReminders => 'تذكيرات الامتحانات';

  @override
  String get announcementNotifications => 'الإعلانات';

  @override
  String get theme => 'المظهر';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeSystem => 'حسب الجهاز';

  @override
  String get cloudSync => 'المزامنة السحابية';

  @override
  String get syncNow => 'زامن هسه';

  @override
  String get exportData => 'صدّر بياناتي';

  @override
  String get exportReady => 'جهزنا ملف بياناتك';

  @override
  String get deleteAccount => 'احذف حسابي';

  @override
  String get deleteAccountBody =>
      'راح نحذف حسابك وكل بياناتك من السيرفر ومن هذا الجهاز. هذا الشي ما يرجع.';

  @override
  String get accountDeleted => 'انحذف حسابك';

  @override
  String get signOut => 'سجّل خروج';

  @override
  String get signIn => 'سجّل دخول';

  @override
  String appVersion(Object version) {
    return 'نسخة التطبيق $version';
  }

  @override
  String get privacy => 'الخصوصية';

  @override
  String get privacyBody =>
      'بياناتك الدراسية إلك وحدك. ما نبيعها ولا نشاركها. المزامنة اختيارية، وتگدر تصدّر بياناتك أو تحذف حسابك متى ما تريد. ما نطلب ولا نحفظ كلمة سر حساب Google مالتك.';

  @override
  String get localAccount => 'حساب محلي (بدون مزامنة)';

  @override
  String get announcement => 'إعلان';

  @override
  String get gotIt => 'تمام، فهمت';

  @override
  String get dismiss => 'سد';

  @override
  String get accountSuspended =>
      'حسابك موقوف مؤقتاً. تواصل ويانا إذا تعتقد أكو غلط.';

  @override
  String minutesShort(Object m) {
    return '$m د';
  }

  @override
  String get today => 'اليوم';

  @override
  String get tomorrow => 'باچر';

  @override
  String get yesterday => 'البارحة';

  @override
  String get calendar => 'التقويم';

  @override
  String get achievement_first_task => 'أول مهمة!';

  @override
  String get achievement_tasks_50 => '50 مهمة';

  @override
  String get achievement_streak_3 => '3 أيام متواصلة';

  @override
  String get achievement_streak_7 => 'أسبوع كامل';

  @override
  String get achievement_streak_30 => 'شهر بلا توقف';

  @override
  String get achievement_hours_10 => '10 ساعات دراسة';

  @override
  String get achievement_hours_100 => '100 ساعة دراسة';

  @override
  String get achievement_first_test => 'أول اختبار';

  @override
  String get achievement_perfect_test => 'درجة كاملة';

  @override
  String achievementUnlocked(Object name) {
    return 'عاشت إيدك! حصلت على إنجاز: $name';
  }

  @override
  String get notifStudyTitle => 'وكت الدراسة!';

  @override
  String notifStudyBody(Object title) {
    return 'عندك حصة $title هسه. يلا نبدي!';
  }

  @override
  String get notifExamTitle => 'انتبه، عندك امتحان باچر';

  @override
  String notifExamBody(Object title) {
    return '$title — راجع زين وبالتوفيق!';
  }

  @override
  String get pomodoroDone => 'خلص وقت التركيز! خذلك استراحة.';

  @override
  String get breakDone => 'خلصت الاستراحة، يلا نرجع للدراسة.';

  @override
  String get dayUnit => 'يوم';

  @override
  String get months =>
      'كانون الثاني,شباط,آذار,نيسان,أيار,حزيران,تموز,آب,أيلول,تشرين الأول,تشرين الثاني,كانون الأول';

  @override
  String get uniPublic => 'حكومية';

  @override
  String get uniPrivate => 'أهلية';

  @override
  String get uniInstitute => 'معهد';

  @override
  String get channelCentral => 'القبول المركزي';

  @override
  String get channelParallel => 'الدراسة الموازية';

  @override
  String get channelEvening => 'الدراسة المسائية';

  @override
  String get channelPrivate => 'الكليات الأهلية';

  @override
  String get channelScholarship => 'منحة';

  @override
  String get channelOther => 'أخرى';

  @override
  String get currencyIqd => 'دينار';
}
