import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AIStylistMessage: Identifiable {
    enum Role {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
    let suggestedProducts: [Product]
    let attachedImage: UIImage?
}

@MainActor
final class AIStylistChatViewModel: ObservableObject {
    @Published private(set) var messages: [AIStylistMessage] = [
        AIStylistMessage(
            role: .assistant,
            text: "Ask for a full outfit, a vibe, or a budget. Example: \"Give me a casual campus outfit under $60.\"",
            suggestedProducts: [],
            attachedImage: nil
        )
    ]
    @Published var isSending = false
    @Published var errorMessage: String?

    private let creator: StylistChatbotCreator

    init(creator: StylistChatbotCreator? = nil) {
        self.creator = creator ?? StylistChatbotFactory.makeCreator()
    }

    func send(prompt: String, catalog: [Product], referenceImage: UIImage?) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || referenceImage != nil else { return }

        let userMessage = trimmed.isEmpty ? "Help me build an outfit that complements this photo." : trimmed

        messages.append(
            AIStylistMessage(
                role: .user,
                text: userMessage,
                suggestedProducts: [],
                attachedImage: referenceImage
            )
        )
        isSending = true
        errorMessage = nil

        let request = StylistChatRequest(prompt: userMessage, catalog: catalog, referenceImage: referenceImage)

        do {
            let response = try await creator.makeChatbot().respond(to: request)
            messages.append(
                AIStylistMessage(
                    role: .assistant,
                    text: response.message,
                    suggestedProducts: response.suggestedProducts,
                    attachedImage: nil
                )
            )
        } catch {
            let fallback = MockStylistChatbotCreator().makeChatbot()
            if let response = try? await fallback.respond(to: request) {
                messages.append(
                    AIStylistMessage(
                        role: .assistant,
                        text: response.message,
                        suggestedProducts: response.suggestedProducts,
                        attachedImage: nil
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
    @State private var selectedReferenceImage: UIImage?
    @State private var showPhotoLibrary = false

    private let promptSuggestions = [
        "Give me a casual campus outfit",
        "Build a streetwear outfit under $80",
        "I need a neutral outfit for class",
        "Build an outfit around this piece"
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
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(source: .photoLibrary) { image in
                selectedReferenceImage = image
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

                VStack(alignment: .leading, spacing: 8) {
                    if let attachedImage = message.attachedImage {
                        Image(uiImage: attachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Text(message.text)
                        .font(.poppinsRegular(14))
                        .foregroundStyle(message.role == .user ? .white : AppTheme.primaryText)
                }
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
        VStack(spacing: 10) {
            if let selectedReferenceImage {
                HStack(spacing: 12) {
                    Image(uiImage: selectedReferenceImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Photo ready for outfit matching")
                        .font(.poppinsRegular(13))
                        .foregroundStyle(AppTheme.secondaryText)

                    Spacer()

                    Button {
                        self.selectedReferenceImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    showPhotoLibrary = true
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                TextField("Ask for an outfit...", text: $draftMessage)
                    .font(.poppinsRegular(14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    let prompt = draftMessage
                    let referenceImage = selectedReferenceImage
                    draftMessage = ""
                    selectedReferenceImage = nil
                    Task {
                        await viewModel.send(prompt: prompt, catalog: productStore.activeProducts, referenceImage: referenceImage)
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
                .disabled(
                    viewModel.isSending ||
                    (
                        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        selectedReferenceImage == nil
                    )
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }
}
