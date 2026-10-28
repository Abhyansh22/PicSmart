//
//  PermissionPrePromptView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct PermissionPrePromptView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppModel.self) private var appModel
    var onCompleted: ((PHAuthorizationStatus) -> Void)?
    
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    // Header Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 96, height: 96)
                        
                        Image(systemName: "photo.badge.checkmark.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .padding(.top, 36)
                    
                    // Title & Description
                    VStack(spacing: 8) {
                        Text("Access Your Photos")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("PicSmart evaluates your gallery to find space-wasting duplicates, blurry photos, and large videos.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Value & Privacy Cards
                    VStack(spacing: 12) {
                        benefitRow(
                            icon: "lock.shield.fill",
                            iconColor: .green,
                            title: "100% On-Device Processing",
                            description: "Your photos never leave your device or upload to servers. All neural analysis runs on the Apple Neural Engine."
                        )
                        
                        benefitRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .orange,
                            title: "Safe 30-Day Recovery",
                            description: "Cleaned items are placed in Apple Photos 'Recently Deleted' for 30 days before permanent deletion."
                        )
                        
                        benefitRow(
                            icon: "checkmark.circle.fill",
                            iconColor: .blue,
                            title: "Zero Original Edits",
                            description: "PicSmart never modifies, re-encodes, or touches your original photo files."
                        )
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Bottom Action Bar
            VStack(spacing: 12) {
                Button {
                    guard !isRequesting else { return }
                    isRequesting = true
                    Task {
                        let status = await photoService.requestAuthorization()
                        isRequesting = false
                        onCompleted?(status)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Allow Photo Access")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                }
                .disabled(isRequesting)
                
                Text("You can change this permission at any time in iOS Settings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(uiColor: .systemBackground))
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
    
    private func benefitRow(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
