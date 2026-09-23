import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SupportContactSheet: View {
    let profile: UserProfile?
    let tier: SubscriptionTier
    let appLanguage: RDAppLanguage
    let contentLocale: RDContentLocale
    var pilot = false
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.novaCanvasStyle) private var canvasStyle
    @FocusState private var focusedField: Field?

    @State private var subject = ""
    @State private var message = ""
    @State private var attachments: [SupportAttachmentDraft] = []
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
        Group {
            if pilot {
                VStack(spacing: 0) {
                    PilotProfilePageHeader(title: RDLocalization.string("localizable.support.contact.sheet.yardim.ve.destek.75b4abab", table: .localizable, fallback: "Yardım ve destek"), onBack: onClose)
                    supportContent
                }
                .background(canvasStyle.color(in: colorScheme).ignoresSafeArea())
            } else {
                NavigationStack {
                    supportContent
                        .navigationTitle(RDLocalization.string("localizable.support.contact.sheet.destek.05e6a313", table: .localizable, fallback: "Destek"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                RDModalCloseButton {
                                    dismiss()
                                    onClose()
                                }
                            }
                        }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.jpeg, .png, .pdf],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImportedFile(result) }
        }
        .onChange(of: selectedPhotoItem) { item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
    }

    private var supportContent: some View {
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
                    .keyboardAdaptivePadding(extra: 16)
                }
                .background(pilot ? canvasStyle.color(in: colorScheme) : Color.rdPaper)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { field in
                    guard !pilot, field != nil else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("sendButton", anchor: .bottom)
                    }
                }
            }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "headphones")
                    .font(NovaFont.font(.screenTitle))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text(pilot ? RDLocalization.string("localizable.support.contact.sheet.isgada.destek.680b5679", table: .localizable, fallback: "İSGADA destek") : RDLocalization.string("localizable.support.contact.sheet.riskdetected.destek.e11a7270", table: .localizable, fallback: "RiskDetected destek"))
                        .font(NovaFont.font(.screenTitle))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("localizable.support.contact.sheet.konu.mesaj.ve.gerekirse.ekran.goruntusu.ekleyere.4dd76367", table: .localizable, fallback: "Konu, mesaj ve gerekirse ekran görüntüsü ekleyerek bize ulaş."))
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(pilot ? Color.clear : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var senderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(RDLocalization.string("localizable.support.contact.sheet.gonderen.1bc4fb4a", table: .localizable, fallback: "Gönderen"))
            supportInfoRow(icon: "person.fill", title: RDLocalization.string("localizable.support.contact.sheet.ad.soyad.76ebaa37", table: .localizable, fallback: "Ad soyad"), value: profile?.displayName ?? RDLocalization.string("localizable.support.contact.sheet.kayitli.degil.d9c4334d", table: .localizable, fallback: "Kayıtlı değil"))
            supportInfoRow(icon: "envelope.fill", title: RDLocalization.string("localizable.support.contact.sheet.e.posta.65913732", table: .localizable, fallback: "E-posta"), value: profile?.email ?? RDLocalization.string("localizable.support.contact.sheet.kayitli.degil.f107e88e", table: .localizable, fallback: "Kayıtlı değil"))
            supportInfoRow(icon: "phone.fill", title: RDLocalization.string("localizable.support.contact.sheet.telefon.886d484e", table: .localizable, fallback: "Telefon"), value: profile?.phone ?? RDLocalization.string("localizable.support.contact.sheet.kayitli.degil.076de3b1", table: .localizable, fallback: "Kayıtlı değil"))
            supportInfoRow(icon: tier.badgeIcon, title: RDLocalization.string("localizable.support.contact.sheet.plan.327d57d0", table: .localizable, fallback: "Planı"), value: tier.title)
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(pilot ? Color.clear : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(RDLocalization.string("localizable.support.contact.sheet.talep.e2063e6f", table: .localizable, fallback: "Talep"))
            VStack(alignment: .leading, spacing: 7) {
                Text(RDLocalization.string("localizable.support.contact.sheet.konu.ed0d8962", table: .localizable, fallback: "Konu"))
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdBlack)
                TextField(RDLocalization.string("localizable.support.contact.sheet.kisa.bir.konu.yaz.765f1671", table: .localizable, fallback: "Kısa bir konu yaz"), text: $subject)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .subject)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .message }
                    .padding(14)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(RDLocalization.string("localizable.support.contact.sheet.mesaj.35edbcb6", table: .localizable, fallback: "Mesaj"))
                    .font(NovaFont.font(.body))
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
                            Text(RDLocalization.string("localizable.support.contact.sheet.sorunu.istegini.veya.gordugun.ekrani.anlat.93c57b7b", table: .localizable, fallback: "Sorunu, isteğini veya gördüğün ekranı anlat..."))
                                .font(NovaFont.font(.cardTitle))
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
                .stroke(pilot ? Color.clear : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var attachmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(RDLocalization.string("localizable.support.contact.sheet.ek.c7e0a951", table: .localizable, fallback: "Ek"))
            ForEach(attachments) { attachment in
                attachmentRow(attachment)
            }

            if attachments.count >= 3 {
                Text(RDLocalization.string("localizable.support.contact.sheet.en.fazla.3.ek.ekleyebilirsin.8ac2432b", table: .localizable, fallback: "En fazla 3 ek ekleyebilirsin."))
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdSlate)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        attachmentButton(icon: "photo.on.rectangle.angled", title: RDLocalization.string("localizable.support.contact.sheet.fotograf.07da075c", table: .localizable, fallback: "Fotoğraf"))
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        attachmentButton(icon: "doc.badge.plus", title: RDLocalization.string("localizable.support.contact.sheet.dosya.f193f199", table: .localizable, fallback: "Dosya"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(pilot ? Color.clear : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func attachmentRow(_ attachment: SupportAttachmentDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo.fill" : "paperclip")
                .font(NovaFont.font(.screenTitle))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 44, height: 44)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark")
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 32, height: 32)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        .font(NovaFont.font(.screenTitle))
                }
                Text(isSending ? RDLocalization.string("localizable.support.contact.sheet.gonderiliyor.5ae65683", table: .localizable, fallback: "Gönderiliyor") : RDLocalization.string("localizable.support.contact.sheet.destek.talebi.gonder.0aeffa33", table: .localizable, fallback: "Destek talebi gönder"))
                    .font(NovaFont.font(.screenTitle))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(canSend ? (pilot ? Color.rdGreen : Color.rdOnyx) : Color.rdSlate.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private func supportInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(NovaFont.font(.body))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 30, height: 30)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(NovaFont.font(.body))
                .foregroundStyle(Color.rdSlate)
            Spacer(minLength: 12)
            Text(value)
                .font(NovaFont.font(.body))
                .foregroundStyle(Color.rdBlack)
                .lineLimit(1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(NovaFont.font(.meta))
            .tracking(0.6)
            .foregroundStyle(Color.rdSlate)
    }

    private func attachmentButton(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(NovaFont.font(.cardTitle))
            Text(title)
                .font(NovaFont.font(.body))
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
                .font(NovaFont.font(.cardTitle))
                .foregroundStyle(color)
            Text(text)
                .font(NovaFont.font(.body))
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
                    attachments: attachments,
                    appLanguage: appLanguage,
                    contentLocale: contentLocale
                )
            )
            let supportID = result.supportID ?? RDLocalization.string("localizable.support.contact.sheet.olusturuldu.55daf5fd", table: .localizable, fallback: "oluşturuldu")
            if let acknowledgement = result.acknowledgement?.trimmingCharacters(in: .whitespacesAndNewlines),
               !acknowledgement.isEmpty {
                successMessage = acknowledgement
            } else if result.deliveryStatus == "sent" {
                successMessage = RDLocalization.format("localizable.support.contact.sheet.talebin.gonderildi.destek.kodu.1.2c87b88e", table: .localizable, fallback: "Talebin gönderildi. Destek kodu: %1$@", arguments: [String(describing: supportID)])
            } else {
                successMessage = RDLocalization.format("localizable.support.contact.sheet.talebin.kaydedildi.destek.kodu.1.af3a6121", table: .localizable, fallback: "Talebin kaydedildi. Destek kodu: %1$@", arguments: [String(describing: supportID)])
            }
            subject = ""
            message = ""
            attachments = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let jpegData = image.supportJPEG(maxDimension: 1600, compressionQuality: 0.78) else {
                errorMessage = RDLocalization.string("localizable.support.contact.sheet.fotograf.hazirlanamadi.71737e0b", table: .localizable, fallback: "Fotoğraf hazırlanamadı.")
                return
            }
            try setAttachment(
                data: jpegData,
                filename: "destek-fotograf.jpg",
                mimeType: "image/jpeg"
            )
        } catch {
            errorMessage = RDLocalization.string("localizable.support.contact.sheet.fotograf.eklenemedi.33fcc117", table: .localizable, fallback: "Fotoğraf eklenemedi.")
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
            errorMessage = RDLocalization.string("localizable.support.contact.sheet.dosya.eklenemedi.3947311d", table: .localizable, fallback: "Dosya eklenemedi.")
        }
    }

    private func setAttachment(data: Data, filename: String, mimeType: String) throws {
        guard attachments.count < 3 else {
            errorMessage = RDLocalization.string("localizable.support.contact.sheet.en.fazla.3.ek.ekleyebilirsin.8d8f0825", table: .localizable, fallback: "En fazla 3 ek ekleyebilirsin.")
            return
        }
        guard data.count <= 5_000_000 else {
            errorMessage = RDLocalization.string("localizable.support.contact.sheet.ek.dosya.5.mb.dan.kucuk.olmali.054a77f6", table: .localizable, fallback: "Ek dosya 5 MB'dan küçük olmalı.")
            return
        }
        attachments.append(SupportAttachmentDraft(filename: uniqueAttachmentName(filename), mimeType: mimeType, data: data))
        errorMessage = nil
    }

    private func uniqueAttachmentName(_ filename: String) -> String {
        guard attachments.contains(where: { $0.filename == filename }) else { return filename }
        let url = URL(fileURLWithPath: filename)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = attachments.count + 1
        return ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
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
