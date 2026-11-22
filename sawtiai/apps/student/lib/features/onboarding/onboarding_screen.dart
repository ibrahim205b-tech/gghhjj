import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/backend.dart';

enum _Step { intro, signIn, profile, stage, grade, branch, year, done }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editAcademicOnly = false});
  final bool editAcademicOnly;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late _Step _step;
  final _intro = PageController();
  int _introPage = 0;
  final _name = TextEditingController();
  String? _governorate;
  String? _stageId, _gradeId, _branchId, _yearId;
  bool _busy = false;
  String? _error;
  late final Backend _backend = ref.read(backendProvider);

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repositoryProvider);
    final p = repo.profile;
    _name.text = p.displayName;
    _governorate = p.governorate;
    _stageId = p.stageId;
    _gradeId = p.gradeId;
    _branchId = p.branchId;
    _yearId = p.yearId;
    final backend = _backend;
    _step = widget.editAcademicOnly
        ? _Step.stage
        : (repo.authMode != 'none' || backend.signedIn)
            ? _Step.profile
            : _Step.intro;
    backend.addListener(_onAuth);
  }

  @override
  void dispose() {
    _backend.removeListener(_onAuth);
    _intro.dispose();
    _name.dispose();
    super.dispose();
  }

  void _onAuth() {
    final b = ref.read(backendProvider);
    if (_step == _Step.signIn && b.signedIn && mounted) {
      final p = ref.read(repositoryProvider).profile;
      setState(() {
        _busy = false;
        if (_name.text.isEmpty) _name.text = p.displayName;
        _step = _Step.profile;
      });
      b.sync(); // fetch the real academic structure
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(backendProvider).signInWithGoogle();
      if (!ok && mounted) setState(() => _error = context.l10n.signInFailed);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.signInFailed);
    } finally {
      // The browser returns through a deep link; keep the spinner until then.
      Future.delayed(const Duration(seconds: 45), () {
        if (mounted && _step == _Step.signIn) setState(() => _busy = false);
      });
    }
  }

  Future<void> _offline() async {
    setState(() => _busy = true);
    final backend = ref.read(backendProvider);
    final anon = await backend.continueWithoutAccount();
    if (anon) await backend.sync();
    if (mounted) {
      setState(() {
        _busy = false;
        _step = _Step.profile;
      });
    }
  }

  void _next() {
    final repo = ref.read(repositoryProvider);
    setState(() {
      _error = null;
      switch (_step) {
        case _Step.intro:
          _step = _Step.signIn;
        case _Step.signIn:
          _step = _Step.profile;
        case _Step.profile:
          if (_name.text.trim().isEmpty) {
            _error = context.l10n.requiredField;
            return;
          }
          _step = _Step.stage;
        case _Step.stage:
          if (_stageId == null) return;
          _step = _Step.grade;
        case _Step.grade:
          if (_gradeId == null) return;
          _step = (repo.grade(_gradeId)?.hasBranches ?? false) ? _Step.branch : _Step.year;
        case _Step.branch:
          if (_branchId == null) return;
          _step = _Step.year;
        case _Step.year:
          _finish();
        case _Step.done:
          break;
      }
    });
  }

  void _back() {
    final repo = ref.read(repositoryProvider);
    setState(() {
      _error = null;
      _step = switch (_step) {
        _Step.signIn => _Step.intro,
        _Step.stage => widget.editAcademicOnly ? _Step.stage : _Step.profile,
        _Step.grade => _Step.stage,
        _Step.branch => _Step.grade,
        _Step.year => (repo.grade(_gradeId)?.hasBranches ?? false) ? _Step.branch : _Step.grade,
        _ => _step,
      };
    });
  }

  Future<void> _finish() async {
    final repo = ref.read(repositoryProvider);
    final g = repo.grade(_gradeId);
    final b = repo.branch(_branchId);
    final p = repo.profile
      ..displayName = _name.text.trim()
      ..governorate = _governorate
      ..stageId = _stageId
      ..gradeId = _gradeId
      ..branchId = (g?.hasBranches ?? false) ? _branchId : null
      ..yearId = _yearId
      ..gradeCode = g?.code
      ..branchCode = (g?.hasBranches ?? false) ? b?.code : null;
    await repo.saveProfile(p);
    if (repo.authMode == 'none') await repo.setKv('auth_mode', 'local');
    await repo.setKv('onboarding_done', '1');
    ref.read(backendProvider).sync();
    if (!mounted) return;
    if (widget.editAcademicOnly) {
      context.pop();
    } else {
      setState(() => _step = _Step.done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.watch(repositoryProvider); // rebuild when the structure syncs
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: KeyedSubtree(key: ValueKey(_step), child: _buildStep(l)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(L10n l) => switch (_step) {
        _Step.intro => _introStep(l),
        _Step.signIn => _signInStep(l),
        _Step.profile => _profileStep(l),
        _Step.stage => _choiceStep(l, l.chooseStage,
            ref.read(repositoryProvider).stages.map((s) => (s.id, s.nameAr)).toList(), _stageId, (v) {
          _stageId = v;
          _gradeId = null;
          _branchId = null;
        }),
        _Step.grade => _choiceStep(l, l.chooseGrade,
            ref.read(repositoryProvider).gradesOf(_stageId!).map((g) => (g.id, g.nameAr)).toList(), _gradeId, (v) {
          _gradeId = v;
          _branchId = null;
        }),
        _Step.branch => _choiceStep(l, l.chooseBranch,
            ref.read(repositoryProvider).branchesOf(_gradeId!).map((b) => (b.id, b.nameAr)).toList(), _branchId,
            (v) => _branchId = v),
        _Step.year => _choiceStep(l, l.chooseYear,
            ref.read(repositoryProvider).years.map((y) => (y.id, y.label)).toList(),
            _yearId ?? ref.read(repositoryProvider).years.where((y) => y.isCurrent).firstOrNull?.id, (v) => _yearId = v,
            last: true),
        _Step.done => _doneStep(l),
      };

  Widget _introStep(L10n l) {
    final pages = [
      (Icons.event_note_rounded, l.onbTitle1, l.onbBody1),
      (Icons.insights_rounded, l.onbTitle2, l.onbBody2),
      (Icons.quiz_rounded, l.onbTitle3, l.onbBody3),
    ];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 24),
        const EnjazLogo(size: 72),
        const SizedBox(height: 16),
        Text(l.welcome, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text(l.slogan, style: TextStyle(color: context.mutedText)),
        Expanded(
          child: PageView(
            controller: _intro,
            onPageChanged: (i) => setState(() => _introPage = i),
            children: [
              for (final (icon, title, body) in pages)
                Center(
                  child: GlassCard(
                    blur: true,
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 64, color: EnjazColors.cyan),
                      const SizedBox(height: 16),
                      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(body, textAlign: TextAlign.center, style: TextStyle(color: context.mutedText, height: 1.7)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < pages.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.all(4),
              width: i == _introPage ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _introPage ? EnjazColors.cyan : context.mutedText.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        GlowButton(label: l.getStarted, gradient: EnjazColors.planGradient, icon: Icons.arrow_back_rounded, onPressed: _next),
      ]),
    );
  }

  Widget _signInStep(L10n l) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const EnjazLogo(size: 88),
          const SizedBox(height: 24),
          Text(l.welcome, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 32),
          if (AppConfig.backendConfigured)
            GlowButton(
              key: const Key('google_sign_in'),
              label: _busy ? l.signingIn : l.signInGoogle,
              gradient: EnjazColors.planGradient,
              icon: Icons.account_circle_rounded,
              loading: _busy,
              onPressed: _google,
            )
          else
            GlassCard(child: Text(l.backendMissing, textAlign: TextAlign.center, style: const TextStyle(height: 1.6))),
          const SizedBox(height: 14),
          OutlinedButton(
            key: const Key('continue_offline'),
            onPressed: _busy ? null : _offline,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(l.continueOffline),
          ),
          const SizedBox(height: 10),
          Text(l.offlineModeNote, textAlign: TextAlign.center, style: TextStyle(color: context.mutedText, fontSize: 12.5)),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: EnjazColors.danger)),
          ],
        ]),
      );

  Widget _profileStep(L10n l) {
    final repo = ref.read(repositoryProvider);
    final govs = ((repo.setting('governorates') as List?) ?? const []).cast<String>();
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      Text(l.profileSetup, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 24),
      TextField(
        key: const Key('name_field'),
        controller: _name,
        maxLength: 40,
        decoration: InputDecoration(labelText: l.displayName, hintText: l.displayNameHint, errorText: _error),
      ),
      if (govs.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: govs.contains(_governorate) ? _governorate : null,
          decoration: InputDecoration(labelText: l.governorate),
          items: [for (final g in govs) DropdownMenuItem(value: g, child: Text(g))],
          onChanged: (v) => _governorate = v,
        ),
      ],
      const SizedBox(height: 28),
      GlowButton(key: const Key('next_button'), label: l.next, gradient: EnjazColors.planGradient, onPressed: _next),
    ]);
  }

  Widget _choiceStep(L10n l, String title, List<(String, String)> options, String? selected,
      void Function(String) onSelect, {bool last = false}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (!(widget.editAcademicOnly && _step == _Step.stage))
            IconButton(onPressed: _back, icon: const Icon(Icons.arrow_forward_rounded), tooltip: l.back),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: options.isEmpty
              ? Center(child: Text(l.loading))
              : ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final (id, name) = options[i];
                    final on = id == selected;
                    return GlassCard(
                      key: ValueKey('choice_$name'),
                      onTap: () => setState(() => onSelect(id)),
                      gradient: on ? EnjazColors.planGradient : null,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                      child: Row(children: [
                        Expanded(child: Text(name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: on ? Colors.white : null))),
                        Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined, color: on ? Colors.white : context.mutedText),
                      ]),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        GlowButton(
          key: const Key('next_button'),
          label: last ? l.done : l.next,
          gradient: EnjazColors.planGradient,
          onPressed: (selected == null && !last) ? null : () {
            if (last && _yearId == null) _yearId = selected;
            _next();
          },
        ),
      ]),
    );
  }

  Widget _doneStep(L10n l) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(gradient: EnjazColors.progressGradient, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 72, color: Color(0xFF14301A)),
          ),
          const SizedBox(height: 24),
          Text(l.setupDone, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(l.setupDoneBody, textAlign: TextAlign.center, style: TextStyle(color: context.mutedText)),
          const SizedBox(height: 32),
          GlowButton(
            key: const Key('enter_app'),
            label: l.enterApp,
            gradient: EnjazColors.studyGradient,
            onPressed: () => context.go('/home'),
          ),
        ]),
      );
}

