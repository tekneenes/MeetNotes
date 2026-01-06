import SwiftUI
import PencilKit

struct ContentView: View {
    @StateObject private var noteManager = NoteManager()
    
    // Logic:
    // 1. SidebarTap -> Sets selectedDate
    // 2. selectedDate != nil -> ZStack Overlay shows DrawingView (Zoomed)
    @State private var selectedDate: Date? = nil
    @Namespace private var namespace
    
    // WEEKLY WORKSPACE STATE
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isWeeklyEditing: Bool = false // False = Preview (Click to Edit), True = Drawing Enabled
    
    @State private var canvasView = PKCanvasView()    // Drawing State (Global)
    @State private var drawingConfig = DrawingConfig()
    @State private var ringMenuConfig = RingMenuConfig()
    
    func openMenu(at location: CGPoint) {
        ringMenuConfig.location = location
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            ringMenuConfig.isVisible = true
            ringMenuConfig.showSatellites = true
        }
    }
    
    var dates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        components.weekday = 2
        guard let startOfWeek = calendar.date(from: components) else { return [] }
        var days: [Date] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        ZStack {
            // BASE LAYER: Split View (Sidebar + Weekly Workspace)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // SIDEBAR
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(dates, id: \.self) { date in
                             DateCardView(date: date, noteManager: noteManager)
                                .onTapGesture {
                                    selectedDate = date
                                    withAnimation {
                                        isWeeklyEditing = false
                                        columnVisibility = .detailOnly
                                    }
                                }
                        }
                    }
                    .padding()
                }
                .navigationTitle("MeetNotes")
                .background(Color(UIColor.systemGroupedBackground))
                
            } detail: {
                // RIGHT SIDE: WEEKLY WORKSPACE
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        GridBackground().opacity(0.15)
                        
                        if let startOfWeek = dates.first {
                            WeeklyCanvasWrapper(
                                noteManager: noteManager,
                                date: startOfWeek,
                                isEditing: $isWeeklyEditing,
                                drawingConfig: $drawingConfig,
                                onTwoFingerTap: { loc in openMenu(at: loc) },
                                onLongPress: { loc in openMenu(at: loc) }
                            )
                            .allowsHitTesting(!ringMenuConfig.isVisible)
                        }
                        
                        // PREVIEW OVERLAY
                        if !isWeeklyEditing {
                            Color.white.opacity(0.001)
                                .onTapGesture {
                                    withAnimation {
                                        isWeeklyEditing = true
                                        columnVisibility = .detailOnly
                                    }
                                }
                            
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("Tap to Start Writing")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .padding()
                                        .background(.thinMaterial)
                                        .cornerRadius(8)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                        
                        // CUSTOM TOOLBAR (Weekly)
                        if isWeeklyEditing {
                            CustomToolbar(
                                config: $drawingConfig,
                                containerSize: geo.size,
                                onOCR: {
                                    // Weekly OCR logic (if needed, or placeholder)
                                    // For now, we use current week's start date
                                    if let startOfWeek = dates.first {
                                        let currentDrawing = noteManager.drawings[startOfWeek] ?? PKDrawing()
                                        noteManager.recognizeText(from: currentDrawing) { newAnnotations in
                                            guard !newAnnotations.isEmpty else { return }
                                            var currentTexts = noteManager.textAnnotations[startOfWeek] ?? []
                                            currentTexts.append(contentsOf: newAnnotations)
                                            noteManager.saveTextAnnotations(currentTexts, for: startOfWeek)
                                        }
                                    }
                                }
                            )
                        }
                        
                        // RING MENU OVERLAY
                        if ringMenuConfig.isVisible {
                            RingMenu(config: $drawingConfig, menuConfig: $ringMenuConfig)
                        }
                    }
                }
            }
            
            // OVERLAY LAYER: ZOOMED DAILY NOTE
            if let date = selectedDate {
                DrawingView(
                    noteManager: noteManager,
                    date: date,
                    drawingConfig: $drawingConfig, // Pass shared config
                    namespace: namespace,
                    onClose: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            selectedDate = nil
                        }
                    }
                )
                .zIndex(100) // Float on top of everything
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
    }
}

