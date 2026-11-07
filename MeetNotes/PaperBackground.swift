import SwiftUI

enum PaperStyle: String, CaseIterable, Identifiable {
    case grid = "Kareli"
    case lined = "Çizgili"
    case dotted = "Noktalı"
    case blank = "Boş"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .lined: return "line.horizontal.3"
        case .dotted: return "circle.grid.2x2.fill"
        case .blank: return "square"
        }
    }
}

struct PaperBackground: View {
    var style: PaperStyle = .grid
    var spacing: CGFloat = 38
    var opacity: Double = 0.18
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let step = max(20, spacing)
            
            let topInset = geometry.safeAreaInsets.top
            let leadingInset = geometry.safeAreaInsets.leading
            
            ZStack {
                // Background base color
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                switch style {
                case .grid:
                    // KARELİ DESEN (Tam kareler, üstten kesilme olmadan)
                    Path { path in
                        // Dikey Çizgiler (İleri ve geri)
                        var x = leadingInset
                        while x <= width + step {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                            x += step
                        }
                        var xBack = leadingInset - step
                        while xBack >= 0 {
                            path.move(to: CGPoint(x: xBack, y: 0))
                            path.addLine(to: CGPoint(x: xBack, y: height))
                            xBack -= step
                        }
                        
                        // Yatay Çizgiler (Başlangıç noktası tam safe area / başlık altı)
                        var y = topInset
                        while y <= height + step {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                            y += step
                        }
                        var yBack = topInset - step
                        while yBack >= 0 {
                            path.move(to: CGPoint(x: 0, y: yBack))
                            path.addLine(to: CGPoint(x: width, y: yBack))
                            yBack -= step
                        }
                    }
                    .stroke(Color.primary.opacity(opacity), lineWidth: 0.5)
                    
                case .lined:
                    // ÇİZGİLİ DEFTER DESENİ (Üstten tam satır yüksekliği ile başlar)
                    Path { path in
                        var y = topInset + step
                        while y <= height + step {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                            y += step
                        }
                    }
                    .stroke(Color.primary.opacity(opacity * 1.1), lineWidth: 0.6)
                    
                case .dotted:
                    // NOKTALI BULLET JOURNAL DESENİ
                    Canvas { context, size in
                        let dotRadius: CGFloat = 1.0
                        let dotColor = Color.primary.opacity(opacity * 2.2)
                        
                        var x = leadingInset + step
                        while x < size.width {
                            var y = topInset + step
                            while y < size.height {
                                let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                                context.fill(Circle().path(in: rect), with: .color(dotColor))
                                y += step
                            }
                            x += step
                        }
                    }
                    
                case .blank:
                    // DÜZ / BOŞ SAYFA
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Paper Settings Dialog / Popover View

struct PaperSettingsView: View {
    @Binding var selectedStyle: PaperStyle
    @Binding var gridSpacing: Double
    @Binding var lineOpacity: Double
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Label("Sayfa Düzeni", systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // 4-Card Style Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("ŞABLON SEÇİMİ")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(PaperStyle.allCases) { style in
                        PaperStyleCard(
                            style: style,
                            isSelected: selectedStyle == style
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedStyle = style
                            }
                        }
                    }
                }
            }
            
            if selectedStyle != .blank {
                Divider()
                
                // Spacing Setting
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Çizgi / Kare Boyutu")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(gridSpacing)) pt")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $gridSpacing, in: 24...52, step: 2)
                        .tint(Color.accentColor)
                }
                
                // Opacity Setting
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Çizgi Belirginliği")
                            .font(.subheadline)
                        Spacer()
                        Text("%\(Int(lineOpacity * 100))")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $lineOpacity, in: 0.08...0.45, step: 0.02)
                        .tint(Color.accentColor)
                }
            }
        }
        .padding(18)
        .frame(width: 290)
        .background(Material.regularMaterial)
    }
}

struct PaperStyleCard: View {
    let style: PaperStyle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Mini preview icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 48)
                    
                    switch style {
                    case .grid:
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    case .lined:
                        Image(systemName: "line.horizontal.3")
                            .font(.system(size: 24))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    case .dotted:
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    case .blank:
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                            .frame(width: 24, height: 24)
                    }
                }
                
                Text(style.rawValue)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.8 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        PaperBackground(style: .grid, spacing: 38, opacity: 0.2)
        PaperSettingsView(
            selectedStyle: .constant(.grid),
            gridSpacing: .constant(38),
            lineOpacity: .constant(0.18)
        )
    }
}
