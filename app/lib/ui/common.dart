import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:generator_core/generator_core.dart';

import '../theme.dart';

String money(num v) => formatMoney(v.round());
String liters(int ml) => formatLiters(ml);

/// Maps any error to an Arabic, user-friendly message.
String errorText(Object e) {
  if (e is DomainException) return e.message;
  final s = e.toString();
  if (s.contains('IMMUTABLE_RECORD')) return 'لا يمكن تعديل أو حذف السجلات المالية المحفوظة. استخدم قيداً عكسياً.';
  if (s.contains('UNIQUE')) return 'القيمة مستخدمة مسبقاً.';
  if (s.contains('SocketException') || s.contains('Connection')) return 'تعذر الاتصال. تحقق من الشبكة.';
  return 'حدث خطأ غير متوقع: ${s.length > 160 ? s.substring(0, 160) : s}';
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(errorText(e)), backgroundColor: Brand.danger, behavior: SnackBarBehavior.floating),
    );
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: Brand.success, behavior: SnackBarBehavior.floating));
}

/// Runs [action], showing errors as a snackbar. Returns true on success.
Future<bool> guard(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showOk(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Loads data with a future and rebuilds; shows errors in Arabic with retry.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  const Loader({super.key, required this.load, required this.builder});
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f;
  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  @override
  void didUpdateWidget(covariant Loader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _f = widget.load();
  }

  void _reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'تعذر تحميل البيانات',
            subtitle: errorText(snap.error!),
            action: OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
          );
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: c.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(color: c.outline),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  final VoidCallback? onTap;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.hint,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (hint != null)
                      Text(
                        hint!,
                        style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of stat cards.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 940
            ? 4
            : c.maxWidth >= 640
            ? 3
            : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

class Section extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsets padding;
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.padding = const EdgeInsets.all(14),
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// Page wrapper with consistent padding and max width on tablets.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  const PageBody({super.key, required this.children, this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final c in children) ...[c, const SizedBox(height: 12)],
      ],
    );
    final body = Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1400), child: list),
    );
    return onRefresh == null ? body : RefreshIndicator(onRefresh: onRefresh!, child: body);
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String ok = 'تأكيد',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Brand.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ---------------------------------------------------------------- forms

enum FieldType { text, multiline, number, money, phone, password, dropdown, date, toggle }

class FieldSpec {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? initial;
  final Map<String, String>? options; // value -> label
  final String? hint;
  final String? Function(String)? validator;
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.initial,
    this.options,
    this.hint,
    this.validator,
  });
}

/// Generic form dialog/sheet; returns the values or null when cancelled.
Future<Map<String, String>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  String submit = 'حفظ',
  String? note,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FormDialog(title: title, fields: fields, submit: submit, note: note),
  );
}

class _FormDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final String submit;
  final String? note;
  const _FormDialog({required this.title, required this.fields, required this.submit, this.note});
  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial ?? ''),
  };
  late final Map<String, String?> _drop = {
    for (final f in widget.fields.where((f) => f.type == FieldType.dropdown || f.type == FieldType.toggle))
      f.key: f.initial ?? (f.type == FieldType.toggle ? '0' : null),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(FieldSpec f) {
    switch (f.type) {
      case FieldType.dropdown:
        return DropdownButtonFormField<String>(
          initialValue: _drop[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
          items: [
            if (!f.required) const DropdownMenuItem(value: null, child: Text('— بدون —')),
            for (final e in (f.options ?? {}).entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _drop[f.key] = v),
          validator: (v) => f.required && (v == null || v.isEmpty) ? 'مطلوب' : null,
        );
      case FieldType.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _drop[f.key] == '1',
          onChanged: (v) => setState(() => _drop[f.key] = v ? '1' : '0'),
        );
      case FieldType.date:
        return TextFormField(
          controller: _c[f.key],
          readOnly: true,
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            suffixIcon: const Icon(Icons.event),
          ),
          onTap: () async {
            final init = DateTime.tryParse(_c[f.key]!.text) ?? DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: init,
              firstDate: DateTime(2015),
              lastDate: DateTime(2100),
            );
            if (d != null) _c[f.key]!.text = ymd(d);
          },
          validator: (v) => f.required && (v == null || v.isEmpty) ? 'مطلوب' : null,
        );
      default:
        final numeric = f.type == FieldType.number || f.type == FieldType.money;
        return TextFormField(
          controller: _c[f.key],
          obscureText: f.type == FieldType.password,
          maxLines: f.type == FieldType.multiline ? 3 : 1,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : f.type == FieldType.phone
              ? TextInputType.phone
              : TextInputType.text,
          inputFormatters: f.type == FieldType.money ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            hintText: f.hint,
            suffixText: f.type == FieldType.money ? 'د.ع' : null,
          ),
          validator: (v) {
            final s = v?.trim() ?? '';
            if (f.required && s.isEmpty) return 'مطلوب';
            if (numeric && s.isNotEmpty && num.tryParse(toLatinDigits(s)) == null) return 'أدخل رقماً صحيحاً';
            return f.validator?.call(s);
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: width > 600 ? 520 : width,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.note != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.note!)),
              for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final out = <String, String>{};
            for (final f in widget.fields) {
              final raw = _c[f.key]!.text.trim();
              final numeric = f.type == FieldType.number || f.type == FieldType.money || f.type == FieldType.phone;
              final v = _drop.containsKey(f.key) ? (_drop[f.key] ?? '') : (numeric ? toLatinDigits(raw) : raw);
              out[f.key] = v;
            }
            Navigator.pop(context, out);
          },
          child: Text(widget.submit),
        ),
      ],
    );
  }
}

/// Converts Arabic-Indic digits typed on Arabic keyboards to Latin digits.
String toLatinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch), j = fa.indexOf(ch);
    b.write(
      i >= 0
          ? '$i'
          : j >= 0
          ? '$j'
          : ch,
    );
  }
  return b.toString().replaceAll('٫', '.').replaceAll(',', '');
}

int? parseMoney(String? s) => s == null || s.isEmpty ? null : int.tryParse(toLatinDigits(s));
double? parseNum(String? s) => s == null || s.isEmpty ? null : double.tryParse(toLatinDigits(s));
String? emptyToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

/// Simple data table that scrolls horizontally on phones.
class DataTableCard extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final List<bool>? numeric;
  const DataTableCard({super.key, required this.headers, required this.rows, this.numeric});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, title: 'لا توجد بيانات للفترة المحددة');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 52,
        columns: [
          for (var i = 0; i < headers.length; i++)
            DataColumn(
              label: Text(headers[i], style: const TextStyle(fontWeight: FontWeight.w700)),
              numeric: numeric != null && numeric![i],
            ),
        ],
        rows: [
          for (final r in rows) DataRow(cells: [for (final c in r) DataCell(Text(c))]),
        ],
      ),
    );
  }
}
