import SwiftUI

struct CustomToolbar: View {
    @Binding var config: DrawingConfig
    var containerSize: CGSize // passed from parent
    
    // Position State
    @State private var position: CGPoint = .zero
    @State private var hasInitializedPosition: Bool = false
    @State private var isDragging: Bool = false
    
    // Configuration State
    @State private var isMinimized: Bool = false
    @State private var showSettings: Bool = false
    @State private var orientation: Orientation = .horizontal
    
    @Namespace private var animation
    
    enum Orientation {
        case horizontal
        case vertical
    }
    
    let colors: [Color] = [.black, .blue, .red, .green, .orange, .purple]
    
    // CONSTANTS
    let toolbarThick: CGFloat = 88
    let minimizedSize: CGFloat = 64
    let toolbarLength: CGFloat = 700 
    
    var currentFrame: CGSize {
        if isMinimized {
            return CGSize(width: minimizedSize, height: minimizedSize)
        }
        return orientation == .horizontal
            ? CGSize(width: toolbarLength, height: toolbarThick)
            : CGSize(width: toolbarThick, height: toolbarLength)
    }
    
    var body: some View {
        ZStack {
            // SETTINGS POPOVER
            if showSettings && !isMinimized {
                ToolSettingsView(config: $config)
                    .transition(.scale.combined(with: .opacity))
                    .offset(settingsOffset)
                    .zIndex(10)
            }
            
            // MAIN TOOLBAR BODY
            mainContent
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .frame(width: isMinimized ? minimizedSize : nil, height: isMinimized ? minimizedSize : nil)
                .zIndex(1)
        }
        .position(position)
        .onAppear {
             if !hasInitializedPosition {
                 position = CGPoint(x: containerSize.width / 2, y: containerSize.height - 100)
                 hasInitializedPosition = true
             }
             snapToEdge(lastLocation: position)
        }
    }
    
    // MARK: - Views
    
