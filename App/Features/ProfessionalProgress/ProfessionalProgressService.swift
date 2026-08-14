import Foundation
import OSLog
import Supabase

@MainActor
final class ProfessionalProgressService {
    static let shared = ProfessionalProgressService()

    private static let logger = Logger(
        subsystem: "com.riskdetected.app",
        category: "ProfessionalProgressService"
    )

    private let supabase: SupabaseService

    init(supabase: SupabaseService = .shared) {
        self.supabase = supabase
    }

    func fetchSummary() async -> ProfessionalProgressSummary? {
        guard RDConfig.Features.professionalProgressEnabled,
              RDProfessionalProgressLocalizationReview.isAvailable
        else { return nil }
        guard let userID = supabase.currentUserID else { return nil }

        do {
            async let profileRows: [ProfessionalProgressProfileRow] = supabase.client
                .from("professional_progress_profiles")
                .select()
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value

            async let competencyRows: [ProfessionalProgressCompetencyStat] = supabase.client
                .from("professional_progress_competency_stats")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            async let badgeRows: [ProfessionalProgressBadge] = supabase.client
                .from("professional_progress_badges")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("unlocked_at", ascending: false)
                .limit(24)
                .execute()
                .value

            async let messageRows: [ProfessionalProgressMessage] = supabase.client
                .from("professional_progress_messages")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .limit(5)
                .execute()
                .value

            async let weeklyRows: [ProfessionalProgressWeeklySummary] = supabase.client
                .from("professional_progress_weekly_summaries")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("week_start", ascending: false)
                .limit(1)
                .execute()
                .value

            let resolvedProfileRows = try await profileRows
            let resolvedCompetencyRows = try await competencyRows
            let resolvedBadgeRows = try await badgeRows
            let resolvedMessageRows = try await messageRows
            let resolvedWeeklyRows = try await weeklyRows

            let profile = resolvedProfileRows.first ?? ProfessionalProgressSummary.empty(userID: userID).profile
            return ProfessionalProgressSummary(
                profile: profile,
                competencies: resolvedCompetencyRows,
                badges: resolvedBadgeRows,
                messages: resolvedMessageRows,
                weeklySummary: resolvedWeeklyRows.first
            )
        } catch {
            Self.logger.error("Progress summary fetch failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func markBadgeSeen(_ badge: ProfessionalProgressBadge) async {
        guard RDConfig.Features.professionalProgressEnabled,
              RDProfessionalProgressLocalizationReview.isAvailable
        else { return }

        struct Payload: Encodable {
            let seen_at: String
        }

        do {
            try await supabase.client
                .from("professional_progress_badges")
                .update(Payload(seen_at: Self.nowISO()))
                .eq("id", value: badge.id.uuidString)
                .execute()
        } catch {
            Self.logger.error("Progress badge seen update failed badge=\(badge.badgeKey, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func markMessageSeen(_ message: ProfessionalProgressMessage) async {
        guard RDConfig.Features.professionalProgressEnabled,
              RDProfessionalProgressLocalizationReview.isAvailable
        else { return }

        struct Payload: Encodable {
            let seen_at: String
        }

        do {
            try await supabase.client
                .from("professional_progress_messages")
                .update(Payload(seen_at: Self.nowISO()))
                .eq("id", value: message.id.uuidString)
                .execute()
        } catch {
            Self.logger.error("Progress message seen update failed message=\(message.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func nowISO() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
