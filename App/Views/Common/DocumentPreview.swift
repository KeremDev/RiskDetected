import QuickLook
import SwiftUI

struct DocumentPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var shareItem: ShareItem?
    @State private var closeDragOffset: CGFloat = 0

    let url: URL

    var body: some View {
        ZStack(alignment: .top) {
            DocumentPreviewController(url: url)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                closeDragHandle
                headerControls
            }
            .padding(.top, 8)
            .offset(y: closeDragOffset)
        }
        .interactiveDismissDisabled(true)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .preferredColorScheme(colorScheme)
        }
    }

    private var closeDragHandle: some View {
        Capsule()
            .fill(Color.rdSlate.opacity(0.28))
            .frame(width: 48, height: 5)
            .padding(.horizontal, 80)
            .padding(.vertical, 10)
            .background(Color.rdWhite.opacity(0.001))
            .contentShape(Rectangle())
            .gesture(closeDragGesture)
            .accessibilityLabel(RDLocalization.string("localizable.document.preview.onizleme.kapatma.tutamaci.9f7dd420", table: .localizable, fallback: "Önizleme kapatma tutamacı"))
            .accessibilityHint(RDLocalization.string("localizable.document.preview.onizlemeyi.kapatmak.icin.asagi.surukle.bfaf70c5", table: .localizable, fallback: "Önizlemeyi kapatmak için aşağı sürükle."))
    }

    private var headerControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 42, height: 42)
                    .background(Color.rdWhite.opacity(0.96))
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.16), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(RDPressableButtonStyle())
            .accessibilityLabel(RDLocalization.string("localizable.document.preview.onizlemeyi.kapat.206e4722", table: .localizable, fallback: "Önizlemeyi kapat"))
            .accessibilityIdentifier("document_preview.close")

            Spacer()

            Button {
                shareItem = ShareItem(url: url)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 42, height: 42)
                    .background(Color.rdWhite.opacity(0.96))
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.16), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(RDPressableButtonStyle())
            .accessibilityLabel(RDLocalization.string("localizable.document.preview.dosyayi.indir.veya.paylas.e6aa8811", table: .localizable, fallback: "Dosyayı indir veya paylaş"))
        }
        .padding(.horizontal, 18)
    }

    private var closeDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let vertical = value.translation.height
                guard vertical > 0, abs(vertical) > abs(value.translation.width) else { return }
                closeDragOffset = min(vertical * 0.28, 26)
            }
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let shouldDismiss = vertical > 90 && vertical > horizontal * 1.4
                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        closeDragOffset = 0
                    }
                }
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
