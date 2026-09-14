import SwiftUI

/// The work handed to the existing AnalyzingView. The analysis itself is the
/// live pipeline; this only carries it.
struct NovaPhotoBridgeJob: Identifiable {
    let id = UUID()
    let work: (@escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> AnalysisResultBundle
    let preview: UIImage?
    let photoCount: Int
}

struct NovaPhotoBridgeResult: Equatable {
    let findings: [NovaAnalysisFinding]
    let workplaces: [NovaNonconformityWorkplace]
}

/// Which band the expert's own method produced. The other method's band is not
/// mixed in, and the method is shown next to it so the choice is not hidden.
func novaAnalysisFindings(from bundle: AnalysisResultBundle, method: RiskMethod) -> [NovaAnalysisFinding] {
    bundle.findings
        .sorted { $0.ordinal < $1.ordinal }
        .map { finding in
            NovaAnalysisFinding(id: finding.id, ordinal: finding.ordinal, title: finding.title,
                category: finding.category,
                band: method == .fineKinney ? finding.fkBand : finding.m5Band,
                methodLabel: method.label)
        }
}
