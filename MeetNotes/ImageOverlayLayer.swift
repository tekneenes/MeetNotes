import SwiftUI

struct ImageOverlayLayer: View {
    @Binding var images: [ImageAnnotation]
    var onImagesChanged: (() -> Void)? = nil
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(images) { item in
                SingleImageCard(
                    annotation: item,
                    onUpdate: { updated in
                        if let idx = images.firstIndex(where: { $0.id == updated.id }) {
                            images[idx] = updated
                            onImagesChanged?()
                        }
                    },
                    onDelete: {
                        images.removeAll(where: { $0.id == item.id })
                        onImagesChanged?()
                    }
                )
            }
        }
    }
}

struct SingleImageCard: View {
    let annotation: ImageAnnotation
    let onUpdate: (ImageAnnotation) -> Void
    let onDelete: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var currentWidth: CGFloat = 260
    @State private var currentHeight: CGFloat = 200
    @State private var isSelected: Bool = false
    
    var body: some View {
        let posX = annotation.x + dragOffset.width
        let posY = annotation.y + dragOffset.height
        
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: annotation.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: currentWidth, height: currentHeight)
                    .clipped()
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 12 : 6, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
                    )
            }
            
            // Delete & resize controls when selected
            if isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, .red)
                        .background(Circle().fill(.white).frame(width: 18, height: 18))
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
                
                // Bottom-right resize handle
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor, .white)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        currentWidth = max(100, annotation.width + value.translation.width)
                                        currentHeight = max(80, annotation.height + value.translation.height)
                                    }
                                    .onEnded { value in
                                        var updated = annotation
                                        updated.width = max(100, annotation.width + value.translation.width)
                                        updated.height = max(80, annotation.height + value.translation.height)
                                        onUpdate(updated)
                                    }
                            )
                            .offset(x: 8, y: 8)
                    }
                }
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .position(x: posX + currentWidth / 2, y: posY + currentHeight / 2)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isSelected.toggle()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    var updated = annotation
                    updated.x += value.translation.width
                    updated.y += value.translation.height
                    dragOffset = .zero
                    onUpdate(updated)
                }
        )
        .onAppear {
            currentWidth = annotation.width
            currentHeight = annotation.height
        }
    }
}
