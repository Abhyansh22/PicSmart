//
//  PermissionDeniedView.swift
//  PicSmart
//

import SwiftUI
import UIKit

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 96, height: 96)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.red)
                }
                
                VStack(spacing: 10) {
                    Text("Photo Access Required")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("PicSmart is a local, offline gallery cleaner. Without access to your photos, it cannot analyze duplicates, blurry shots, or large videos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Instructions Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("How to Enable Access")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    instructionStep(number: "1", text: "Tap \"Open Settings\" below")
                    instructionStep(number: "2", text: "Select \"Photos\" in the list")
                    instructionStep(number: "3", text: "Choose \"Full Access\" (or \"Limited Access\")")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Bottom Action
            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                        Text("Open Settings")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                }
                
                Text("Once enabled, return to PicSmart to begin scanning.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
    
    private func instructionStep(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 26, height: 26)
                
                Text(number)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
