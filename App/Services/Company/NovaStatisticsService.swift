import Foundation
import Supabase

@MainActor struct NovaStatisticsService {
    let identity: NovaSessionIdentity
    func load(company: UUID?, months: Int) async throws -> NovaStatisticsSnapshot {
        func check() throws {
            try Task.checkCancellation()
            guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
        }
        try check()
        let data = try await SupabaseService.shared.client.rpc("isg_statistics_v1", params: [
            "p_company": PersonnelRPCValue.id(company), "p_months": .number(Int64(months))
        ]).execute().data
        try check()
        guard data.count <= 2_097_152 else { throw NovaPersonnelFailure.unavailable }
        let result = try JSONDecoder().decode(NovaStatisticsSnapshot.self, from: data)
        guard result.validate(owner: identity.userID, company: company, period: months) else { throw NovaPersonnelFailure.denied }
        return result
    }
}
