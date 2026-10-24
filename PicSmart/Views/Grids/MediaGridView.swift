//
//  MediaGridView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct MediaGridView: View {
    let category: GalleryCategory
    @Environment(AppModel.self) private var appModel
    @State private var selectedAsset: PHAsset?
    
    private var viewModel: MediaCollectionViewModel {
        appModel.mediaViewModel(for: category)
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.totalCount == 0 && !viewModel.hasLoaded {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(viewModel.progressMessage ?? "Loading \(category.title.lowercased())…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.totalCount == 0 {
                ContentUnavailableView(
                    "No \(category.title) Found",
                    systemImage: category.iconName,
                    description: Text("Your photo library doesn't contain any items in this category.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // Summary Bar
                        HStack {
                            Text("\(viewModel.totalCount) items")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        // Zero-copy lazy grid over cursor
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(0..<viewModel.totalCount, id: \.self) { index in
                                if let asset = viewModel.asset(at: index) {
                                    ThumbnailView(asset: asset)
                                        .onTapGesture {
                                            selectedAsset = asset
                                        }
                                        .onAppear {
                                            viewModel.prefetch(around: index)
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            viewModel.startLoadIfNeeded()
        }
        .sheet(item: $selectedAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
    }
}
