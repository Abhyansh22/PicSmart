//
//  CategoryCardView.swift
//  PicSmart
//

import SwiftUI

struct CategoryCardView: View {
    let category: GalleryCategory
    var count: Int?
    var isScanning: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(category.themeColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: category.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(category.themeColor)
                }
                
                Spacer()
                
                if isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        if let count = count, count > 0 {
                            Text("\(count)")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                } else if let count = count {
                    Text("\(count)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 0)
            
            HStack(spacing: 4) {
                Text(isScanning ? "Scanning…" : (count != nil ? "\(count!) items" : "Open"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(category.themeColor)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(category.themeColor.opacity(0.8))
            }
        }
        .padding(14)
        .frame(minHeight: 140)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}
