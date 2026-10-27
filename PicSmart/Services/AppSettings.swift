//
//  AppSettings.swift
//  PicSmart
//

import SwiftUI
import Observation

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()
    
    init() {}
    
    #if DEBUG
    func resetToFreshInstall(appModel: AppModel) async {
        await TestingResetManager.resetAll(appModel: appModel)
    }
    #endif
}
