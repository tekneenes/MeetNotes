//
//  MeetNotesApp.swift
//  MeetNotes
//
//  Created by ENES EMİN    on 1/3/26.
//

import SwiftUI
import CoreData

@main
struct MeetNotesApp: App {
    let persistenceController = PersistenceController.shared
    @State private var isShowingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                
                if isShowingSplash {
                    SplashScreenView(isActive: $isShowingSplash)
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .scale(scale: 1.06).combined(with: .opacity)
                        ))
                        .zIndex(999)
                }
            }
        }
    }
}
