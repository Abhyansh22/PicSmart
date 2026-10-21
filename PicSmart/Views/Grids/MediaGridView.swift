//
//  MediaGridView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct MediaGridView: View {
    let category: GalleryCategory
    @State private var viewModel: MediaCollectionViewModel
    @State private var selectedAsset: PHAsset?
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    init(category: GalleryCategory) {
        self.category = category
        _viewModel = State(wrappedValue: MediaCollectionViewModel(category: category))
    }
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.totalCount == 0 {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    if let msg = viewModel.progressMessage {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
                .refreshable {
                    viewModel.load()
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
        .sheet(item: $selectedAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
    }
}
