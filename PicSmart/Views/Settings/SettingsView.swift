//
//  SettingsView.swift
//  PicSmart
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    
    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                let index = AppSettings.presetsMB.firstIndex(of: settings.largeVideoThresholdMB) ?? 2
                return Double(index)
            },
            set: { newIndex in
                let idx = Int(newIndex.rounded())
                if idx >= 0 && idx < AppSettings.presetsMB.count {
                    settings.largeVideoThresholdMB = AppSettings.presetsMB[idx]
                }
            }
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Large Video Threshold", systemImage: "arrow.down.circle.fill")
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(AppSettings.formatMB(settings.largeVideoThresholdMB))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.tint)
                                .contentTransition(.numericText())
                        }
                        
                        VStack(spacing: 6) {
                            Slider(
                                value: sliderBinding,
                                in: 0...Double(AppSettings.presetsMB.count - 1),
                                step: 1
                            )
                            .tint(.blue)
                            .sensoryFeedback(.selection, trigger: settings.largeVideoThresholdMB)
                            
                            HStack {
                                Text(AppSettings.formatMB(AppSettings.presetsMB.first ?? 50))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(AppSettings.formatMB(AppSettings.presetsMB.last ?? 1000))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Preset tap chips
                        HStack(spacing: 8) {
                            ForEach(AppSettings.presetsMB, id: \.self) { preset in
                                let isSelected = settings.largeVideoThresholdMB == preset
                                Button {
                                    settings.largeVideoThresholdMB = preset
                                } label: {
                                    Text(AppSettings.formatMB(preset))
                                        .font(.caption.weight(isSelected ? .bold : .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Video Size Filter")
                } footer: {
                    Text("Videos with file size exceeding \(AppSettings.formatMB(settings.largeVideoThresholdMB)) will be classified under Large Videos. Default is \(AppSettings.formatMB(AppSettings.defaultThresholdMB)).")
                }
                
                if settings.largeVideoThresholdMB != AppSettings.defaultThresholdMB {
                    Section {
                        Button(role: .destructive) {
                            settings.resetToDefault()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Reset to Default (200 MB)")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }
                }
                
                Section {
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