// Wrapper to handle Weekly Canvas Persistence
struct WeeklyCanvasWrapper: View {
    @ObservedObject var noteManager: NoteManager
    var date: Date
    @Binding var isEditing: Bool
    @Binding var drawingConfig: DrawingConfig
    
    // Gestures passed from parent
    var onTwoFingerTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    
    @State private var canvasView = PKCanvasView()
    
    var body: some View {
        ZStack {
            CanvasView(
                canvasView: $canvasView,
                config: $drawingConfig,
                onTwoFingerTap: onTwoFingerTap,
                onLongPress: onLongPress
            )
            .disabled(!isEditing)
            
            // TEXT LAYER
            if isEditing {
                TextLayer(noteManager: noteManager, date: date, drawingConfig: $drawingConfig)
            }
        }
        .onAppear {
            let weeklyKeyDate = Date(timeIntervalSince1970: 0)
            canvasView.drawing = noteManager.loadDrawing(for: weeklyKeyDate)
        }
        .onDisappear {
            let weeklyKeyDate = Date(timeIntervalSince1970: 0)
            noteManager.saveDrawing(canvasView.drawing, for: weeklyKeyDate)
        }
    }
}

// BEAUTIFIED CARD COMPONENT
struct DateCardView: View {
    var date: Date
    @ObservedObject var noteManager: NoteManager
    
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        ZStack {
            // Card Background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // Highlight for Today
            if isToday {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
            }
            
            HStack(spacing: 0) {
                // Left Strip: Date Info
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? Color.blue : Color.primary)
                    
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground))
                
                Divider()
                
                // Right Side: Drawing Preview
                ZStack {
                     // subtle grid
                    GridBackground().opacity(0.1)
                    
                    Image(uiImage: noteManager.thumbnail(for: date, size: CGSize(width: 200, height: 100)))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DrawingView: View {
    @ObservedObject var noteManager: NoteManager
    var date: Date
    @Binding var drawingConfig: DrawingConfig
    var namespace: Namespace.ID
    var onClose: () -> Void
    
    @State private var canvasView = PKCanvasView()
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Background morphs from the Sidebar Card
                GridBackground()
                    .opacity(0.3)
                    .background(Color(UIColor.systemBackground))
                    .matchedGeometryEffect(id: date.timeIntervalSince1970, in: namespace)
                    .frame(width: geo.size.width, height: geo.size.height) // Ensure background fills
                
                CanvasView(canvasView: $canvasView, config: $drawingConfig)
                
                // Custom Toolbar for Daily Note
                VStack {
                    Spacer()
                    CustomToolbar(
                        config: $drawingConfig,
                        containerSize: geo.size,
                        onOCR: {
                            let currentDrawing = noteManager.drawings[date] ?? PKDrawing()
                            noteManager.recognizeText(from: currentDrawing) { newAnnotations in
                                guard !newAnnotations.isEmpty else { return }
                                var currentTexts = noteManager.textAnnotations[date] ?? []
                                currentTexts.append(contentsOf: newAnnotations)
                                noteManager.saveTextAnnotations(currentTexts, for: date)
                            }
                        }
                    )
                        .padding(.bottom, 20)
                }
                .zIndex(90)
                
                Button("Done", action: onClose)
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(8)
                    .padding()
                    .zIndex(100)
            }
        }
        .onAppear {
            canvasView.drawing = noteManager.loadDrawing(for: date)
        }
        .onDisappear {
            noteManager.saveDrawing(canvasView.drawing, for: date)
        }
        .statusBar(hidden: true)
    }
}

struct GridBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let step: CGFloat = 40
                let width = geometry.size.width
                let height = geometry.size.height
                for x in stride(from: 0, to: width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                for y in stride(from: 0, to: height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.gray, lineWidth: 0.5)
        }
        .background(Color(UIColor.systemBackground))
    }
}
