import SwiftUI

struct CustomToolbar: View {
    @Binding var config: DrawingConfig
    var containerSize: CGSize
    
    enum DockEdge {
        case left
        case right
        case bottom
    }
    
    // Position State
    @State private var position: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var hasInitializedPosition: Bool = false
    @State private var isDragging: Bool = false
    @State private var currentEdge: DockEdge = .bottom
    
    // Configuration State
    @State private var isMinimized: Bool = false
    @State private var showSettings: Bool = false
    @State private var orientation: Orientation = .horizontal
    
    enum Orientation {
        case horizontal
        case vertical
    }
    
    let defaultColors: [Color] = [.black, .blue, .red, .green]
    
    // CONSTANTS
    let toolbarThick: CGFloat = 54
    let minimizedSize: CGFloat = 48
    let approxLength: CGFloat = 630
    
    var body: some View {
        ZStack {
            // SETTINGS POPOVER
            if showSettings && !isMinimized && !isDragging {
                ToolSettingsView(config: $config)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .offset(settingsOffset)
                    .zIndex(10)
            }
            
            // MAIN TOOLBAR BODY
            mainContent
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(isDragging ? 0.32 : 0.15),
                    radius: isDragging ? 22 : 10,
                    x: 0,
                    y: isDragging ? 8 : 4
                )
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .contentShape(Capsule())
                .highPriorityGesture(dragGesture)
                .onTapGesture {
                    if isMinimized || isDragging {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            isMinimized = false
                            isDragging = false
                            snapToEdge(lastLocation: position)
                        }
                    }
                }
                .zIndex(1)
        }
        .position(position)
        .offset(dragOffset)
        .onAppear {
            if !hasInitializedPosition {
                position = CGPoint(x: containerSize.width / 2, y: containerSize.height - 70)
                hasInitializedPosition = true
            }
            snapToEdge(lastLocation: position)
        }
    }
    
    // MARK: - Views
    
    var mainContent: some View {
        ZStack {
            if isDragging || isMinimized {
                // KÜÇÜLMÜŞ TAŞIMA / SİMGE PAKETİ (Tıklanabilir ve Taşınabilir)
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 4, height: 18)
                    
                    Image(systemName: config.toolType.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 14)
                .frame(height: toolbarThick)
                .contentShape(Capsule())
                
            } else {
                // TAM AÇIK DOCK
                if orientation == .horizontal {
                    HStack(spacing: 8) {
                        minimizeHandle
                        dividerView
                        drawingToolsStack
                        dividerView
                        utilityToolsStack
                        dividerView
                        colorsStack
                        dividerView
                        actionButtonsStack
                    }
                    .padding(.horizontal, 14)
                    .frame(height: toolbarThick)
                    
                } else {
                    VStack(spacing: 5) {
                        minimizeHandle
                        dividerView
                        drawingToolsStack
                        dividerView
                        utilityToolsStack
                        dividerView
                        colorsStack
                        dividerView
                        actionButtonsStack
                    }
                    .padding(.vertical, 14)
                    .frame(width: toolbarThick)
                }
            }
        }
    }
    
    // Taşıma ve Küçültme Tutamacı
    var minimizeHandle: some View {
        Button(action: toggleMinimize) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(
                    width: orientation == .horizontal ? 4 : 24,
                    height: orientation == .horizontal ? 24 : 4
                )
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Araç çubuğunu küçült veya sürükle")
    }
    
    var dividerView: some View {
        Group {
            if orientation == .horizontal {
                Divider().frame(height: 18)
            } else {
                Divider().frame(width: 18)
            }
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let finalLocation = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
                dragOffset = .zero
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isDragging = false
                    isMinimized = false
                    snapToEdge(lastLocation: finalLocation)
                }
            }
    }
    
    var onOCR: () -> Void
    
    var drawingToolsStack: some View {
        Group {
            if orientation == .horizontal {
                HStack(spacing: 4) {
                    ForEach(ToolType.drawingTools) { tool in
                        ToolButton(tool: tool, isSelected: config.toolType == tool) {
                            handleToolTap(tool)
                        }
                    }
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(ToolType.drawingTools) { tool in
                        ToolButton(tool: tool, isSelected: config.toolType == tool) {
                            handleToolTap(tool)
                        }
                    }
                }
            }
        }
    }
    
    var utilityToolsStack: some View {
        Group {
            if orientation == .horizontal {
                HStack(spacing: 4) {
                    ForEach(ToolType.utilityTools) { tool in
                        ToolButton(tool: tool, isSelected: config.toolType == tool) {
                            handleToolTap(tool)
                        }
                    }
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(ToolType.utilityTools) { tool in
                        ToolButton(tool: tool, isSelected: config.toolType == tool) {
                            handleToolTap(tool)
                        }
                    }
                }
            }
        }
    }
    
    var colorsStack: some View {
        Group {
            if config.toolType != .eraser && config.toolType != .lasso {
                if orientation == .horizontal {
                    HStack(spacing: 5) { colorItems }
                } else {
                    VStack(spacing: 5) { colorItems }
                }
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
        }
    }
    
    var colorItems: some View {
        Group {
            ForEach(defaultColors, id: \.self) { color in
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        config.color = color
                    }
                }) {
                    ConfigColorCircle(color: color, isSelected: config.color == color)
                }
                .buttonStyle(.plain)
            }
            
            // Custom Rainbow Color Wheel Picker
            RainbowColorPickerCircle(selection: $config.color)
        }
    }
    
    var actionButtonsStack: some View {
        Group {
            if orientation == .horizontal {
                HStack(spacing: 6) {
                    rulerIcon
                    moreButton
                }
            } else {
                VStack(spacing: 6) {
                    rulerIcon
                    moreButton
                }
            }
        }
    }
    
    var moreButton: some View {
        Menu {
            Button(action: onOCR) {
                Label("Metne Çevir (OCR)", systemImage: "text.viewfinder")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Daha Fazla Seçenek")
    }
    
    var rulerIcon: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                config.isRulerActive.toggle()
            }
        }) {
            Image(systemName: config.isRulerActive ? "ruler.fill" : "ruler")
                .font(.system(size: 16))
                .foregroundStyle(config.isRulerActive ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help("Cetvel")
    }
    
    // MARK: - Logic
    
    func toggleMinimize() {
        showSettings = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.74)) {
            isMinimized.toggle()
        }
    }
    
    private func snapToEdge(lastLocation: CGPoint) {
        let margin: CGFloat = 16
        let bottomDist = containerSize.height - lastLocation.y
        let leftDist = lastLocation.x
        let rightDist = containerSize.width - lastLocation.x
        
        let minDist = min(bottomDist, leftDist, rightDist)
        let targetEdge: DockEdge
        if minDist == bottomDist {
            targetEdge = .bottom
        } else if minDist == leftDist {
            targetEdge = .left
        } else {
            targetEdge = .right
        }
        
        let isNewEdge = (targetEdge != currentEdge)
        currentEdge = targetEdge
        
        if isMinimized {
            let clampedX = min(max(lastLocation.x, minimizedSize / 2 + margin), containerSize.width - minimizedSize / 2 - margin)
            let clampedY = min(max(lastLocation.y, minimizedSize / 2 + margin), containerSize.height - minimizedSize / 2 - margin)
            position = CGPoint(x: clampedX, y: clampedY)
            return
        }
        
        switch targetEdge {
        case .bottom:
            orientation = .horizontal
            let targetW = approxLength
            let targetH = toolbarThick
            let finalY = containerSize.height - (targetH / 2) - margin
            // Yeni kenara bırakıldıysa İLK OLARAK ORTALA, aynı kenarda ise kullanıcının sürüklediği yeri koru
            let finalX: CGFloat
            if isNewEdge {
                finalX = containerSize.width / 2
            } else {
                finalX = min(max(lastLocation.x, (targetW / 2) + margin), containerSize.width - (targetW / 2) - margin)
            }
            position = CGPoint(x: finalX, y: finalY)
            
        case .left:
            orientation = .vertical
            let targetW = toolbarThick
            let targetH = approxLength
            let finalX = (targetW / 2) + margin
            // Yeni kenara bırakıldıysa İLK OLARAK ORTALA, aynı kenarda ise kullanıcının sürüklediği yeri koru
            let finalY: CGFloat
            if isNewEdge {
                finalY = containerSize.height / 2
            } else {
                finalY = min(max(lastLocation.y, (targetH / 2) + margin), containerSize.height - (targetH / 2) - margin)
            }
            position = CGPoint(x: finalX, y: finalY)
            
        case .right:
            orientation = .vertical
            let targetW = toolbarThick
            let targetH = approxLength
            let finalX = containerSize.width - (targetW / 2) - margin
            // Yeni kenara bırakıldıysa İLK OLARAK ORTALA, aynı kenarda ise kullanıcının sürüklediği yeri koru
            let finalY: CGFloat
            if isNewEdge {
                finalY = containerSize.height / 2
            } else {
                finalY = min(max(lastLocation.y, (targetH / 2) + margin), containerSize.height - (targetH / 2) - margin)
            }
            position = CGPoint(x: finalX, y: finalY)
        }
    }
    
    private var settingsOffset: CGSize {
        if orientation == .horizontal {
            return CGSize(width: 0, height: -125)
        } else {
            return position.x < containerSize.width / 2 ? CGSize(width: 140, height: 0) : CGSize(width: -140, height: 0)
        }
    }
    
    func handleToolTap(_ tool: ToolType) {
        if config.toolType == tool {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                showSettings.toggle()
            }
        } else {
            if showSettings {
                withAnimation { showSettings = false }
            }
            config.toolType = tool
        }
    }
}

