//
//  RootView.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI
import FirebaseAuth

private enum AuthRoute: Hashable {
    case register
}

struct RootView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject private var productStore: ProductStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var authPath: [AuthRoute] = []

    var body: some View {
        GeometryReader { proxy in
            Group {
                if session.isLoading {
                    LoadingView()
                } else if session.isLoggedIn {
                    MainTabView()
                } else {
                    NavigationStack(path: $authPath) {
                        LoginView(onRegisterTap: { authPath.append(.register) })
                            .navigationDestination(for: AuthRoute.self) { route in
                                switch route {
                                case .register:
                                    RegisterView()
                                }
                            }
                    }
                }
            }
            .onChange(of: session.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    authPath = []
                    // Start observing chat conversations when user logs in
                    chatStore.startObservingConversations()
                } else {
                    // Stop observing when user logs out
                    chatStore.stopObservingConversations()
                }
            }
            .onAppear {
                syncListingReminder(for: session.user?.uid)
                // Start observing conversations if already logged in
                if session.isLoggedIn {
                    chatStore.startObservingConversations()
                }
            }
            .onChange(of: session.user?.uid) { previousUserID, currentUserID in
                if let previousUserID, previousUserID != currentUserID {
                    Task {
                        await ListingReminderService.shared.clearReminder(for: previousUserID)
                    }
                }

                syncListingReminder(for: currentUserID)
            }
            .onChange(of: productStore.products) { _, _ in
                syncListingReminder(for: session.user?.uid)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func syncListingReminder(for userID: String?) {
        guard let userID else { return }

        let lastListingDate = productStore
            .myListings(for: userID)
            .map(\.createdAt)
            .max()

        Task {
            await ListingReminderService.shared.syncReminder(for: userID, lastListingDate: lastListingDate)
        }
    }
}
