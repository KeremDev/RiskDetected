import SwiftUI
import UIKit
import OSLog

struct AnalysisThumbnail: View {
    let path: String?
    var isTextAnalysis: Bool = false
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?
    @State private var loadedPath: String?
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "AnalysisThumbnail")

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    RDPlaceholderPhoto(cornerRadius: cornerRadius)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        guard let path, loadedPath != path else { return }
        loadedPath = path
        image = nil
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        do {
            let data = try await AnalysisService.shared.photoData(
                path: path,
                requestID: requestID,
                supportID: supportID
            )
            if let downloaded = UIImage(data: data) {
                image = downloaded
            }
        } catch {
            Self.logger.error("Thumbnail photo load failed support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) path=\(path, privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)")
            image = nil
        }
    }
}
