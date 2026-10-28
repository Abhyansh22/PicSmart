//
//  RootView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct RootView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var isShowingSplash: Bool = true
    
    var body: some View {
        ZStack {
            if isShowingSplash {
                AppSplashScreen()
                    .transition(.opacity)
            } else if !hasCompletedOnboarding {
                OnboardingView {
                    withAnimation(.snappy(duration: 0.35)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            } else {
                authenticatedContentView
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.35), value: isShowingSplash)
        .animation(.snappy(duration: 0.35), value: hasCompletedOnboarding)
        .animation(.snappy(duration: 0.35), value: photoService.authorizationStatus)
        .task {
            photoService.checkAuthorization()
            // 0.5s splash screen
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.snappy(duration: 0.35)) {
                isShowingSplash = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                photoService.checkAuthorization()
            }
        }
        .onChange(of: photoService.authorizationStatus) { oldStatus, newStatus in
            if (oldStatus == .notDetermined || oldStatus == .denied) && (newStatus == .authorized || newStatus == .limited) {
                appModel.onPhotoAccessGranted()
            }
        }
    }
    
    @ViewBuilder
    private var authenticatedContentView: some View {
        switch photoService.authorizationStatus {
        case .authorized, .limited:
            HomeView()
            
        case .notDetermined:
            PermissionPrePromptView { status in
                if status == .authorized || status == .limited {
                    appModel.onPhotoAccessGranted()
                }
            }
            
        case .denied, .restricted:
            PermissionDeniedView()
            
        @unknown default:
            PermissionDeniedView()
        }
    }
}
