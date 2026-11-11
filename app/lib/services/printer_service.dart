import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'pdf_service.dart';

/// A destination that can print a PDF document.
///
/// New printer kinds (Bluetooth SPP, USB OTG, vendor SDKs) are added by
/// implementing this interface; the rest of the app only deals with PDFs,
/// which guarantees correct Arabic shaping and right-to-left layout on every
/// printer because text is rendered by our embedded font, not the printer.
abstract class PrinterTarget {
  String get id;
  String get label;
  Future<void> printPdf(List<int> pdf, PaperSize paper, {String name = 'document'});
}

/// Android system print service (Wi-Fi/USB printers with a print plugin,
/// "Save as PDF"). Works with any printer Android itself supports.
class SystemPrinter implements PrinterTarget {
  @override
  String get id => 'system';
  @override
  String get label => 'خدمة الطباعة في أندرويد';
  @override
  Future<void> printPdf(List<int> pdf, PaperSize paper, {String name = 'document'}) async {
    await Printing.layoutPdf(name: name, format: paper.format, onLayout: (_) async => Uint8List.fromList(pdf));
  }
}

/// ESC/POS thermal printer reachable over the network (raw TCP, usually port
/// 9100). The PDF is rasterised to a monochrome bitmap and sent with the
/// `GS v 0` raster command, so Arabic prints correctly even on printers that
/// have no Arabic code page.
///
/// Status: implemented, NOT yet verified on physical hardware in this
/// project. Test on the target printer before relying on it.
class NetworkEscPosPrinter implements PrinterTarget {
  final String host;
  final int port;
  NetworkEscPosPrinter(this.host, {this.port = 9100});

  @override
  String get id => 'escpos:$host:$port';
  @override
  String get label => 'طابعة حرارية شبكية $host:$port';

  static int dotsFor(PaperSize p) => p == PaperSize.roll58 ? 384 : 576;

  @override
  Future<void> printPdf(List<int> pdf, PaperSize paper, {String name = 'document'}) async {
    final widthDots = dotsFor(paper);
    final bytes = BytesBuilder();
    bytes.add([0x1B, 0x40]); // ESC @ initialise
    // 203 dpi printers: dpi chosen so the page width maps to the printhead.
    final pageWidthInches = paper.format.width / 72.0;
    final dpi = widthDots / pageWidthInches;
    await for (final page in Printing.raster(Uint8List.fromList(pdf), dpi: dpi)) {
      final rgba = await page.toImage().then((img) async => (await img.toByteData())!.buffer.asUint8List());
      bytes.add(rasterCommand(rgba, page.width, page.height));
    }
    bytes.add([0x1B, 0x64, 0x04]); // feed 4 lines
    bytes.add([0x1D, 0x56, 0x42, 0x00]); // partial cut
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
    try {
      socket.add(bytes.toBytes());
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Converts RGBA pixels to an ESC/POS `GS v 0` monochrome raster block.
  static List<int> rasterCommand(Uint8List rgba, int width, int height) {
    final bytesPerRow = (width + 7) ~/ 8;
    final out = BytesBuilder();
    out.add([0x1D, 0x76, 0x30, 0x00, bytesPerRow & 0xFF, bytesPerRow >> 8, height & 0xFF, height >> 8]);
    final row = Uint8List(bytesPerRow);
    for (var y = 0; y < height; y++) {
      row.fillRange(0, bytesPerRow, 0);
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final a = rgba[i + 3];
        final lum = a < 128 ? 255 : (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (lum < 140) row[x >> 3] |= 0x80 >> (x & 7);
      }
      out.add(row);
    }
    return out.toBytes();
  }
}

/// Holds the user's printer choice.
class PrinterService {
  static PrinterTarget fromSetting(String? value) {
    if (value != null && value.startsWith('escpos:')) {
      final parts = value.split(':');
      if (parts.length == 3) return NetworkEscPosPrinter(parts[1], port: int.tryParse(parts[2]) ?? 9100);
    }
    return SystemPrinter();
  }
}
