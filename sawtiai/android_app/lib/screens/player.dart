import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/file_actions.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'generate.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.item, this.autoPlay = false});
  final LibraryItem item;
  final bool autoPlay;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  double _volume = 1;
  String? _error;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!File(widget.item.filePath).existsSync()) throw Exception('missing');
      final d = await _player.setFilePath(widget.item.filePath);
      if (!mounted) return;
      setState(() => _duration = d ?? Duration(milliseconds: widget.item.durationMs));
      _subs.add(_player.positionStream.listen((p) => mounted ? setState(() => _position = p) : null));
      _subs.add(_player.playerStateStream.listen((st) {
        if (!mounted) return;
        if (st.processingState == ProcessingState.completed) {
          _player.pause();
          _player.seek(Duration.zero);
        }
        setState(() => _playing = st.playing && st.processingState != ProcessingState.completed);
      }));
      if (widget.autoPlay) await _player.play();
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر فتح الملف الصوتي.');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _seekBy(int seconds) async {
    var t = _position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > _duration) t = _duration;
    await _player.seek(t);
  }

  Future<void> _save() async {
    try {
      final ok = await saveCopy(widget.item);
      if (mounted && ok) showSnack(context, 'تم حفظ الملف');
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر حفظ الملف', error: true);
    }
  }

  Future<void> _share() async {
    try {
      await shareItem(widget.item);
    } catch (_) {
      if (mounted) showSnack(context, 'تعذرت المشاركة', error: true);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: 'حذف التسجيل', body: 'سيُحذف هذا الملف نهائياً من جهازك.')) return;
    await _player.stop();
    if (!mounted) return;
    await context.read<AppState>().deleteLibraryItem(widget.item);
    if (mounted) Navigator.pop(context);
  }

  void _regenerate() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GenerateScreen(voiceId: widget.item.voiceId, initialText: widget.item.text, params: widget.item.params),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final maxMs = _duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
    return SawtiScaffold(
      title: 'مشغل الصوت',
      body: ListView(padding: const EdgeInsets.all(20), children: [
        GlassCard(
          gradient: const LinearGradient(colors: [SawtiColors.purpleDark, Color(0xFF1B3A75)]),
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            const SawtiLogo(size: 76),
            const SizedBox(height: 16),
            Text(i.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('بصوت: ${i.voiceName} • ${formatDate(i.createdAt)}',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('${formatBytes(i.sizeBytes)} • ${i.format.toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 18),
        if (_error != null) InfoBanner(text: _error!, color: SawtiColors.danger),
        Slider(
          key: const Key('seek_slider'),
          value: _position.inMilliseconds.toDouble().clamp(0, maxMs),
          max: maxMs,
          onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: [
            Text(formatDuration(_position), key: const Key('position_text')),
            const Spacer(),
            Text(formatDuration(_duration)),
          ]),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(iconSize: 34, tooltip: 'تأخير 10 ثوانٍ', icon: const Icon(Icons.replay_10_rounded), onPressed: () => _seekBy(-10)),
          const SizedBox(width: 16),
          Semantics(
            button: true,
            label: _playing ? 'إيقاف مؤقت' : 'تشغيل',
            child: InkWell(
              key: const Key('play_button'),
              customBorder: const CircleBorder(),
              onTap: _error != null ? null : () => _playing ? _player.pause() : _player.play(),
              child: Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(gradient: SawtiColors.brandGradient, shape: BoxShape.circle),
                child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 44),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(iconSize: 34, tooltip: 'تقديم 10 ثوانٍ', icon: const Icon(Icons.forward_10_rounded), onPressed: () => _seekBy(10)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Icon(_volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: context.muted),
          Expanded(
            child: Slider(
              value: _volume,
              onChanged: (v) {
                setState(() => _volume = v);
                _player.setVolume(v);
              },
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          SoftButton(label: 'تنزيل', icon: Icons.download_rounded, onPressed: _save),
          SoftButton(label: 'مشاركة', icon: Icons.share_rounded, onPressed: _share),
          SoftButton(label: 'إعادة التوليد', icon: Icons.autorenew_rounded, onPressed: _regenerate),
          SoftButton(label: 'حذف', icon: Icons.delete_outline_rounded, color: SawtiColors.danger, onPressed: _delete),
        ]),
        const SizedBox(height: 18),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('النص', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SelectableText(i.text, style: const TextStyle(height: 1.7)),
          ]),
        ),
      ]),
    );
  }
}
