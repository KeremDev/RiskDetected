import SwiftUI

/// The work handed to the existing AnalyzingView. The analysis itself is the
/// live pipeline; this only carries it.
struct NovaPhotoBridgeJob: Identifiable {
    let id = UUID()
    let work: (@escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> UUID
    let preview: UIImage?
    let photoCount: Int
}
