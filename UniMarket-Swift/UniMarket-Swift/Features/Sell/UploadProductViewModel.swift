import SwiftUI
import PhotosUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

final class UploadProductViewModel: ObservableObject {
    private let analytics = AnalyticsService.shared
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var selectedImages: [Image] = []
    @Published var imagesData: [Data] = []

    @Published var title: String = ""
    @Published var price: String = ""
    @Published var condition: String = "Good"
    @Published var description: String = ""
    @Published var selectedTags: [String] = []
    @Published var tagSearchText: String = ""
    @Published var customTagInput: String = ""

    @Published var isPosting: Bool = false
    @Published var errorMessage: String? = nil

    func loadSelectedPhotos() async {
        errorMessage = nil

        await MainActor.run {
            selectedImages = []
            imagesData = []
        }

        for item in selectedItems {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: data) {
                        let swiftUIImage = Image(uiImage: uiImage)
                        await MainActor.run {
                            imagesData.append(data)
                            selectedImages.append(swiftUIImage)
                        }
                    } else {
                        await MainActor.run { errorMessage = "Could not read one of the images." }
                    }
                    #else
                    await MainActor.run { imagesData.append(data) }
                    #endif
                }
            } catch {
                await MainActor.run { errorMessage = "Error loading one of the photos." }
            }
        }
    }

    func addImageFromCamera(_ uiImage: UIImage) {
        guard selectedImages.count < 5 else {
            errorMessage = "Maximum 5 photos."
            return
        }
        if let data = uiImage.jpegData(compressionQuality: 0.85) {
            imagesData.append(data)
            selectedImages.append(Image(uiImage: uiImage))
        } else {
            errorMessage = "Could not process the photo."
        }
    }

    func removeImage(at index: Int) {
        if index < selectedImages.count { selectedImages.remove(at: index) }
        if index < imagesData.count { imagesData.remove(at: index) }
        if index < selectedItems.count { selectedItems.remove(at: index) }
    }

    var canPost: Bool {
        !imagesData.isEmpty &&
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(price) != nil
    }

    func postProduct(using productStore: ProductStore) async -> Bool {
        guard canPost, let parsedPrice = Int(price) else { return false }
        analytics.track(.listingSubmitAttempt(
            photoCount: imagesData.count,
            hasDescription: !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            condition: condition,
            priceBucket: priceBucket(for: parsedPrice)
        ))

        await MainActor.run {
            isPosting = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in self.isPosting = false }
        }

        do {
            let input = CreateProductInput(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                price: parsedPrice,
                conditionTag: condition,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                imagesData: imagesData,
                tags: selectedTags
            )

            let product = try await productStore.createProduct(input: input)
            await ListingReminderService.shared.recordListing(for: product.sellerId, at: product.createdAt)
            await MainActor.run { resetForm() }
            return true
        } catch {
            analytics.track(.listingSubmitFailed(reason: error.localizedDescription))
            await MainActor.run { errorMessage = error.localizedDescription }
            return false
        }
    }

    @MainActor
    private func resetForm() {
        selectedItems = []
        selectedImages = []
        imagesData = []
        title = ""
        price = ""
        condition = "Good"
        description = ""
        selectedTags = []
        tagSearchText = ""
        customTagInput = ""
        errorMessage = nil
    }

    var normalizedCustomTag: String {
        normalizeTag(customTagInput)
    }

    func toggleTag(_ tag: String) {
        let normalized = normalizeTag(tag)
        guard !normalized.isEmpty else { return }

        if let index = selectedTags.firstIndex(of: normalized) {
            selectedTags.remove(at: index)
        } else if selectedTags.count < 8 {
            selectedTags.append(normalized)
        } else {
            errorMessage = "Maximum 8 tags."
        }
    }

    func addCustomTag() {
        let normalized = normalizedCustomTag
        guard !normalized.isEmpty else { return }

        if selectedTags.contains(normalized) {
            customTagInput = ""
            return
        }

        guard selectedTags.count < 8 else {
            errorMessage = "Maximum 8 tags."
            return
        }

        selectedTags.append(normalized)
        customTagInput = ""
        errorMessage = nil
    }

    func filteredAvailableTags(from tags: [String]) -> [String] {
        let query = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return tags
            .map(normalizeTag)
            .filter { !selectedTags.contains($0) }
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .sorted()
    }

    private func normalizeTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func priceBucket(for price: Int) -> String {
        switch price {
        case ..<25000:
            return "under_25k"
        case 25000..<50000:
            return "25k_50k"
        case 50000..<100000:
            return "50k_100k"
        default:
            return "100k_plus"
        }
    }
}

// MARK: - Fix onChange iOS 17

private struct ItemsOnChangeFix: ViewModifier {
    let items: [PhotosPickerItem]
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: items) { _, _ in action() }
        } else {
            content.onChange(of: items) { _ in action() }
        }
    }
}
