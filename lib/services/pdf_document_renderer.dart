import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// Direct PDFium-backed renderer for PDF notes.
/// Keeps documents in native `.pdf` format (no PNG/base64 bloat) and renders
/// both base page previews and zoom-adaptive viewport tiles directly to GPU `ui.Image`.
class PdfDocumentRenderer {
  PdfDocumentRenderer._();
  static final PdfDocumentRenderer instance = PdfDocumentRenderer._();

  final Map<String, PdfDocument> _openDocs = {};
  final Map<String, Future<PdfDocument?>> _pendingOpens = {};
  final Map<String, ui.Image> _basePageImages = {};

  Future<PdfDocument?> openDocument(
    String fileId, {
    String? path,
    Uint8List? bytes,
  }) async {
    final existing = _openDocs[fileId];
    if (existing != null) return existing;

    final pending = _pendingOpens[fileId];
    if (pending != null) return pending;

    final future = _openDocumentInternal(fileId, path: path, bytes: bytes);
    _pendingOpens[fileId] = future;
    try {
      return await future;
    } finally {
      _pendingOpens.remove(fileId);
    }
  }

  Future<PdfDocument?> _openDocumentInternal(
    String fileId, {
    String? path,
    Uint8List? bytes,
  }) async {
    try {
      PdfDocument? doc;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) {
          doc = await PdfDocument.openFile(path);
        }
      }
      if (doc == null && bytes != null && bytes.isNotEmpty) {
        doc = await PdfDocument.openData(bytes);
      }
      if (doc != null) {
        _openDocs[fileId] = doc;
      }
      return doc;
    } catch (e) {
      debugPrint('PdfDocumentRenderer.openDocument error: $e');
      return null;
    }
  }

  PdfDocument? getOpenDocument(String fileId) => _openDocs[fileId];

  String _baseKey(String fileId, int pageIndex) => '${fileId}_$pageIndex';

  ui.Image? getCachedBaseImage(String fileId, int pageIndex) =>
      _basePageImages[_baseKey(fileId, pageIndex)];

  Future<ui.Image?> renderPageBase(
    String fileId,
    int pageIndex, {
    double targetWidth = 1200.0,
    String? path,
    Uint8List? bytes,
  }) async {
    final key = _baseKey(fileId, pageIndex);
    final cached = _basePageImages[key];
    if (cached != null) return cached;

    final doc = await openDocument(fileId, path: path, bytes: bytes);
    if (doc == null || pageIndex < 0 || pageIndex >= doc.pages.length) {
      return null;
    }

    try {
      final page = doc.pages[pageIndex];
      final aspect = page.height > 0 ? page.width / page.height : 0.707;
      final fullW = targetWidth;
      final fullH = targetWidth / aspect;
      final pdfImage = await page.render(
        x: 0,
        y: 0,
        width: fullW.round(),
        height: fullH.round(),
        fullWidth: fullW,
        fullHeight: fullH,
        backgroundColor: 0xFFFFFFFF,
        flags: PdfPageRenderFlags.lcdText,
      );
      if (pdfImage == null) return null;
      final uiImg = await pdfImage.createImage();
      pdfImage.dispose();
      _basePageImages[key] = uiImg;
      return uiImg;
    } catch (e) {
      debugPrint('PdfDocumentRenderer.renderPageBase error: $e');
      return null;
    }
  }

  /// Renders ONLY the visible cropped viewport tile of [pageIndex] at exact
  /// target pixel resolution (supports up to 1600%+ zoom with zero pixelation).
  Future<ui.Image?> renderPageViewportTile(
    String fileId,
    int pageIndex, {
    required double fullWidth,
    required double fullHeight,
    required int cropX,
    required int cropY,
    required int cropWidth,
    required int cropHeight,
    String? path,
    Uint8List? bytes,
  }) async {
    if (cropWidth <= 0 || cropHeight <= 0) return null;
    final doc = await openDocument(fileId, path: path, bytes: bytes);
    if (doc == null || pageIndex < 0 || pageIndex >= doc.pages.length) {
      return null;
    }

    try {
      final page = doc.pages[pageIndex];
      final pdfImage = await page.render(
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: 0xFFFFFFFF,
        flags: PdfPageRenderFlags.lcdText,
      );
      if (pdfImage == null) return null;
      final uiImg = await pdfImage.createImage();
      pdfImage.dispose();
      return uiImg;
    } catch (e) {
      debugPrint('PdfDocumentRenderer.renderPageViewportTile error: $e');
      return null;
    }
  }

  Future<void> releaseDocument(String fileId) async {
    final prefix = '${fileId}_';
    final keysToRemove =
        _basePageImages.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keysToRemove) {
      _basePageImages.remove(k)?.dispose();
    }
    final doc = _openDocs.remove(fileId);
    await doc?.dispose();
  }
}
