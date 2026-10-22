//
//  PersonDetailView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct PersonDetailView: View {
    @Binding var person: PersonCluster
    var onRename: ((String) -> Void)?
    
    @Environment(AppModel.self) private var appModel
    @State private var isEditingName = false
    @State private var nameText = ""
    @State private var selectedAssetForPreview: PHAsset?
    @State private var selectedIds: Set<String> = []
    @State private var showingDeleteAlert = false
    @State private var isCleaning = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 6)
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Hero Person Header Card
                    heroPersonHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    
                    // Photos Grid
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(person.assets) { asset in
                            let isSelected = selectedIds.contains(asset.localIdentifier)
                            
                            ZStack(alignment: .topTrailing) {
                                ThumbnailView(asset: asset)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedAssetForPreview = asset
                                    }
                                
                                Button {
                                    if selectedIds.contains(asset.localIdentifier) {
                                        selectedIds.remove(asset.localIdentifier)
                                    } else {
                                        selectedIds.insert(asset.localIdentifier)
                                    }
                                } label: {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .bold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(
                                            isSelected ? .white : .secondary,
                                            isSelected ? Color.blue : Color.black.opacity(0.4)
                                        )
                                        .background(Circle().fill(.ultraThinMaterial))
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        let deleted = try? await appModel.deleteAssets(
                                            localIdentifiers: [asset.localIdentifier],
                                            categoryTitle: person.displayName
                                        )
                                        if let deleted {
                                            person.assets.removeAll { deleted.contains($0.localIdentifier) }
                                        }
                                    }
                                } label: {
                                    Label("Delete Photo", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }
            }
            
            // Bottom Clean Bar
            if !selectedIds.isEmpty {
                bottomCleanBar
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAssetForPreview) { asset in
            FullScreenAssetView(asset: asset)
        }
        .alert("Delete \(selectedIds.count) Photos?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    isCleaning = true
                    let toDelete = Array(selectedIds)
                    let deleted = try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: person.displayName)
                    if let deleted {
                        person.assets.removeAll { deleted.contains($0.localIdentifier) }
                        selectedIds.subtract(deleted)
                    }
                    isCleaning = false
                }
            }
        } message: {
            Text("These photos will be moved to Recently Deleted in Apple Photos.")
        }
    }
    
    // MARK: - Hero Person Header
    
    private var heroPersonHeader: some View {
        VStack(spacing: 12) {
            FaceAvatarView(
                asset: person.avatarAsset,
                faceBoundingBox: person.avatarFaceBoundingBox,
                size: 92
            )
            
            if isEditingName {
                HStack(spacing: 8) {
                    TextField("Enter Name", text: $nameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    
                    Button {
                        if !nameText.trimmingCharacters(in: .whitespaces).isEmpty {
                            person.name = nameText.trimmingCharacters(in: .whitespaces)
                            onRename?(person.name ?? "")
                        }
                        isEditingName = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                Button {
                    nameText = person.name ?? ""
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(person.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        
                        Image(systemName: "pencil.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            
            Text("\(person.count) photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    
    // MARK: - Floating Clean Bar
    
    private var bottomCleanBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(selectedIds.count) items selected")
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Button {
                    showingDeleteAlert = true
                } label: {
                    HStack(spacing: 6) {
                        if isCleaning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text("Clean Selected")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(isCleaning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}
