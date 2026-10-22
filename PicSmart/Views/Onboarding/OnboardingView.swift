//
//  OnboardingView.swift
//  PicSmart
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentStep = 0
    
    private let slides = [
        OnboardingSlide(
            icon: "sparkles",
            iconColor: Color.blue,
            title: "Smart Gallery Cleaner",
            description: "Automatically identify blurry photos, visual look-alikes, exact duplicate files, and heavy videos eating up your device storage.",
            badge: "100% On-Device Neural AI"
        ),
        OnboardingSlide(
            icon: "checkmark.seal.fill",
            iconColor: Color.orange,
            title: "Best-Shot & Keepers",
            description: "PicSmart algorithmically detects facial sharpness and Laplacian edge clarity to tag the best photo in every burst. Tap any item to swap keepers or compare side-by-side.",
            badge: "Intelligent Selection"
        ),
        OnboardingSlide(
            icon: "arrow.clockwise.circle.fill",
            iconColor: Color.green,
            title: "Pull to Refresh & Safe Trash",
            description: "Pull down anywhere to refresh your gallery. When you clean items, they are safely held in Apple Photos 'Recently Deleted' for 30 days before permanent removal.",
            badge: "Safe 30-Day Recovery"
        )
    ]
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Top skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                
                // Page Carousel
                TabView(selection: $currentStep) {
                    ForEach(0..<slides.count, id: \.self) { index in
                        slideView(slides[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                
                // Bottom Button
                VStack(spacing: 12) {
                    Button {
                        if currentStep < slides.count - 1 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentStep == slides.count - 1 ? "Get Started" : "Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    
                    Text("PicSmart processes everything on-device. Your photos never leave your device.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    private func slideView(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(slide.iconColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                
                Image(systemName: slide.icon)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(slide.iconColor)
            }
            .padding(.bottom, 8)
            
            Text(slide.badge)
                .font(.caption.weight(.bold))
                .foregroundStyle(slide.iconColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(slide.iconColor.opacity(0.12), in: Capsule())
            
            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                
                Text(slide.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

private struct OnboardingSlide {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let badge: String
}