// MARK: - Subcomponents

struct ConfigColorCircle: View {
    var color: Color
    var isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            
            if isSelected {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(width: 26, height: 26)
    }
}

struct RainbowColorPickerCircle: View {
    @Binding var selection: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                        center: .center
                    )
                )
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
            
            // Invisible ColorPicker overlay capturing native tap
            ColorPicker("", selection: $selection)
                .labelsHidden()
                .opacity(0.015)
                .frame(width: 22, height: 22)
        }
        .frame(width: 26, height: 26)
        .help("Özel Renk Seç")
    }
}

struct ToolButton: View {
    let tool: ToolType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 32, height: 32)
                    
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }
                
                Image(systemName: tool.icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .frame(width: 30, height: 30)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }
}

struct ToolSettingsView: View {
    @Binding var config: DrawingConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(config.toolType == .eraser ? "SİLGİ MODU" : config.toolType.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            if config.toolType == .eraser {
                Picker("Silgi Türü", selection: $config.eraserMode) {
                    Text("Piksel").tag(DrawingConfig.EraserMode.bitmap)
                    Text("Nesne").tag(DrawingConfig.EraserMode.object)
                }
                .pickerStyle(.segmented)
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(config.width)) pt").font(.caption2.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                    Slider(value: $config.width, in: 1...40).tint(config.color)
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    HStack {
                        Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("%\(Int(config.opacity * 100))").font(.caption2.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Slider(value: $config.opacity, in: 0.1...1.0).tint(config.color)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(Material.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        CustomToolbar(
            config: .constant(DrawingConfig()),
            containerSize: CGSize(width: 800, height: 900),
            onOCR: {}
        )
    }
}

