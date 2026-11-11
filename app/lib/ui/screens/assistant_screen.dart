import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _Msg {
  final bool me;
  final String text;
  final List<AssistantFact> facts;
  _Msg(this.me, this.text, [this.facts = const []]);
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[
    _Msg(
      false,
      'أهلاً! أنا Generator AI. أجيب من بيانات نظامك الفعلية، وكل الأرقام محسوبة من القيود المحاسبية — يعمل دون إنترنت. اسألني بالعربي أو باللهجة العراقية.',
    ),
  ];
  bool _busy = false;

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty || _busy) return;
    final app = AppScope.read(context);
    setState(() {
      _msgs.add(_Msg(true, q.trim()));
      _busy = true;
    });
    _q.clear();
    try {
      final a = await app.os.assistant.ask(app.generatorId!, q);
      _msgs.add(_Msg(false, a.text, a.facts));
    } catch (e) {
      _msgs.add(_Msg(false, errorText(e)));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (context, i) {
              final m = _msgs[i];
              return Align(
                alignment: m.me ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.me ? c.primaryContainer : c.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!m.me)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 16, color: Brand.accent),
                              SizedBox(width: 4),
                              Text('Generator AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        SelectableText(m.text),
                        if (m.facts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final f in m.facts)
                                Chip(label: Text('${f.label}: ${f.value}', style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in GeneratorAssistant.examples)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ActionChip(label: Text(e), onPressed: () => _ask(e)),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: const InputDecoration(hintText: 'مثال: شكد ربحي هذا الشهر؟'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : () => _ask(_q.text),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
