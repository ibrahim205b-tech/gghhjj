import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ar')];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'إنجاز'**
  String get appName;

  /// No description provided for @slogan.
  ///
  /// In ar, this message translates to:
  /// **'خطوتك اليوم تصنع مستقبلك'**
  String get slogan;

  /// No description provided for @welcome.
  ///
  /// In ar, this message translates to:
  /// **'هلا بيك بإنجاز'**
  String get welcome;

  /// No description provided for @goodMorning.
  ///
  /// In ar, this message translates to:
  /// **'صباح الخير'**
  String get goodMorning;

  /// No description provided for @goodEvening.
  ///
  /// In ar, this message translates to:
  /// **'مساء الخير'**
  String get goodEvening;

  /// No description provided for @helloName.
  ///
  /// In ar, this message translates to:
  /// **'هلا {name}'**
  String helloName(Object name);

  /// No description provided for @todayProgress.
  ///
  /// In ar, this message translates to:
  /// **'شكد أنجزت اليوم؟'**
  String get todayProgress;

  /// No description provided for @todayTasks.
  ///
  /// In ar, this message translates to:
  /// **'شنو عندك اليوم؟'**
  String get todayTasks;

  /// No description provided for @studySchedule.
  ///
  /// In ar, this message translates to:
  /// **'جدولي الدراسي'**
  String get studySchedule;

  /// No description provided for @startStudying.
  ///
  /// In ar, this message translates to:
  /// **'يلا نبدي دراسة'**
  String get startStudying;

  /// No description provided for @addTask.
  ///
  /// In ar, this message translates to:
  /// **'ضيف مهمة'**
  String get addTask;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In ar, this message translates to:
  /// **'سد'**
  String get close;

  /// No description provided for @done.
  ///
  /// In ar, this message translates to:
  /// **'تم'**
  String get done;

  /// No description provided for @next.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get next;

  /// No description provided for @back.
  ///
  /// In ar, this message translates to:
  /// **'رجوع'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get skip;

  /// No description provided for @confirm.
  ///
  /// In ar, this message translates to:
  /// **'أكد'**
  String get confirm;

  /// No description provided for @areYouSure.
  ///
  /// In ar, this message translates to:
  /// **'متأكد تريد تكمل؟'**
  String get areYouSure;

  /// No description provided for @deleteConfirm.
  ///
  /// In ar, this message translates to:
  /// **'متأكد تريد تحذفها؟ ما تگدر ترجعها بعدين.'**
  String get deleteConfirm;

  /// No description provided for @noInternet.
  ///
  /// In ar, this message translates to:
  /// **'ماكو اتصال بالإنترنت'**
  String get noInternet;

  /// No description provided for @offlineHint.
  ///
  /// In ar, this message translates to:
  /// **'تگدر تكمل شغلك، وراح نزامن من يرجع النت.'**
  String get offlineHint;

  /// No description provided for @syncing.
  ///
  /// In ar, this message translates to:
  /// **'دا نزامن بياناتك...'**
  String get syncing;

  /// No description provided for @syncDone.
  ///
  /// In ar, this message translates to:
  /// **'تمت المزامنة بنجاح'**
  String get syncDone;

  /// No description provided for @syncFailed.
  ///
  /// In ar, this message translates to:
  /// **'ما گدرنا نزامن هسه، راح نحاول بعدين'**
  String get syncFailed;

  /// No description provided for @lastSync.
  ///
  /// In ar, this message translates to:
  /// **'آخر مزامنة: {when}'**
  String lastSync(Object when);

  /// No description provided for @neverSynced.
  ///
  /// In ar, this message translates to:
  /// **'بعد ما صارت مزامنة'**
  String get neverSynced;

  /// No description provided for @noTasks.
  ///
  /// In ar, this message translates to:
  /// **'حالياً ما عندك مهام'**
  String get noTasks;

  /// No description provided for @congrats.
  ///
  /// In ar, this message translates to:
  /// **'عاشت إيدك!'**
  String get congrats;

  /// No description provided for @upcomingExams.
  ///
  /// In ar, this message translates to:
  /// **'امتحاناتك الجاية'**
  String get upcomingExams;

  /// No description provided for @dailyMotivation.
  ///
  /// In ar, this message translates to:
  /// **'تحفيز اليوم'**
  String get dailyMotivation;

  /// No description provided for @myNotes.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظاتي'**
  String get myNotes;

  /// No description provided for @myLibrary.
  ///
  /// In ar, this message translates to:
  /// **'مكتبتي'**
  String get myLibrary;

  /// No description provided for @myAchievements.
  ///
  /// In ar, this message translates to:
  /// **'إنجازاتي'**
  String get myAchievements;

  /// No description provided for @tryAgain.
  ///
  /// In ar, this message translates to:
  /// **'حاول مرة ثانية'**
  String get tryAgain;

  /// No description provided for @loading.
  ///
  /// In ar, this message translates to:
  /// **'لحظة، دا نحمل البيانات...'**
  String get loading;

  /// No description provided for @newUpdate.
  ///
  /// In ar, this message translates to:
  /// **'أكو تحديث جديد للتطبيق'**
  String get newUpdate;

  /// No description provided for @openTelegram.
  ///
  /// In ar, this message translates to:
  /// **'افتح قناة التليجرام'**
  String get openTelegram;

  /// No description provided for @downloadUpdate.
  ///
  /// In ar, this message translates to:
  /// **'نزّل التحديث الجديد'**
  String get downloadUpdate;

  /// No description provided for @updateNow.
  ///
  /// In ar, this message translates to:
  /// **'حدّث التطبيق'**
  String get updateNow;

  /// No description provided for @later.
  ///
  /// In ar, this message translates to:
  /// **'لاحقاً'**
  String get later;

  /// No description provided for @updateBody.
  ///
  /// In ar, this message translates to:
  /// **'هلا بيك! أكو تحديث جديد لتطبيق إنجاز. حدّث التطبيق حتى تستفاد من الميزات الجديدة.'**
  String get updateBody;

  /// No description provided for @updateMandatory.
  ///
  /// In ar, this message translates to:
  /// **'هذا التحديث ضروري حتى تكمل تستخدم التطبيق.'**
  String get updateMandatory;

  /// No description provided for @completed.
  ///
  /// In ar, this message translates to:
  /// **'مكتمل'**
  String get completed;

  /// No description provided for @inProgress.
  ///
  /// In ar, this message translates to:
  /// **'دا تشتغل عليه'**
  String get inProgress;

  /// No description provided for @notStarted.
  ///
  /// In ar, this message translates to:
  /// **'بعدك ما بديت'**
  String get notStarted;

  /// No description provided for @needsReview.
  ///
  /// In ar, this message translates to:
  /// **'يحتاج مراجعة'**
  String get needsReview;

  /// No description provided for @errorGeneric.
  ///
  /// In ar, this message translates to:
  /// **'صار خلل، حاول مرة ثانية'**
  String get errorGeneric;

  /// No description provided for @requiredField.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل مطلوب'**
  String get requiredField;

  /// No description provided for @seeAll.
  ///
  /// In ar, this message translates to:
  /// **'شوف الكل'**
  String get seeAll;

  /// No description provided for @quickActions.
  ///
  /// In ar, this message translates to:
  /// **'اختصارات'**
  String get quickActions;

  /// No description provided for @homeTab.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get homeTab;

  /// No description provided for @scheduleTab.
  ///
  /// In ar, this message translates to:
  /// **'جدولي'**
  String get scheduleTab;

  /// No description provided for @subjectsTab.
  ///
  /// In ar, this message translates to:
  /// **'موادي'**
  String get subjectsTab;

  /// No description provided for @examsTab.
  ///
  /// In ar, this message translates to:
  /// **'الاختبارات'**
  String get examsTab;

  /// No description provided for @moreTab.
  ///
  /// In ar, this message translates to:
  /// **'المزيد'**
  String get moreTab;

  /// No description provided for @onbTitle1.
  ///
  /// In ar, this message translates to:
  /// **'نظّم دراستك'**
  String get onbTitle1;

  /// No description provided for @onbBody1.
  ///
  /// In ar, this message translates to:
  /// **'جدول، مهام، ومنظم ذكي يرتبلك وقتك حسب امتحاناتك.'**
  String get onbBody1;

  /// No description provided for @onbTitle2.
  ///
  /// In ar, this message translates to:
  /// **'تابع تقدمك'**
  String get onbTitle2;

  /// No description provided for @onbBody2.
  ///
  /// In ar, this message translates to:
  /// **'شوف شكد خلصت من كل مادة، وشكد درست كل يوم.'**
  String get onbBody2;

  /// No description provided for @onbTitle3.
  ///
  /// In ar, this message translates to:
  /// **'اختبر نفسك'**
  String get onbTitle3;

  /// No description provided for @onbBody3.
  ///
  /// In ar, this message translates to:
  /// **'بنك أسئلة ومكتبة ملازم مرتبة حسب صفك وفرعك.'**
  String get onbBody3;

  /// No description provided for @getStarted.
  ///
  /// In ar, this message translates to:
  /// **'يلا نبدي'**
  String get getStarted;

  /// No description provided for @signInGoogle.
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول بحساب Google'**
  String get signInGoogle;

  /// No description provided for @continueOffline.
  ///
  /// In ar, this message translates to:
  /// **'كمل بدون حساب'**
  String get continueOffline;

  /// No description provided for @offlineModeNote.
  ///
  /// In ar, this message translates to:
  /// **'بدون حساب، بياناتك تبقى على هذا الجهاز بس وما تنزامن.'**
  String get offlineModeNote;

  /// No description provided for @backendMissing.
  ///
  /// In ar, this message translates to:
  /// **'خدمة الحسابات بعدها ما مفعّلة بهذي النسخة. تگدر تستخدم التطبيق بدون حساب.'**
  String get backendMissing;

  /// No description provided for @signInFailed.
  ///
  /// In ar, this message translates to:
  /// **'ما گدرنا نسجل دخولك. حاول مرة ثانية.'**
  String get signInFailed;

  /// No description provided for @signingIn.
  ///
  /// In ar, this message translates to:
  /// **'دا نسجل دخولك...'**
  String get signingIn;

  /// No description provided for @profileSetup.
  ///
  /// In ar, this message translates to:
  /// **'عرّفنا بنفسك'**
  String get profileSetup;

  /// No description provided for @displayName.
  ///
  /// In ar, this message translates to:
  /// **'اسمك'**
  String get displayName;

  /// No description provided for @displayNameHint.
  ///
  /// In ar, this message translates to:
  /// **'شنو تحب نناديك؟'**
  String get displayNameHint;

  /// No description provided for @governorate.
  ///
  /// In ar, this message translates to:
  /// **'المحافظة (اختياري)'**
  String get governorate;

  /// No description provided for @chooseStage.
  ///
  /// In ar, this message translates to:
  /// **'بأي مرحلة أنت؟'**
  String get chooseStage;

  /// No description provided for @chooseGrade.
  ///
  /// In ar, this message translates to:
  /// **'بأي صف؟'**
  String get chooseGrade;

  /// No description provided for @chooseBranch.
  ///
  /// In ar, this message translates to:
  /// **'شنو فرعك؟'**
  String get chooseBranch;

  /// No description provided for @chooseYear.
  ///
  /// In ar, this message translates to:
  /// **'السنة الدراسية'**
  String get chooseYear;

  /// No description provided for @setupDone.
  ///
  /// In ar, this message translates to:
  /// **'كلشي جاهز!'**
  String get setupDone;

  /// No description provided for @setupDoneBody.
  ///
  /// In ar, this message translates to:
  /// **'هسه نطلعلك المواد والمحتوى الخاص بصفك.'**
  String get setupDoneBody;

  /// No description provided for @enterApp.
  ///
  /// In ar, this message translates to:
  /// **'خش للتطبيق'**
  String get enterApp;

  /// No description provided for @subjectsCount.
  ///
  /// In ar, this message translates to:
  /// **'المواد'**
  String get subjectsCount;

  /// No description provided for @weeklyGoal.
  ///
  /// In ar, this message translates to:
  /// **'هدف الأسبوع'**
  String get weeklyGoal;

  /// No description provided for @streakDays.
  ///
  /// In ar, this message translates to:
  /// **'أيام متواصلة'**
  String get streakDays;

  /// No description provided for @tasksOf.
  ///
  /// In ar, this message translates to:
  /// **'{done} من {total} مهام'**
  String tasksOf(Object done, Object total);

  /// No description provided for @studiedToday.
  ///
  /// In ar, this message translates to:
  /// **'درست {time}'**
  String studiedToday(Object time);

  /// No description provided for @hoursMinutes.
  ///
  /// In ar, this message translates to:
  /// **'{h}س {m}د'**
  String hoursMinutes(Object h, Object m);

  /// No description provided for @fromYesterday.
  ///
  /// In ar, this message translates to:
  /// **'{diff} عن البارحة'**
  String fromYesterday(Object diff);

  /// No description provided for @aiStudyPlan.
  ///
  /// In ar, this message translates to:
  /// **'رتبلي دراستي'**
  String get aiStudyPlan;

  /// No description provided for @studyNow.
  ///
  /// In ar, this message translates to:
  /// **'ادرس هسه'**
  String get studyNow;

  /// No description provided for @weeklyPerformance.
  ///
  /// In ar, this message translates to:
  /// **'أداءك هذا الأسبوع'**
  String get weeklyPerformance;

  /// No description provided for @latestAnnouncements.
  ///
  /// In ar, this message translates to:
  /// **'آخر الإعلانات'**
  String get latestAnnouncements;

  /// No description provided for @upcomingTasks.
  ///
  /// In ar, this message translates to:
  /// **'مهامك الجاية'**
  String get upcomingTasks;

  /// No description provided for @priorityHigh.
  ///
  /// In ar, this message translates to:
  /// **'مهم'**
  String get priorityHigh;

  /// No description provided for @priorityNormal.
  ///
  /// In ar, this message translates to:
  /// **'عادي'**
  String get priorityNormal;

  /// No description provided for @priorityLow.
  ///
  /// In ar, this message translates to:
  /// **'مو مستعجل'**
  String get priorityLow;

  /// No description provided for @taskTitle.
  ///
  /// In ar, this message translates to:
  /// **'عنوان المهمة'**
  String get taskTitle;

  /// No description provided for @dueDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ التسليم'**
  String get dueDate;

  /// No description provided for @startTime.
  ///
  /// In ar, this message translates to:
  /// **'يبدي'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In ar, this message translates to:
  /// **'يخلص'**
  String get endTime;

  /// No description provided for @priority.
  ///
  /// In ar, this message translates to:
  /// **'الأهمية'**
  String get priority;

  /// No description provided for @subject.
  ///
  /// In ar, this message translates to:
  /// **'المادة'**
  String get subject;

  /// No description provided for @noSubject.
  ///
  /// In ar, this message translates to:
  /// **'بدون مادة'**
  String get noSubject;

  /// No description provided for @estimatedMinutes.
  ///
  /// In ar, this message translates to:
  /// **'الوقت المتوقع (دقايق)'**
  String get estimatedMinutes;

  /// No description provided for @addSession.
  ///
  /// In ar, this message translates to:
  /// **'ضيف حصة دراسة'**
  String get addSession;

  /// No description provided for @editSession.
  ///
  /// In ar, this message translates to:
  /// **'عدّل الحصة'**
  String get editSession;

  /// No description provided for @sessionTitle.
  ///
  /// In ar, this message translates to:
  /// **'شنو راح تدرس؟'**
  String get sessionTitle;

  /// No description provided for @repeatWeekly.
  ///
  /// In ar, this message translates to:
  /// **'تتكرر كل أسبوع'**
  String get repeatWeekly;

  /// No description provided for @breakMinutes.
  ///
  /// In ar, this message translates to:
  /// **'الاستراحة (دقايق)'**
  String get breakMinutes;

  /// No description provided for @note.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظة'**
  String get note;

  /// No description provided for @markDone.
  ///
  /// In ar, this message translates to:
  /// **'خلصتها'**
  String get markDone;

  /// No description provided for @plannedVsActual.
  ///
  /// In ar, this message translates to:
  /// **'المخطط: {planned} • الفعلي: {actual}'**
  String plannedVsActual(Object planned, Object actual);

  /// No description provided for @listView.
  ///
  /// In ar, this message translates to:
  /// **'قائمة'**
  String get listView;

  /// No description provided for @calendarView.
  ///
  /// In ar, this message translates to:
  /// **'تقويم'**
  String get calendarView;

  /// No description provided for @noSessions.
  ///
  /// In ar, this message translates to:
  /// **'ماكو حصص بهذا اليوم'**
  String get noSessions;

  /// No description provided for @weekdays.
  ///
  /// In ar, this message translates to:
  /// **'الاثنين,الثلاثاء,الأربعاء,الخميس,الجمعة,السبت,الأحد'**
  String get weekdays;

  /// No description provided for @chapters.
  ///
  /// In ar, this message translates to:
  /// **'الفصول'**
  String get chapters;

  /// No description provided for @topics.
  ///
  /// In ar, this message translates to:
  /// **'المواضيع'**
  String get topics;

  /// No description provided for @difficultTopic.
  ///
  /// In ar, this message translates to:
  /// **'موضوع صعب'**
  String get difficultTopic;

  /// No description provided for @markDifficult.
  ///
  /// In ar, this message translates to:
  /// **'علّمه صعب'**
  String get markDifficult;

  /// No description provided for @revision.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة'**
  String get revision;

  /// No description provided for @noSubjects.
  ///
  /// In ar, this message translates to:
  /// **'بعد ما انضافت مواد لصفك. راح تطلع هنا أول ما تنضاف.'**
  String get noSubjects;

  /// No description provided for @subjectProgress.
  ///
  /// In ar, this message translates to:
  /// **'خلصت {percent}٪'**
  String subjectProgress(Object percent);

  /// No description provided for @difficulty.
  ///
  /// In ar, this message translates to:
  /// **'الصعوبة'**
  String get difficulty;

  /// No description provided for @easy.
  ///
  /// In ar, this message translates to:
  /// **'سهل'**
  String get easy;

  /// No description provided for @medium.
  ///
  /// In ar, this message translates to:
  /// **'متوسط'**
  String get medium;

  /// No description provided for @hard.
  ///
  /// In ar, this message translates to:
  /// **'صعب'**
  String get hard;

  /// No description provided for @planner.
  ///
  /// In ar, this message translates to:
  /// **'المنظم الذكي'**
  String get planner;

  /// No description provided for @plannerIntro.
  ///
  /// In ar, this message translates to:
  /// **'گلّي شكد ساعة تگدر تدرس باليوم، وأني أوزعلك المواضيع الباقية حسب الصعوبة وموعد الامتحانات.'**
  String get plannerIntro;

  /// No description provided for @dailyHours.
  ///
  /// In ar, this message translates to:
  /// **'ساعات الدراسة باليوم'**
  String get dailyHours;

  /// No description provided for @planDays.
  ///
  /// In ar, this message translates to:
  /// **'لكم يوم أرتب؟'**
  String get planDays;

  /// No description provided for @generatePlan.
  ///
  /// In ar, this message translates to:
  /// **'رتبلي الخطة'**
  String get generatePlan;

  /// No description provided for @planReady.
  ///
  /// In ar, this message translates to:
  /// **'رتبتلك {count} مهمة. بالتوفيق!'**
  String planReady(Object count);

  /// No description provided for @behindSchedule.
  ///
  /// In ar, this message translates to:
  /// **'عندك {count} مهام فاتت وما خلصتها'**
  String behindSchedule(Object count);

  /// No description provided for @redistribute.
  ///
  /// In ar, this message translates to:
  /// **'وزعها من جديد'**
  String get redistribute;

  /// No description provided for @redistributed.
  ///
  /// In ar, this message translates to:
  /// **'رتبنا المهام اللي فاتتك على الأيام الجاية'**
  String get redistributed;

  /// No description provided for @nothingToPlan.
  ///
  /// In ar, this message translates to:
  /// **'ماكو مواضيع باقية حتى نرتبها. يا سلام!'**
  String get nothingToPlan;

  /// No description provided for @exams.
  ///
  /// In ar, this message translates to:
  /// **'امتحاناتي'**
  String get exams;

  /// No description provided for @addExam.
  ///
  /// In ar, this message translates to:
  /// **'ضيف امتحان'**
  String get addExam;

  /// No description provided for @examTitle.
  ///
  /// In ar, this message translates to:
  /// **'اسم الامتحان'**
  String get examTitle;

  /// No description provided for @examDate.
  ///
  /// In ar, this message translates to:
  /// **'موعد الامتحان'**
  String get examDate;

  /// No description provided for @officialExam.
  ///
  /// In ar, this message translates to:
  /// **'موعد رسمي'**
  String get officialExam;

  /// No description provided for @personalExam.
  ///
  /// In ar, this message translates to:
  /// **'تذكير شخصي'**
  String get personalExam;

  /// No description provided for @daysLeft.
  ///
  /// In ar, this message translates to:
  /// **'باقي {days} يوم'**
  String daysLeft(Object days);

  /// No description provided for @examToday.
  ///
  /// In ar, this message translates to:
  /// **'الامتحان اليوم!'**
  String get examToday;

  /// No description provided for @examTomorrow.
  ///
  /// In ar, this message translates to:
  /// **'عندك امتحان باچر'**
  String get examTomorrow;

  /// No description provided for @examPassed.
  ///
  /// In ar, this message translates to:
  /// **'خلص'**
  String get examPassed;

  /// No description provided for @score.
  ///
  /// In ar, this message translates to:
  /// **'الدرجة'**
  String get score;

  /// No description provided for @maxScore.
  ///
  /// In ar, this message translates to:
  /// **'من كم'**
  String get maxScore;

  /// No description provided for @targetScore.
  ///
  /// In ar, this message translates to:
  /// **'الدرجة اللي تريدها'**
  String get targetScore;

  /// No description provided for @recordScore.
  ///
  /// In ar, this message translates to:
  /// **'سجّل درجتك'**
  String get recordScore;

  /// No description provided for @requiredScore.
  ///
  /// In ar, this message translates to:
  /// **'حتى توصل لمعدل {target} تحتاج {needed} بالامتحانات الباقية'**
  String requiredScore(Object target, Object needed);

  /// No description provided for @source.
  ///
  /// In ar, this message translates to:
  /// **'المصدر'**
  String get source;

  /// No description provided for @noExams.
  ///
  /// In ar, this message translates to:
  /// **'ماكو امتحانات جاية'**
  String get noExams;

  /// No description provided for @questionBank.
  ///
  /// In ar, this message translates to:
  /// **'بنك الأسئلة'**
  String get questionBank;

  /// No description provided for @startTest.
  ///
  /// In ar, this message translates to:
  /// **'ابدي الاختبار'**
  String get startTest;

  /// No description provided for @timedTest.
  ///
  /// In ar, this message translates to:
  /// **'بوقت'**
  String get timedTest;

  /// No description provided for @untimedTest.
  ///
  /// In ar, this message translates to:
  /// **'بدون وقت'**
  String get untimedTest;

  /// No description provided for @chooseSubject.
  ///
  /// In ar, this message translates to:
  /// **'اختار المادة'**
  String get chooseSubject;

  /// No description provided for @chooseChapter.
  ///
  /// In ar, this message translates to:
  /// **'اختار الفصل (اختياري)'**
  String get chooseChapter;

  /// No description provided for @allChapters.
  ///
  /// In ar, this message translates to:
  /// **'كل الفصول'**
  String get allChapters;

  /// No description provided for @questionsCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد الأسئلة'**
  String get questionsCount;

  /// No description provided for @noQuestions.
  ///
  /// In ar, this message translates to:
  /// **'بعد ماكو أسئلة منشورة لهذا الاختيار.'**
  String get noQuestions;

  /// No description provided for @questionNofM.
  ///
  /// In ar, this message translates to:
  /// **'سؤال {n} من {m}'**
  String questionNofM(Object n, Object m);

  /// No description provided for @trueLabel.
  ///
  /// In ar, this message translates to:
  /// **'صح'**
  String get trueLabel;

  /// No description provided for @falseLabel.
  ///
  /// In ar, this message translates to:
  /// **'غلط'**
  String get falseLabel;

  /// No description provided for @yourAnswer.
  ///
  /// In ar, this message translates to:
  /// **'جوابك'**
  String get yourAnswer;

  /// No description provided for @typeAnswer.
  ///
  /// In ar, this message translates to:
  /// **'اكتب جوابك هنا'**
  String get typeAnswer;

  /// No description provided for @submit.
  ///
  /// In ar, this message translates to:
  /// **'سلّم'**
  String get submit;

  /// No description provided for @submitConfirm.
  ///
  /// In ar, this message translates to:
  /// **'متأكد تريد تسلم؟ باقي أسئلة ما جاوبتها.'**
  String get submitConfirm;

  /// No description provided for @result.
  ///
  /// In ar, this message translates to:
  /// **'النتيجة'**
  String get result;

  /// No description provided for @correctOf.
  ///
  /// In ar, this message translates to:
  /// **'{correct} صح من {total}'**
  String correctOf(Object correct, Object total);

  /// No description provided for @reviewAnswers.
  ///
  /// In ar, this message translates to:
  /// **'راجع الأجوبة'**
  String get reviewAnswers;

  /// No description provided for @explanation.
  ///
  /// In ar, this message translates to:
  /// **'الشرح'**
  String get explanation;

  /// No description provided for @correctAnswer.
  ///
  /// In ar, this message translates to:
  /// **'الجواب الصح'**
  String get correctAnswer;

  /// No description provided for @saveQuestion.
  ///
  /// In ar, this message translates to:
  /// **'احفظ السؤال'**
  String get saveQuestion;

  /// No description provided for @savedQuestions.
  ///
  /// In ar, this message translates to:
  /// **'الأسئلة المحفوظة'**
  String get savedQuestions;

  /// No description provided for @retryMistakes.
  ///
  /// In ar, this message translates to:
  /// **'عيد الأسئلة اللي غلطت بيها'**
  String get retryMistakes;

  /// No description provided for @testHistory.
  ///
  /// In ar, this message translates to:
  /// **'سجل الاختبارات'**
  String get testHistory;

  /// No description provided for @timeUp.
  ///
  /// In ar, this message translates to:
  /// **'خلص الوقت!'**
  String get timeUp;

  /// No description provided for @officialSourceBadge.
  ///
  /// In ar, this message translates to:
  /// **'سؤال وزاري'**
  String get officialSourceBadge;

  /// No description provided for @practiceBadge.
  ///
  /// In ar, this message translates to:
  /// **'سؤال تدريبي'**
  String get practiceBadge;

  /// No description provided for @library.
  ///
  /// In ar, this message translates to:
  /// **'المكتبة'**
  String get library;

  /// No description provided for @search.
  ///
  /// In ar, this message translates to:
  /// **'دوّر...'**
  String get search;

  /// No description provided for @allTypes.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get allTypes;

  /// No description provided for @download.
  ///
  /// In ar, this message translates to:
  /// **'نزّل'**
  String get download;

  /// No description provided for @downloading.
  ///
  /// In ar, this message translates to:
  /// **'دا ننزل...'**
  String get downloading;

  /// No description provided for @downloaded.
  ///
  /// In ar, this message translates to:
  /// **'منزّل على جهازك'**
  String get downloaded;

  /// No description provided for @open.
  ///
  /// In ar, this message translates to:
  /// **'افتح'**
  String get open;

  /// No description provided for @favorites.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة'**
  String get favorites;

  /// No description provided for @readingHistory.
  ///
  /// In ar, this message translates to:
  /// **'قريتها مؤخراً'**
  String get readingHistory;

  /// No description provided for @noFiles.
  ///
  /// In ar, this message translates to:
  /// **'ماكو ملفات بعد'**
  String get noFiles;

  /// No description provided for @fileSize.
  ///
  /// In ar, this message translates to:
  /// **'الحجم: {size}'**
  String fileSize(Object size);

  /// No description provided for @needOnlineToDownload.
  ///
  /// In ar, this message translates to:
  /// **'تحتاج إنترنت حتى تنزل الملف أول مرة'**
  String get needOnlineToDownload;

  /// No description provided for @motivation.
  ///
  /// In ar, this message translates to:
  /// **'التحفيز'**
  String get motivation;

  /// No description provided for @share.
  ///
  /// In ar, this message translates to:
  /// **'شارك'**
  String get share;

  /// No description provided for @previousMotivation.
  ///
  /// In ar, this message translates to:
  /// **'تحفيزات سابقة'**
  String get previousMotivation;

  /// No description provided for @noMotivation.
  ///
  /// In ar, this message translates to:
  /// **'بعد ماكو تحفيز منشور'**
  String get noMotivation;

  /// No description provided for @tools.
  ///
  /// In ar, this message translates to:
  /// **'الأدوات'**
  String get tools;

  /// No description provided for @pomodoro.
  ///
  /// In ar, this message translates to:
  /// **'بومودورو'**
  String get pomodoro;

  /// No description provided for @focusTime.
  ///
  /// In ar, this message translates to:
  /// **'وقت التركيز'**
  String get focusTime;

  /// No description provided for @breakTime.
  ///
  /// In ar, this message translates to:
  /// **'وقت الاستراحة'**
  String get breakTime;

  /// No description provided for @start.
  ///
  /// In ar, this message translates to:
  /// **'ابدي'**
  String get start;

  /// No description provided for @pause.
  ///
  /// In ar, this message translates to:
  /// **'وكف'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In ar, this message translates to:
  /// **'كمّل'**
  String get resume;

  /// No description provided for @reset.
  ///
  /// In ar, this message translates to:
  /// **'صفّر'**
  String get reset;

  /// No description provided for @stopwatch.
  ///
  /// In ar, this message translates to:
  /// **'ساعة إيقاف'**
  String get stopwatch;

  /// No description provided for @saveStudyTime.
  ///
  /// In ar, this message translates to:
  /// **'سجّل وقت الدراسة'**
  String get saveStudyTime;

  /// No description provided for @studyTimeSaved.
  ///
  /// In ar, this message translates to:
  /// **'سجلنا {minutes} دقيقة دراسة. عاشت إيدك!'**
  String studyTimeSaved(Object minutes);

  /// No description provided for @gradeCalculator.
  ///
  /// In ar, this message translates to:
  /// **'حاسبة المعدل'**
  String get gradeCalculator;

  /// No description provided for @percentageCalculator.
  ///
  /// In ar, this message translates to:
  /// **'حاسبة النسبة'**
  String get percentageCalculator;

  /// No description provided for @addRow.
  ///
  /// In ar, this message translates to:
  /// **'ضيف مادة'**
  String get addRow;

  /// No description provided for @average.
  ///
  /// In ar, this message translates to:
  /// **'المعدل'**
  String get average;

  /// No description provided for @value.
  ///
  /// In ar, this message translates to:
  /// **'القيمة'**
  String get value;

  /// No description provided for @total.
  ///
  /// In ar, this message translates to:
  /// **'المجموع'**
  String get total;

  /// No description provided for @percentage.
  ///
  /// In ar, this message translates to:
  /// **'النسبة'**
  String get percentage;

  /// No description provided for @tasks.
  ///
  /// In ar, this message translates to:
  /// **'مهامي'**
  String get tasks;

  /// No description provided for @expenses.
  ///
  /// In ar, this message translates to:
  /// **'مصاريفي'**
  String get expenses;

  /// No description provided for @addExpense.
  ///
  /// In ar, this message translates to:
  /// **'ضيف مصروف'**
  String get addExpense;

  /// No description provided for @amount.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ (دينار)'**
  String get amount;

  /// No description provided for @monthTotal.
  ///
  /// In ar, this message translates to:
  /// **'مجموع هذا الشهر'**
  String get monthTotal;

  /// No description provided for @goals.
  ///
  /// In ar, this message translates to:
  /// **'أهدافي'**
  String get goals;

  /// No description provided for @weeklyGoals.
  ///
  /// In ar, this message translates to:
  /// **'أهداف الأسبوع'**
  String get weeklyGoals;

  /// No description provided for @monthlyGoals.
  ///
  /// In ar, this message translates to:
  /// **'أهداف الشهر'**
  String get monthlyGoals;

  /// No description provided for @addGoal.
  ///
  /// In ar, this message translates to:
  /// **'ضيف هدف'**
  String get addGoal;

  /// No description provided for @goalTitle.
  ///
  /// In ar, this message translates to:
  /// **'شنو هدفك؟'**
  String get goalTitle;

  /// No description provided for @targetValue.
  ///
  /// In ar, this message translates to:
  /// **'الهدف'**
  String get targetValue;

  /// No description provided for @progressValue.
  ///
  /// In ar, this message translates to:
  /// **'وصلت'**
  String get progressValue;

  /// No description provided for @statistics.
  ///
  /// In ar, this message translates to:
  /// **'إحصائياتي'**
  String get statistics;

  /// No description provided for @totalStudyHours.
  ///
  /// In ar, this message translates to:
  /// **'مجموع ساعات الدراسة'**
  String get totalStudyHours;

  /// No description provided for @tasksCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مهام خلصتها'**
  String get tasksCompleted;

  /// No description provided for @testsTaken.
  ///
  /// In ar, this message translates to:
  /// **'اختبارات سويتها'**
  String get testsTaken;

  /// No description provided for @avgScore.
  ///
  /// In ar, this message translates to:
  /// **'معدل درجاتك'**
  String get avgScore;

  /// No description provided for @achievementLocked.
  ///
  /// In ar, this message translates to:
  /// **'بعدك ما وصلتله'**
  String get achievementLocked;

  /// No description provided for @reminders.
  ///
  /// In ar, this message translates to:
  /// **'التذكيرات'**
  String get reminders;

  /// No description provided for @addNote.
  ///
  /// In ar, this message translates to:
  /// **'ضيف ملاحظة'**
  String get addNote;

  /// No description provided for @noteTitle.
  ///
  /// In ar, this message translates to:
  /// **'العنوان'**
  String get noteTitle;

  /// No description provided for @noteBody.
  ///
  /// In ar, this message translates to:
  /// **'اكتب ملاحظتك...'**
  String get noteBody;

  /// No description provided for @noNotes.
  ///
  /// In ar, this message translates to:
  /// **'ماكو ملاحظات بعد'**
  String get noNotes;

  /// No description provided for @guidance.
  ///
  /// In ar, this message translates to:
  /// **'دليل الجامعات'**
  String get guidance;

  /// No description provided for @guidanceIntro.
  ///
  /// In ar, this message translates to:
  /// **'معلومات عن الجامعات والكليات ومعدلات القبول.'**
  String get guidanceIntro;

  /// No description provided for @admissionAverage.
  ///
  /// In ar, this message translates to:
  /// **'معدل القبول'**
  String get admissionAverage;

  /// No description provided for @deadline.
  ///
  /// In ar, this message translates to:
  /// **'آخر موعد للتقديم'**
  String get deadline;

  /// No description provided for @lastUpdated.
  ///
  /// In ar, this message translates to:
  /// **'آخر تحديث: {date}'**
  String lastUpdated(Object date);

  /// No description provided for @officialInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومة رسمية موثقة'**
  String get officialInfo;

  /// No description provided for @unofficialInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومة غير رسمية — تأكد منها'**
  String get unofficialInfo;

  /// No description provided for @noGuidance.
  ///
  /// In ar, this message translates to:
  /// **'بعد ماكو معلومات منشورة'**
  String get noGuidance;

  /// No description provided for @settings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In ar, this message translates to:
  /// **'ملفي الشخصي'**
  String get profile;

  /// No description provided for @editProfile.
  ///
  /// In ar, this message translates to:
  /// **'عدّل ملفي'**
  String get editProfile;

  /// No description provided for @academicInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلوماتي الدراسية'**
  String get academicInfo;

  /// No description provided for @changeYear.
  ///
  /// In ar, this message translates to:
  /// **'غيّر السنة أو الصف'**
  String get changeYear;

  /// No description provided for @notifications.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get notifications;

  /// No description provided for @motivationNotifications.
  ///
  /// In ar, this message translates to:
  /// **'إشعارات التحفيز'**
  String get motivationNotifications;

  /// No description provided for @studyReminders.
  ///
  /// In ar, this message translates to:
  /// **'تذكيرات الدراسة'**
  String get studyReminders;

  /// No description provided for @examReminders.
  ///
  /// In ar, this message translates to:
  /// **'تذكيرات الامتحانات'**
  String get examReminders;

  /// No description provided for @announcementNotifications.
  ///
  /// In ar, this message translates to:
  /// **'الإعلانات'**
  String get announcementNotifications;

  /// No description provided for @theme.
  ///
  /// In ar, this message translates to:
  /// **'المظهر'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In ar, this message translates to:
  /// **'داكن'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In ar, this message translates to:
  /// **'فاتح'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In ar, this message translates to:
  /// **'حسب الجهاز'**
  String get themeSystem;

  /// No description provided for @cloudSync.
  ///
  /// In ar, this message translates to:
  /// **'المزامنة السحابية'**
  String get cloudSync;

  /// No description provided for @syncNow.
  ///
  /// In ar, this message translates to:
  /// **'زامن هسه'**
  String get syncNow;

  /// No description provided for @exportData.
  ///
  /// In ar, this message translates to:
  /// **'صدّر بياناتي'**
  String get exportData;

  /// No description provided for @exportReady.
  ///
  /// In ar, this message translates to:
  /// **'جهزنا ملف بياناتك'**
  String get exportReady;

  /// No description provided for @deleteAccount.
  ///
  /// In ar, this message translates to:
  /// **'احذف حسابي'**
  String get deleteAccount;

  /// No description provided for @deleteAccountBody.
  ///
  /// In ar, this message translates to:
  /// **'راح نحذف حسابك وكل بياناتك من السيرفر ومن هذا الجهاز. هذا الشي ما يرجع.'**
  String get deleteAccountBody;

  /// No description provided for @accountDeleted.
  ///
  /// In ar, this message translates to:
  /// **'انحذف حسابك'**
  String get accountDeleted;

  /// No description provided for @signOut.
  ///
  /// In ar, this message translates to:
  /// **'سجّل خروج'**
  String get signOut;

  /// No description provided for @signIn.
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول'**
  String get signIn;

  /// No description provided for @appVersion.
  ///
  /// In ar, this message translates to:
  /// **'نسخة التطبيق {version}'**
  String appVersion(Object version);

  /// No description provided for @privacy.
  ///
  /// In ar, this message translates to:
  /// **'الخصوصية'**
  String get privacy;

  /// No description provided for @privacyBody.
  ///
  /// In ar, this message translates to:
  /// **'بياناتك الدراسية إلك وحدك. ما نبيعها ولا نشاركها. المزامنة اختيارية، وتگدر تصدّر بياناتك أو تحذف حسابك متى ما تريد. ما نطلب ولا نحفظ كلمة سر حساب Google مالتك.'**
  String get privacyBody;

  /// No description provided for @localAccount.
  ///
  /// In ar, this message translates to:
  /// **'حساب محلي (بدون مزامنة)'**
  String get localAccount;

  /// No description provided for @announcement.
  ///
  /// In ar, this message translates to:
  /// **'إعلان'**
  String get announcement;

  /// No description provided for @gotIt.
  ///
  /// In ar, this message translates to:
  /// **'تمام، فهمت'**
  String get gotIt;

  /// No description provided for @dismiss.
  ///
  /// In ar, this message translates to:
  /// **'سد'**
  String get dismiss;

  /// No description provided for @accountSuspended.
  ///
  /// In ar, this message translates to:
  /// **'حسابك موقوف مؤقتاً. تواصل ويانا إذا تعتقد أكو غلط.'**
  String get accountSuspended;

  /// No description provided for @minutesShort.
  ///
  /// In ar, this message translates to:
  /// **'{m} د'**
  String minutesShort(Object m);

  /// No description provided for @today.
  ///
  /// In ar, this message translates to:
  /// **'اليوم'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In ar, this message translates to:
  /// **'باچر'**
  String get tomorrow;

  /// No description provided for @yesterday.
  ///
  /// In ar, this message translates to:
  /// **'البارحة'**
  String get yesterday;

  /// No description provided for @calendar.
  ///
  /// In ar, this message translates to:
  /// **'التقويم'**
  String get calendar;

  /// No description provided for @achievement_first_task.
  ///
  /// In ar, this message translates to:
  /// **'أول مهمة!'**
  String get achievement_first_task;

  /// No description provided for @achievement_tasks_50.
  ///
  /// In ar, this message translates to:
  /// **'50 مهمة'**
  String get achievement_tasks_50;

  /// No description provided for @achievement_streak_3.
  ///
  /// In ar, this message translates to:
  /// **'3 أيام متواصلة'**
  String get achievement_streak_3;

  /// No description provided for @achievement_streak_7.
  ///
  /// In ar, this message translates to:
  /// **'أسبوع كامل'**
  String get achievement_streak_7;

  /// No description provided for @achievement_streak_30.
  ///
  /// In ar, this message translates to:
  /// **'شهر بلا توقف'**
  String get achievement_streak_30;

  /// No description provided for @achievement_hours_10.
  ///
  /// In ar, this message translates to:
  /// **'10 ساعات دراسة'**
  String get achievement_hours_10;

  /// No description provided for @achievement_hours_100.
  ///
  /// In ar, this message translates to:
  /// **'100 ساعة دراسة'**
  String get achievement_hours_100;

  /// No description provided for @achievement_first_test.
  ///
  /// In ar, this message translates to:
  /// **'أول اختبار'**
  String get achievement_first_test;

  /// No description provided for @achievement_perfect_test.
  ///
  /// In ar, this message translates to:
  /// **'درجة كاملة'**
  String get achievement_perfect_test;

  /// No description provided for @achievementUnlocked.
  ///
  /// In ar, this message translates to:
  /// **'عاشت إيدك! حصلت على إنجاز: {name}'**
  String achievementUnlocked(Object name);

  /// No description provided for @notifStudyTitle.
  ///
  /// In ar, this message translates to:
  /// **'وكت الدراسة!'**
  String get notifStudyTitle;

  /// No description provided for @notifStudyBody.
  ///
  /// In ar, this message translates to:
  /// **'عندك حصة {title} هسه. يلا نبدي!'**
  String notifStudyBody(Object title);

  /// No description provided for @notifExamTitle.
  ///
  /// In ar, this message translates to:
  /// **'انتبه، عندك امتحان باچر'**
  String get notifExamTitle;

  /// No description provided for @notifExamBody.
  ///
  /// In ar, this message translates to:
  /// **'{title} — راجع زين وبالتوفيق!'**
  String notifExamBody(Object title);

  /// No description provided for @pomodoroDone.
  ///
  /// In ar, this message translates to:
  /// **'خلص وقت التركيز! خذلك استراحة.'**
  String get pomodoroDone;

  /// No description provided for @breakDone.
  ///
  /// In ar, this message translates to:
  /// **'خلصت الاستراحة، يلا نرجع للدراسة.'**
  String get breakDone;

  /// No description provided for @dayUnit.
  ///
  /// In ar, this message translates to:
  /// **'يوم'**
  String get dayUnit;

  /// No description provided for @months.
  ///
  /// In ar, this message translates to:
  /// **'كانون الثاني,شباط,آذار,نيسان,أيار,حزيران,تموز,آب,أيلول,تشرين الأول,تشرين الثاني,كانون الأول'**
  String get months;

  /// No description provided for @uniPublic.
  ///
  /// In ar, this message translates to:
  /// **'حكومية'**
  String get uniPublic;

  /// No description provided for @uniPrivate.
  ///
  /// In ar, this message translates to:
  /// **'أهلية'**
  String get uniPrivate;

  /// No description provided for @uniInstitute.
  ///
  /// In ar, this message translates to:
  /// **'معهد'**
  String get uniInstitute;

  /// No description provided for @channelCentral.
  ///
  /// In ar, this message translates to:
  /// **'القبول المركزي'**
  String get channelCentral;

  /// No description provided for @channelParallel.
  ///
  /// In ar, this message translates to:
  /// **'الدراسة الموازية'**
  String get channelParallel;

  /// No description provided for @channelEvening.
  ///
  /// In ar, this message translates to:
  /// **'الدراسة المسائية'**
  String get channelEvening;

  /// No description provided for @channelPrivate.
  ///
  /// In ar, this message translates to:
  /// **'الكليات الأهلية'**
  String get channelPrivate;

  /// No description provided for @channelScholarship.
  ///
  /// In ar, this message translates to:
  /// **'منحة'**
  String get channelScholarship;

  /// No description provided for @channelOther.
  ///
  /// In ar, this message translates to:
  /// **'أخرى'**
  String get channelOther;

  /// No description provided for @currencyIqd.
  ///
  /// In ar, this message translates to:
  /// **'دينار'**
  String get currencyIqd;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return L10nAr();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
