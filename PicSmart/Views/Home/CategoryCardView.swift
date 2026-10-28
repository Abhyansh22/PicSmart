//
//  CategoryCardView.swift
//  PicSmart
//

import SwiftUI

struct CategoryCardView: View {
    let category: GalleryCategory
    let status: CategoryStatus
    
    init(category: GalleryCategory, status: CategoryStatus) {
        self.category = category
        self.status = status
    }
    
    init(category: GalleryCategory, count: Int? = nil, isScanning: Bool = false) {
        self.category = category
        if isScanning {
            self.status = .analyzing(progress: 0, stage: "Scanning…", completed: count ?? 0, total: 0)
        } else if let count {
            self.status = .completed(count: count)
        } else {
            self.status = .notStarted
        }
    }
    
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
                
                switch status {
                case .analyzing(_, _, let completed, _):
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        if completed > 0 {
                            Text("\(completed)")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    
                case .completed(let count):
                    Text("\(count)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        
                case .paused(let completed, _):
                    if completed > 0 {
                        Text("\(completed)")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                    
                case .notStarted:
                    EmptyView()
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
                Text(bottomActionText)
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
    
    private var bottomActionText: String {
        switch status {
        case .analyzing:
            return "Scanning…"
        case .completed(let count):
            return "\(count) items"
        case .paused:
            return "Resume"
        case .notStarted:
            return "Open"
        }
    }
}
