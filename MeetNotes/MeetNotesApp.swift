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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
