import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'privacy.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((p) => mounted ? setState(() => _version = '${p.version} (${p.buildNumber})') : null)
        .catchError((_) => null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshServerStatus();
    });
  }

  Future<void> _editServer() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ServerSheet(),
    );
    if (changed == true && mounted) await context.read<AppState>().refreshServerStatus();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showSnack(context, done);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر تنفيذ العملية', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final eng = s.server.engine;
    final voice = s.activeVoice;
    return SawtiScaffold(
      title: 'الإعدادات',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _Section('الخادم', [
          ListTile(
            leading: const Icon(Icons.dns_rounded),
            title: const Text('حالة الخادم'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(alignment: AlignmentDirectional.centerStart, child: ServerStatusPill(status: s.server)),
            ),
            trailing: IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: s.refreshServerStatus),
          ),
          if (s.server.message != null && s.server.state != ConnectionState2.online)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(s.server.message!, style: TextStyle(color: context.muted, fontSize: 12.5)),
            ),
          ListTile(
            key: const Key('server_settings_tile'),
            leading: const Icon(Icons.link_rounded),
            title: const Text('عنوان الخادم ومفتاح الوصول'),
            subtitle: Text(s.settings.serverUrl.isEmpty ? 'غير مضبوط' : s.settings.serverUrl, textDirection: TextDirection.ltr),
            trailing: const Icon(Icons.edit_rounded),
            onTap: _editServer,
          ),
          if (s.server.state == ConnectionState2.online)
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: const Text('موارد التشغيل'),
              subtitle: Text(
                  'معالج CPU بدون GPU • الحد الأقصى للنص ${s.server.maxTextChars} حرف • '
                  'تُحذف الملفات من الخادم بعد ${s.server.audioTtlMinutes} دقيقة'
                  '${s.server.persistentStorage ? '' : ' • التخزين على الخادم مؤقت'}'),
            ),
        ]),
        _Section('معلومات المحرك', [
          if (eng == null)
            const ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('تظهر بعد الاتصال بالخادم'))
          else ...[
            ListTile(
              leading: const Icon(Icons.psychology_rounded),
              title: Text(eng.name),
              subtitle: Text(eng.notes),
            ),
            ListTile(leading: const Icon(Icons.gavel_rounded), title: const Text('الترخيص'), subtitle: Text(eng.license)),
            _LinkTile(label: 'المصدر الرسمي', url: eng.sourceUrl),
            _LinkTile(label: 'أوزان النموذج', url: eng.modelUrl),
            ListTile(
              leading: const Icon(Icons.mic_external_on_rounded),
              title: const Text('متطلبات العينة'),
              subtitle: Text('من ${eng.minSampleSeconds.toStringAsFixed(0)} إلى ${eng.maxUsefulSampleSeconds.toStringAsFixed(0)} ثوانٍ '
                  '(المستحسن ${eng.recommendedSampleSeconds.toStringAsFixed(0)})'
                  '${eng.needsTranscript ? ' مع نص العينة' : ''}'),
            ),
          ],
        ]),
        _Section('اللغة والمظهر', [
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: const Text('لغة التوليد الافتراضية'),
            subtitle: const Text('واجهة التطبيق بالعربية'),
            trailing: DropdownButton<String>(
              value: s.settings.language,
              underline: const SizedBox(),
              items: [
                for (final l in (eng?.languages ?? const ['ar', 'en']))
                  DropdownMenuItem(value: l, child: Text(l == 'ar' ? 'العربية' : l == 'en' ? 'English' : l)),
                if (!(eng?.languages ?? const ['ar', 'en']).contains(s.settings.language))
                  DropdownMenuItem(value: s.settings.language, child: Text(s.settings.language)),
              ],
              onChanged: (v) => s.updateSettings((x) => x.language = v ?? 'ar'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_rounded)),
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_rounded)),
                ButtonSegment(value: ThemeMode.system, label: Text('النظام'), icon: Icon(Icons.brightness_auto_rounded)),
              ],
              selected: {s.settings.themeMode},
              onSelectionChanged: (v) => s.updateSettings((x) => x.themeMode = v.first),
            ),
          ),
        ]),
        _Section('إعدادات الصوت', [
          if (eng?.supportsSpeed ?? true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('السرعة الافتراضية'),
                Expanded(
                  child: Slider(
                    value: s.settings.speed.clamp(eng?.speedMin ?? 0.7, eng?.speedMax ?? 1.3),
                    min: eng?.speedMin ?? 0.7,
                    max: eng?.speedMax ?? 1.3,
                    divisions: 12,
                    label: '${s.settings.speed.toStringAsFixed(2)}×',
                    onChanged: (v) => s.updateSettings((x) => x.speed = v),
                  ),
                ),
                Text('${s.settings.speed.toStringAsFixed(2)}×'),
              ]),
            ),
          if (eng?.qualities.isNotEmpty ?? false)
            ListTile(
              title: const Text('جودة التوليد'),
              trailing: DropdownButton<String>(
                value: s.settings.quality ?? 'balanced',
                underline: const SizedBox(),
                items: [for (final q in eng!.qualities) DropdownMenuItem(value: q.id, child: Text(q.label))],
                onChanged: (v) => s.updateSettings((x) => x.quality = v),
              ),
            ),
          if (eng?.styles.isNotEmpty ?? false)
            ListTile(
              title: const Text('نمط الكلام'),
              trailing: DropdownButton<String>(
                value: s.settings.style ?? 'natural',
                underline: const SizedBox(),
                items: [for (final st in eng!.styles) DropdownMenuItem(value: st.id, child: Text(st.label))],
                onChanged: (v) => s.updateSettings((x) => x.style = v),
              ),
            ),
          ListTile(
            title: const Text('صيغة الملفات المحفوظة'),
            subtitle: const Text('WAV أعلى جودة • MP3 أصغر حجماً للمشاركة'),
            trailing: DropdownButton<String>(
              value: s.settings.downloadFormat,
              underline: const SizedBox(),
              items: const [DropdownMenuItem(value: 'wav', child: Text('WAV')), DropdownMenuItem(value: 'mp3', child: Text('MP3'))],
              onChanged: (v) => s.updateSettings((x) => x.downloadFormat = v ?? 'wav'),
            ),
          ),
          SwitchListTile(
            title: const Text('حذف الملف من الخادم بعد تنزيله'),
            subtitle: const Text('مستحسن للخصوصية'),
            value: s.settings.deleteFromServerAfterDownload,
            onChanged: (v) => s.updateSettings((x) => x.deleteFromServerAfterDownload = v),
          ),
        ]),
        _Section('الخصوصية والبيانات', [
          ListTile(
            leading: const Icon(Icons.privacy_tip_rounded),
            title: const Text('سياسة الخصوصية'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyScreen())),
          ),
          if (voice != null) ...[
            ListTile(
              leading: const Icon(Icons.content_cut_rounded),
              title: const Text('حذف العينة الأصلية من الخادم'),
              subtitle: const Text('يبقى المقطع المرجعي القصير اللازم للتوليد'),
              enabled: voice.serverVoiceId != null,
              onTap: () async {
                if (await confirmDialog(context, title: 'حذف العينة الأصلية', body: 'سيُحذف ملف العينة الكامل من الخادم.')) {
                  await _run(() => s.deleteVoiceOriginalOnServer(voice), 'حُذفت العينة الأصلية من الخادم');
                }
              },
            ),
            ListTile(
              key: const Key('delete_voice_tile'),
              leading: const Icon(Icons.person_remove_rounded, color: SawtiColors.danger),
              title: const Text('حذف النسخة الصوتية'),
              subtitle: Text('«${voice.name}» من الخادم ومن جهازك'),
              onTap: () async {
                if (await confirmDialog(context,
                    title: 'حذف النسخة الصوتية',
                    body: 'ستُحذف النسخة الصوتية وعينتها من الخادم ومن هذا الجهاز. الملفات المولدة في المكتبة تبقى.')) {
                  await _run(() => s.deleteVoice(voice), 'حُذفت النسخة الصوتية');
                }
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded, color: SawtiColors.danger),
            title: const Text('حذف جميع الملفات الصوتية المحلية'),
            subtitle: Text('${s.library.length} ملف في المكتبة'),
            onTap: () async {
              if (await confirmDialog(context, title: 'حذف جميع الملفات', body: 'ستُحذف كل الملفات من مكتبتك على هذا الجهاز نهائياً.')) {
                await _run(s.deleteAllLocalAudio, 'حُذفت جميع الملفات المحلية');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_off_rounded, color: SawtiColors.danger),
            title: const Text('حذف كل بياناتي من الخادم'),
            subtitle: const Text('جميع النسخ الصوتية والعينات والملفات المؤقتة'),
            enabled: s.settings.serverConfigured,
            onTap: () async {
              if (await confirmDialog(context, title: 'حذف بيانات الخادم', body: 'سيُحذف كل ما يخص صوتك من الخادم.')) {
                await _run(() async => await s.deleteAllServerData(), 'حُذفت جميع البيانات من الخادم');
              }
            },
          ),
        ]),
        _Section('حول التطبيق', [
          const ListTile(
            leading: SawtiLogo(size: 36),
            title: Text('صوتي AI — Sawti AI'),
            subtitle: Text('صوتك... بكلماتك. تطبيق شخصي لاستنساخ صوتك وتوليد الكلام.'),
          ),
          ListTile(leading: const Icon(Icons.tag_rounded), title: const Text('رقم الإصدار'), subtitle: Text(_version.isEmpty ? '—' : _version)),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
          ),
          GlassCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
        ]),
      );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.open_in_new_rounded),
        title: Text(label),
        subtitle: Text(url, textDirection: TextDirection.ltr),
        trailing: const Icon(Icons.copy_rounded, size: 18),
        onTap: () {
          Clipboard.setData(ClipboardData(text: url));
          showSnack(context, 'نُسخ الرابط');
        },
      );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet();

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  bool _obscure = true;
  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _url = TextEditingController(text: s.serverUrl);
    _key = TextEditingController(text: s.apiKey);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final err = AppState.validateServerUrl(_url.text);
    if (err != null) {
      setState(() {
        _result = err;
        _ok = false;
      });
      return;
    }
    if (_key.text.trim().isEmpty) {
      setState(() {
        _result = 'أدخل مفتاح الوصول';
        _ok = false;
      });
      return;
    }
    setState(() {
        _testing = true;
        _result = null;
      });
    final st = await context.read<AppState>().testConnection(_url.text, _key.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = st.state == ConnectionState2.online;
      _result = _ok
          ? 'تم الاتصال بنجاح ✓ — المحرك: ${st.engine?.name ?? '-'} (${st.engineState == 'ready' ? 'جاهز' : 'يُحمَّل'})'
          : (st.message ?? 'تعذر الاتصال');
    });
  }

  Future<void> _save() async {
    final err = AppState.validateServerUrl(_url.text);
    if (err != null) {
      setState(() {
        _result = err;
        _ok = false;
      });
      return;
    }
    await context.read<AppState>().updateSettings((s) {
      s.serverUrl = _url.text.trim();
      s.apiKey = _key.text.trim();
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('ربط الخادم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('أدخل عنوان خادمك (مثل مساحة Hugging Face) والمفتاح الذي ضبطته في أسرار الخادم. يُحفظ المفتاح مشفراً على جهازك فقط.',
              style: TextStyle(color: context.muted, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('server_url_field'),
            controller: _url,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'عنوان الخادم', hintText: 'https://username-sawtiai.hf.space', prefixIcon: Icon(Icons.link_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('api_key_field'),
            controller: _key,
            obscureText: _obscure,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'مفتاح الوصول (SAWTI_API_KEY)',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            InfoBanner(
              text: _result!,
              color: _ok ? SawtiColors.success : SawtiColors.danger,
              icon: _ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: SoftButton(label: _testing ? 'جارٍ الفحص...' : 'اختبار الاتصال', icon: Icons.wifi_tethering_rounded, onPressed: _testing ? null : _test)),
            const SizedBox(width: 12),
            Expanded(child: GradientButton(key: const Key('save_server_button'), label: 'حفظ', icon: Icons.save_rounded, onPressed: _save)),
          ]),
        ]),
      ),
    );
  }
}
