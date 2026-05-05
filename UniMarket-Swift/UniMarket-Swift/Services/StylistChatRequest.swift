import Foundation
import UIKit

struct StylistChatRequest {
    let prompt: String
    let catalog: [Product]
    let referenceImage: UIImage?
}

struct StylistChatResponse {
    let message: String
    let suggestedProducts: [Product]
}
