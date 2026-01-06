import SwiftUI
import PencilKit
import Combine
import Vision

struct TextAnnotation: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var position: CGPoint
    var color: [CGFloat] // Store as RGB array for Codable
    var fontSize: CGFloat
}

class NoteManager: ObservableObject {
    @Published var drawings: [Date: PKDrawing] = [:]
    @Published var textAnnotations: [Date: [TextAnnotation]] = [:]
    
    // File System Helpers
    private var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
    
    func filename(for date: Date, type: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return documentsFolder.appendingPathComponent("\(dateString).\(type)")
    }
    
    // SAVE / LOAD
    func saveDrawing(_ drawing: PKDrawing, for date: Date) {
        drawings[date] = drawing
        DispatchQueue.global(qos: .background).async {
            do {
                let data = drawing.dataRepresentation() // No try needed
                try data.write(to: self.filename(for: date, type: "drawing"))
            } catch {
                print("Failed to save drawing: \(error)")
            }
        }
    }
    
    func saveTextAnnotations(_ annotations: [TextAnnotation], for date: Date) {
        textAnnotations[date] = annotations
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(annotations)
                try data.write(to: self.filename(for: date, type: "json"))
            } catch {
                print("Failed to save texts: \(error)")
            }
        }
    }
    
    func loadDrawing(for date: Date) -> PKDrawing {
        if let drawing = drawings[date] { return drawing }
        // Try Disk
        do {
            let data = try Data(contentsOf: filename(for: date, type: "drawing"))
            let drawing = try PKDrawing(data: data)
            DispatchQueue.main.async { self.drawings[date] = drawing }
            return drawing
        } catch {
            return PKDrawing()
        }
    }
    
    func loadTextAnnotations(for date: Date) -> [TextAnnotation] {
        if let texts = textAnnotations[date] { return texts }
        do {
            let data = try Data(contentsOf: filename(for: date, type: "json"))
            let texts = try JSONDecoder().decode([TextAnnotation].self, from: data)
            DispatchQueue.main.async { self.textAnnotations[date] = texts }
            return texts
        } catch {
            return []
        }
    }
    
    // ... thumbnail ...
    func thumbnail(for date: Date, size: CGSize) -> UIImage {
        let drawing = loadDrawing(for: date)
        let rect = CGRect(origin: .zero, size: size)
        return drawing.image(from: rect, scale: 1.0)
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - OCR (Handwriting to Text)
    func recognizeText(from drawing: PKDrawing, completion: @escaping ([TextAnnotation]) -> Void) {
        // Guard against empty or tiny drawings (prevents Vision Error 13)
        let bounds = drawing.bounds
        if bounds.width < 10 || bounds.height < 10 {
            print("OCR: Drawing too small, skipping.")
            completion([])
            return
        }

        // 1. Convert Drawing to Image
        let image = drawing.image(from: bounds, scale: 2.0)
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        // 2. Create Vision Request
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            var newAnnotations: [TextAnnotation] = []
            let drawingBounds = drawing.bounds
            
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                
                // 3. Convert Normalized Coordinates to View Coordinates
                // Vision uses bottom-left (0,0) normalized (0-1).
                // UIKit/SwiftUI uses top-left (0,0).
                
                let box = observation.boundingBox // Normalized
                
                // Calculate size based on drawing bounds
                let width = box.width * drawingBounds.width
                let height = box.height * drawingBounds.height
                
                // Calculate position (Center)
                // X: Start + (NormalizedX * Width) + Correction
                // Y: Start + ((1 - NormalizedY - NormalizedHeight) * Height) -> Flip Y
                let x = drawingBounds.minX + (box.minX * drawingBounds.width) + (width / 2)
                let y = drawingBounds.minY + ((1 - box.minY - box.height) * drawingBounds.height) + (height / 2)
                
                let annotation = TextAnnotation(
                    text: candidate.string,
                    position: CGPoint(x: x, y: y),
                    color: [0, 0, 0], // Default Black
                    fontSize: 20 // Default size, hard to guess from OCR
                )
                newAnnotations.append(annotation)
            }
            
            DispatchQueue.main.async {
                completion(newAnnotations)
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        // 3. Perform Request
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("OCR Error: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}