    var mainContent: some View {
        ZStack {
            if isMinimized {
                // MINIMIZED (Draggable)
                Button(action: toggleMinimize) {
                    Image(systemName: "pencil.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.secondary)
                }
                .frame(width: minimizedSize, height: minimizedSize)
                .highPriorityGesture(dragGesture)
                .matchedGeometryEffect(id: "handle", in: animation)
                
            } else {
                // EXPANDED
                if orientation == .horizontal {
                    HStack(spacing: 16) {
                        minimizeHandle // Draggable Handle
                        Divider().frame(height: 24)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) { toolButtons }
                            .padding(.horizontal, 8)
                        }
                        .frame(minWidth: 100)
                        
                        Divider().frame(height: 24)
                        colorsStack
                        Divider().frame(height: 24)
                        
                        // Action Buttons
                        HStack(spacing: 16) {
                            rulerIcon
                            moreButton
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(width: toolbarLength, height: toolbarThick)
                    
                } else {
                    VStack(spacing: 12) {
                        minimizeHandle // Draggable Handle
                        Divider().frame(width: 24)
                        
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 16) { toolButtons }
                            .padding(.vertical, 8)
                        }
                        .frame(minHeight: 100)
                        
                        Divider().frame(width: 24)
                        colorsStack
                        Divider().frame(width: 24)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            rulerIcon
                            moreButton
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 14)
                    .frame(width: toolbarThick, height: toolbarLength)
                }
            }
        }
    }
    
    var minimizeHandle: some View {
        HStack(spacing: 0) {
            Button(action: toggleMinimize) {
                 Image(systemName: "line.3.horizontal")
                    .rotationEffect(.degrees(orientation == .horizontal ? 90 : 0))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .contentShape(Rectangle())
        }
        .matchedGeometryEffect(id: "handle", in: animation)
        .gesture(dragGesture)
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging { withAnimation(.interactiveSpring) { isDragging = true } }
                position = value.location
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    isDragging = false
                    snapToEdge(lastLocation: value.location)
                }
            }
    }
    
    var onOCR: () -> Void // New Callback
    
    // ...
    
    var moreButton: some View {
        Menu {
            Button(action: onOCR) {
                Label("Metne Çevir (OCR)", systemImage: "text.viewfinder")
            }
        } label: {
            Image(systemName: "ellipsis.circle") // Changed to circle for better touch target
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }
    
    var toolButtons: some View {
        ForEach(ToolType.allCases) { tool in
            ToolButton(tool: tool, isSelected: config.toolType == tool) {
                handleToolTap(tool)
            }
        }
    }
    
    var colorsStack: some View {
        Group {
            if config.toolType != .eraser && config.toolType != .lasso {
                if orientation == .horizontal {
                    HStack(spacing: 8) { colorButtons }
                } else {
                    VStack(spacing: 8) { colorButtons }
                }
            } else {
                 Color.clear.frame(width: 20, height: 20)
            }
        }
    }
    
    var colorButtons: some View {
        Group {
            ForEach(colors.prefix(3), id: \.self) { color in
                Button(action: { withAnimation { config.color = color } }) {
                    ConfigColorCircle(color: color, isSelected: config.color == color)
                }
            }
            ColorPicker("", selection: $config.color).labelsHidden().scaleEffect(0.8)
        }
    }
    
    var rulerIcon: some View {
        Button(action: { config.isRulerActive.toggle() }) {
            Image(systemName: config.isRulerActive ? "ruler.fill" : "ruler")
                .font(.title3)
                .foregroundStyle(config.isRulerActive ? .blue : .secondary)
        }
    }
    
    // MARK: - Logic
    
    func toggleMinimize() {
        showSettings = false
        let shiftAmount: CGFloat = (toolbarLength / 2) - (minimizedSize / 2) - 16
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            if !isMinimized {
                if orientation == .horizontal { position.x -= shiftAmount }
                else { position.y -= shiftAmount }
            } else {
                if orientation == .horizontal { position.x += shiftAmount }
                else { position.y += shiftAmount }
            }
            isMinimized.toggle()
        }
    }
    
    private func snapToEdge(lastLocation: CGPoint) {
        let margin: CGFloat = 16
        let bottomDist = containerSize.height - lastLocation.y
        let leftDist = lastLocation.x
        let rightDist = containerSize.width - lastLocation.x
        
        let minDist = min(bottomDist, leftDist, rightDist)
        
        var targetW: CGFloat = 0
        var targetH: CGFloat = 0
        
        if isMinimized {
            targetW = minimizedSize
            targetH = minimizedSize
        } else {
            if minDist == bottomDist {
                orientation = .horizontal
                targetW = toolbarLength
                targetH = toolbarThick
            } else {
                orientation = .vertical
                targetW = toolbarThick
                targetH = toolbarLength
            }
        }
        
        var finalX = lastLocation.x
        var finalY = lastLocation.y
        
        if minDist == bottomDist {
            finalY = containerSize.height - (targetH / 2) - margin
            finalX = containerSize.width / 2 
        } else if minDist == leftDist {
            finalX = (targetW / 2) + margin
            finalY = containerSize.height / 2 
        } else {
            finalX = containerSize.width - (targetW / 2) - margin
            finalY = containerSize.height / 2 
        }
        
        position = CGPoint(x: finalX, y: finalY)
    }
    
    private var settingsOffset: CGSize {
        if orientation == .horizontal {
            return CGSize(width: 0, height: -120)
        } else {
             return position.x < 100 ? CGSize(width: 120, height: 0) : CGSize(width: -120, height: 0)
        }
    }
    
    func handleToolTap(_ tool: ToolType) {
        if config.toolType == tool {
            withAnimation(.spring) { showSettings.toggle() }
        } else {
            if showSettings { withAnimation { showSettings = false } }
            config.toolType = tool
        }
    }
}

// ... Helpers ...
struct ConfigColorCircle: View {
    var color: Color
    var isSelected: Bool
    var body: some View {
        Circle().fill(color).frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            .overlay(Circle().stroke(Color.primary, lineWidth: isSelected ? 2.5 : 0).scaleEffect(isSelected ? 1.2 : 1.0))
    }
}

struct ToolButton: View {
    let tool: ToolType
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(Circle().fill(isSelected ? Color.black : Color.clear))
                .scaleEffect(isSelected ? 1.1 : 1.0)
        }
    }
}

struct ToolSettingsView: View {
    @Binding var config: DrawingConfig
    var body: some View {
         VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(config.toolType == .eraser ? "ERASER TYPE" : "OPTIONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 4)
            if config.toolType == .eraser {
                Picker("Eraser Type", selection: $config.eraserMode) {
                    Text("Pixel").tag(DrawingConfig.EraserMode.bitmap)
                    Text("Object").tag(DrawingConfig.EraserMode.object)
                }
                .pickerStyle(.segmented)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(config.width)) pts").font(.caption2.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                    Slider(value: $config.width, in: 1...40).tint(config.color)
                    Divider().background(Color.white.opacity(0.2))
                    HStack {
                        Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(config.opacity * 100))%").font(.caption2.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Slider(value: $config.opacity, in: 0.1...1.0).tint(config.color)
                }
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(Material.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 10)
    }
}
