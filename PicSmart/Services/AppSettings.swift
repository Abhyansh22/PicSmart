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
}
