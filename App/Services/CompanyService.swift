import Foundation
import OSLog
import Supabase
import UIKit

@MainActor
final class CompanyService {
    static let shared = CompanyService()

    private static let logger = Logger(
        subsystem: "com.riskdetected.app",
        category: "CompanyService"
    )

    private let supabase = SupabaseService.shared

    func listCompanies(includeArchived: Bool = false) async throws -> [Company] {
        do {
            let rows: [Company]
            if includeArchived {
                rows = try await supabase.client
                    .from("companies")
                    .select()
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            } else {
                rows = try await supabase.client
                    .from("companies")
                    .select()
                    .eq("is_archived", value: false)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            }
            return rows
        } catch {
            Self.logger.error("Company list failed: \(error.localizedDescription, privacy: .public)")
            throw AnalysisService.AnalysisError.databaseFailed(RDLocalization.string("localizable.company.service.firmalar.yuklenemedi.7dc2bef5", table: .localizable, fallback: "Firmalar yüklenemedi."))
        }
    }

    func saveCompany(_ draft: CompanyDraft) async throws -> Company {
        guard let userID = supabase.currentUserID else {
            throw AnalysisService.AnalysisError.notAuthenticated
        }
        guard draft.isValid else {
            throw AnalysisService.AnalysisError.invalidInput(RDLocalization.string("localizable.company.service.firma.adi.zorunlu.5b063a40", table: .localizable, fallback: "Firma adı zorunlu."))
        }

        if let id = draft.id {
            struct UpdatePayload: Encodable {
                let name: String
                let hazard_class: String
                let logo_path: String?
                let address: String?
                let contact_person: String?
                let department: String?
                let default_responsible: String?
                let default_due_days: Int?
            }
            let payload = UpdatePayload(
                name: draft.trimmedName,
                hazard_class: draft.hazardClass.rawValue,
                logo_path: draft.logoPath,
                address: draft.address.trimmedNonEmpty,
                contact_person: draft.contactPerson.trimmedNonEmpty,
                department: draft.department.trimmedNonEmpty,
                default_responsible: draft.defaultResponsible.trimmedNonEmpty,
                default_due_days: draft.defaultDueDays
            )
            do {
                let row: Company = try await supabase.client
                    .from("companies")
                    .update(payload)
                    .eq("id", value: id.uuidString)
                    .select()
                    .single()
                    .execute()
                    .value
                return row
            } catch {
                Self.logger.error("Company update failed: \(error.localizedDescription, privacy: .public)")
                throw normalizedCompanyError(error)
            }
        } else {
            struct InsertPayload: Encodable {
                let user_id: String
                let name: String
                let hazard_class: String
                let logo_path: String?
                let address: String?
                let contact_person: String?
                let department: String?
                let default_responsible: String?
                let default_due_days: Int?
            }
            let payload = InsertPayload(
                user_id: userID.uuidString,
                name: draft.trimmedName,
                hazard_class: draft.hazardClass.rawValue,
                logo_path: draft.logoPath,
                address: draft.address.trimmedNonEmpty,
                contact_person: draft.contactPerson.trimmedNonEmpty,
                department: draft.department.trimmedNonEmpty,
                default_responsible: draft.defaultResponsible.trimmedNonEmpty,
                default_due_days: draft.defaultDueDays
            )
            do {
                let row: Company = try await supabase.client
                    .from("companies")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                    .value
                return row
            } catch {
                Self.logger.error("Company insert failed: \(error.localizedDescription, privacy: .public)")
                throw normalizedCompanyError(error)
            }
        }
    }

    func archiveCompany(_ company: Company) async throws {
        struct Payload: Encodable {
            let is_archived: Bool
        }

        do {
            try await supabase.client
                .from("companies")
                .update(Payload(is_archived: true))
                .eq("id", value: company.id.uuidString)
                .execute()
        } catch {
            Self.logger.error("Company archive failed: \(error.localizedDescription, privacy: .public)")
            throw AnalysisService.AnalysisError.databaseFailed(RDLocalization.string("localizable.company.service.firma.arsivlenemedi.6b5218d2", table: .localizable, fallback: "Firma arşivlenemedi."))
        }
    }

    func uploadLogo(_ image: UIImage, companyID: UUID) async throws -> String {
        guard let userID = supabase.currentUserID else {
            throw AnalysisService.AnalysisError.notAuthenticated
        }
        guard let data = image.normalizedJPEG(maxDimension: 900, compressionQuality: 0.82) else {
            throw AnalysisService.AnalysisError.storageFailed(RDLocalization.string("localizable.company.service.logo.dosyasi.hazirlanamadi.f493f057", table: .localizable, fallback: "Logo dosyası hazırlanamadı."))
        }

        let path = "\(userID.uuidString.lowercased())/companies/\(companyID.uuidString.lowercased())/logo.jpg"
        do {
            _ = try await supabase.storage
                .from(RDConfig.Bucket.logos)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            return path
        } catch {
            Self.logger.error("Company logo upload failed: \(error.localizedDescription, privacy: .public)")
            throw AnalysisService.AnalysisError.storageFailed(RDLocalization.string("localizable.company.service.firma.logosu.yuklenemedi.d3f6dcd5", table: .localizable, fallback: "Firma logosu yüklenemedi."))
        }
    }

    func logoImage(path: String) async throws -> UIImage? {
        let data = try await supabase.storage
            .from(RDConfig.Bucket.logos)
            .download(path: path)
        return UIImage(data: data)
    }

    private func normalizedCompanyError(_ error: Error) -> Error {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("company_feature_requires_paid_plan") {
            return AnalysisService.AnalysisError.invalidInput(RDLocalization.string("localizable.company.service.firma.eklemek.icin.plus.veya.pro.plana.gecmelisi.971a5339", table: .localizable, fallback: "Firma eklemek için Plus veya Pro plana geçmelisin."))
        }
        if message.localizedCaseInsensitiveContains("company_limit_exceeded") {
            return AnalysisService.AnalysisError.invalidInput(RDLocalization.string("localizable.company.service.planindaki.firma.limitine.ulastin.e4b2888b", table: .localizable, fallback: "Planındaki firma limitine ulaştın."))
        }
        if message.localizedCaseInsensitiveContains("company_default_due_days_invalid") {
            return AnalysisService.AnalysisError.invalidInput(RDLocalization.string("localizable.company.service.varsayilan.termin.1.365.gun.arasinda.olmali.698f66b8", table: .localizable, fallback: "Varsayılan termin 1-365 gün arasında olmalı."))
        }
        if message.localizedCaseInsensitiveContains("duplicate") ||
            message.localizedCaseInsensitiveContains("companies_user_active_name_idx") {
            return AnalysisService.AnalysisError.invalidInput(RDLocalization.string("localizable.company.service.bu.firma.adi.zaten.listende.var.56298152", table: .localizable, fallback: "Bu firma adı zaten listende var."))
        }
        return AnalysisService.AnalysisError.databaseFailed(RDLocalization.string("localizable.company.service.firma.kaydedilemedi.e5800490", table: .localizable, fallback: "Firma kaydedilemedi."))
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension UIImage {
    func normalizedJPEG(maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.jpegData(compressionQuality: compressionQuality)
    }
}
