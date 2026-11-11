/// Every permission the application checks. Services enforce these – the UI
/// only hides what the user cannot use.
class Perm {
  static const dashboardView = 'dashboard.view';
  static const financeView = 'finance.view'; // profits, P&L, cash balances
  static const generatorsManage = 'generators.manage';
  static const networkManage = 'network.manage'; // areas, cabinets, lines
  static const subscribersView = 'subscribers.view';
  static const subscribersEdit = 'subscribers.edit';
  static const subscribersEditPrice = 'subscribers.edit_price';
  static const subscribersTransfer = 'subscribers.transfer';
  static const subscribersStatus = 'subscribers.status';
  static const billingGenerate = 'billing.generate';
  static const billingAdjust = 'billing.adjust';
  static const billingClosePeriod = 'billing.close_period';
  static const paymentsCollect = 'payments.collect';
  static const paymentsReverse = 'payments.reverse';
  static const collectorsManage = 'collectors.manage';
  static const collectorsViewAll = 'collectors.view_all';
  static const cashboxManage = 'cashbox.manage';
  static const expensesManage = 'expenses.manage';
  static const fuelManage = 'fuel.manage';
  static const operationsManage = 'operations.manage';
  static const maintenanceManage = 'maintenance.manage';
  static const complaintsManage = 'complaints.manage';
  static const reportsView = 'reports.view';
  static const usersManage = 'users.manage';
  static const auditView = 'audit.view';
  static const backupManage = 'backup.manage';
  static const settingsManage = 'settings.manage';
  static const aiUse = 'ai.use';

  static const all = <String>[
    dashboardView, financeView, generatorsManage, networkManage, subscribersView,
    subscribersEdit, subscribersEditPrice, subscribersTransfer, subscribersStatus,
    billingGenerate, billingAdjust, billingClosePeriod, paymentsCollect, paymentsReverse,
    collectorsManage, collectorsViewAll, cashboxManage, expensesManage, fuelManage,
    operationsManage, maintenanceManage, complaintsManage, reportsView, usersManage,
    auditView, backupManage, settingsManage, aiUse,
  ];

  static const labels = <String, String>{
    dashboardView: 'عرض لوحة التحكم',
    financeView: 'عرض الأرباح والأرصدة المالية',
    generatorsManage: 'إدارة المولدات والفروع',
    networkManage: 'إدارة المناطق والكابينات والخطوط',
    subscribersView: 'عرض المشتركين',
    subscribersEdit: 'إضافة وتعديل المشتركين',
    subscribersEditPrice: 'تعديل سعر الأمبير',
    subscribersTransfer: 'نقل المشتركين',
    subscribersStatus: 'إيقاف وتفعيل المشتركين',
    billingGenerate: 'إصدار الفواتير',
    billingAdjust: 'تعديل وإعادة احتساب الفواتير',
    billingClosePeriod: 'إغلاق الشهر',
    paymentsCollect: 'تسجيل الجباية',
    paymentsReverse: 'إلغاء دفعة بقيد عكسي',
    collectorsManage: 'إدارة الجباة',
    collectorsViewAll: 'عرض حسابات جميع الجباة',
    cashboxManage: 'إدارة الصندوق والإغلاق',
    expensesManage: 'تسجيل المصروفات',
    fuelManage: 'إدارة الوقود',
    operationsManage: 'سجل التشغيل',
    maintenanceManage: 'الصيانة والأعطال',
    complaintsManage: 'الشكاوى',
    reportsView: 'التقارير',
    usersManage: 'المستخدمون والصلاحيات',
    auditView: 'سجل التدقيق',
    backupManage: 'النسخ الاحتياطي والاستعادة',
    settingsManage: 'الإعدادات',
    aiUse: 'المساعد الذكي',
  };
}

class SystemRole {
  final String id;
  final String name;
  final Set<String> permissions;
  const SystemRole(this.id, this.name, this.permissions);
}

const roleOwner = 'role_owner';
const roleGeneralManager = 'role_general_manager';
const roleGeneratorManager = 'role_generator_manager';
const roleAccountant = 'role_accountant';
const roleCollector = 'role_collector';
const roleTechnician = 'role_technician';
const roleCustomerService = 'role_customer_service';

final systemRoles = <SystemRole>[
  SystemRole(roleOwner, 'المالك', Perm.all.toSet()),
  SystemRole(roleGeneralManager, 'المدير العام',
      Perm.all.where((p) => p != Perm.backupManage).toSet()),
  SystemRole(roleGeneratorManager, 'مدير المولدة', {
    Perm.dashboardView, Perm.financeView, Perm.networkManage, Perm.subscribersView,
    Perm.subscribersEdit, Perm.subscribersEditPrice, Perm.subscribersTransfer,
    Perm.subscribersStatus, Perm.billingGenerate, Perm.paymentsCollect,
    Perm.collectorsManage, Perm.collectorsViewAll, Perm.cashboxManage,
    Perm.expensesManage, Perm.fuelManage, Perm.operationsManage,
    Perm.maintenanceManage, Perm.complaintsManage, Perm.reportsView, Perm.aiUse,
  }),
  SystemRole(roleAccountant, 'المحاسب', {
    Perm.dashboardView, Perm.financeView, Perm.subscribersView, Perm.billingGenerate,
    Perm.billingAdjust, Perm.billingClosePeriod, Perm.paymentsCollect,
    Perm.paymentsReverse, Perm.collectorsViewAll, Perm.cashboxManage,
    Perm.expensesManage, Perm.fuelManage, Perm.reportsView, Perm.aiUse,
  }),
  SystemRole(roleCollector, 'الجابي', {
    Perm.subscribersView, Perm.paymentsCollect,
  }),
  SystemRole(roleTechnician, 'الفني', {
    Perm.operationsManage, Perm.maintenanceManage, Perm.fuelManage,
  }),
  SystemRole(roleCustomerService, 'خدمة المشتركين', {
    Perm.subscribersView, Perm.subscribersEdit, Perm.complaintsManage,
  }),
];
