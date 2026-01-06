import SwiftUI
import UIKit

struct TextLayer: View {
    @ObservedObject var noteManager: NoteManager
    var date: Date
    @Binding var drawingConfig: DrawingConfig
    
    @State private var localTexts: [TextAnnotation] = []
    
    // We use a separate ID tracker to know which view should be active
    @State private var activeAnnotationID: UUID?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // RENDER EXISTING TEXTS (Always interactive)
            // Use By-Value iteration + Custom Safe Binding to avoid Index Out of Range crash
            ForEach(localTexts) { annotation in
                ResizableTextViewWrapper(
                    text: safeTextBinding(for: annotation),
                    color: safeColorBinding(for: annotation),
                    fontSize: annotation.fontSize,
                    isActive: activeAnnotationID == annotation.id,
                    onTap: {
                        activeAnnotationID = annotation.id
                    },
                    onDidEndEditing: {
                        activeAnnotationID = nil
                        save()
                    },
                    onDelete: {
                        // Delete logic
                        if let index = localTexts.firstIndex(where: { $0.id == annotation.id }) {
                            localTexts.remove(at: index)
                            activeAnnotationID = nil
                            save()
                        }
                    }
                )
                // Remove fixed frame constraint to allow intrinsic sizing, 
                // but we need a max width to prevent screen overflow.
                .frame(width: max(120, CGFloat(annotation.text.count) * annotation.fontSize * 0.7 + 40)) 
                .fixedSize() // Allow vertical growth
                .position(annotation.position)
                .gesture(
                    DragGesture(coordinateSpace: .named("canvas")) // Use stable coordinate space
                        .onChanged { value in
                            // Only allow drag if NOT editing
                            if activeAnnotationID != annotation.id {
                                // Smoothly update position using global coordinates
                                // We need to update the actual source of truth safely
                                if let index = localTexts.firstIndex(where: { $0.id == annotation.id }) {
                                    localTexts[index].position = value.location
                                }
                            }
                        }
                        .onEnded { _ in save() }
                )
            }
            
            // TAP TO CREATE (Only if Text Tool is active)
            if drawingConfig.toolType == .text {
                Color.white.opacity(0.001) // Hit target overlay
                    .onTapGesture { location in
                        // If we are editing something, finish it first
                        if activeAnnotationID != nil {
                            activeAnnotationID = nil
                            save()
                            return
                        }
                        addText(at: location)
                    }
            }
        }
        // KEY CHANGE: Removed the global .allowsHitTesting() modifier.
        // Existing texts are now always interactive.
        // The background "creation touches" are limited by the `if drawingConfig.toolType == .text` check above.
        .coordinateSpace(name: "canvas") // Define coordinate space
        .onAppear { load() }
        .onDisappear { save() }
    }
    
    // MARK: - Safe Bindings Helpers
    func safeTextBinding(for annotation: TextAnnotation) -> Binding<String> {
        Binding(
            get: {
                if let index = localTexts.firstIndex(where: { $0.id == annotation.id }) {
                    return localTexts[index].text
                }
                return ""
            },
            set: { newValue in
                if let index = localTexts.firstIndex(where: { $0.id == annotation.id }) {
                    localTexts[index].text = newValue
                }
            }
        )
    }
    
    func safeColorBinding(for annotation: TextAnnotation) -> Binding<[CGFloat]> {
        Binding(
            get: {
                if let index = localTexts.firstIndex(where: { $0.id == annotation.id }) {
                    return localTexts[index].color
                }
                return [0, 0, 0]
            },
            set: { newValue in
                if let index = localTexts.firstIndex(where: { $0.id == annotation.id }) {
                    localTexts[index].color = newValue
                }
            }
        )
    }
    
    func addText(at location: CGPoint) {
        let uiColor = UIColor(drawingConfig.color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        
        let newNote = TextAnnotation(
            text: "",
            position: location,
            color: [red, green, blue],
            fontSize: drawingConfig.width * 5
        )
        localTexts.append(newNote)
        
        // Activate immediately
        DispatchQueue.main.async {
            activeAnnotationID = newNote.id
        }
    }
    
    func load() {
        localTexts = noteManager.loadTextAnnotations(for: date)
    }
    
    func save() {
        // Remove empty texts
        localTexts.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        noteManager.saveTextAnnotations(localTexts, for: date)
    }
}

// MARK: - Custom Internal TextView for Menu Actions
class CustomTextView: UITextView {
    // No specific overrides needed for the new menu system unless blocking standard actions
}

// MARK: - UIKit Wrapper
struct ResizableTextViewWrapper: UIViewRepresentable {
    @Binding var text: String
    @Binding var color: [CGFloat]
    var fontSize: CGFloat
    var isActive: Bool
    var onTap: () -> Void
    var onDidEndEditing: () -> Void
    var onDelete: () -> Void // NEW: Deletion callback
    
    func makeUIView(context: Context) -> CustomTextView {
        let textView = CustomTextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.layer.cornerRadius = 8
        textView.delegate = context.coordinator
        
        textView.backgroundColor = UIColor.white.withAlphaComponent(0.01)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        textView.addGestureRecognizer(tap)
        
        return textView
    }
    
    func updateUIView(_ uiView: CustomTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        
        let uiColor = UIColor(red: color[0], green: color[1], blue: color[2], alpha: 1.0)
        if uiView.textColor != uiColor {
            uiView.textColor = uiColor
        }
        
        if uiView.font?.pointSize != fontSize {
            uiView.font = .systemFont(ofSize: fontSize)
        }
        
        if isActive {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.backgroundColor = UIColor.white.withAlphaComponent(0.8)
                    uiView.becomeFirstResponder()
                }
            }
        } else {
            if uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.resignFirstResponder()
                    uiView.backgroundColor = UIColor.white.withAlphaComponent(0.01)
                }
            } else {
                uiView.backgroundColor = UIColor.white.withAlphaComponent(0.01)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ResizableTextViewWrapper
        var isDeleting: Bool = false // Safety flag
        
        init(_ parent: ResizableTextViewWrapper) {
            self.parent = parent
        }
        
        // MARK: - iOS 16+ Menu Handling
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            // Create Custom Actions
            let changeColorAction = UIAction(title: "Rengi Değiştir", image: UIImage(systemName: "paintpalette")) { [weak self] _ in
                self?.changeColor()
            }
            
            let deleteAction = UIAction(title: "Sil", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.deleteText()
            }
            
            // combine with suggested actions or create a new structured menu
            var newActions = suggestedActions
            newActions.insert(changeColorAction, at: 0)
            newActions.insert(deleteAction, at: 1)
            
            return UIMenu(children: newActions)
        }
        
        func changeColor() {
            guard !isDeleting else { return }
            // Demo Action: Red
            parent.color = [1.0, 0.0, 0.0]
        }
        
        func deleteText() {
            isDeleting = true // Mark as deleting to block future updates
            DispatchQueue.main.async {
                self.parent.onDelete()
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
             guard !isDeleting else { return } // Block updates if deleting
             
             DispatchQueue.main.async {
                 // Double check inside async in case deletion happened in between
                 guard !self.isDeleting else { return }
                 
                 if self.parent.text != textView.text {
                     self.parent.text = textView.text
                     textView.invalidateIntrinsicContentSize()
                 }
             }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            guard !isDeleting else { return }
            DispatchQueue.main.async {
                self.parent.onDidEndEditing()
            }
        }
        
        @objc func handleTap() {
            guard !isDeleting else { return }
            DispatchQueue.main.async {
                self.parent.onTap()
            }
        }
    }
}
