//
//  SettingsView.swift
//  PicSmart
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingOnboardingTour = false
    
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
            }
            .sheet(isPresented: $showingOnboardingTour) {
                OnboardingView()
            }
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
