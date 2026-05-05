import SwiftUI
import UIKit

struct CachedRemoteImageView: View {
    enum PlaceholderStyle {
        case image
        case profile

        var systemName: String {
            switch self {
            case .image:   return "photo"
            case .profile: return "person.circle.fill"
            }
        }
    }

    let urlString: String
    let cacheKey: String?
    let placeholderStyle: PlaceholderStyle

    init(
        urlString: String,
        cacheKey: String? = nil,
        placeholderStyle: PlaceholderStyle = .image
    ) {
        self.urlString = urlString
        self.cacheKey = cacheKey
        self.placeholderStyle = placeholderStyle
    }

    private var resolvedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var placeholderView: some View {
        Image(systemName: placeholderStyle.systemName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.gray)
    }

    var body: some View {
        Group {
            if let resolvedURL {
                ProductImageView(url: resolvedURL, placeholder: placeholderView)
            } else {
                placeholderView
            }
        }
    }

    static func invalidateCache(for key: String) {
        guard let url = URL(string: key) else { return }
        ProductImageCache.shared.remove(for: url)
    }
}

// MARK: - Internal loader view

private struct ProductImageView<Placeholder: View>: View {
    let url: URL
    let placeholder: Placeholder

    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            switch loader.state {
            case .idle, .loading:
                placeholder
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case .failed:
                placeholder
            }
        }
        .onAppear  { loader.load(url: url) }
        .onDisappear { loader.cancel() }
    }
}

// MARK: - Image loader

// Checks ProductImageCache first; downloads via URLSession on a cache miss.
// Cancelling an in-flight download resets state so the next onAppear restarts cleanly.
// A completed download is kept in state even after cancellation so re-appearing
// views render instantly without a network round-trip.
@MainActor
private final class ImageLoader: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case loaded(UIImage)
        case failed
    }

    @Published private(set) var state: LoadState = .idle

    private var currentURL: URL?
    private var task: Task<Void, Never>?

    func load(url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        task?.cancel()

        if let cached = ProductImageCache.shared.image(for: url) {
            state = .loaded(cached)
            return
        }

        state = .loading
        task = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                guard let image = UIImage(data: data) else {
                    state = .failed
                    return
                }
                ProductImageCache.shared.store(image, for: url)
                state = .loaded(image)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        // Only reset when still loading — a completed image stays in state so
        // re-appearing views don't flash the placeholder before the cache hit.
        if case .loading = state {
            state = .idle
            currentURL = nil
        }
    }
}

// MARK: - Preview

struct CachedRemoteImageViewPreview: PreviewProvider {
    static var previews: some View {
        CachedRemoteImageView(urlString: "")
            .frame(width: 56, height: 56)
    }
}
