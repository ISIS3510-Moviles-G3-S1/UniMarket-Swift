import SwiftUI
import Kingfisher

struct CachedRemoteImageView: View {
    enum PlaceholderStyle {
        case image
        case profile

        var systemName: String {
            switch self {
            case .image:
                return "photo"
            case .profile:
                return "person.circle.fill"
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
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return nil }
        return URL(string: trimmedURL)
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
                KFImage(resolvedURL)
                    .placeholder {
                        placeholderView
                    }
                    .onFailure { _ in }
                    .cancelOnDisappear(true)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
            }
        }
    }

    static func invalidateCache(for key: String) {
        ImageCache.default.removeImage(forKey: key)
    }
}

struct CachedRemoteImageViewPreview: PreviewProvider {
    static var previews: some View {
        CachedRemoteImageView(urlString: "")
            .frame(width: 56, height: 56)
    }
}
