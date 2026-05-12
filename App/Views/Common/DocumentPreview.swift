import QuickLook
import SwiftUI

struct DocumentPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var shareItem: ShareItem?

    let url: URL

    var body: some View {
        ZStack(alignment: .top) {
            DocumentPreviewController(url: url)
                .ignoresSafeArea()

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .frame(width: 42, height: 42)
                        .background(Color.rdWhite.opacity(0.96))
                        .clipShape(Circle())
                        .shadow(color: Color.rdOnyx.opacity(0.16), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(RDPressableButtonStyle())
                .accessibilityLabel("Önizlemeyi kapat")

                Spacer()

                Button {
                    shareItem = ShareItem(url: url)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .frame(width: 42, height: 42)
                        .background(Color.rdWhite.opacity(0.96))
                        .clipShape(Circle())
                        .shadow(color: Color.rdOnyx.opacity(0.16), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(RDPressableButtonStyle())
                .accessibilityLabel("Dosyayı indir veya paylaş")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .preferredColorScheme(colorScheme)
        }
    }
}

private struct DocumentPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
