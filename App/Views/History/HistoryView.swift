import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var search: String = ""
    @State private var activeChip: String = "Tümü"
    @State private var showFilter: Bool = false
    @State private var items: [HistoryItem] = []
    @State private var analysisResult: AnalysisResultBundle? = nil
    @State private var showResult = false
    @State private var analysisError: String? = nil
    @State private var openingItemID: UUID? = nil
    @State private var deletingItemID: UUID? = nil
    @State private var itemPendingDelete: HistoryItem?
    @State private var showPaywall = false

    private let chips = ["Tümü", "Bu hafta", "Kritik", "KKD", "Genel"]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Analizler")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.rdBlack)
                Spacer()
                RDHeaderAccountCTA {
                    showPaywall = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Search row
            HStack(spacing: 8) {
                searchField
                filterButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Chip row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { c in
                        let active = c == activeChip
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            activeChip = c
                        } label: {
                            Text(c)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .foregroundStyle(active ? .white : Color.rdCharcoal)
                                .background(
                                    Capsule()
                                        .fill(active ? Color.rdBlack : Color.rdWhite)
                                        .overlay(
                                            Capsule()
                                                .stroke(active ? Color.clear : Color.rdLine,
                                                        lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)

            // List
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if filteredItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredItems) { item in
                            HistoryRow(
                                item: item,
                                isLoading: openingItemID == item.id,
                                isDeleting: deletingItemID == item.id
                            ) {
                                openAnalysis(item)
                            } onDelete: {
                                itemPendingDelete = item
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdPaper)
        .task {
            await loadItems()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task { await loadItems() }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet { showFilter = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
        }
        .fullScreenCover(isPresented: $showResult) {
            ResultView(
                bundle: analysisResult,
                onClose: {
                    showResult = false
                    analysisResult = nil
                    Task { await loadItems() }
                }
            )
            .environmentObject(app)
        }
        .confirmationDialog(
            "Analiz silinsin mi?",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Analizi sil", role: .destructive) {
                if let item = itemPendingDelete {
                    deleteAnalysis(item)
                }
            }
            Button("Vazgeç", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text("Analiz, bulgular, fotoğraf kaydı ve bu analize bağlı rapor kayıtları silinir.")
        }
        .alert("Analiz Hatası", isPresented: .init(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button("Tamam") { analysisError = nil }
        } message: {
            Text(analysisError ?? "")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.rdSlate)
            TextField("Analiz ara", text: $search)
                .font(.system(size: 14))
                .foregroundStyle(Color.rdBlack)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.rdFog)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var filterButton: some View {
        Button {
            showFilter = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(Color.rdBlack)
                .background(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var filteredItems: [HistoryItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            let matchesSearch = needle.isEmpty
                || item.title.lowercased().contains(needle)
                || item.kind.lowercased().contains(needle)

            let matchesChip: Bool
            switch activeChip {
            case "Bu hafta":
                matchesChip = isThisWeek(item.createdAt)
            case "Kritik":
                matchesChip = item.level == .critical
            case "KKD":
                matchesChip = item.kind.localizedCaseInsensitiveContains("KKD")
            case "Genel":
                matchesChip = item.kind.localizedCaseInsensitiveContains("Genel")
            default:
                matchesChip = true
            }

            return matchesSearch && matchesChip
        }
    }

    private var emptyState: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Analiz bulunamadı")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.rdBlack)
                Text("Filtreyi değiştir veya yeni bir saha taraması başlat.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rdSlate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadItems() async {
        guard app.auth.session != nil else { return }
        do {
            let rows = try await AnalysisService.shared.listRecent(limit: 50)
            let paths = try await AnalysisService.shared.firstPhotoPaths(analysisIDs: rows.map(\.id))
            items = rows.map { row in
                HistoryItem(row: row, photoPath: paths[row.id])
            }
        } catch {
            analysisError = AppErrorMessage.make(error, context: "Analizler yüklenemedi", fallbackTitle: "Analizler yüklenemedi").fullText
            items = []
        }
    }

    private func openAnalysis(_ item: HistoryItem) {
        guard openingItemID == nil else { return }
        openingItemID = item.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                analysisResult = try await AnalysisService.shared.result(analysisID: item.id)
                showResult = true
            } catch {
                analysisError = AppErrorMessage.make(error, context: "Analiz açılamadı", fallbackTitle: "Analiz açılamadı").fullText
            }
            openingItemID = nil
        }
    }

    private func deleteAnalysis(_ item: HistoryItem) {
        guard deletingItemID == nil else { return }
        itemPendingDelete = nil
        deletingItemID = item.id

        Task {
            do {
                try await AnalysisService.shared.deleteAnalysis(analysisID: item.id)
                items.removeAll { $0.id == item.id }
                if analysisResult?.analysis.id == item.id {
                    analysisResult = nil
                    showResult = false
                }
            } catch {
                analysisError = AppErrorMessage.make(error, context: "Analiz silinemedi", fallbackTitle: "Analiz silinemedi").fullText
            }
            deletingItemID = nil
        }
    }

    private func isThisWeek(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let item: HistoryItem
    var isLoading: Bool = false
    var isDeleting: Bool = false
    let action: () -> Void
    let onDelete: () -> Void
    @State private var dragOffset: CGFloat = 0

    private let revealWidth: CGFloat = 74

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                onDelete()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Sil")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: revealWidth, height: 84)
            }
            .background(Color.rdCritical)
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
            .opacity(dragOffset < -8 ? 1 : 0)

            rowContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            let horizontal = value.translation.width
                            let vertical = abs(value.translation.height)
                            guard abs(horizontal) > vertical else { return }
                            dragOffset = min(0, max(-revealWidth, horizontal))
                        }
                        .onEnded { value in
                            let shouldOpen = value.translation.width < -36
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                dragOffset = shouldOpen ? -revealWidth : 0
                            }
                        }
                )
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            AnalysisThumbnail(path: item.photoPath, cornerRadius: 10)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RDChip(level: item.level)
                }

                HStack(spacing: 6) {
                    Text(item.date)
                    Text("·")
                    Text(item.kind)
                    Text("·")
                    Text("\(item.count) bulgu")
                        .rdMono(size: 12)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.rdSlate)

                Text(item.status.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(item.status.textColor)
                    .background(item.status.bgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading || isDeleting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .contentShape(Rectangle())
        .onTapGesture {
            if dragOffset < 0 {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
            } else {
                action()
            }
        }
    }
}

#Preview {
    HistoryView()
}
