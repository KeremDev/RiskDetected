import Foundation
import SwiftUI

enum ProfessionalProgressTitle: String, CaseIterable, Identifiable {
    case candidate = "candidate"
    case fieldObserver = "field_observer"
    case riskHunter = "risk_hunter"
    case hazardAnalyst = "hazard_analyst"
    case seniorRiskSpecialist = "senior_risk_specialist"
    case safetyStrategist = "safety_strategist"
    case masterHSESpecialist = "master_hse_specialist"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .candidate: return RDLocalization.string("professionalprogress.professional.progress.models.aday.uzman.80c60806", table: .professionalProgress, fallback: "Aday Uzman")
        case .fieldObserver: return RDLocalization.string("professionalprogress.professional.progress.models.saha.gozlemcisi.2eea7f98", table: .professionalProgress, fallback: "Saha Gözlemcisi")
        case .riskHunter: return RDLocalization.string("professionalprogress.professional.progress.models.risk.avcisi.743f242e", table: .professionalProgress, fallback: "Risk Avcısı")
        case .hazardAnalyst: return RDLocalization.string("professionalprogress.professional.progress.models.tehlike.analisti.cccb6405", table: .professionalProgress, fallback: "Tehlike Analisti")
        case .seniorRiskSpecialist: return RDLocalization.string("professionalprogress.professional.progress.models.kidemli.risk.uzmani.b252366f", table: .professionalProgress, fallback: "Kıdemli Risk Uzmanı")
        case .safetyStrategist: return RDLocalization.string("professionalprogress.professional.progress.models.guvenlik.stratejisti.be6b9332", table: .professionalProgress, fallback: "Güvenlik Stratejisti")
        case .masterHSESpecialist: return RDLocalization.string("professionalprogress.professional.progress.models.usta.isg.uzmani.f2c16a87", table: .professionalProgress, fallback: "Usta İSG Uzmanı")
        }
    }

    var threshold: Int {
        switch self {
        case .candidate: return 0
        case .fieldObserver: return 1_000
        case .riskHunter: return 5_000
        case .hazardAnalyst: return 15_000
        case .seniorRiskSpecialist: return 40_000
        case .safetyStrategist: return 90_000
        case .masterHSESpecialist: return 180_000
        }
    }

    var color: Color {
        switch self {
        case .candidate: return .rdSlate
        case .fieldObserver: return Color(hex: "#9A5B00")
        case .riskHunter: return Color(hex: "#A15C38")
        case .hazardAnalyst: return Color(hex: "#7C8794")
        case .seniorRiskSpecialist: return Color(hex: "#8EA0B8")
        case .safetyStrategist: return .rdPlanPlus
        case .masterHSESpecialist: return Color(hex: "#102A43")
        }
    }

    static func current(for mdp: Int) -> ProfessionalProgressTitle {
        allCases.last { mdp >= $0.threshold } ?? .candidate
    }

    static func next(after title: ProfessionalProgressTitle) -> ProfessionalProgressTitle? {
        guard let index = allCases.firstIndex(of: title), index + 1 < allCases.count else {
            return nil
        }
        return allCases[index + 1]
    }
}

