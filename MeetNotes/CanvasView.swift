import SwiftUI
import PencilKit

// Safe PKCanvasView subclass that blocks UIEditMenuInteraction on Mac Catalyst to prevent known Apple crash
class SafePKCanvasView: PKCanvasView {
    #if targetEnvironment(macCatalyst)
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }
    
    override func addInteraction(_ interaction: UIInteraction) {
        if String(describing: type(of: interaction)).contains("EditMenu") {
            return
        }
        super.addInteraction(interaction)
    }
    #endif
}

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var config: DrawingConfig
    
    // Callbacks for Gestures
    var onTwoFingerTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        #if targetEnvironment(macCatalyst)
        // Remove unsupported UIEditMenuInteraction to prevent Catalyst crash
        canvasView.interactions.removeAll { interaction in
            String(describing: type(of: interaction)).contains("EditMenu")
        }
        #endif
        
        // Prevent scroll bounce from triggering navigation bar height changes (stops dock jitter)
        canvasView.contentInsetAdjustmentBehavior = .never
        
        // Scrolling & Zooming (Dikey Kaydırma ve Yakınlaştırma)
        canvasView.isScrollEnabled = true
        canvasView.showsVerticalScrollIndicator = true
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        canvasView.bouncesZoom = true
        
        // Ensure large enough initial content size so drawing is NEVER clipped across the screen
        canvasView.contentSize = CGSize(width: 5000, height: 6000)
        
        // Attach Gestures
        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.cancelsTouchesInView = true
        twoFingerTap.delegate = context.coordinator
        canvasView.addGestureRecognizer(twoFingerTap)
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.cancelsTouchesInView = true // Cancels PencilKit stroke selection to prevent UIEditMenu crash
        longPress.delegate = context.coordinator
        canvasView.addGestureRecognizer(longPress)
        
        // Two-Finger Horizontal Swipes for Page Navigation
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft(_:)))
        swipeLeft.direction = .left
        swipeLeft.numberOfTouchesRequired = 2
        swipeLeft.delegate = context.coordinator
        canvasView.addGestureRecognizer(swipeLeft)
        
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight(_:)))
        swipeRight.direction = .right
        swipeRight.numberOfTouchesRequired = 2
        swipeRight.delegate = context.coordinator
        canvasView.addGestureRecognizer(swipeRight)
        
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = config.toPKTool()
        uiView.isRulerActive = config.isRulerActive
        
        // Canvas width must ALWAYS at least fill the full window width, and allow drawing across the entire view
        let targetWidth = max(uiView.bounds.width * 2, 5000)
        let targetHeight = max(uiView.bounds.height * 3, 6000)
        if uiView.contentSize.width < targetWidth || uiView.contentSize.height < targetHeight {
            uiView.contentSize = CGSize(width: targetWidth, height: targetHeight)
        }
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
        
        @objc func handleSwipeLeft(_ sender: UISwipeGestureRecognizer) {
            parent.onSwipeLeft?()
        }
        
        @objc func handleSwipeRight(_ sender: UISwipeGestureRecognizer) {
            parent.onSwipeRight?()
        }
        
        // Allow simultaneous recognition with PencilKit's internal gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}
