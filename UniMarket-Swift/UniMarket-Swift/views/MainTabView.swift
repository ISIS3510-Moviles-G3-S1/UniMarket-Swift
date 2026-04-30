//
//  MainTabView.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

enum MainTab: Hashable {
    case home
    case search
    case activity
    case profile
}

struct MainTabView: View {
    private let analytics = AnalyticsService.shared
    @State private var selectedTab: MainTab = .home
    @State private var showUpload = false
    @State private var tabBarHidden = false
    @StateObject private var profileViewModel = ProfileViewModel()
    @ObservedObject private var pendingSyncer = PendingListingsSyncer.shared

    private let barHeight: CGFloat = 64
    private let sidePadding: CGFloat = 16
    private let bottomSpacing: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                tabContent
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if pendingSyncer.pendingCount > 0 {
                    pendingListingsBanner
                        .frame(width: proxy.size.width - (sidePadding * 2))
                        .position(x: proxy.size.width / 2, y: 44)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !tabBarHidden {
                    CustomTabBar(
                        selectedTab: $selectedTab,
                        onTapUpload: { showUpload = true }
                    )
                    .frame(width: proxy.size.width - (sidePadding * 2), height: barHeight)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height - (barHeight / 2) - bottomSpacing
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showUpload) {
            NavigationStack {
                UploadProductView()
            }
        }
        .onAppear {
            analytics.track(.tabSelected(selectedTab.analyticsName))
        }
        .onChange(of: selectedTab) { _, newTab in
            analytics.track(.tabSelected(newTab.analyticsName))
            guard newTab == .profile else { return }
            Task {
                await profileViewModel.onProfileTabSelected()
            }
        }
        .environment(\.hideTabBar, $tabBarHidden)
    }

    private var pendingListingsBanner: some View {
        let count = pendingSyncer.pendingCount
        let label: String = {
            if pendingSyncer.isDraining {
                return "Publishing \(count) queued listing\(count == 1 ? "" : "s")…"
            }
            return "\(count) listing\(count == 1 ? "" : "s") waiting for connectivity"
        }()
        return HStack(spacing: 10) {
            if pendingSyncer.isDraining {
                ProgressView()
                    .tint(AppTheme.primaryText)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(AppTheme.primaryText)
            }
            Text(label)
                .font(.poppinsRegular(13))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.accentAlt.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var tabContent: some View {
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
        case .activity:
            NavigationStack { ActivityView() }
        case .profile:
            NavigationStack { ProfileView(viewModel: profileViewModel) }
        }
    }
}

private extension MainTab {
    var analyticsName: String {
        switch self {
        case .home: return "home"
        case .search: return "search"
        case .activity: return "activity"
        case .profile: return "profile"
        }
    }
}