enum ProfessionalProgressCompetency: String, CaseIterable, Identifiable, Codable {
    case fire
    case chemical
    case electrical
    case mechanical
    case ergonomics
    case psychosocial
    case workingAtHeight = "working_at_height"
    case ppe
    case mining
    case construction
    case factory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fire: return RDLocalization.string("professionalprogress.professional.progress.models.yangin.653d5ecb", table: .professionalProgress, fallback: "Yangın")
        case .chemical: return RDLocalization.string("professionalprogress.professional.progress.models.kimyasal.58ad8545", table: .professionalProgress, fallback: "Kimyasal")
        case .electrical: return RDLocalization.string("professionalprogress.professional.progress.models.elektrik.fbb087fa", table: .professionalProgress, fallback: "Elektrik")
        case .mechanical: return RDLocalization.string("professionalprogress.professional.progress.models.mekanik.6824d368", table: .professionalProgress, fallback: "Mekanik")
        case .ergonomics: return RDLocalization.string("professionalprogress.professional.progress.models.ergonomi.47cb2b71", table: .professionalProgress, fallback: "Ergonomi")
        case .psychosocial: return RDLocalization.string("professionalprogress.professional.progress.models.psikososyal.404024f2", table: .professionalProgress, fallback: "Psikososyal")
        case .workingAtHeight: return RDLocalization.string("professionalprogress.professional.progress.models.yuksekte.calisma.97ec4e45", table: .professionalProgress, fallback: "Yüksekte Çalışma")
        case .ppe: return "KKD"
        case .mining: return RDLocalization.string("professionalprogress.professional.progress.models.maden.653693ae", table: .professionalProgress, fallback: "Maden")
        case .construction: return RDLocalization.string("professionalprogress.professional.progress.models.insaat.d9446df6", table: .professionalProgress, fallback: "İnşaat")
        case .factory: return RDLocalization.string("professionalprogress.professional.progress.models.fabrika.4b480755", table: .professionalProgress, fallback: "Fabrika")
        }
    }

    var icon: String {
        switch self {
        case .fire: return "flame.fill"
        case .chemical: return "testtube.2"
        case .electrical: return "bolt.fill"
        case .mechanical: return "gearshape.2.fill"
        case .ergonomics: return "figure.strengthtraining.traditional"
        case .psychosocial: return "brain.head.profile"
        case .workingAtHeight: return "figure.climbing"
        case .ppe: return "shield.lefthalf.filled"
        case .mining: return "mountain.2.fill"
        case .construction: return "hammer.fill"
        case .factory: return "building.2.fill"
        }
    }

    var accent: Color {
        switch self {
        case .fire: return .rdHigh
        case .chemical: return .rdInfo
        case .electrical: return .rdMedium
        case .mechanical: return .rdCharcoal
        case .ergonomics: return .rdLow
        case .psychosocial: return Color(hex: "#7C3AED")
        case .workingAtHeight: return .rdCritical
        case .ppe: return .rdGreen
        case .mining: return Color(hex: "#475569")
        case .construction: return .rdPlanPlus
        case .factory: return Color(hex: "#0F766E")
        }
    }
}

struct ProfessionalProgressProfileRow: Codable, Equatable {
    let userID: UUID
    let totalMDP: Int
    let currentTitleKey: String
    let totalAnalyses: Int
    let totalReports: Int
    let totalFindings: Int
    let criticalFindings: Int
    let highFindings: Int
    let mediumFindings: Int
    let lowFindings: Int
    let unknownFindings: Int
    let activeDays: Int
    let lastEventAt: String?
    let lastTitleChangeAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case totalMDP = "total_mdp"
        case currentTitleKey = "current_title_key"
        case totalAnalyses = "total_analyses"
        case totalReports = "total_reports"
        case totalFindings = "total_findings"
        case criticalFindings = "critical_findings"
        case highFindings = "high_findings"
        case mediumFindings = "medium_findings"
        case lowFindings = "low_findings"
        case unknownFindings = "unknown_findings"
        case activeDays = "active_days"
        case lastEventAt = "last_event_at"
        case lastTitleChangeAt = "last_title_change_at"
    }
}

struct ProfessionalProgressCompetencyStat: Codable, Identifiable, Equatable {
    let userID: UUID
    let competencyKey: String
    let analysisCount: Int
    let reportCount: Int
    let findingCount: Int
    let criticalCount: Int
    let highCount: Int
    let mediumCount: Int
    let lowCount: Int
    let unknownCount: Int
    let onboardingSeed: Bool
    let lastDetectedAt: String?

    var id: String { competencyKey }

    var competency: ProfessionalProgressCompetency? {
        ProfessionalProgressCompetency(rawValue: competencyKey)
    }

