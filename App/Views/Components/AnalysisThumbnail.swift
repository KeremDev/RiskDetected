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
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                if isTextAnalysis {
                    RDTextAnalysisArtwork(cornerRadius: cornerRadius)
                } else {
                    RDPlaceholderPhoto(cornerRadius: cornerRadius)
                }
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

struct RDTextAnalysisArtwork: View {
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.rdGreenSoft,
                            Color.rdWhite,
                            Color.rdFog,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 7) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 36, height: 36)
                    .background(Color.rdWhite.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .shadow(color: Color.rdGreen.opacity(0.18), radius: 10, x: 0, y: 5)

                Text("METİN")
                    .rdMono(size: 9, weight: .bold)
                    .foregroundStyle(Color.rdSlate)
            }
            .padding(8)

            VStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.rdGreen.opacity(index == 0 ? 0.18 : 0.10))
                        .frame(width: 48 - CGFloat(index * 7), height: 3)
                }
            }
            .offset(x: 10, y: 34)
            .opacity(0.9)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.rdGreen.opacity(0.20), lineWidth: 1)
        )
        .accessibilityLabel("Metin analizi")
    }
}
