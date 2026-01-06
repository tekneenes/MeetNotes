import SwiftUI
import PencilKit

enum ToolType: String, CaseIterable, Identifiable {
    case pen
    case pencil
    case marker
    case monoline
    case fountain
    case watercolor
    case crayon
    case text // New Text Tool
    case eraser
    case lasso
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .monoline: return "scribble.variable"
        case .fountain: return "scribble.variable" // Fixed icon
        case .watercolor: return "paintbrush.fill"
        case .crayon: return "scribble"
        case .text: return "textformat" // Icon for text
        case .eraser: return "eraser.fill"
        case .lasso: return "lasso"
        }
    }
}

struct DrawingConfig {
    var toolType: ToolType = .pen
    var color: Color = .black
    var width: CGFloat = 5.0
    var opacity: Double = 1.0 // 0.0 to 1.0
    var isRulerActive: Bool = false
    
    // ERASER TYPES
    enum EraserMode {
        case bitmap
        case object
    }
    
    var eraserMode: EraserMode = .bitmap
    
    // Helper to Convert to PKTool
    func toPKTool() -> PKTool {
        let uiColor = UIColor(color).withAlphaComponent(opacity)
        
        switch toolType {
        case .pen:
            return PKInkingTool(.pen, color: uiColor, width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: uiColor, width: width)
        case .marker:
            return PKInkingTool(.marker, color: uiColor, width: width * 3)
        case .monoline:
            if #available(iOS 17.0, *) {
                return PKInkingTool(.monoline, color: uiColor, width: width)
            } else {
                return PKInkingTool(.pen, color: uiColor, width: width) // Fallback
            }
        case .fountain:
            if #available(iOS 17.0, *) {
                return PKInkingTool(.fountainPen, color: uiColor, width: width)
            } else {
                return PKInkingTool(.pen, color: uiColor, width: width) // Fallback
            }
        case .watercolor:
            if #available(iOS 17.0, *) {
                return PKInkingTool(.watercolor, color: uiColor, width: width * 2)
            } else {
                return PKInkingTool(.marker, color: uiColor, width: width) // Fallback
            }
        case .crayon:
            if #available(iOS 17.0, *) {
                return PKInkingTool(.crayon, color: uiColor, width: width * 2)
            } else {
                return PKInkingTool(.pencil, color: uiColor, width: width) // Fallback
            }
        case .text:
            return PKInkingTool(.pen, color: uiColor, width: width) // Fallback/Placeholder
        case .eraser:
            return PKEraserTool(eraserMode == .bitmap ? .bitmap : .vector)
        case .lasso:
            return PKLassoTool()
        }
    }
}