    var signalCount: Int {
        findingCount + reportCount
    }

    var score: Int {
        guard signalCount > 0 else { return onboardingSeed ? 8 : 0 }
        let normalized = 100 * log(1 + Double(signalCount)) / log(26)
        return min(100, max(0, Int(normalized.rounded())))
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case competencyKey = "competency_key"
        case analysisCount = "analysis_count"
        case reportCount = "report_count"
        case findingCount = "finding_count"
        case criticalCount = "critical_count"
        case highCount = "high_count"
        case mediumCount = "medium_count"
        case lowCount = "low_count"
        case unknownCount = "unknown_count"
        case onboardingSeed = "onboarding_seed"
        case lastDetectedAt = "last_detected_at"
    }
}

struct ProfessionalProgressBadge: Codable, Identifiable, Equatable {
    let id: UUID
    let badgeKey: String
    let badgeType: String
    let title: String
    let subtitle: String
    let iconName: String
    let unlockedAt: String?
    let seenAt: String?

    var isSeen: Bool { seenAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case badgeKey = "badge_key"
        case badgeType = "badge_type"
        case title
        case subtitle
        case iconName = "icon_name"
        case unlockedAt = "unlocked_at"
        case seenAt = "seen_at"
    }
}

struct ProfessionalProgressMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let messageType: String
    let title: String
    let body: String
    let competencyKey: String?
    let riskLevel: String?
    let seenAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case messageType = "message_type"
        case title
        case body
        case competencyKey = "competency_key"
        case riskLevel = "risk_level"
        case seenAt = "seen_at"
        case createdAt = "created_at"
    }
}

struct ProfessionalProgressWeeklySummary: Codable, Identifiable, Equatable {
    let id: UUID
    let weekStart: String
    let reportsCount: Int
    let analysesCount: Int
    let findingsCount: Int
    let topCompetencyKey: String?
    let messageTitle: String?
    let messageBody: String?

    enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case reportsCount = "reports_count"
        case analysesCount = "analyses_count"
        case findingsCount = "findings_count"
        case topCompetencyKey = "top_competency_key"
        case messageTitle = "message_title"
        case messageBody = "message_body"
    }
}

struct ProfessionalProgressWeeklyTracking: Equatable {
    let title: String
    let body: String
    let reportsCount: Int
    let analysesCount: Int
    let findingsCount: Int
    let topCompetency: ProfessionalProgressCompetency?

    var hasActivity: Bool {
        reportsCount > 0 || analysesCount > 0
    }
}

struct ProfessionalProgressSummary: Equatable {
    let profile: ProfessionalProgressProfileRow
    let competencies: [ProfessionalProgressCompetencyStat]
    let badges: [ProfessionalProgressBadge]
    let messages: [ProfessionalProgressMessage]
    let weeklySummary: ProfessionalProgressWeeklySummary?

    var currentTitle: ProfessionalProgressTitle {
        ProfessionalProgressTitle.current(for: profile.totalMDP)
    }

    var nextTitle: ProfessionalProgressTitle? {
        ProfessionalProgressTitle.next(after: currentTitle)
    }

    var nextTitleRemaining: Int {
        guard let nextTitle else { return 0 }
        return max(nextTitle.threshold - profile.totalMDP, 0)
    }

    var titleProgress: Double {
        guard let nextTitle else { return 1 }
        let current = currentTitle.threshold
        let span = max(nextTitle.threshold - current, 1)
        return min(1, max(0, Double(profile.totalMDP - current) / Double(span)))
    }

    var topCompetencies: [ProfessionalProgressCompetencyStat] {
        competencies
            .filter { $0.signalCount > 0 || $0.onboardingSeed }
            .sorted {
                if $0.signalCount == $1.signalCount {
                    return $0.score > $1.score
                }
                return $0.signalCount > $1.signalCount
            }
    }

