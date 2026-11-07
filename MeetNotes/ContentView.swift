import SwiftUI
import PencilKit
import PhotosUI

struct ContentView: View {
    @StateObject private var noteManager = NoteManager()
    
    // EXPANDING CARD HERO STATE (Nur İslami Yaşam Style)
    @State private var activeExpandingDate: Date? = nil
    @State private var isDetailExpanded: Bool = false
    @State private var cardFrames: [Date: CGRect] = [:]
    @Namespace private var namespace
    
    private func openDayNote(for date: Date) {
        guard activeExpandingDate == nil else { return }
        activeExpandingDate = date
        isWeeklyEditing = false
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
            isDetailExpanded = true
        }
    }
    
    private func closeDayNote() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            isDetailExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            activeExpandingDate = nil
        }
    }
    
    // WEEKLY WORKSPACE STATE
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isWeeklyEditing: Bool = false // False = Preview (Click to Edit), True = Drawing Enabled
    
    @State private var canvasView: PKCanvasView = SafePKCanvasView()    // Drawing State (Global)
    @State private var drawingConfig = DrawingConfig()
    @State private var ringMenuConfig = RingMenuConfig()
    
    // PAPER BACKGROUND STATE
    @State private var paperStyle: PaperStyle = .grid
    @State private var gridSpacing: Double = 38.0
    @State private var lineOpacity: Double = 0.16
    @State private var showPaperSettings: Bool = false
    
    // MULTI-PAGE & IMAGE STATE (Weekly)
    @State private var currentPage: Int = 0
    @State private var weeklyImages: [ImageAnnotation] = []
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    var weeklyKeyDate: Date {
        Date(timeIntervalSince1970: 0)
    }
    
    var weeklyPageCount: Int {
        noteManager.getPageCount(for: weeklyKeyDate)
    }
    
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
                    LazyVStack(spacing: 12) {
                        // Section Header: Date Range & Quick Jump
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("GÜNLÜK NOTLAR")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.8)
                                
                                if let first = dates.first, let last = dates.last {
                                    Text("\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                            }
                            Spacer()
                            
                            if let todayDate = dates.first(where: { Calendar.current.isDateInToday($0) }) {
                                Button {
                                    openDayNote(for: todayDate)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar.badge.clock")
                                            .font(.system(size: 11, weight: .medium))
                                        Text("Bugün")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.blue.opacity(0.14)))
                                    .foregroundStyle(Color.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        
                        ForEach(dates, id: \.self) { date in
                             DateCardView(date: date, noteManager: noteManager)
                                .opacity(activeExpandingDate == date ? 0.0 : 1.0)
                                .onTapGesture {
                                    openDayNote(for: date)
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .navigationTitle("MeetNotes")
                .background(Color(UIColor.systemGroupedBackground))
                
            } detail: {
                // RIGHT SIDE: WEEKLY WORKSPACE
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // DYNAMIC PAPER BACKGROUND (Kareli, Çizgili, Noktalı, Boş)
                        PaperBackground(
                            style: paperStyle,
                            spacing: CGFloat(gridSpacing),
                            opacity: lineOpacity
                        )
                        
                        if let startOfWeek = dates.first {
                            WeeklyCanvasWrapper(
                                noteManager: noteManager,
                                date: startOfWeek,
                                currentPage: currentPage,
                                isEditing: $isWeeklyEditing,
                                drawingConfig: $drawingConfig,
                                images: $weeklyImages,
                                onTwoFingerTap: { loc in openMenu(at: loc) },
                                onLongPress: { loc in openMenu(at: loc) },
                                onSwipeLeft: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        if currentPage < weeklyPageCount - 1 {
                                            currentPage += 1
                                        } else {
                                            let newIdx = noteManager.addPage(for: weeklyKeyDate)
                                            currentPage = newIdx
                                        }
                                    }
                                },
                                onSwipeRight: {
                                    if currentPage > 0 {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            currentPage -= 1
                                        }
                                    }
                                }
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(!ringMenuConfig.isVisible)
                        }
                        
                        // FLOATING PAGE NAVIGATION CHEVRONS (Edge Buttons)
                        if currentPage > 0 {
                            VStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        currentPage -= 1
                                    }
                                }) {
                                    Image(systemName: "chevron.compact.left")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 26, height: 54)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                        )
                                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 10)
                                Spacer()
                            }
                            .zIndex(40)
                        }
                        
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        if currentPage < weeklyPageCount - 1 {
                                            currentPage += 1
                                        } else {
                                            let newIdx = noteManager.addPage(for: weeklyKeyDate)
                                            currentPage = newIdx
                                        }
                                    }
                                }) {
                                    Image(systemName: currentPage < weeklyPageCount - 1 ? "chevron.compact.right" : "plus")
                                        .font(.system(size: currentPage < weeklyPageCount - 1 ? 20 : 16, weight: .bold))
                                        .foregroundStyle(currentPage < weeklyPageCount - 1 ? Color.secondary : Color.accentColor)
                                        .frame(width: 26, height: 54)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                        )
                                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 10)
                            }
                            Spacer()
                        }
                        .zIndex(40)
                        
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
                                    // Weekly OCR logic
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
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    // CENTER: PAGE INDICATOR & DOTS (⟨ ● ○ ○ ⟩ [+])
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            // Previous Page
                            Button(action: {
                                if currentPage > 0 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        currentPage -= 1
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .disabled(currentPage == 0)
                            
                            // Page Dots (Hangi sayfada olduğumuz)
                            HStack(spacing: 6) {
                                ForEach(0..<weeklyPageCount, id: \.self) { idx in
                                    Circle()
                                        .fill(currentPage == idx ? Color.accentColor : Color.primary.opacity(0.25))
                                        .frame(width: currentPage == idx ? 8 : 5, height: currentPage == idx ? 8 : 5)
                                        .scaleEffect(currentPage == idx ? 1.2 : 1.0)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                currentPage = idx
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 4)
                            
                            // Next Page
                            Button(action: {
                                if currentPage < weeklyPageCount - 1 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        currentPage += 1
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .disabled(currentPage >= weeklyPageCount - 1)
                            
                            // Add New Page Button (+)
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    let newIdx = noteManager.addPage(for: weeklyKeyDate)
                                    currentPage = newIdx
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .help("Yeni Sayfa Ekle")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    
                    // RIGHT: PHOTO PICKER & PAPER STYLE (Same level as sidebar button!)
                    ToolbarItemGroup(placement: .primaryAction) {
                        // Resim Ekle (Photo Picker)
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 14))
                                Text("Resim Ekle")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        
                        // Sayfa Düzeni (Kareli, Çizgili, Noktalı, Boş)
                        Button(action: { showPaperSettings.toggle() }) {
                            HStack(spacing: 5) {
                                Image(systemName: paperStyle.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(paperStyle.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .popover(isPresented: $showPaperSettings, arrowEdge: .top) {
                            PaperSettingsView(
                                selectedStyle: $paperStyle,
                                gridSpacing: $gridSpacing,
                                lineOpacity: $lineOpacity
                            )
                        }
                    }
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                let newImg = ImageAnnotation(imageData: data, x: 80, y: 120, width: 260, height: 200)
                                weeklyImages.append(newImg)
                                noteManager.saveImageAnnotations(weeklyImages, for: weeklyKeyDate, page: currentPage)
                                selectedPhotoItem = nil
                            }
                        }
                    }
                }
            }
            
            // OVERLAY LAYER: EXPANDING HERO NOTE (Smooth card-to-fullscreen growth like Nur İslami Yaşam)
            if let date = activeExpandingDate {
                GeometryReader { screenGeo in
                    let screenRect = CGRect(origin: .zero, size: screenGeo.size)
                    let originRect = cardFrames[date] ?? CGRect(x: 16, y: 120, width: 330, height: 102)
                    
                    let currentRect = isDetailExpanded ? screenRect : originRect
                    let cornerRadius: CGFloat = isDetailExpanded ? 0 : 18
                    
                    ZStack(alignment: .topLeading) {
                        // Full Note Canvas View
                        DrawingView(
                            noteManager: noteManager,
                            date: date,
                            drawingConfig: $drawingConfig,
                            paperStyle: $paperStyle,
                            gridSpacing: $gridSpacing,
                            lineOpacity: $lineOpacity,
                            namespace: namespace,
                            onClose: {
                                closeDayNote()
                            }
                        )
                        .frame(width: screenGeo.size.width, height: screenGeo.size.height)
                        .opacity(isDetailExpanded ? 1.0 : 0.0)
                        
                        // Card Preview during the morphing transition
                        if !isDetailExpanded {
                            DateCardView(date: date, noteManager: noteManager)
                                .frame(width: originRect.width, height: originRect.height)
                        }
                    }
                    .frame(width: currentRect.width, height: currentRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.blue.opacity(isDetailExpanded ? 0.0 : 0.5), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isDetailExpanded ? 0 : 1.5
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(isDetailExpanded ? 0.35 : 0.1),
                        radius: isDetailExpanded ? 24 : 8,
                        x: 0,
                        y: isDetailExpanded ? 8 : 2
                    )
                    .position(x: currentRect.midX, y: currentRect.midY)
                }
                .ignoresSafeArea()
                .zIndex(200)
            }
        }
        .coordinateSpace(name: "AppWindowSpace")
        .onPreferenceChange(CardFramePreferenceKey.self) { frames in
            self.cardFrames = frames
        }
    }
}

