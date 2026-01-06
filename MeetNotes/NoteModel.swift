import Foundation
import PencilKit

struct NoteModel: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = "Untitled Note"
    var drawingData: Data = Data()
    
    // Helper to load PKDrawing
    func getDrawing() -> PKDrawing {
        do {
            return try PKDrawing(data: drawingData)
        } catch {
            return PKDrawing()
        }
    }
}