    var pendingCelebration: ProfessionalProgressBadge? {
        badges.first { !$0.isSeen }
    }

    var weeklyTracking: ProfessionalProgressWeeklyTracking {
        guard let weeklySummary,
              weeklySummary.normalizedWeekStart == Self.currentWeekStartString else {
            return ProfessionalProgressWeeklyTracking(
                title: RDLocalization.string("professionalprogress.professional.progress.models.haftalik.takip.00850983", table: .professionalProgress, fallback: "Haftalık Takip"),
                body: Self.weeklyTrackingBody(
                    reports: 0,
                    analyses: 0,
                    findings: 0,
                    topCompetency: nil
                ),
                reportsCount: 0,
                analysesCount: 0,
                findingsCount: 0,
                topCompetency: nil
            )
        }

        let topCompetency = weeklySummary.topCompetencyKey.flatMap(ProfessionalProgressCompetency.init(rawValue:))
        return ProfessionalProgressWeeklyTracking(
            title: weeklySummary.messageTitle ?? RDLocalization.string("professionalprogress.professional.progress.models.haftalik.takip.192ca0ad", table: .professionalProgress, fallback: "Haftalık Takip"),
            body: weeklySummary.messageBody ?? Self.weeklyTrackingBody(
                reports: weeklySummary.reportsCount,
                analyses: weeklySummary.analysesCount,
                findings: weeklySummary.findingsCount,
                topCompetency: topCompetency
            ),
            reportsCount: weeklySummary.reportsCount,
            analysesCount: weeklySummary.analysesCount,
            findingsCount: weeklySummary.findingsCount,
            topCompetency: topCompetency
        )
    }

    static func empty(userID: UUID) -> ProfessionalProgressSummary {
        ProfessionalProgressSummary(
            profile: ProfessionalProgressProfileRow(
                userID: userID,
                totalMDP: 0,
                currentTitleKey: ProfessionalProgressTitle.candidate.rawValue,
                totalAnalyses: 0,
                totalReports: 0,
                totalFindings: 0,
                criticalFindings: 0,
                highFindings: 0,
                mediumFindings: 0,
                lowFindings: 0,
                unknownFindings: 0,
                activeDays: 0,
                lastEventAt: nil,
                lastTitleChangeAt: nil
            ),
            competencies: [],
            badges: [],
            messages: [],
            weeklySummary: nil
        )
    }

    private static var currentWeekStartString: String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = RDConfig.Quota.businessTimeZone
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }

    private static func weeklyTrackingBody(
        reports: Int,
        analyses: Int,
        findings: Int,
        topCompetency: ProfessionalProgressCompetency?
    ) -> String {
        var body: String
        if reports == 0 && analyses == 0 {
            body = RDLocalization.string("professionalprogress.professional.progress.models.bu.hafta.ilk.analizini.baslat.6f6b8e2e", table: .professionalProgress, fallback: "Bu hafta ilk analizini başlat. 😔")
        } else if reports == 0 {
            body = RDLocalization.format("professionalprogress.professional.progress.models.1.analiz.tamamladin.simdi.rapora.donustur.2ba431b2", table: .professionalProgress, fallback: "%1$@ analiz tamamladın. Şimdi rapora dönüştür.", arguments: [String(describing: analyses)])
        } else if reports == 1 {
            body = RDLocalization.string("professionalprogress.professional.progress.models.ilk.rapor.tamam.devam.et.663e1cfb", table: .professionalProgress, fallback: "İlk rapor tamam. Devam et.")
        } else {
            body = RDLocalization.format("professionalprogress.professional.progress.models.bu.hafta.1.rapor.tamamladin.ea8ca37d", table: .professionalProgress, fallback: "Bu hafta %1$@ rapor tamamladın. 💪", arguments: [String(describing: reports)])
        }

        return body
    }
}

private extension ProfessionalProgressWeeklySummary {
    var normalizedWeekStart: String {
        String(weekStart.prefix(10))
    }
}
