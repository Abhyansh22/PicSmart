//
//  CleanupHistoryView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct CleanupHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var records: [(id: UUID, date: Date, categoryTitle: String, itemCount: Int, bytesSaved: Int64, sampleIds: [String])] = []
    @State private var totalLifetime: Int64 = 0
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Storage Reclaimed Hero Card
                heroStorageCard
                
                // Cleanup Sessions List
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if records.isEmpty {
                    ContentUnavailableView(
                        "No Cleanup History",
                        systemImage: "trash.slash",
                        description: Text("Items you clean will appear here along with lifetime storage metrics.")
                    )
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recent Cleanup Activity")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                        
                        ForEach(records, id: \.id) { session in
                            sessionCard(session)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Cleanup & Trash")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
    }
    
    // MARK: - Hero Card
    
    private var heroStorageCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "sparkles")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Space Recovered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(ByteCountFormatter.string(fromByteCount: totalLifetime, countStyle: .file))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safe 30-Day Recovery")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Cleaned items are held in Apple Photos 'Recently Deleted' for 30 days before permanent deletion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    if let url = URL(string: "photos-redirect://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Open Trash")
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    
    // MARK: - Session Card
    
    private func sessionCard(_ session: (id: UUID, date: Date, categoryTitle: String, itemCount: Int, bytesSaved: Int64, sampleIds: [String])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.categoryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("-\(ByteCountFormatter.string(fromByteCount: session.bytesSaved, countStyle: .file))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                    
                    Text("\(session.itemCount) item\(session.itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Sample previews
            if !session.sampleIds.isEmpty {
                HStack(spacing: 8) {
                    ForEach(session.sampleIds, id: \.self) { assetId in
                        SampleThumbnail(assetId: assetId)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
            }
            
            Divider()
            
            // Revert / Restore action
            HStack {
                Text("Made a mistake?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    if let url = URL(string: "photos-redirect://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward.circle")
                        Text("Recover in Apple Photos")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private func loadHistory() async {
        if let items = try? await PersistentClusterStore.shared.fetchCleanupHistory() {
            self.records = items
            self.totalLifetime = (try? await PersistentClusterStore.shared.totalLifetimeBytesSaved()) ?? 0
        }
        self.isLoading = false
    }
}

private struct SampleThumbnail: View {
    let assetId: String
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .tertiarySystemFill)
            }
        }
        .task {
            let options = PHFetchOptions()
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: options)
            if let asset = result.firstObject {
                let _ = ThumbnailService.shared.requestThumbnail(for: asset, targetSize: CGSize(width: 100, height: 100)) { img in
                    self.image = img
                }
            }
        }
    }
}
