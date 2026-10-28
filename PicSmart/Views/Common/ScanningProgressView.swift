//
//  ScanningProgressView.swift
//  PicSmart
//

import SwiftUI

struct ScanningProgressView: View {
    let category: GalleryCategory
    let progress: AnalysisProgress?
    let statusMessage: String?
    var onCancel: (() -> Void)? = nil
    
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Animated Icon with Pulsing Halo
            ZStack {
                Circle()
                    .fill(category.themeColor.opacity(isPulsing ? 0.22 : 0.08))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isPulsing ? 1.08 : 0.95)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                
                Circle()
                    .fill(category.themeColor.opacity(0.15))
                    .frame(width: 88, height: 88)
                
                Image(systemName: category.iconName)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(category.themeColor)
            }
            .onAppear {
                isPulsing = true
            }
            
            // Titles & Stage Description
            VStack(spacing: 8) {
                Text("Analyzing \(category.title)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                
                if let message = statusMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .frame(minHeight: 44)
                }
            }
            
            // Progress Bar & Percentage
            VStack(spacing: 10) {
                if let prog = progress, prog.total > 0 {
                    ProgressView(value: prog.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(category.themeColor)
                        .padding(.horizontal, 48)
                    
                    HStack {
                        Text("\(Int(prog.fractionCompleted * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(category.themeColor)
                        
                        Spacer()
                        
                        Text("\(prog.completed) of \(prog.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 48)
                } else {
                    ProgressView()
                        .tint(category.themeColor)
                        .scaleEffect(1.1)
                        .padding(.vertical, 8)
                }
            }
            
            Spacer()
            
            // On-device privacy note
            Text("PicSmart analyzes media securely on-device")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
