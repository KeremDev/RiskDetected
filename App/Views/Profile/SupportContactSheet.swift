import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SupportContactSheet: View {
    let profile: UserProfile?
    let tier: SubscriptionTier
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var subject = ""
    @State private var message = ""
    @State private var attachment: SupportAttachmentDraft?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private enum Field {
        case subject
        case message
    }

    private var canSend: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 &&
        !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        heroCard
                        senderCard
                        formCard
                        attachmentCard

                        if let errorMessage {
                            noticeCard(errorMessage, icon: "exclamationmark.triangle.fill", color: .rdCriticalText, background: .rdCriticalBg)
                        }
                        if let successMessage {
                            noticeCard(successMessage, icon: "checkmark.seal.fill", color: .rdGreen, background: .rdGreenSoft)
                        }

                        sendButton
                            .id("sendButton")
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
                .background(Color.rdPaper)
                .onChange(of: focusedField) { field in
                    guard field != nil else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("sendButton", anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Destek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                        onClose()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImportedFile(result) }
        }
        .onChange(of: selectedPhotoItem) { item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "headphones")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text("RiskDetected destek")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Konu, mesaj ve gerekirse ekran görüntüsü ekleyerek bize ulaş.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var senderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Gönderen")
            supportInfoRow(icon: "person.fill", title: "Ad soyad", value: profile?.displayName ?? "Kayıtlı değil")
            supportInfoRow(icon: "envelope.fill", title: "E-posta", value: profile?.email ?? "Kayıtlı değil")
            supportInfoRow(icon: "phone.fill", title: "Telefon", value: profile?.phone ?? "Kayıtlı değil")
            supportInfoRow(icon: tier.badgeIcon, title: "Plan", value: tier.title)
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Talep")
            VStack(alignment: .leading, spacing: 7) {
                Text("Konu")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                TextField("Kısa bir konu yaz", text: $subject)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .subject)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .message }
                    .padding(14)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Mesaj")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                TextEditor(text: $message)
                    .focused($focusedField, equals: .message)
                    .frame(minHeight: 132)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Sorunu, isteğini veya gördüğün ekranı anlat...")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Color.rdSlate.opacity(0.72))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var attachmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Ek")
            if let attachment {
                HStack(spacing: 12) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdGreen)
                        .frame(width: 44, height: 44)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(1)
                        Text(attachment.formattedSize)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                    Spacer()
                    Button {
                        self.attachment = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .frame(width: 32, height: 32)
                            .background(Color.rdFog)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    attachmentButton(icon: "photo.on.rectangle.angled", title: "Fotoğraf")
                }
                Button {
                    showFileImporter = true
                } label: {
                    attachmentButton(icon: "doc.badge.plus", title: "Dosya")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var sendButton: some View {
        Button {
            Task { await sendSupportRequest() }
        } label: {
            HStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                Text(isSending ? "Gönderiliyor" : "Destek talebi gönder")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(canSend ? Color.rdOnyx : Color.rdSlate.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private func supportInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 30, height: 30)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .lineLimit(1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Color.rdSlate)
    }

    private func attachmentButton(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.rdBlack)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func noticeCard(_ text: String, icon: String, color: Color, background: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sendSupportRequest() async {
        guard canSend else { return }
        focusedField = nil
        errorMessage = nil
        successMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let result = try await SupportService.shared.send(
                SupportRequestInput(
                    subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    attachments: attachment.map { [$0] } ?? []
                )
            )
            let supportID = result.supportID ?? "oluşturuldu"
            successMessage = "Talebin gönderildi. Destek kodu: \(supportID)"
            subject = ""
            message = ""
            attachment = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let jpegData = image.supportJPEG(maxDimension: 1600, compressionQuality: 0.78) else {
                errorMessage = "Fotoğraf hazırlanamadı."
                return
            }
            try setAttachment(
                data: jpegData,
                filename: "destek-fotograf.jpg",
                mimeType: "image/jpeg"
            )
        } catch {
            errorMessage = "Fotoğraf eklenemedi."
        }
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            try setAttachment(data: data, filename: url.lastPathComponent, mimeType: mimeType)
        } catch {
            errorMessage = "Dosya eklenemedi."
        }
    }

    private func setAttachment(data: Data, filename: String, mimeType: String) throws {
        guard data.count <= 5_000_000 else {
            errorMessage = "Ek dosya 5 MB'dan küçük olmalı."
            return
        }
        attachment = SupportAttachmentDraft(filename: filename, mimeType: mimeType, data: data)
        errorMessage = nil
    }
}

private extension UIImage {
    func supportJPEG(maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return image.jpegData(compressionQuality: compressionQuality)
    }
}
