import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AIStylistHistoryViewModel: ObservableObject {
    @Published private(set) var conversations: [AIStylistConversationSummary] = []
    @Published var searchText = ""
    @Published var isLoading = false

    private let store = AIStylistConversationFileStore()

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try store.listConversations(for: storageKey)
        } catch {
            conversations = []
        }
    }

    func refreshSearch() async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try store.searchConversations(matching: searchText, for: storageKey)
        } catch {
            conversations = []
        }
    }

    func deleteConversation(id: String) async {
        do {
            try store.deleteConversation(id: id, for: storageKey)
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversations.removeAll { $0.id == id }
            } else {
                await refreshSearch()
            }
        } catch { }
    }

    private var storageKey: String {
        Auth.auth().currentUser?.uid ?? "guest"
    }
}
