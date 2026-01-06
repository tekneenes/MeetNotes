import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var config: DrawingConfig
    
    // Callbacks for Gestures
    var onTwoFingerTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        // Attach Gestures
        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.cancelsTouchesInView = false
        twoFingerTap.delegate = context.coordinator
        canvasView.addGestureRecognizer(twoFingerTap)
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.cancelsTouchesInView = false
        longPress.delegate = context.coordinator
        canvasView.addGestureRecognizer(longPress)
        
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = config.toPKTool()
        uiView.isRulerActive = config.isRulerActive
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasView
        
        init(parent: CanvasView) {
            self.parent = parent
        }
        
        @objc func handleTwoFingerTap(_ sender: UITapGestureRecognizer) {
            if sender.state == .ended {
                let location = sender.location(in: sender.view)
                parent.onTwoFingerTap?(location)
            }
        }
        
        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            if sender.state == .began {
                let location = sender.location(in: sender.view)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                parent.onLongPress?(location)
            }
        }
        
        // Allow simultaneous recognition with PencilKit's internal gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}
