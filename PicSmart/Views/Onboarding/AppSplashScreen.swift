//
//  AppSplashScreen.swift
//  PicSmart
//

import SwiftUI

struct AppSplashScreen: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color(red: 0.1, green: 0.6, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.blue.opacity(0.32), radius: 18, x: 0, y: 8)
                    
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isAnimating ? 1.0 : 0.82)
                .opacity(isAnimating ? 1.0 : 0.0)
                
                VStack(spacing: 4) {
                    Text("PicSmart")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Intelligent Gallery Optimization")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(isAnimating ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                isAnimating = true
            }
        }
    }
}
