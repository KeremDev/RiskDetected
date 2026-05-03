import SwiftUI

struct HistoryView: View {
    @State private var search: String = ""
    @State private var activeChip: String = "Tümü"
    @State private var showFilter: Bool = false
    @State private var selectedItem: HistoryItem? = nil

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
                    ForEach(HistoryItem.mock) { item in
                        HistoryRow(item: item) {
                            selectedItem = item
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdPaper)
        .sheet(isPresented: $showFilter) {
            FilterSheet { showFilter = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
}

// MARK: - History Row

private struct HistoryRow: View {
    let item: HistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RDPlaceholderPhoto(cornerRadius: 10)
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
            }
            .padding(14)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
        .buttonStyle(RDPressableButtonStyle())
    }
}

#Preview {
    HistoryView()
}
