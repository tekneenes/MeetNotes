import Cocoa
import FlutterMacOS
import PDFKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupPdfChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func setupPdfChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "meet_notes/pdf_render", binaryMessenger: messenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getPdfInfo" {
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
          return
        }
        var pdfDoc: PDFDocument? = nil
        if let data = (args["data"] as? FlutterStandardTypedData)?.data {
          pdfDoc = PDFDocument(data: data)
        } else if let path = args["path"] as? String {
          pdfDoc = PDFDocument(url: URL(fileURLWithPath: path))
        }
        guard let doc = pdfDoc else {
          result(FlutterError(code: "LOAD_FAILED", message: "Could not open PDF document", details: nil))
          return
        }
        var pages: [[String: Any]] = []
        for i in 0..<doc.pageCount {
          if let page = doc.page(at: i) {
            let bounds = page.bounds(for: .mediaBox)
            pages.append([
              "pageIndex": i,
              "width": bounds.width,
              "height": bounds.height,
            ])
          }
        }
        result([
          "pageCount": doc.pageCount,
          "pages": pages,
        ])
      } else if call.method == "renderPdfPage" {
        guard let args = call.arguments as? [String: Any],
              let pageIndex = args["pageIndex"] as? Int else {
          result(FlutterError(code: "INVALID_ARGS", message: "pageIndex required", details: nil))
          return
        }
        var pdfDoc: PDFDocument? = nil
        if let data = (args["data"] as? FlutterStandardTypedData)?.data {
          pdfDoc = PDFDocument(data: data)
        } else if let path = args["path"] as? String {
          pdfDoc = PDFDocument(url: URL(fileURLWithPath: path))
        }
        guard let doc = pdfDoc, let page = doc.page(at: pageIndex) else {
          result(FlutterError(code: "LOAD_FAILED", message: "Could not load PDF page at index \(pageIndex)", details: nil))
          return
        }
        let bounds = page.bounds(for: .mediaBox)
        let targetWidth = (args["width"] as? Double) ?? 720.0
        let targetHeight = bounds.width > 0 ? (bounds.height / bounds.width) * targetWidth : 960.0
        let renderSize = NSSize(width: targetWidth, height: targetHeight)
        let thumbnail = page.thumbnail(of: renderSize, for: .mediaBox)
        if let tiff = thumbnail.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
          result(FlutterStandardTypedData(bytes: png))
        } else {
          result(FlutterError(code: "RENDER_FAILED", message: "Could not encode page to PNG", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
