//
//  MainTabView.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

enum MainTab: Hashable {
    case home, search, listings, profile
}

struct MainTabView: View {
    @State private var selectedTab: MainTab = .home
    @State private var showUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack {
                        HomeView(
                            onBrowseItems: { selectedTab = .search },
                            onStartSelling: { showUpload = true }
                        )
                    }
                case .search:
                    NavigationStack { SearchView() }
                case .listings:
                    NavigationStack { ListingsView() }
                case .profile:
                    NavigationStack { ProfileView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 90)
            }

            CustomTabBar(
                selectedTab: $selectedTab,
                onTapUpload: { showUpload = true }
            )
        }
        .sheet(isPresented: $showUpload) {
            NavigationStack { UploadProductView() }
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: MainTab
    let onTapUpload: () -> Void

    var body: some View {
        ZStack {
            // Fondo de la barra
            RoundedRectangle(cornerRadius: 18)
                .fill(.background)
                .shadow(radius: 10)
                .frame(height: 64)
                .padding(.horizontal, 16)

            // Botones laterales
            HStack {
                tabButton(.home, icon: "house")
                Spacer()
                tabButton(.search, icon: "magnifyingglass")
                Spacer()
                Color.clear.frame(width: 56)
                Spacer()
                tabButton(.listings, icon: "list.bullet")
                Spacer()
                tabButton(.profile, icon: "person")
            }
            .padding(.horizontal, 36)

            // Botón central flotante
            Button {
                onTapUpload()
            } label: {
                ZStack {
                    Circle()
                        .fill(.background)
                        .shadow(radius: 10)
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color.green.opacity(0.30))
                        .frame(width: 56, height: 56)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                }
            }
            .offset(y: -18)
        }
        .padding(.bottom, UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0)
    }

    private func tabButton(_ tab: MainTab, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}