// Wrapper to handle Weekly Canvas Persistence
struct WeeklyCanvasWrapper: View {
    @ObservedObject var noteManager: NoteManager
    var date: Date
    var currentPage: Int
    @Binding var isEditing: Bool
    @Binding var drawingConfig: DrawingConfig
    @Binding var images: [ImageAnnotation]
    
    // Gestures passed from parent
    var onTwoFingerTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    
    @State private var canvasView: PKCanvasView = SafePKCanvasView()
    
    var weeklyKeyDate: Date {
        Date(timeIntervalSince1970: 0)
    }
    
    var body: some View {
        ZStack {
            // IMAGE LAYER (Interactive images placed on canvas)
            ImageOverlayLayer(images: $images) {
                noteManager.saveImageAnnotations(images, for: weeklyKeyDate, page: currentPage)
            }
            
            CanvasView(
                canvasView: $canvasView,
                config: $drawingConfig,
                onTwoFingerTap: onTwoFingerTap,
                onLongPress: onLongPress,
                onSwipeLeft: onSwipeLeft,
                onSwipeRight: onSwipeRight
            )
            .disabled(!isEditing)
            
            // TEXT LAYER
            if isEditing {
                TextLayer(noteManager: noteManager, date: date, drawingConfig: $drawingConfig)
            }
        }
        .onAppear {
            loadCanvas(for: currentPage)
        }
        .onChange(of: currentPage) { _, newPage in
            saveCanvas(for: currentPage)
            loadCanvas(for: newPage)
        }
        .onDisappear {
            saveCanvas(for: currentPage)
        }
    }
    
