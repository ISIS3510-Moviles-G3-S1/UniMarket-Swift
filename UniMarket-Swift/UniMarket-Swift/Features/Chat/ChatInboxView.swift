import SwiftUI
import Kingfisher

struct ChatInboxView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        Group {
            if chatStore.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
            } else if chatStore.conversations.isEmpty {
                emptyState
            } else {
                inboxList
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Inbox")
        .onAppear {
            chatStore.startObservingConversations()
        }
        .onDisappear {
            chatStore.stopObservingConversations()
        }
    }

    private var inboxList: some View {
        List {
            ForEach(chatStore.conversations) { conversation in
                NavigationLink {
                    ChatThreadView(conversationID: conversation.id)
                } label: {
                    HStack(spacing: 12) {
                        // Other user's avatar
                        Group {
                            if let avatarURL = conversation.otherParticipantAvatar,
                               let url = URL(string: avatarURL) {
                                KFImage(url)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.otherParticipantName)
                                .font(.poppinsSemiBold(14))
                                .foregroundStyle(AppTheme.primaryText)

                            if let listing = conversation.listingSnapshot {
                                Text(listing.title)
                                    .font(.poppinsRegular(11))
                                    .foregroundStyle(AppTheme.accent)
                                    .lineLimit(1)
                            }

                            Text(conversation.lastMessageText)
                                .font(.poppinsRegular(12))
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            if let date = conversation.lastMessageAt {
                                Text(date.conversationTimestamp)
                                    .font(.poppinsRegular(11))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }

                            if conversation.unreadCount > 0 {
                                Text("\(conversation.unreadCount)")
                                    .font(.poppinsSemiBold(12))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.accent)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(AppTheme.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.secondaryText)
            Text("No messages yet")
                .font(.poppinsSemiBold(16))
                .foregroundStyle(AppTheme.primaryText)
            Text("Tap Message on a product to start chatting.")
                .font(.poppinsRegular(13))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Date formatting helper

private extension Date {
    var conversationTimestamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: self)
        } else if cal.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }
}
