//
//  HomeView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct HomeView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppSettings.self) private var settings
    @State private var viewModel = HomeViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showingSettings = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Subtitle
                    Text("Intelligent multi-stage gallery analysis, duplicate detection, and storage optimization.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    
                    // Limited permission banner if needed
                    if photoService.authorizationStatus == .limited {
                        limitedAccessBanner
                            .padding(.horizontal, 16)
                    }
                    
                    // 6 Categories Grid
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GalleryCategory.allCases) { category in
                            NavigationLink(value: category) {
                                CategoryCardView(
                                    category: category,
                                    count: viewModel.counts[category]
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
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
                } else {
                    MediaGridView(category: category)
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
            .refreshable {
                viewModel.refreshCounts()
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            viewModel.refreshCounts()
        }) {
            SettingsView()
        }
        .onChange(of: settings.largeVideoThresholdMB) { _, _ in
            if viewModel.isViewActive {
                viewModel.refreshCounts()
            }
        }
        .onAppear {
            viewModel.onAppear()
            handleCommandLineArguments()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
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
