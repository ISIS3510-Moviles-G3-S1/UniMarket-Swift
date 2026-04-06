import SwiftUI
import Kingfisher
import PhotosUI

struct ChatThreadView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: String

    @State private var draftMessage: String = ""
    @State private var isSending = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var errorMessage: String? = nil
    @State private var replyingTo: ChatMessage.ReplySnapshot? = nil

    private var messages: [ChatMessage] {
        chatStore.messagesByConversation[conversationID] ?? []
    }

    private var conversation: ChatConversation? {
        chatStore.conversations.first(where: { $0.id == conversationID })
    }

    var body: some View {
        VStack(spacing: 0) {
            // listing context banner
            if let listing = conversation?.listingSnapshot {
                listingBanner(listing)
            }

            // messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, onReply: {
                                replyingTo = ChatMessage.ReplySnapshot(
                                    messageId: message.id,
                                    senderId: message.senderId,
                                    textPreview: message.text.isEmpty ? "📷 Image" : String(message.text.prefix(60))
                                )
                            })
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // error banner
            if let error = errorMessage {
                Text(error)
                    .font(.poppinsRegular(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
            }

            // reply preview
            if let reply = replyingTo {
                replyPreviewBar(reply)
            }

            // input bar
            inputBar
        }
        .background(AppTheme.background)
        .navigationTitle(conversation?.otherParticipantName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            chatStore.startObservingMessages(for: conversationID)
            chatStore.markConversationAsRead(conversationID)
        }
        .onDisappear {
            chatStore.stopObservingMessages(for: conversationID)
        }
        .onChange(of: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            Task { await sendImage(from: item) }
        }
    }

    // MARK: - Listing banner

    private func listingBanner(_ listing: ChatMessage.ListingSnapshot) -> some View {
        HStack(spacing: 10) {
            KFImage(URL(string: listing.imagePath))
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(listing.title)
                    .font(.poppinsSemiBold(12))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text("$\(listing.price)")
                    .font(.poppinsRegular(11))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.6))
    }

    // MARK: - Reply preview bar

    private func replyPreviewBar(_ reply: ChatMessage.ReplySnapshot) -> some View {
        HStack {
            Rectangle()
                .frame(width: 3)
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to message")
                    .font(.poppinsSemiBold(11))
                    .foregroundStyle(AppTheme.accent)
                Text(reply.textPreview)
                    .font(.poppinsRegular(11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                replyingTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            TextField("Write a message...", text: $draftMessage)
                .font(.poppinsRegular(14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Task { await sendDraft() }
            } label: {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 38)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 44, height: 38)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .disabled(isSending || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }

    // MARK: - Actions

    private func sendDraft() async {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        errorMessage = nil
        let reply = replyingTo
        draftMessage = ""
        replyingTo = nil

        do {
            try await chatStore.sendMessage(text: trimmed, in: conversationID, replyTo: reply)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    private func sendImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        isSending = true
        errorMessage = nil

        do {
            try await chatStore.sendImageMessage(image: image, in: conversationID)
        } catch {
            errorMessage = error.localizedDescription
        }

        selectedPhotoItem = nil
        isSending = false
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onReply: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isFromCurrentUser { Spacer(minLength: 40) }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // reply context
                if let reply = message.replyTo {
                    HStack {
                        Rectangle()
                            .frame(width: 2)
                            .foregroundStyle(message.isFromCurrentUser ? .white.opacity(0.6) : AppTheme.accent)

                        Text(reply.textPreview)
                            .font(.poppinsRegular(11))
                            .foregroundStyle(message.isFromCurrentUser ? .white.opacity(0.7) : AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        message.isFromCurrentUser
                            ? AppTheme.accent.opacity(0.6)
                            : Color.gray.opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // image content
                if !message.imageURLs.isEmpty {
                    ForEach(message.imageURLs, id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 220, maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                // text content
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.poppinsRegular(14))
                        .foregroundStyle(message.isFromCurrentUser ? .white : AppTheme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(message.isFromCurrentUser ? AppTheme.accent : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // timestamp + read receipt
                HStack(spacing: 4) {
                    Text(message.sentAt.messageTimestamp)
                        .font(.poppinsRegular(10))
                        .foregroundStyle(AppTheme.secondaryText)

                    if message.isFromCurrentUser {
                        Image(systemName: message.readAt != nil ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(message.readAt != nil ? AppTheme.accent : AppTheme.secondaryText)
                    }
                }
            }
            .contextMenu {
                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }

            if !message.isFromCurrentUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Date formatting helper

private extension Date {
    var messageTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(self) ? "h:mm a" : "MMM d, h:mm a"
        return f.string(from: self)
    }
}