    private func loadCanvas(for page: Int) {
        canvasView.drawing = noteManager.loadDrawing(for: weeklyKeyDate, page: page)
        images = noteManager.loadImageAnnotations(for: weeklyKeyDate, page: page)
    }
    
    private func saveCanvas(for page: Int) {
        noteManager.saveDrawing(canvasView.drawing, for: weeklyKeyDate, page: page)
        noteManager.saveImageAnnotations(images, for: weeklyKeyDate, page: page)
    }
}

// BEAUTIFIED CARD COMPONENT
struct DateCardView: View {
    var date: Date
    @ObservedObject var noteManager: NoteManager
    
    @State private var isHovered: Bool = false
    
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var pageCount: Int {
        noteManager.getPageCount(for: date)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Calendar Date Tile
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? Color.blue : Color.secondary)
                    .tracking(0.8)
                
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(isToday ? Color.blue : Color.primary)
                
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isToday ? Color.primary.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if isToday {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                        Text("BUGÜN")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.blue)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.16)))
                    .padding(.top, 1)
                }
            }
            .frame(width: 76)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        isToday
                        ? Color.blue.opacity(0.12)
                        : Color(UIColor.tertiarySystemGroupedBackground).opacity(0.6)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isToday
                        ? Color.blue.opacity(0.35)
                        : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            }
            
            // Right: Mini Paper Preview Sheet
            ZStack {
                // Paper Base with subtle grid
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemGroupedBackground).opacity(0.45))
                    .overlay {
                        PaperBackground(style: .grid, spacing: 10, opacity: 0.05)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                
                // Content Thumbnail or Empty State
                if let thumb = noteManager.thumbnail(for: date) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                } else {
                    // Empty placeholder
                    VStack(spacing: 4) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(isToday ? Color.blue.opacity(0.6) : Color.secondary.opacity(0.35))
                        Text(isToday ? "Not Başlat" : "Boş Sayfa")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isToday ? Color.blue.opacity(0.75) : Color.secondary.opacity(0.45))
                    }
                }
                
                // Badges in top corners
                VStack {
                    HStack {
                        Spacer()
                        if pageCount > 1 {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 8))
                                Text("\(pageCount)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.secondary)
                            .padding(6)
                        }
                    }
                    Spacer()
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
            }
        }
        .padding(10)
        .frame(height: 102)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay {
                    // Subtle light sheen gradient
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.08 : (isToday ? 0.06 : 0.02)),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.16 : 0.06), lineWidth: 1)
            }
        }
        .shadow(
            color: isToday ? Color.blue.opacity(0.22) : Color.black.opacity(isHovered ? 0.12 : 0.05),
            radius: isToday ? 8 : (isHovered ? 6 : 3),
            x: 0,
            y: isToday ? 3 : (isHovered ? 3 : 1)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .background(
            GeometryReader { cardGeo in
                Color.clear.preference(
                    key: CardFramePreferenceKey.self,
                    value: [date: cardGeo.frame(in: .named("AppWindowSpace"))]
                )
            }
        )
    }
}

