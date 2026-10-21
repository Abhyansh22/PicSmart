//
//  PicSmartApp.swift
//  PicSmart
//

import SwiftUI
import SwiftData

@main
struct PicSmartApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(PhotoLibraryService.shared)
                .environment(AppSettings.shared)
        }
    }
}
