import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';
import 'assistant_screen.dart';
import 'billing_screen.dart';
import 'cashbox_screen.dart';
import 'collect_screen.dart';
import 'collectors_screen.dart';
import 'complaints_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'fuel_screen.dart';
import 'network_screen.dart';
import 'notifications_screen.dart';
import 'operations_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'subscribers_screen.dart';
import 'users_screen.dart';

class _Module {
  final String title;
  final IconData icon;
  final bool Function(AppState) visible;
  final Widget Function() build;
  const _Module(this.title, this.icon, this.visible, this.build);
}

final _modules = <_Module>[
  _Module(
    'لوحة التحكم',
    Icons.space_dashboard_rounded,
    (a) => a.can(Perm.dashboardView),
    () => const DashboardScreen(),
  ),
  _Module('الجباية', Icons.point_of_sale_rounded, (a) => a.can(Perm.paymentsCollect), () => const CollectScreen()),
  _Module('المشتركون', Icons.people_alt_rounded, (a) => a.can(Perm.subscribersView), () => const SubscribersScreen()),
  _Module('الفواتير', Icons.receipt_long_rounded, (a) => a.can(Perm.billingGenerate), () => const BillingScreen()),
  _Module(
    'الجباة',
    Icons.badge_rounded,
    (a) => a.can(Perm.collectorsManage) || a.can(Perm.collectorsViewAll) || a.session?.isCollector == true,
    () => const CollectorsScreen(),
  ),
  _Module(
    'الصندوق',
    Icons.account_balance_wallet_rounded,
    (a) => a.can(Perm.cashboxManage),
    () => const CashboxScreen(),
  ),
  _Module(
    'المصروفات والمجهزون',
    Icons.payments_rounded,
    (a) => a.can(Perm.expensesManage),
    () => const ExpensesScreen(),
  ),
  _Module('الوقود', Icons.local_gas_station_rounded, (a) => a.can(Perm.fuelManage), () => const FuelScreen()),
  _Module(
    'التشغيل والصيانة',
    Icons.build_circle_rounded,
    (a) => a.can(Perm.operationsManage) || a.can(Perm.maintenanceManage),
    () => const OperationsScreen(),
  ),
  _Module(
    'الكابينات والأحمال',
    Icons.electrical_services_rounded,
    (a) => a.can(Perm.networkManage),
    () => const NetworkScreen(),
  ),
  _Module('الشكاوى', Icons.support_agent_rounded, (a) => a.can(Perm.complaintsManage), () => const ComplaintsScreen()),
  _Module('التقارير', Icons.bar_chart_rounded, (a) => a.can(Perm.reportsView), () => const ReportsScreen()),
  _Module('المساعد الذكي', Icons.auto_awesome_rounded, (a) => a.can(Perm.aiUse), () => const AssistantScreen()),
  _Module('التنبيهات', Icons.notifications_rounded, (a) => true, () => const NotificationsScreen()),
  _Module(
    'المستخدمون والصلاحيات',
    Icons.admin_panel_settings_rounded,
    (a) => a.can(Perm.usersManage),
    () => const UsersScreen(),
  ),
  _Module('الإعدادات', Icons.settings_rounded, (a) => true, () => const SettingsScreen()),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final mods = _modules.where((m) => m.visible(app)).toList();
    if (_index >= mods.length) _index = 0;
    final current = mods[_index];
    final wide = isWide(context);

    if (app.generatorId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Generator OS'),
          actions: [IconButton(onPressed: app.logout, icon: const Icon(Icons.logout), tooltip: 'خروج')],
        ),
        body: EmptyState(
          icon: Icons.bolt,
          title: 'لا توجد مولدة مرتبطة بحسابك',
          subtitle: 'اطلب من المالك ربط حسابك بمولدة، أو أضف مولدة من الإعدادات إذا كانت لديك الصلاحية.',
          action: app.can(Perm.generatorsManage)
              ? FilledButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  child: const Text('الإعدادات'),
                )
              : null,
        ),
      );
    }

    final body = KeyedSubtree(key: ValueKey('${current.title}:${app.generatorId}'), child: current.build());
    final appBar = AppBar(
      title: Text(current.title),
      actions: [
        const _GeneratorPicker(),
        IconButton(
          tooltip: 'التنبيهات',
          onPressed: () => setState(() => _index = mods.indexWhere((m) => m.title == 'التنبيهات')),
          icon: Badge(
            isLabelVisible: app.unreadAlerts > 0,
            label: Text('${app.unreadAlerts}'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - kToolbarHeight - 24),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    extended: MediaQuery.sizeOf(context).width >= 1200,
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: MediaQuery.sizeOf(context).width >= 1200
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    leading: _UserBadge(compact: MediaQuery.sizeOf(context).width < 1200),
                    destinations: [
                      for (final m in mods) NavigationRailDestination(icon: Icon(m.icon), label: Text(m.title)),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    // Phone: first four modules in the bottom bar, everything in the drawer.
    final bottom = mods.take(4).toList();
    final inBottom = _index < bottom.length;
    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const Padding(padding: EdgeInsets.all(16), child: _UserBadge(compact: false)),
              const Divider(),
              for (var i = 0; i < mods.length; i++)
                ListTile(
                  leading: Icon(mods[i].icon),
                  title: Text(mods[i].title),
                  selected: i == _index,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _index = i);
                  },
                ),
              const Divider(),
              ListTile(leading: const Icon(Icons.logout), title: const Text('تسجيل الخروج'), onTap: app.logout),
            ],
          ),
        ),
      ),
      body: body,
      bottomNavigationBar: bottom.length < 2
          ? null
          : NavigationBar(
              selectedIndex: inBottom ? _index : 0,
              indicatorColor: inBottom ? null : Colors.transparent,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final m in bottom) NavigationDestination(icon: Icon(m.icon), label: m.title)],
            ),
    );
  }
}

class _UserBadge extends StatelessWidget {
  final bool compact;
  const _UserBadge({required this.compact});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.session!;
    final avatar = CircleAvatar(
      backgroundColor: Brand.accent,
      child: Text(
        s.fullName.isEmpty ? '?' : s.fullName.characters.first,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: PopupMenuButton<String>(
          child: avatar,
          itemBuilder: (_) => [PopupMenuItem(value: 'out', child: Text('خروج (${s.fullName})'))],
          onSelected: (_) => app.logout(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                systemRoles.where((r) => r.id == s.roleId).map((r) => r.name).firstOrNull ?? 'دور مخصص',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
              ),
            ],
          ),
          if (isWide(context)) ...[
            const SizedBox(width: 8),
            IconButton(onPressed: app.logout, icon: const Icon(Icons.logout), tooltip: 'خروج'),
          ],
        ],
      ),
    );
  }
}

class _GeneratorPicker extends StatelessWidget {
  const _GeneratorPicker();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return FutureBuilder<List<Map<String, Object?>>>(
      future: app.os.network.listGenerators(),
      builder: (context, snap) {
        final gens = snap.data ?? const [];
        if (gens.isEmpty) return const SizedBox.shrink();
        final current = gens.where((g) => g['id'] == app.generatorId).firstOrNull ?? gens.first;
        return PopupMenuButton<String>(
          tooltip: 'اختيار المولدة',
          onSelected: app.selectGenerator,
          itemBuilder: (_) => [
            for (final g in gens)
              CheckedPopupMenuItem(
                value: g['id'] as String,
                checked: g['id'] == app.generatorId,
                child: Text('${g['name']}'),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: Brand.accent),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide(context) ? 220 : 110),
                  child: Text('${current['name']}', overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
    );
  }
}
