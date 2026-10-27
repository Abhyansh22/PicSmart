//
//  SettingsView.swift
//  PicSmart
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var showingOnboardingTour = false
    
    #if DEBUG
    @State private var showingResetConfirmation = false
    @State private var isResetting = false
    #endif
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingOnboardingTour = true
                    } label: {
                        HStack {
                            Label("View Feature Tour & Tips", systemImage: "sparkles")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About PicSmart")
                }
                
                #if DEBUG
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Label("Reset to Fresh Install", systemImage: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(.red)
                            Spacer()
                            if isResetting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isResetting)
                } header: {
                    Text("Developer / Testing")
                } footer: {
                    Text("Wipes all SwiftData databases, resets delta checkpoints, and restarts onboarding as if the app was just installed.")
                }
                #endif
            }
            .sheet(isPresented: $showingOnboardingTour) {
                OnboardingView()
            }
            #if DEBUG
            .confirmationDialog("Reset App to Fresh Install?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    isResetting = true
                    Task {
                        await AppSettings.shared.resetToFreshInstall(appModel: appModel)
                        isResetting = false
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will purge all cached clusters, face embeddings, and settings. The app will immediately present onboarding and start a clean baseline scan.")
            }
            #endif
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
