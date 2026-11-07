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

struct ImageAnnotation: Identifiable, Codable {
    var id: UUID = UUID()
    var imageData: Data
    var x: CGFloat = 80
    var y: CGFloat = 80
    var width: CGFloat = 260
    var height: CGFloat = 200
}

class NoteManager: ObservableObject {
    // In-memory cache dictionaries (NOT @Published to prevent SwiftUI view update re-entrancy during reads)
    var drawings: [Date: PKDrawing] = [:]
    var pageDrawings: [String: PKDrawing] = [:]
    var textAnnotations: [Date: [TextAnnotation]] = [:]
    var imageAnnotations: [String: [ImageAnnotation]] = [:]
    var pageCounts: [String: Int] = [:]
    
    // File System Helpers
    private var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
    
    func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func pageKey(for date: Date, page: Int) -> String {
        return "\(dateKey(for: date))_p\(page)"
    }
    
    func filename(for date: Date, page: Int = 0, type: String) -> URL {
        let dateString = dateKey(for: date)
        let pageSuffix = page > 0 ? "_p\(page)" : ""
        return documentsFolder.appendingPathComponent("\(dateString)\(pageSuffix).\(type)")
    }
    
    // MARK: - Page Management
    func getPageCount(for date: Date) -> Int {
        let key = dateKey(for: date)
        if let count = pageCounts[key] {
            return max(1, count)
        }
        // Check disk for saved pages
        var count = 1
        while FileManager.default.fileExists(atPath: filename(for: date, page: count, type: "drawing").path) {
            count += 1
        }
        pageCounts[key] = count
        return count
    }
    
    @discardableResult
    func addPage(for date: Date) -> Int {
        let current = getPageCount(for: date)
        let newCount = current + 1
        pageCounts[dateKey(for: date)] = newCount
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        return newCount - 1 // Returns the new page's 0-based index
    }
    
    // SAVE / LOAD
    func saveDrawing(_ drawing: PKDrawing, for date: Date, page: Int = 0) {
        let key = pageKey(for: date, page: page)
        pageDrawings[key] = drawing
        if page == 0 { drawings[date] = drawing }
        
        DispatchQueue.global(qos: .background).async {
            do {
                let data = drawing.dataRepresentation()
                try data.write(to: self.filename(for: date, page: page, type: "drawing"))
            } catch {
                print("Failed to save drawing for page \(page): \(error)")
            }
        }
    }
    
    func loadDrawing(for date: Date, page: Int = 0) -> PKDrawing {
        let key = pageKey(for: date, page: page)
        if let drawing = pageDrawings[key] { return drawing }
        if page == 0, let drawing = drawings[date] { return drawing }
        
        let fileURL = filename(for: date, page: page, type: "drawing")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PKDrawing()
        }
        
        // Try Disk
        do {
            let data = try Data(contentsOf: fileURL)
            let drawing = try PKDrawing(data: data)
            // Cache in memory without asynchronous dispatch during view evaluation
            self.pageDrawings[key] = drawing
            if page == 0 { self.drawings[date] = drawing }
            return drawing
        } catch {
            print("Error loading drawing page \(page): \(error)")
            return PKDrawing()
        }
    }
    
    // MARK: - Images
    func saveImageAnnotations(_ annotations: [ImageAnnotation], for date: Date, page: Int = 0) {
        let key = pageKey(for: date, page: page)
        imageAnnotations[key] = annotations
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(annotations)
                try data.write(to: self.filename(for: date, page: page, type: "images.json"))
            } catch {
                print("Failed to save image annotations: \(error)")
            }
        }
    }
    
    func loadImageAnnotations(for date: Date, page: Int = 0) -> [ImageAnnotation] {
        let key = pageKey(for: date, page: page)
        if let cached = imageAnnotations[key] { return cached }
        let fileURL = filename(for: date, page: page, type: "images.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([ImageAnnotation].self, from: data)
            self.imageAnnotations[key] = loaded
            return loaded
        } catch {
            print("Error loading images: \(error)")
            return []
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
    
    func loadTextAnnotations(for date: Date) -> [TextAnnotation] {
        if let texts = textAnnotations[date] { return texts }
        let fileURL = filename(for: date, type: "json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let texts = try JSONDecoder().decode([TextAnnotation].self, from: data)
            self.textAnnotations[date] = texts
            return texts
        } catch {
            return []
        }
    }
    
    // MARK: - Thumbnail & Preview
    func thumbnail(for date: Date, size: CGSize = CGSize(width: 200, height: 120)) -> UIImage? {
        let drawing = loadDrawing(for: date, page: 0)
        guard !drawing.strokes.isEmpty else { return nil }
        
        let bounds = drawing.bounds
        guard bounds.width > 2 && bounds.height > 2 else { return nil }
        
        // Add 12% breathing room margin
        let marginX = max(bounds.width * 0.12, 16)
        let marginY = max(bounds.height * 0.12, 16)
        let renderRect = bounds.insetBy(dx: -marginX, dy: -marginY)
        
        return drawing.image(from: renderRect, scale: 2.0)
    }
    
    func hasContent(for date: Date) -> Bool {
        let drawing = loadDrawing(for: date, page: 0)
        if !drawing.strokes.isEmpty { return true }
        if !loadImageAnnotations(for: date, page: 0).isEmpty { return true }
        if getPageCount(for: date) > 1 { return true }
        return false
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
