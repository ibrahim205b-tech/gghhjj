import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _rev = 0;
  void _r() => setState(() => _rev++);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'المستخدمون'),
              Tab(text: 'الأدوار والصلاحيات'),
              Tab(text: 'الأجهزة والجلسات'),
            ],
          ),
          Expanded(child: TabBarView(children: [_users(context, app), _roles(context, app), _devices(context, app)])),
        ],
      ),
    );
  }

  Widget _users(BuildContext context, AppState app) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('مستخدم'),
        onPressed: () async {
          final roles = await app.os.auth.listRoles();
          final gens = await app.os.network.listGenerators();
          if (!context.mounted) return;
          final v = await showFormDialog(
            context,
            title: 'مستخدم جديد',
            fields: [
              const FieldSpec('name', 'الاسم الكامل', required: true),
              const FieldSpec('username', 'اسم المستخدم (إنجليزي)', required: true),
              const FieldSpec(
                'password',
                'كلمة المرور',
                type: FieldType.password,
                required: true,
                hint: '8 أحرف على الأقل مع أرقام',
              ),
              const FieldSpec('phone', 'الهاتف', type: FieldType.phone),
              FieldSpec(
                'role',
                'الدور',
                type: FieldType.dropdown,
                required: true,
                options: {
                  for (final r in roles.where((r) => r['id'] != roleOwner)) r['id'] as String: r['name'] as String,
                },
              ),
              FieldSpec(
                'gen',
                'المولدة',
                type: FieldType.dropdown,
                options: {for (final g in gens) g['id'] as String: g['name'] as String},
              ),
              const FieldSpec('all', 'الوصول لكل المولدات', type: FieldType.toggle),
            ],
          );
          if (v == null || !context.mounted) return;
          await guard(
            context,
            () => app.os.auth.createUser(
              fullName: v['name']!,
              username: v['username']!,
              password: v['password']!,
              roleId: v['role']!,
              phone: emptyToNull(v['phone']),
              allGenerators: v['all'] == '1',
              generatorIds: [if (emptyToNull(v['gen']) != null) v['gen']!],
            ),
            success: 'تم إنشاء المستخدم',
          );
          _r();
        },
      ),
      body: Loader<List<Map<String, Object?>>>(
        key: ValueKey('u$_rev'),
        load: app.os.auth.listUsers,
        builder: (context, rows, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            for (final u in rows)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text((u['full_name'] as String).characters.first)),
                  title: Text('${u['full_name']}'),
                  subtitle: Text(
                    '${u['username']} · ${u['role_name']}${u['all_generators'] == 1 ? ' · كل المولدات' : ''}',
                  ),
                  trailing: u['active'] == 1
                      ? const StatusChip('فعال', Brand.success)
                      : const StatusChip('موقوف', Brand.danger),
                  onTap: u['id'] == app.session!.userId
                      ? null
                      : () => showModalBottomSheet(
                          context: context,
                          builder: (c) => SafeArea(
                            child: Wrap(
                              children: [
                                ListTile(
                                  leading: Icon(u['active'] == 1 ? Icons.block : Icons.check_circle),
                                  title: Text(u['active'] == 1 ? 'إيقاف الحساب' : 'تفعيل الحساب'),
                                  onTap: () async {
                                    Navigator.pop(c);
                                    await guard(
                                      context,
                                      () => app.os.auth.setUserActive(u['id'] as String, u['active'] != 1),
                                    );
                                    _r();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.password),
                                  title: const Text('تعيين كلمة مرور جديدة'),
                                  onTap: () async {
                                    Navigator.pop(c);
                                    final v = await showFormDialog(
                                      context,
                                      title: 'كلمة مرور جديدة',
                                      fields: const [
                                        FieldSpec('p', 'كلمة المرور', type: FieldType.password, required: true),
                                      ],
                                    );
                                    if (v == null || !context.mounted) return;
                                    await guard(
                                      context,
                                      () => app.os.auth.resetPassword(u['id'] as String, v['p']!),
                                      success: 'تم التغيير وإبطال جلساته',
                                    );
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.bolt),
                                  title: const Text('المولدات المسموحة'),
                                  onTap: () async {
                                    Navigator.pop(c);
                                    final gens = await app.os.network.listGenerators();
                                    if (!context.mounted) return;
                                    final v = await showFormDialog(
                                      context,
                                      title: 'المولدات المسموحة',
                                      fields: [
                                        for (final g in gens)
                                          FieldSpec(g['id'] as String, '${g['name']}', type: FieldType.toggle),
                                      ],
                                    );
                                    if (v == null || !context.mounted) return;
                                    await guard(
                                      context,
                                      () => app.os.auth.setUserGenerators(u['id'] as String, [
                                        for (final e in v.entries)
                                          if (e.value == '1') e.key,
                                      ]),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roles(BuildContext context, AppState app) {
    return Loader<List<(Map<String, Object?>, Set<String>)>>(
      key: ValueKey('r$_rev'),
      load: () async => [
        for (final r in await app.os.auth.listRoles()) (r, await app.os.auth.permissionsOf(r['id'] as String)),
      ],
      builder: (context, roles, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('دور مخصص جديد'),
            onPressed: () async {
              final v = await showFormDialog(
                context,
                title: 'دور جديد',
                fields: const [FieldSpec('name', 'اسم الدور', required: true)],
              );
              if (v == null || !context.mounted) return;
              await guard(context, () => app.os.auth.createRole(v['name']!, {Perm.dashboardView}));
              _r();
            },
          ),
          const SizedBox(height: 8),
          for (final (r, perms) in roles)
            Card(
              child: ExpansionTile(
                title: Text('${r['name']}'),
                subtitle: Text('${perms.length} صلاحية${r['id'] == roleOwner ? ' · ثابتة' : ''}'),
                children: [
                  for (final p in Perm.all)
                    CheckboxListTile(
                      dense: true,
                      title: Text(Perm.labels[p] ?? p),
                      value: perms.contains(p),
                      onChanged: r['id'] == roleOwner
                          ? null
                          : (v) async {
                              await guard(
                                context,
                                () => app.os.auth.setRolePermission(r['id'] as String, p, v == true),
                              );
                              _r();
                            },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _devices(BuildContext context, AppState app) {
    return Loader<(List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      key: ValueKey('d$_rev'),
      load: () async => (await app.os.auth.listSessions(), await app.os.auth.listDevices()),
      builder: (context, d, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('الجلسات النشطة على هذا الجهاز', style: Theme.of(context).textTheme.titleSmall),
          for (final s in d.$1)
            Card(
              child: ListTile(
                leading: const Icon(Icons.login),
                title: Text('${s['full_name']}'),
                subtitle: Text('منذ ${(s['created_at'] as String).substring(0, 16).replaceFirst('T', ' ')}'),
                trailing: s['id'] == app.session!.sessionId
                    ? const StatusChip('الحالية', Brand.info)
                    : TextButton(
                        onPressed: () async {
                          await guard(context, () => app.os.auth.revokeSession(s['id'] as String));
                          _r();
                        },
                        child: const Text('إبطال'),
                      ),
              ),
            ),
          const SizedBox(height: 12),
          Text('الأجهزة', style: Theme.of(context).textTheme.titleSmall),
          for (final dv in d.$2)
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text('${dv['id']}'.substring(0, 8)),
                subtitle: Text('آخر استخدام ${(dv['last_seen'] as String).substring(0, 16).replaceFirst('T', ' ')}'),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('لإبطال جهاز مفقود: أبطله من لوحة إدارة الخادم ليتوقف عن المزامنة، وغيّر كلمات مرور مستخدميه.'),
          ),
        ],
      ),
    );
  }
}
