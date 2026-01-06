import SwiftUI

struct RingMenu: View {
    @Binding var config: DrawingConfig
    @Binding var menuConfig: RingMenuConfig
    
    // Geometry
    let centerSize: CGFloat = 60
    let ringRadius: CGFloat = 80
    let satelliteRadius: CGFloat = 120
    
    var body: some View {
        ZStack {
            // BACKDROP (Tap to dismiss)
            Color.black.opacity(0.01) // Invisible hit target
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        menuConfig.isVisible = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // MENU CONTENT
            ZStack {
                // 1. SATELLITES (Colors/Tools)
                if menuConfig.showSatellites {
                    satellitesLayer
                        .transition(.scale.combined(with: .opacity))
                }
                
                // 2. CONTROL RINGS (Thickness / Opacity)
                if config.toolType != .eraser && config.toolType != .lasso {
                    controlArc(isOpacity: false) // Thickness (Right)
                    controlArc(isOpacity: true)  // Opacity (Left)
                }
                
                // 3. CENTER BUTTON
                centerButton
            }
            .position(menuConfig.location)
        }
    }
    
    // MARK: - Components
    
    var centerButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                menuConfig.showSatellites.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                Circle()
                    .stroke(config.color, lineWidth: 3)
                    .padding(2)
                
                Image(systemName: config.toolType.icon)
                    .font(.title2)
                    .foregroundStyle(config.color)
            }
            .frame(width: centerSize, height: centerSize)
        }
    }
    
    var satellitesLayer: some View {
        ZStack {
            // Example Satellites: 3 Colors + Eraser Toggle
            satelliteButton(angle: -90, icon: "eraser.fill", color: .gray) {
                config.toolType = .eraser
            }
            
            satelliteButton(angle: -30, color: .blue) { config.color = .blue }
            satelliteButton(angle: 30, color: .red) { config.color = .red }
            satelliteButton(angle: 90, color: .black) { config.color = .black }
            satelliteButton(angle: 150, color: .green) { config.color = .green }
        }
    }
    
    func satelliteButton(angle: Double, icon: String? = nil, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation { action() }
        }) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 44, height: 44)
                    .shadow(radius: 4)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .offset(x: satelliteRadius * cos(angle.degreesToRadians), 
                y: satelliteRadius * sin(angle.degreesToRadians))
    }
    
    // MARK: - Arc Controls
    
    func controlArc(isOpacity: Bool) -> some View {
        // Opacity: Left (-135 to -225), Thickness: Right (-45 to 45) -> Adjusted for coordinate system
        // Let's do:
        // Thickness: Right Side (-60 to +60 degrees)
        // Opacity: Left Side (120 to 240 degrees)
        
        let startAngle: Double = isOpacity ? 140 : -40
        let endAngle: Double = isOpacity ? 220 : 40
        
        return ZStack {
            // Track
            ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
                .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: ringRadius * 2, height: ringRadius * 2)
            
            // ACTIVE DRAG ZONES (Overlays for hit testing and calculation)
            // Thickness Drag Zone (Right)
            ArcShape(startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: false)
                .stroke(Color.white.opacity(0.001), lineWidth: 30) // Invisible Touch Area
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            calculateValue(from: value.location, isOpacity: false)
                        }
                )
            
            // Opacity Drag Zone (Left)
            ArcShape(startAngle: .degrees(140), endAngle: .degrees(220), clockwise: false)
                .stroke(Color.white.opacity(0.001), lineWidth: 30)
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            calculateValue(from: value.location, isOpacity: true)
                        }
                )
        }
    }
    
    func calculateValue(from location: CGPoint, isOpacity: Bool) {
        // Center of the arc frame (width: ringRadius*2) is (ringRadius, ringRadius)
        let center = CGPoint(x: ringRadius, y: ringRadius)
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)
        var angle = atan2(vector.y, vector.x) * 180 / .pi
        if angle < 0 { angle += 360 }
        
        // Define Ranges
        // let thickStart: Double = 320 // Unused
        // let thickEnd: Double = 40 // Unused
        let opStart: Double = 140
        let opEnd: Double = 220
        
        if isOpacity {
            // Range 140 -> 220
            let clamped = min(max(angle, opStart), opEnd)
            let percentage = (clamped - opStart) / (opEnd - opStart)
            config.opacity = max(0.1, percentage) // Min 0.1
        } else {
            // Range -40 (320) -> 40
            // Normalize angle for this wrap-around range
            var effectiveAngle = angle
            if effectiveAngle > 180 { effectiveAngle -= 360 } // Convert 320 to -40
            
            let clamped = min(max(effectiveAngle, -40), 40)
            let percentage = (clamped - (-40)) / (80)
            config.width = max(1, percentage * 40)
        }
    }
    
    // ... ArcShape and Extension kept ....
}

// Move Helper here to ensure compilation if not already valid
struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Improve center calculation
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(center: center,
                    radius: rect.width / 2,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: !clockwise) // SwiftUI Arc clockwise is inverted relative to math usually, check usage
        return path
    }
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
}

