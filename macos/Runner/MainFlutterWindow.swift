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
        let targetWidth = max((args["width"] as? Double) ?? 1200.0, 1.0)
        let targetHeight = bounds.width > 0 ? (bounds.height / bounds.width) * targetWidth : 960.0
        let pixelWidth = max(Int(ceil(targetWidth)), 1)
        let pixelHeight = max(Int(ceil(targetHeight)), 1)

        guard let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: pixelWidth,
          pixelsHigh: pixelHeight,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ),
        let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
          result(FlutterError(code: "RENDER_FAILED", message: "Could not create graphics context", details: nil))
          return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let ctx = nsCtx.cgContext
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(true)
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setAllowsFontSubpixelQuantization(true)

        let scaleX = CGFloat(pixelWidth) / max(bounds.width, 1.0)
        let scaleY = CGFloat(pixelHeight) / max(bounds.height, 1.0)
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.restoreGraphicsState()

        if let png = rep.representation(using: .png, properties: [:]) {
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
