import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class _AuthFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _AuthFrame({required this.title, required this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Brand.primary, Color.lerp(Brand.primary, Colors.black, 0.45)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Generator OS',
                                    style: Theme.of(context).textTheme.titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text('نظام إدارة المولدات الأهلية', style: TextStyle(color: c.outline)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle, style: TextStyle(color: c.outline)),
                        const SizedBox(height: 20),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _gen = TextEditingController();
  final _price = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final app = AppScope.read(context);
    setState(() => _busy = true);
    final ok = await guard(context, () async {
      await app.os.auth.createOwner(fullName: _name.text, username: _user.text, password: _pass.text);
      await app.os.auth.login(_user.text, _pass.text);
      await app.os.network.createGenerator(name: _gen.text.trim(), defaultAmpPrice: parseMoney(_price.text) ?? 0);
      await app.afterLogin();
    });
    if (!ok && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'الإعداد الأول',
      subtitle: 'أنشئ حساب المالك وأول مولدة. تُحفظ البيانات على هذا الجهاز وتعمل دون إنترنت.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم المالك الكامل'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'أدخل الاسم' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'اسم المستخدم (بالإنجليزية)'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'اسم المستخدم 3 أحرف على الأقل' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  helperText: '8 أحرف على الأقل، حروف وأرقام',
                ),
                validator: (v) {
                  try {
                    AuthService.validatePassword(v ?? '');
                    return null;
                  } on DomainException catch (e) {
                    return e.message;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                validator: (v) => v != _pass.text ? 'كلمتا المرور غير متطابقتين' : null,
              ),
              const Divider(height: 32),
              TextFormField(
                controller: _gen,
                decoration: const InputDecoration(labelText: 'اسم المولدة'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'أدخل اسم المولدة' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'سعر الأمبير الافتراضي', suffixText: 'د.ع'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('بدء الاستخدام'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RestoreAtSetup())),
                icon: const Icon(Icons.restore),
                label: const Text('استعادة نسخة احتياطية موجودة'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Restore entry point before any account exists (new phone).
class RestoreAtSetup extends StatelessWidget {
  const RestoreAtSetup({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة نسخة احتياطية')),
      body: const Padding(padding: EdgeInsets.all(16), child: RestoreBackupPanel()),
    );
  }
}

class RestoreBackupPanel extends StatefulWidget {
  const RestoreBackupPanel({super.key});
  @override
  State<RestoreBackupPanel> createState() => _RestoreBackupPanelState();
}

class _RestoreBackupPanelState extends State<RestoreBackupPanel> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر ملف النسخة الاحتياطية (.gosbak) وأدخل كلمة مرورها. ستُستبدل بيانات هذا الجهاز بالكامل '
          'بمحتوى النسخة، وتُحفظ نسخة من القاعدة الحالية باسم before-restore.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('اختيار الملف'),
          onPressed: () => pickAndRestore(context),
        ),
      ],
    );
  }
}

Future<void> pickAndRestore(BuildContext context) async {
  final app = AppScope.read(context);
  final picked = await pickBackupFile();
  if (picked == null || !context.mounted) return;
  final v = await showFormDialog(
    context,
    title: 'كلمة مرور النسخة',
    fields: const [FieldSpec('password', 'كلمة المرور', type: FieldType.password, required: true)],
    submit: 'استعادة',
  );
  if (v == null || !context.mounted) return;
  if (!await confirm(
    context,
    'تأكيد الاستعادة',
    'سيتم استبدال جميع بيانات هذا الجهاز. هل تريد المتابعة؟',
    danger: true,
    ok: 'استعادة',
  )) {
    return;
  }
  if (!context.mounted) return;
  await guard(context, () async {
    final counts = await app.restoreBackup(picked, v['password']!);
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      showOk(context, 'تمت الاستعادة: ${counts['subscribers'] ?? 0} مشترك، ${counts['payments'] ?? 0} دفعة.');
    }
  });
}

Future<List<int>?> pickBackupFile() async {
  final f = await FilePicker.pickFile(dialogTitle: 'اختر ملف النسخة الاحتياطية');
  if (f == null) return null;
  return f.readAsBytes();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;

  Future<void> _login() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    final ok = await guard(context, () async {
      await app.os.auth.login(_user.text, _pass.text);
      await app.afterLogin();
    });
    if (!ok && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'تسجيل الدخول',
      subtitle: 'أدخل اسم المستخدم وكلمة المرور.',
      children: [
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person)),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: !_show,
          onSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'كلمة المرور',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('دخول'),
        ),
      ],
    );
  }
}
