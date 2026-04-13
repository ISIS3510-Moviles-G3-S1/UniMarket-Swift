import Combine
import SwiftUI

struct AIStylistMessage: Identifiable {
    enum Role {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
    let suggestedProducts: [Product]
}

@MainActor
final class AIStylistChatViewModel: ObservableObject {
    @Published private(set) var messages: [AIStylistMessage] = [
        AIStylistMessage(
            role: .assistant,
            text: "Ask for a full outfit, a vibe, or a budget. Example: \"Give me a casual campus outfit under $60.\"",
            suggestedProducts: []
        )
    ]
    @Published var isSending = false
    @Published var errorMessage: String?

    private let creator: StylistChatbotCreator

    init(creator: StylistChatbotCreator? = nil) {
        self.creator = creator ?? StylistChatbotFactory.makeCreator()
    }

    func send(prompt: String, catalog: [Product]) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AIStylistMessage(role: .user, text: trimmed, suggestedProducts: []))
        isSending = true
        errorMessage = nil

        let request = StylistChatRequest(prompt: trimmed, catalog: catalog)

        do {
            let response = try await creator.makeChatbot().respond(to: request)
            messages.append(
                AIStylistMessage(
                    role: .assistant,
                    text: response.message,
                    suggestedProducts: response.suggestedProducts
                )
            )
        } catch {
            let fallback = MockStylistChatbotCreator().makeChatbot()
            if let response = try? await fallback.respond(to: request) {
                messages.append(
                    AIStylistMessage(
                        role: .assistant,
                        text: response.message,
                        suggestedProducts: response.suggestedProducts
                    )
                )
            }
            errorMessage = "Live AI was unavailable, so the stylist used demo mode."
        }

        isSending = false
    }
}

struct AIStylistChatView: View {
    @EnvironmentObject private var productStore: ProductStore
    @Environment(\.hideTabBar) private var hideTabBar
    @StateObject private var viewModel = AIStylistChatViewModel()
    @State private var draftMessage = ""

    private let promptSuggestions = [
        "Give me a casual campus outfit",
        "Build a streetwear outfit under $80",
        "I need a neutral outfit for class"
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        promptStrip

                        ForEach(viewModel.messages) { message in
                            stylistBubble(message)
                                .id(message.id)
                        }

                        if viewModel.isSending {
                            ProgressView("Stylist is thinking...")
                                .font(.poppinsRegular(13))
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.poppinsRegular(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.9))
            }

            inputBar
        }
        .background(AppTheme.background)
        .navigationTitle("AI Stylist")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation {
                hideTabBar.wrappedValue = true
            }
        }
        .onDisappear {
            withAnimation {
                hideTabBar.wrappedValue = false
            }
        }
    }

    private var promptStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(promptSuggestions, id: \.self) { prompt in
                    Button(prompt) {
                        draftMessage = prompt
                    }
                    .font(.poppinsRegular(12))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.cardBackground)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func stylistBubble(_ message: AIStylistMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.role == .user {
                    Spacer(minLength: 40)
                }

                Text(message.text)
                    .font(.poppinsRegular(14))
                    .foregroundStyle(message.role == .user ? .white : AppTheme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? AppTheme.accent : AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if message.role == .assistant {
                    Spacer(minLength: 40)
                }
            }

            if message.role == .assistant && !message.suggestedProducts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested items")
                        .font(.poppinsSemiBold(12))
                        .foregroundStyle(AppTheme.secondaryText)

                    ForEach(message.suggestedProducts, id: \.id) { product in
                        NavigationLink {
                            ProductDetailView(product: product)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: product.primaryImageURL ?? "")) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.gray.opacity(0.15))
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.title)
                                        .font(.poppinsSemiBold(13))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .lineLimit(1)
                                    Text("$\(product.price)")
                                        .font(.poppinsRegular(12))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask for an outfit...", text: $draftMessage)
                .font(.poppinsRegular(14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                let prompt = draftMessage
                draftMessage = ""
                Task {
                    await viewModel.send(prompt: prompt, catalog: productStore.activeProducts)
                }
            } label: {
                if viewModel.isSending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 38)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 38)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .disabled(viewModel.isSending || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }
}
