//
//  OnboardingView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @Environment(AppModel.self) private var appModel
    @Environment(PhotoLibraryService.self) private var photoService
    
    @State private var currentStep = 0
    @State private var isShowingPermissionPrompt = false
    
    var onFinished: (() -> Void)?
    
    private let slides = [
        OnboardingSlide(
            icon: "square.stack.3d.down.right.fill",
            iconColor: Color.blue,
            title: "Reclaim Gigabytes",
            description: "Automatically surface exact duplicates, similar burst photos, and heavy video files eating up your device storage.",
            badge: "Intelligent Deduplication"
        ),
        OnboardingSlide(
            icon: "camera.metering.matrix",
            iconColor: Color.orange,
            title: "Find Blurry Shots",
            description: "Advanced on-device neural edge analysis tags accidental out-of-focus photos while keeping portrait bokeh and sunsets safe.",
            badge: "Neural Vision Analysis"
        ),
        OnboardingSlide(
            icon: "person.2.circle.fill",
            iconColor: Color.purple,
            title: "Private Face Directory",
            description: "Biometrically groups family and friends with closed-eye blink detection — 100% on-device with zero cloud uploads.",
            badge: "100% Offline & Private"
        )
    ]
    
    var body: some View {
        ZStack {
            if isShowingPermissionPrompt {
                PermissionPrePromptView { status in
                    hasCompletedOnboarding = true
                    if status == .authorized || status == .limited {
                        appModel.onPhotoAccessGranted()
                    }
                    onFinished?()
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            } else {
                carouselView
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.35), value: isShowingPermissionPrompt)
    }
    
    private var carouselView: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        withAnimation(.snappy(duration: 0.35)) {
                            isShowingPermissionPrompt = true
                        }
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
                            withAnimation(.snappy(duration: 0.3)) {
                                currentStep += 1
                            }
                        } else {
                            withAnimation(.snappy(duration: 0.35)) {
                                isShowingPermissionPrompt = true
                            }
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
                    
                    Text("PicSmart processes everything offline. Your photos never leave your device.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 24)
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
}

private struct OnboardingSlide {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let badge: String
}
