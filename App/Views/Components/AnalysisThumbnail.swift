import SwiftUI
import UIKit

struct AnalysisThumbnail: View {
    let path: String?
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RDPlaceholderPhoto(cornerRadius: cornerRadius)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        guard let path, loadedPath != path else { return }
        loadedPath = path
        image = nil
        do {
            let data = try await AnalysisService.shared.photoData(path: path)
            if let downloaded = UIImage(data: data) {
                image = downloaded
            }
        } catch {
            image = nil
        }
    }
}
