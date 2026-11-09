import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PdfPageInfo {
  final int pageIndex;
  final double width;
  final double height;

  const PdfPageInfo({
    required this.pageIndex,
    required this.width,
    required this.height,
  });

  double get aspectRatio => height > 0 ? width / height : 0.707;
}

class PdfDocumentInfo {
  final int pageCount;
  final List<PdfPageInfo> pages;

  const PdfDocumentInfo({
    required this.pageCount,
    required this.pages,
  });
}

class PdfService {
  static const MethodChannel _channel = MethodChannel('meet_notes/pdf_render');
  static bool hasMissingPlugin = false;

  static Future<PdfDocumentInfo?> getPdfInfo({String? path, Uint8List? data}) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getPdfInfo', {
        if (path != null) 'path': path,
        if (data != null) 'data': data,
      });
      if (res == null) return null;
      hasMissingPlugin = false;
      final pageCount = (res['pageCount'] as num?)?.toInt() ?? 0;
      final rawPages = res['pages'] as List<dynamic>? ?? [];
      final pages = rawPages.map((p) {
        final m = p as Map<dynamic, dynamic>;
        return PdfPageInfo(
          pageIndex: (m['pageIndex'] as num?)?.toInt() ?? 0,
          width: (m['width'] as num?)?.toDouble() ?? 595.0,
          height: (m['height'] as num?)?.toDouble() ?? 842.0,
        );
      }).toList();
      return PdfDocumentInfo(pageCount: pageCount, pages: pages);
    } on MissingPluginException catch (e) {
      hasMissingPlugin = true;
      debugPrint('PdfService.getPdfInfo MissingPluginException: $e');
      return null;
    } catch (e) {
      debugPrint('PdfService.getPdfInfo error: $e');
      return null;
    }
  }

  static Future<Uint8List?> renderPage({
    String? path,
    Uint8List? data,
    required int pageIndex,
    double width = 720.0,
  }) async {
    try {
      final res = await _channel.invokeMethod<Uint8List>('renderPdfPage', {
        if (path != null) 'path': path,
        if (data != null) 'data': data,
        'pageIndex': pageIndex,
        'width': width,
      });
      return res;
    } catch (e) {
      debugPrint('PdfService.renderPage error: $e');
      return null;
    }
  }
}
