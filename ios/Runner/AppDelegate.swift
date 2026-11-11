import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "MeetNotesOcrPlugin") {
      setupOcrChannel(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupOcrChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "meet_notes/ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "recognizeHandwriting" {
        guard let args = call.arguments as? [String: Any],
              let pngData = (args["pngBytes"] as? FlutterStandardTypedData)?.data else {
          result(FlutterError(code: "INVALID_ARGS", message: "pngBytes required", details: nil))
          return
        }
        guard let uiImage = UIImage(data: pngData),
              let cgImage = uiImage.cgImage else {
          result(FlutterError(code: "DECODE_FAILED", message: "Could not decode PNG image", details: nil))
          return
        }
        let language = (args["language"] as? String) ?? "tr-TR"
        DispatchQueue.global(qos: .userInitiated).async {
          let request = VNRecognizeTextRequest { req, error in
            if let error = error {
              DispatchQueue.main.async {
                result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
              }
              return
            }
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
              result([
                "text": lines.joined(separator: "\n"),
                "engine": "Apple Vision",
              ])
            }
          }
          request.recognitionLevel = .accurate
          request.usesLanguageCorrection = true
          if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLanguages = [language, "en-US"]
          } else {
            request.recognitionLanguages = ["en-US"]
          }

          let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
          do {
            try handler.perform([request])
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "OCR_PERFORM_FAILED", message: error.localizedDescription, details: nil))
            }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
