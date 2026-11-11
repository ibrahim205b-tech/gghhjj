import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:generator_core/generator_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes report files (CSV / Excel / PDF) and shares them (WhatsApp, Drive,
/// e-mail ...) through the Android share sheet.
class ExportService {
  static Future<File> _file(String name) async {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File(p.join(dir.path, safe));
  }

  static Future<File> csv(String name, List<String> headers, List<List<Object?>> rows) async {
    final f = await _file('$name.csv');
    await f.writeAsString(toCsv(headers, rows), encoding: utf8, flush: true);
    return f;
  }

  /// Encodes rows as an .xlsx workbook (right-to-left sheet).
  static List<int> xlsxBytes(List<String> headers, List<List<Object?>> rows) {
    final x = Excel.createExcel();
    final sheetName = x.getDefaultSheet() ?? 'Sheet1';
    final sheet = x[sheetName];
    sheet.isRTL = true;
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final r in rows) {
      sheet.appendRow([
        for (final c in r)
          c is int
              ? IntCellValue(c)
              : c is double
              ? DoubleCellValue(c)
              : TextCellValue(c?.toString() ?? ''),
      ]);
    }
    return x.encode()!;
  }

  static Future<File> xlsx(String name, List<String> headers, List<List<Object?>> rows) async {
    final f = await _file('$name.xlsx');
    await f.writeAsBytes(xlsxBytes(headers, rows), flush: true);
    return f;
  }

  static Future<File> bytes(String fileName, List<int> data) async {
    final f = await _file(fileName);
    await f.writeAsBytes(data, flush: true);
    return f;
  }

  static Future<void> share(File f, {String? text}) =>
      SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: text));

  static Future<void> shareText(String text) => SharePlus.instance.share(ShareParams(text: text));
}
