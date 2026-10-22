//
//  PicSmartApp.swift
//  PicSmart
//

import SwiftUI
import SwiftData
import TipKit

@main
struct PicSmartApp: App {
    @State private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(PhotoLibraryService.shared)
                .environment(AppSettings.shared)
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate),
                        .datastoreLocation(.applicationDefault)
                    ])
                }
        }
    }
}
