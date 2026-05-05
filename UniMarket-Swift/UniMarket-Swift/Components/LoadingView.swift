//
//  LoadingView.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

struct LoadingView: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulsing ? 1.06 : 1.0)
                    .opacity(pulsing ? 0.85 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulsing
                    )
            }
        }
        .onAppear {
            pulsing = true
        }
    }
}

#Preview {
    LoadingView()
}
