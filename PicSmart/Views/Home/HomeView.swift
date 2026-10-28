//
//  HomeView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct HomeView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var navigationPath = NavigationPath()
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Reclaimed Storage & Trash Quick Banner
                    storageHeaderBanner
                        .padding(.horizontal, 16)
                    
                    // Limited permission banner if needed
                    if photoService.authorizationStatus == .limited {
                        limitedAccessBanner
                            .padding(.horizontal, 16)
                    }
                    
                    // Section 1: Clean Up Recommendations
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                            Text("Clean Up Recommendations")
                                .font(.headline.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(GalleryCategory.allCases.filter { $0.section == .cleanUp }) { category in
                                NavigationLink(value: category) {
                                    CategoryCardView(
                                        category: category,
                                        status: appModel.status(for: category)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Section 2: Organize & Review
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(.purple)
                            Text("Organize & Review")
                                .font(.headline.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(GalleryCategory.allCases.filter { $0.section == .organize }) { category in
                                NavigationLink(value: category) {
                                    CategoryCardView(
                                        category: category,
                                        status: appModel.status(for: category)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("PicSmart")
            .navigationDestination(for: GalleryCategory.self) { category in
                if category.isGrouped {
                    GroupedAssetGridView(category: category)
                } else if category == .largeVideos {
                    LargeVideosView()
                } else if category == .blurredPhotos {
                    BlurredPhotosView()
                } else if category == .people {
                    PeopleAndFacesView()
                } else {
                    MediaGridView(category: category)
                }
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "cleanupHistory" {
                    CleanupHistoryView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            appModel.refreshCounts()
        }) {
            SettingsView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                appModel.handleDidEnterBackground()
            case .active:
                appModel.handleDidBecomeActive()
            default:
                break
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, newValue in
            if !newValue {
                showingOnboarding = true
            }
        }
        .onAppear {
            AnalysisPipelineCoordinator.shared.resumeFromBackground()
            if appModel.counts[.screenshots] == nil || appModel.counts[.screenshots] == 0 {
                appModel.refreshCounts()
            }
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
            handleCommandLineArguments()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }
    
    private var storageHeaderBanner: some View {
        NavigationLink(value: "cleanupHistory") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup Activity & Trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    if appModel.lifetimeBytesSaved > 0 {
                        Text("\(ByteCountFormatter.string(fromByteCount: appModel.lifetimeBytesSaved, countStyle: .file)) recovered to date")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Track storage recovered & review trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var limitedAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited Photo Access")
                    .font(.subheadline.weight(.semibold))
                Text("PicSmart only has access to selected photos. You can update this in iOS Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func handleCommandLineArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingSettings = true
            }
        }
        if let idx = args.firstIndex(of: "-category"), idx + 1 < args.count {
            let catArg = args[idx + 1].lowercased()
            if let matched = GalleryCategory.allCases.first(where: { $0.rawValue.lowercased() == catArg }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigationPath = NavigationPath([matched])
                }
            }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        if url.host == "settings" || url.lastPathComponent == "settings" {
            showingSettings = true
            return
        }
        let catArg = url.lastPathComponent.lowercased()
        if let matched = GalleryCategory.allCases.first(where: { $0.rawValue.lowercased() == catArg }) {
            navigationPath = NavigationPath([matched])
        }
    }
}
