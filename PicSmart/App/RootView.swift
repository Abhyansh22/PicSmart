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
    
    var body: some View {
        Group {
            switch photoService.authorizationStatus {
            case .authorized, .limited:
                HomeView()
                
            case .notDetermined:
                PermissionRequestView()
                
            case .denied, .restricted:
                PermissionDeniedView()
                
            @unknown default:
                PermissionDeniedView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: photoService.authorizationStatus)
        .task {
            photoService.checkAuthorization()
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
}

// MARK: - Permission Prompt View

struct PermissionRequestView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppModel.self) private var appModel
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Welcome to PicSmart")
                    .font(.title2.weight(.bold))
                
                Text("PicSmart uses advanced on-device matrix signal processing and neural vision to organize your screenshots, identify exact duplicate files, and surface large videos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            Button {
                guard !isRequesting else { return }
                isRequesting = true
                Task {
                    let status = await photoService.requestAuthorization()
                    isRequesting = false
                    if status == .authorized || status == .limited {
                        appModel.onPhotoAccessGranted()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Allow Photo Access")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRequesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
            }
            
            VStack(spacing: 8) {
                Text("Photo Access Required")
                    .font(.title2.weight(.bold))
                
                Text("PicSmart requires photo library access to organize your media and detect duplicates. Please enable access in iOS Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}
