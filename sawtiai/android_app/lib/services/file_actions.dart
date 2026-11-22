import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

String mimeFor(String format) => switch (format) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      _ => 'audio/wav',
    };

String exportName(LibraryItem i) {
  final safe = i.title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
  final base = safe.isEmpty ? 'sawti' : (safe.length > 40 ? safe.substring(0, 40) : safe);
  return 'صوتي - $base.${i.format}';
}

/// Lets the user pick where to save a copy (Android Storage Access Framework),
/// e.g. the Downloads folder. Returns false if cancelled.
Future<bool> saveCopy(LibraryItem i) async {
  final bytes = await File(i.filePath).readAsBytes();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'حفظ الملف الصوتي',
    fileName: exportName(i),
    bytes: bytes,
    mimeType: mimeFor(i.format),
  );
  return uri != null;
}

Future<void> shareItem(LibraryItem i) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(i.filePath, mimeType: mimeFor(i.format), name: exportName(i))],
    title: i.title,
  ));
}
