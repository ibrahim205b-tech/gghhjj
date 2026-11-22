import 'dart:async';
import 'dart:math' as math;

import 'package:record/record.dart';

enum MicPermission { granted, denied }

/// Microphone recording to 24 kHz mono WAV (the format the engine works with,
/// so no lossy step is added) with a live level stream for the UI.
class VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  final _levels = StreamController<double>.broadcast();

  /// Normalised 0..1 input level, ~10 per second while recording.
  Stream<double> get levels => _levels.stream;

  /// Asks Android for the microphone permission (system dialog) if needed.
  Future<MicPermission> ensurePermission() async =>
      await _rec.hasPermission(request: true) ? MicPermission.granted : MicPermission.denied;

  Future<void> start(String path) async {
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 24000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: path,
    );
    await _ampSub?.cancel();
    _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // dBFS (-160..0) -> 0..1 with a perceptual curve.
      final db = a.current.isFinite ? a.current : -60.0;
      final v = ((db + 60) / 60).clamp(0.0, 1.0);
      _levels.add(math.pow(v, 1.6).toDouble());
    });
  }

  Future<String?> stop() async {
    await _ampSub?.cancel();
    _ampSub = null;
    return _rec.stop();
  }

  Future<void> cancel() async {
    await _ampSub?.cancel();
    _ampSub = null;
    await _rec.cancel();
  }

  Future<bool> isRecording() => _rec.isRecording();

  Future<void> dispose() async {
    await _ampSub?.cancel();
    await _levels.close();
    await _rec.dispose();
  }
}