// TRACK CARD SCREEN RECTANGLES FOR HERO EXPANSION
struct CardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct DrawingView: View {
    @ObservedObject var noteManager: NoteManager
    var date: Date
    @Binding var drawingConfig: DrawingConfig
    @Binding var paperStyle: PaperStyle
    @Binding var gridSpacing: Double
    @Binding var lineOpacity: Double
    var namespace: Namespace.ID
    var onClose: () -> Void
    
    @State private var canvasView: PKCanvasView = SafePKCanvasView()
    @State private var showPaperSettings: Bool = false
    @State private var dailyPage: Int = 0
    @State private var dailyImages: [ImageAnnotation] = []
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    var dailyPageCount: Int {
        noteManager.getPageCount(for: date)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Background morphs from the Sidebar Card
                PaperBackground(
                    style: paperStyle,
                    spacing: CGFloat(gridSpacing),
                    opacity: lineOpacity
                )
                .matchedGeometryEffect(id: date.timeIntervalSince1970, in: namespace)
                .frame(width: geo.size.width, height: geo.size.height)
                
                // Images Layer
                ImageOverlayLayer(images: $dailyImages) {
                    noteManager.saveImageAnnotations(dailyImages, for: date, page: dailyPage)
                }
                
                CanvasView(
                    canvasView: $canvasView,
                    config: $drawingConfig,
                    onSwipeLeft: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if dailyPage < dailyPageCount - 1 {
                                dailyPage += 1
                            } else {
                                let newIdx = noteManager.addPage(for: date)
                                dailyPage = newIdx
                            }
                        }
                    },
                    onSwipeRight: {
                        if dailyPage > 0 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dailyPage -= 1
                            }
                        }
                    }
                )
                
                // FLOATING PAGE NAVIGATION CHEVRONS (Edge Buttons for Daily Note)
                if dailyPage > 0 {
                    VStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dailyPage -= 1
                            }
                        }) {
                            Image(systemName: "chevron.compact.left")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: 54)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 10)
                        Spacer()
                    }
                    .zIndex(40)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if dailyPage < dailyPageCount - 1 {
                                    dailyPage += 1
                                } else {
                                    let newIdx = noteManager.addPage(for: date)
                                    dailyPage = newIdx
                                }
                            }
                        }) {
                            Image(systemName: dailyPage < dailyPageCount - 1 ? "chevron.compact.right" : "plus")
                                .font(.system(size: dailyPage < dailyPageCount - 1 ? 20 : 16, weight: .bold))
                                .foregroundStyle(dailyPage < dailyPageCount - 1 ? Color.secondary : Color.accentColor)
                                .frame(width: 26, height: 54)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                    }
                    Spacer()
                }
                .zIndex(40)
                
                // UNIFIED TOP BAR: Done (Left) | Page Indicator (Center) | Photos & Style (Right)
                VStack {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            // Bitti (Done) Button
                            Button(action: onClose) {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.backward")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Bitti")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.escape, modifiers: [])
                            
                            // Date Title Pill
                            HStack(spacing: 5) {
                                Text(date.formatted(.dateTime.day()))
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                Text(date.formatted(.dateTime.month(.wide)))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(date.formatted(.dateTime.weekday(.wide)))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                        }
                        
                        Spacer()
                        
                        // Center Page Dots & Pager
                        HStack(spacing: 7) {
                            Button(action: {
                                if dailyPage > 0 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        dailyPage -= 1
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .disabled(dailyPage == 0)
                            
                            HStack(spacing: 5) {
                                ForEach(0..<dailyPageCount, id: \.self) { idx in
                                    Circle()
                                        .fill(dailyPage == idx ? Color.accentColor : Color.primary.opacity(0.25))
                                        .frame(width: dailyPage == idx ? 8 : 5, height: dailyPage == idx ? 8 : 5)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                dailyPage = idx
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 3)
                            
                            Button(action: {
                                if dailyPage < dailyPageCount - 1 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        dailyPage += 1
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .disabled(dailyPage >= dailyPageCount - 1)
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    let newIdx = noteManager.addPage(for: date)
                                    dailyPage = newIdx
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .help("Yeni Sayfa Ekle")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                        
                        Spacer()
                        
                        // Right Side Controls: Resim Ekle & Sayfa Düzeni
                        HStack(spacing: 8) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 13))
                                    Text("Resim")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { showPaperSettings.toggle() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: paperStyle.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(paperStyle.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showPaperSettings, arrowEdge: .top) {
                                PaperSettingsView(
                                    selectedStyle: $paperStyle,
                                    gridSpacing: $gridSpacing,
                                    lineOpacity: $lineOpacity
                                )
                            }
                        }
                    }
                    .padding(.leading, 84)
                    .padding(.trailing, 18)
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .zIndex(100)
                
                // Custom Toolbar for Daily Note
                VStack {
                    Spacer()
                    CustomToolbar(
                        config: $drawingConfig,
                        containerSize: geo.size,
                        onOCR: {
                            let currentDrawing = noteManager.loadDrawing(for: date, page: dailyPage)
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
            }
        }
        .onAppear {
            loadDailyCanvas(for: dailyPage)
        }
        .onChange(of: dailyPage) { _, newPage in
            saveDailyCanvas(for: dailyPage)
            loadDailyCanvas(for: newPage)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        let newImg = ImageAnnotation(imageData: data, x: 80, y: 120, width: 260, height: 200)
                        dailyImages.append(newImg)
                        noteManager.saveImageAnnotations(dailyImages, for: date, page: dailyPage)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .onDisappear {
            saveDailyCanvas(for: dailyPage)
        }
        .statusBar(hidden: true)
    }
    
    private func loadDailyCanvas(for page: Int) {
        canvasView.drawing = noteManager.loadDrawing(for: date, page: page)
        dailyImages = noteManager.loadImageAnnotations(for: date, page: page)
    }
    
    private func saveDailyCanvas(for page: Int) {
        noteManager.saveDrawing(canvasView.drawing, for: date, page: page)
        noteManager.saveImageAnnotations(dailyImages, for: date, page: page)
    }
}

struct GridBackground: View {
    var body: some View {
        PaperBackground(style: .grid, spacing: 38, opacity: 0.16)
    }
}

#Preview {
    ContentView()
}
