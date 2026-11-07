import SwiftUI

struct SplashScreenView: View {
    @Binding var isActive: Bool
    
    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var strokeProgress: CGFloat = 0.0
    @State private var glowPulse: Bool = false
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            // Subtle Grid
            GridBackground()
                .opacity(0.12)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // Animated App Icon
                ZStack {
                    // Outer Glow
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 124, height: 124)
                        .blur(radius: glowPulse ? 24 : 12)
                        .scaleEffect(glowPulse ? 1.08 : 0.98)
                    
                    // Main App Tile
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color(red: 0.35, green: 0.3, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                        )
                        .shadow(color: Color.blue.opacity(0.35), radius: 20, x: 0, y: 10)
                    
                    // Drawing Animation on Tile
                    ZStack {
                        // Drawing Swoosh Path
                        Path { path in
                            path.move(to: CGPoint(x: 25, y: 70))
                            path.addCurve(
                                to: CGPoint(x: 85, y: 40),
                                control1: CGPoint(x: 45, y: 85),
                                control2: CGPoint(x: 65, y: 25)
                            )
                        }
                        .trim(from: 0, to: strokeProgress)
                        .stroke(
                            Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 110, height: 110)
                        
                        // Pencil Tip Icon
                        Image(systemName: "applepencil.tip")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .offset(x: 6, y: -6)
                    }
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                
                // Titles
                VStack(spacing: 8) {
                    Text("MeetNotes")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .tracking(0.5)
                    
                    Text("Akıllı Toplantı & Çizim Defteri")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .opacity(textOpacity)
                .offset(y: textOpacity == 1 ? 0 : 12)
                
                Spacer()
                
                // Bottom loading / tap indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .scaleEffect(glowPulse ? 1.3 : 0.8)
                    Text("Hazırlanıyor...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .opacity(textOpacity)
                .padding(.bottom, 36)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSplash()
        }
        .onAppear {
            // Step 1: Reveal Icon
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            
            // Step 2: Animate Pencil Path & Glow
            withAnimation(.easeInOut(duration: 0.9).delay(0.2)) {
                strokeProgress = 1.0
            }
            
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            
            // Step 3: Reveal Text
            withAnimation(.easeOut(duration: 0.5).delay(0.45)) {
                textOpacity = 1.0
            }
            
            // Step 4: Auto Dismiss after 1.8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                dismissSplash()
            }
        }
    }
    
    private func dismissSplash() {
        withAnimation(.easeInOut(duration: 0.45)) {
            isActive = false
        }
    }
}

#Preview {
    SplashScreenView(isActive: .constant(true))
}
