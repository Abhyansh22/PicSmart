//
//  PeopleAndFacesView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct PeopleAndFacesView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var renamingPersonId: String? = nil
    @State private var renamingText = ""
    @State private var showingRenameAlert = false
    
    private var viewModel: PeopleAndFacesViewModel {
        appModel.peopleAndFacesViewModel
    }
    
    private let directoryColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private let favoritesColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private var filteredClusters: [PersonCluster] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return viewModel.personClusters
        }
        return viewModel.personClusters.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var favoriteClusters: [PersonCluster] {
        filteredClusters.filter { $0.isFavorite }
    }
    
    private var otherClusters: [PersonCluster] {
        filteredClusters.filter { !$0.isFavorite }
    }
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.personClusters.isEmpty && !viewModel.hasCompletedScan {
                ScanningProgressView(
                    category: .people,
                    progress: viewModel.progress,
                    statusMessage: viewModel.statusMessage ?? "Analyzing people and faces…"
                )
            } else if viewModel.personClusters.isEmpty {
                ContentUnavailableView(
                    "No People Found",
                    systemImage: "person.2.slash",
                    description: Text("No photos with clear human faces were detected in your gallery.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Section 1: Clean Up Recommendations Tray
                        if !viewModel.blinks.isEmpty {
                            cleanupAssistantSection
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                        }
                        
                        // Section 2: Favorites (Hero Cards)
                        if !favoriteClusters.isEmpty {
                            favoritesSection
                                .padding(.horizontal, 16)
                        }
                        
                        // Section 3: People Directory Grid
                        peopleDirectorySection
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("People & Pets")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search people")
        .onAppear {
            AnalysisPipelineCoordinator.shared.userEntered(.people, in: appModel)
            viewModel.onAppear()
        }
        .onDisappear {
            AnalysisPipelineCoordinator.shared.userExited(.people)
            viewModel.onDisappear()
        }
        .alert("Name Person", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renamingText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let id = renamingPersonId {
                    viewModel.renamePerson(id: id, newName: renamingText)
                }
            }
        } message: {
            Text("Add a name for this person to easily search and organize photos.")
        }
    }
    
    // MARK: - Section 1: Cleanup Assistant Tray
    
    private var cleanupAssistantSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clean Up Recommendations")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            
            NavigationLink {
                PeopleCleanupReviewView(
                    cleanupType: .blinks,
                    items: viewModel.blinks
                )
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "eye.slash.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Review Blinks & Closed Eyes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(viewModel.blinks.count) photo\(viewModel.blinks.count == 1 ? "" : "s") with closed eyes detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Section 2: Favorites (Hero Cards)
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Favorites")
                    .font(.headline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: favoritesColumns, spacing: 12) {
                ForEach(favoriteClusters) { person in
                    NavigationLink {
                        PersonDetailView(personId: person.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            FaceAvatarView(
                                asset: person.avatarAsset,
                                faceBoundingBox: person.avatarFaceBoundingBox,
                                size: 140,
                                isHeroCard: true,
                                cornerRadius: 16
                            )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(person.isNamed ? person.displayName : "Add Name")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(person.isNamed ? Color.primary : Color.blue)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "heart.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                                
                                Text("\(person.count) photo\(person.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.toggleFavorite(id: person.id)
                        } label: {
                            Label("Unfavorite", systemImage: "heart.slash")
                        }
                        
                        Button {
                            renamingPersonId = person.id
                            renamingText = person.name ?? ""
                            showingRenameAlert = true
                        } label: {
                            Label("Edit Name", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            viewModel.removePerson(id: person.id)
                        } label: {
                            Label("Remove from People", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Section 3: People Directory Grid
    
    private var peopleDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("People")
                    .font(.headline.weight(.semibold))
                
                Text("\(otherClusters.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: directoryColumns, spacing: 18) {
                ForEach(otherClusters) { person in
                    NavigationLink {
                        PersonDetailView(personId: person.id)
                    } label: {
                        VStack(spacing: 8) {
                            FaceAvatarView(
                                asset: person.avatarAsset,
                                faceBoundingBox: person.avatarFaceBoundingBox,
                                size: 92
                            )
                            
                            VStack(spacing: 3) {
                                if person.isNamed {
                                    Text(person.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 96)
                                } else {
                                    Button {
                                        renamingPersonId = person.id
                                        renamingText = ""
                                        showingRenameAlert = true
                                    } label: {
                                        Text("Add Name")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.12), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Text("\(person.count) photo\(person.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.toggleFavorite(id: person.id)
                        } label: {
                            Label("Favorite", systemImage: "heart")
                        }
                        
                        Button {
                            renamingPersonId = person.id
                            renamingText = person.name ?? ""
                            showingRenameAlert = true
                        } label: {
                            Label("Edit Name", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            viewModel.removePerson(id: person.id)
                        } label: {
                            Label("Remove from People", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                }
            }
        }
    }
}
