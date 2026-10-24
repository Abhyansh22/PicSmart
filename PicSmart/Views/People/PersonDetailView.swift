//
//  PersonDetailView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct PersonDetailView: View {
    let personId: String
    
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSelectionMode = false
    @State private var selectedIds = Set<String>()
    @State private var activeAsset: PHAsset?
    @State private var showingDeleteAlert = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var isCleaning = false
    
    private var viewModel: PeopleAndFacesViewModel {
        appModel.peopleAndFacesViewModel
    }
    
    private var person: PersonCluster? {
        viewModel.personClusters.first { $0.id == personId }
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if let person {
                ScrollView {
                    VStack(spacing: 14) {
                        // Hero Header
                        heroHeader(for: person)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        
                        // Edge-to-edge photos grid
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(person.assets) { asset in
                                let isSelected = selectedIds.contains(asset.localIdentifier)
                                
                                ThumbnailView(
                                    asset: asset,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: isSelected,
                                    onToggleSelect: {
                                        toggleSelection(asset.localIdentifier)
                                    }
                                )
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(asset.localIdentifier)
                                    } else {
                                        activeAsset = asset
                                    }
                                }
                            }
                        }
                        .padding(.bottom, isSelectionMode && !selectedIds.isEmpty ? 90 : 20)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Person Removed",
                    systemImage: "person.slash",
                    description: Text("This person has been removed from your People directory.")
                )
            }
            
            // Bottom Clean Bar in Selection Mode
            if isSelectionMode && !selectedIds.isEmpty {
                bottomCleanBar
            }
        }
        .navigationTitle(person?.displayName ?? "Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let person, !person.assets.isEmpty {
                    HStack(spacing: 12) {
                        Button(isSelectionMode ? "Done" : "Select") {
                            withAnimation(.snappy(duration: 0.25)) {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedIds.removeAll()
                                }
                            }
                        }
                        .fontWeight(isSelectionMode ? .semibold : .regular)
                        
                        Menu {
                            Button {
                                viewModel.toggleFavorite(id: personId)
                            } label: {
                                Label(person.isFavorite ? "Unfavorite" : "Favorite", systemImage: person.isFavorite ? "heart.slash" : "heart")
                            }
                            
                            Button {
                                renameText = person.name ?? ""
                                showingRenameAlert = true
                            } label: {
                                Label("Edit Name", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                viewModel.removePerson(id: personId)
                                dismiss()
                            } label: {
                                Label("Remove from People", systemImage: "person.crop.circle.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body)
                        }
                    }
                }
            }
        }
        .sheet(item: $activeAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
        .alert("Name Person", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                viewModel.renamePerson(id: personId, newName: renameText)
            }
        } message: {
            Text("Add or update this person's name.")
        }
        .alert("Delete \(selectedIds.count) Photos?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedIds.count) Photos", role: .destructive) {
                Task {
                    isCleaning = true
                    let toDelete = Array(selectedIds)
                    try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: person?.displayName ?? "Person")
                    selectedIds.removeAll()
                    isCleaning = false
                    if let p = person, p.assets.isEmpty {
                        isSelectionMode = false
                    }
                }
            }
        } message: {
            Text("These photos will be moved to Recently Deleted in Apple Photos.")
        }
    }
    
    // MARK: - Hero Header
    
    private func heroHeader(for person: PersonCluster) -> some View {
        VStack(spacing: 12) {
            FaceAvatarView(
                asset: person.avatarAsset,
                faceBoundingBox: person.avatarFaceBoundingBox,
                size: 100
            )
            
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(person.isNamed ? person.displayName : "Add Name")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(person.isNamed ? Color.primary : Color.blue)
                    
                    if person.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    
                    Button {
                        renameText = person.name ?? ""
                        showingRenameAlert = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("\(person.count) photo\(person.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
    
    // MARK: - Floating Clean Bar
    
    private var bottomCleanBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(selectedIds.count) photos selected")
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
                        Text("Delete Selected")
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
